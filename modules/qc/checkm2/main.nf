#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// CheckM2 — assess MAG quality (completeness & contamination)
process checkm2 {
    tag "$sample"
    publishDir "${params.outdir}/checkm/${sample}", mode: 'copy'

    input:
    tuple val(sample), path(bins_dir)

    output:
    tuple val(sample), path("quality_report.tsv"), emit: quality

    script:
    def extra = params.checkm_predict_options ?: ""
    """
    if ls ${bins_dir}/*.bin.[0-9]*.fa 2>/dev/null | grep -q .; then
        checkm2 predict \\
            -x fa \\
            --input ${bins_dir} \\
            --output-directory checkm2_out/ \\
            --threads ${task.cpus} \\
            ${extra}
        mv checkm2_out/quality_report.tsv quality_report.tsv
    else
        # No valid bins — write header-only report
        echo -e "Name\tCompleteness\tContamination\tCompleteness_Model_Used\tTranslation_Table_Used\tCoding_Density\tContig_N50\tAverage_Gene_Length\tGenome_Size\tGC_Content\tTotal_Coding_Sequences\tAdditional_Notes" \
            > quality_report.tsv
    fi
    """
}

// Merge per-sample CheckM2 quality reports into one table
process checkm2_merge {
    publishDir "${params.outdir}/checkm", mode: 'copy'

    input:
    // CheckM2 names every sample's report quality_report.tsv -- see the note on
    // mag_n50 below.
    path reports, stageAs: 'quality_report_*.tsv'  // collected per-sample reports

    output:
    path "merged_quality_report.tsv", emit: merged

    script:
    """
    # Capture the input list first: the output is also a .tsv here, so a later
    # glob can pick the partial output up as one of its own inputs. It happens to
    # be safe today only because "merged_" sorts before the staged input names.
    ls quality_report_*.tsv | sort > .checkm2_inputs.txt
    head -1 \$(head -1 .checkm2_inputs.txt) > merged_quality_report.tsv
    for f in \$(cat .checkm2_inputs.txt); do
        tail -n +2 "\$f" >> merged_quality_report.tsv
    done
    """
}

// Compute N50 for each MAG bin
process mag_n50 {
    publishDir "${params.outdir}/checkm/n50", mode: 'copy'

    input:
    // Every sample's directory is called "bins", so staging them under their own
    // names collides as soon as there is more than one sample. stageAs numbers
    // them; mag_n50_calc.py walks the whole input tree for *.fa, and the bin
    // files inside are already sample-prefixed.
    path bins_dirs, stageAs: 'bins_*'  // collected bins/ directories from all samples

    output:
    path "mags_n50.tsv", emit: n50

    script:
    """
    # -o is a directory: the script writes <dir>/mags_n50.tsv
    python ${projectDir}/bin/scripts/mag_n50_calc.py \\
        -i . \\
        -o . \\
        -t ${task.cpus}
    """
}

// Merge CheckM2 QA with N50 stats and filter by completeness/contamination thresholds
process checkm2_wrangling {
    publishDir "${params.outdir}/checkm/qa", mode: 'copy'

    input:
    path quality_report
    path n50_report

    output:
    path "checkm_qa_and_n50.tsv", emit: qa_n50

    script:
    def completeness   = params.sgb_completeness   ?: 50
    def contamination  = params.sgb_contamination  ?: 10
    """
    python ${projectDir}/bin/scripts/checkm_wrangling.py \\
        --checkm-qa ${quality_report} \\
        --n50 ${n50_report} \\
        --out_file checkm_qa_and_n50.tsv \\
        --completeness ${completeness} \\
        --contamination ${contamination}
    """
}
