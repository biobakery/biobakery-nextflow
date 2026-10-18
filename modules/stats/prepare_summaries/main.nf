nextflow.enable.dsl=2

process prepare_report_summaries {
    label 'stats_viz'
    tag "$db"

    input:
    tuple val(db), path(source)

    output:
    tuple val(db), path('report_data'), emit: folder

    script:
    """
    python ${params.reporting_root}/bin/scripts/prepare_report_summaries.py \\
        --input '${source}' --output report_data \\
        --humann-version '${params.humann_version}'
    """
}
