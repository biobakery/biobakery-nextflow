#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Work out the multivariate covariate equation for the beta diversity models.
// Ports the equation-building portion of utilities.run_beta_diversity()
// (utilities.py 406-421).
//
// AnADAMA computes this while building the DAG, and uses it to decide whether
// the multivariate and pairwise beta diversity tasks exist at all. Nextflow
// needs the same answer at runtime, so it is emitted as JSON for the workflow
// to branch on.
process covariate_equation {
    publishDir "${params.outdir}/stats", mode: 'copy'

    input:
    path manifest

    output:
    path "covariate_equation.json", emit: json

    script:
    """
    python ${projectDir}/bin/scripts/stats_covariate_equation.py \\
        --manifest ${manifest} \\
        --output covariate_equation.json \\
        --fixed-effects '${params.stats_fixed_effects}' \\
        --multivariable-fixed-effects '${params.stats_multivariable_fixed_effects}' \\
        --random-effects '${params.stats_random_effects}'
    """
}
