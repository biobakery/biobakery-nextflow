#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Sketch each qualifying MAG, the first step of the Mash distance pipeline.
process mash_sketch {
    publishDir "${params.outdir}/sgbs/mash", mode: 'copy'

    input:
    path mag_filepaths   // text file listing MAG FASTA paths (from mash_list_inputs.py)

    output:
    path "sketches.msh", emit: sketch

    script:
    def extra = params.mash_sketch_options ?: ""
    """
    if [ ! -s ${mag_filepaths} ]; then
        touch sketches.msh
    else
        mash sketch -p ${task.cpus} -l ${mag_filepaths} -o sketches ${extra}
    fi
    """
}

// Paste the per-MAG Mash sketches into one reference sketch.
process mash_paste {
    publishDir "${params.outdir}/sgbs/mash", mode: 'copy'

    input:
    path sketch

    output:
    path "references.msh", emit: references

    script:
    """
    if [ ! -s ${sketch} ]; then
        touch references.msh
    else
        mash paste references ${sketch}
    fi
    """
}

// Pairwise Mash distances between every MAG and the reference sketch.
process mash_dist {
    publishDir "${params.outdir}/sgbs/mash", mode: 'copy'

    input:
    path references
    path sketch

    output:
    path "mash_dist_out.tsv", emit: distances

    script:
    """
    if [ ! -s ${references} ]; then
        touch mash_dist_out.tsv
    else
        mash dist -p ${task.cpus} -t ${references} ${sketch} > mash_dist_out.tsv
    fi
    """
}

// List qualifying MAG FASTA paths to feed into Mash
process mash_list_inputs {
    publishDir "${params.outdir}/sgbs/mash", mode: 'copy'

    input:
    path checkm_qa_n50
    path phylophlan_relab
    // Every sample's bins directory, staged here rather than one sample's work
    // directory: mash_list_inputs.py globs the tree recursively for *.fa, so
    // the numbering stageAs adds is invisible to it, and the MAG files inside
    // are already sample-prefixed. Passing one sample's directory silently
    // dropped every other sample's MAGs from SGB clustering.
    path bins_dirs, stageAs: 'bins_*'

    output:
    path "mags_filepaths.txt", emit: filepaths
    // The script copies the MAGs that pass QC into <bins>/qc_bins; emitting it
    // hands sgb_cluster a real input instead of having it reach back into
    // another task's work directory for a folder written there as a side effect.
    path "qc_bins", emit: qc_bins

    script:
    """
    python ${projectDir}/bin/scripts/mash_list_inputs.py \\
        --checkm ${checkm_qa_n50} \\
        --phylophlan ${phylophlan_relab} \\
        --bins . \\
        --mash . \\
        --threads ${task.cpus}

    # the script creates qc_bins itself; this only guarantees the declared
    # output exists if that ever changes
    mkdir -p qc_bins
    """
}

// Cluster MAGs into SGBs using Mash distances + CheckM/PhyloPhlAn metadata
process sgb_cluster {
    publishDir "${params.outdir}/sgbs/sgbs", mode: 'copy'

    input:
    path mash_distances
    path phylophlan_relab
    path checkm_qa_n50
    path qc_bins     // the QC-passing MAGs, from mash_list_inputs

    output:
    path "SGB_info.tsv",     emit: sgb_info
    path "SGB_list.txt",     emit: sgb_list, optional: true

    script:
    """
    if [ ! -s ${mash_distances} ]; then
        mkdir -p fastANI
        touch fastANI/SGB_list.txt
        echo -e "cluster\tgenome\tcluster_members\tn_genomes\tcompleteness\tcontamination\tstrain_heterogeneity\tn50\tquality\tkeep\tcluster_name\tsgb" > SGB_info.tsv
    else
        Rscript ${projectDir}/bin/Rscripts/mash_clusters.R \\
            --mash ${mash_distances} \\
            --checkm ${checkm_qa_n50} \\
            --phylo ${phylophlan_relab} \\
            --out_dir . \\
            --threads ${task.cpus} \\
            --mag_dir ${qc_bins}

        # mash_clusters.R writes into <out_dir>/sgbs/ and <out_dir>/fastANI/, but
        # the declared outputs are at the top level (and that is where the branch
        # above writes them). Without this the task exits 0 and nextflow then
        # reports the outputs as missing.
        cp sgbs/SGB_info.tsv SGB_info.tsv
        if [ -f fastANI/SGB_list.txt ]; then cp fastANI/SGB_list.txt SGB_list.txt; fi
    fi
    """
}

// Merge abundance data with taxonomy and SGB assignments into the final profile
process merge_tax_abundance {
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path abundance_tables   // collected *.abundance.tsv, staged into this directory
    path phylophlan_relab
    path checkm_qa_n50
    path sgb_info

    output:
    path "final_profile.tsv", emit: final_profile

    script:
    def abundance_type = params.sgb_abundance_type ?: "by_sample"
    """
    # A run where no sample yielded a MAG leaves every one of these tables with
    # nothing but its header, which routinely happens on small or heavily
    # host-dominated libraries. The rest of the assembly workflow already
    # carries that case: metabat2 writes placeholder bins, checkm2 and
    # phylophlan write header-only reports, sgb_cluster takes its empty branch.
    # merge_tax_and_abundance.R is the one step that does not -- fread() types
    # the empty ID columns as logical and left_join() aborts on
    # "Can't join x\$ID with y\$ID due to incompatible types" -- so stop short
    # of it and write the header the script would have produced.
    tax_rows=\$(tail -n +2 ${phylophlan_relab} | grep -c . || true)
    qa_rows=\$(tail -n +2 ${checkm_qa_n50} | grep -c . || true)

    if [ "\${tax_rows}" -eq 0 ] || [ "\${qa_rows}" -eq 0 ]; then
        echo "No MAGs were placed or passed QC; writing an empty profile." >&2
        printf 'Taxonomy' > final_profile.tsv
        for f in *.abundance.tsv; do
            printf '\\t%s' "\$(basename "\$f" .abundance.tsv)" >> final_profile.tsv
        done
        printf '\\n' >> final_profile.tsv
    else
        Rscript ${projectDir}/bin/Rscripts/merge_tax_and_abundance.R \\
            -i . \\
            --tax ${phylophlan_relab} \\
            --qa ${checkm_qa_n50} \\
            --sgbs ${sgb_info} \\
            -o final_profile.tsv
    fi
    """
}
