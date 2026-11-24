#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Mantel test across all pairs of feature tables.
// Ports utilities.run_mantel_tests() (utilities.py 286-305).
//
// The test compares two matrices of the same dimension, so it only runs when
// more than one data set is present. The calling workflow enforces that.
process mantel_test {
    label 'stats_viz'
    publishDir path: { "${params.outdir}/${db ? "databases/${db}" : ""}/stats/mantel_test" }, mode: 'copy'

    input:
    tuple val(db), path(features)
    path metadata

    output:
    tuple val(db), path("mantel_plot.png"), emit: plot

    script:
    def input_files = features.collect { it.toString() }.join(',')
    """
    Rscript \$(python ${params.reporting_root}/bin/scripts/biobakery_bootstrap.py --rscript mantel_test) \\
        ${metadata} \\
        '${input_files}' \\
        mantel_plot.png \\
        --permutations ${params.stats_permutations}
    """
}
