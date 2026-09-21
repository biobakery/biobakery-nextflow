#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// PhyloPhlAn metagenomic — phylogenetic placement of MAGs to nearest SGBs/GGBs/FGBs
process phylophlan_metagenomic {
    tag "$sample"
    publishDir "${params.outdir}/phylophlan/${sample}", mode: 'copy'

    input:
    tuple val(sample), path(bins_dir)

    output:
    tuple val(sample), path("phylophlan_out.tsv"), emit: placement

    script:
    def db_folder = params.phylophlan_path
    def db        = file(params.phylophlan_path).list()?.find { it.count('.') == 1 } ?: ""
    def extra     = params.phylophlan_metagenomic_options ?: ""
    """
    if ls ${bins_dir}/*.bin.[0-9]*.fa 2>/dev/null | grep -q .; then
        # Stage only the numbered bins, as the anadama2 workflow's copy_bins step
        # does. MetaBAT also emits empty lowDepth/tooShort/unbinned placeholders,
        # and mash cannot sketch a zero-byte file: phylophlan reports
        # "error while sketching ... expected str, bytes or os.PathLike object,
        # not NoneType" and exits.
        mkdir -p numbered_bins
        cp ${bins_dir}/*.bin.[0-9]*.fa numbered_bins/
        phylophlan_assign_sgbs_legacy \\
            -i numbered_bins \\
            -n 1 \\
            --add_ggb --add_fgb \\
            -d ${db} \\
            -o phylophlan_out \\
            --nproc ${task.cpus} \\
            --verbose \\
            -e fa \\
            --database_folder ${db_folder} \\
            ${extra}
        # phylophlan writes phylophlan_out.tsv directly from -o phylophlan_out;
        # the previous self-move here failed with "are the same file" and took the
        # task down after the full 20+ minute mash dist had already succeeded
    else
        echo -e "line1\nline2\nline3\n#mag\tsgb\tggb\tfgb\tref" > phylophlan_out.tsv
    fi
    """
}

// Merge per-sample PhyloPhlAn placements and add taxonomic labels
process phylophlan_merge {
    publishDir "${params.outdir}/phylophlan", mode: 'copy'

    input:
    // Every sample's placement is called phylophlan_out.tsv, and so is this
    // process's own output; stageAs both separates the inputs from each other
    // and keeps the glob below from picking the partial output up.
    path placements, stageAs: 'placement_*.tsv'  // collected per-sample placements

    output:
    path "phylophlan_out.tsv",    emit: merged
    path "phylophlan_relab.tsv",  emit: relab

    script:
    """
    # Take the first file whole, then append only the data rows of the others,
    # as the anadama2 workflow does. PhyloPhlAn writes a four-line header
    # (#last SGB/GGB/FGB id, then #input_bin), and phylophlan_add_tax_assignment.py
    # reads the result with skiprows=[0,1,2], so the full header has to survive.
    # Previously this kept only "head -1", losing three header lines, and the loop
    # ran over every file including the first, duplicating its data rows.
    # Capture the input list before writing anything: the output is also a .tsv
    # in this directory, so re-globbing mid-merge picks the partial output up as
    # one of its own inputs and duplicates every row.
    ls placement_*.tsv | sort > .phylophlan_inputs.txt
    first=\$(head -1 .phylophlan_inputs.txt)
    cat "\$first" > merged_tmp.tsv
    tail -n +2 .phylophlan_inputs.txt | while read -r f; do
        tail -n +5 "\$f" >> merged_tmp.tsv
    done
    mv merged_tmp.tsv phylophlan_out.tsv

    python ${projectDir}/bin/scripts/phylophlan_add_tax_assignment.py \\
        --table phylophlan_out.tsv \\
        --output phylophlan_relab.tsv
    """
}
