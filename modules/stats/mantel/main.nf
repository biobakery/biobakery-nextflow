#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Mantel test across all pairs of feature tables.
// Ports utilities.run_mantel_tests() (utilities.py 286-305).
//
// The test compares two matrices of the same dimension, so it only runs when
// more than one data set is present. The calling workflow enforces that.
process mantel_test {
    publishDir "${params.outdir}/stats/mantel_test", mode: 'copy'

    input:
    path features
    path metadata

    output:
    path "mantel_plot.png", emit: plot

    script:
    def input_files = features.collect { it.toString() }.join(',')
    """
    Rscript \$(python ${projectDir}/bin/scripts/biobakery_bootstrap.py --rscript mantel_test) \\
        ${metadata} \\
        '${input_files}' \\
        mantel_plot.png \\
        --permutations ${params.stats_permutations}
    """
}
