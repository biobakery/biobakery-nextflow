#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Beta diversity and PERMANOVA.
// Ports utilities.run_beta_diversity() (utilities.py 398-464) and
// utilities.run_permanova() (utilities.py 369-395).
//
// stats.py runs the PERMANOVA for longitudinal studies -- those with random
// effects set -- and beta diversity otherwise. The calling workflow makes that
// choice; these processes just run what they are given.

// One beta diversity analysis for one feature table.
// analysis is one of univariate | multivariate | pairwise.
process beta_diversity {
    tag "${analysis}:${feature_type}"
    publishDir "${params.outdir}/stats/beta_diversity", mode: 'copy'

    input:
    tuple val(feature_type), path(features), val(analysis), val(covariate_equation)
    path metadata

    output:
    path "${feature_type}_${analysis}.png", emit: plot

    script:
    def adonis_opt = params.stats_adonis_method ? "--adonis_method ${params.stats_adonis_method}" : ''
    def analysis_opt = ''
    if (analysis == 'multivariate')
        analysis_opt = "--covariate_equation='${covariate_equation}'"
    else if (analysis == 'pairwise')
        analysis_opt = '--pairwise TRUE'
    """
    Rscript \$(python ${projectDir}/bin/scripts/biobakery_bootstrap.py --rscript beta_diversity) \\
        ${features} \\
        ${metadata} \\
        ${feature_type}_${analysis}.png \\
        --min_abundance ${params.stats_min_abundance} \\
        --min_prevalence ${params.stats_min_prevalence} \\
        --max_missing ${params.max_missing} \\
        ${analysis_opt} ${adonis_opt}
    """
}

// PERMANOVA across every feature table at once, for longitudinal studies.
process permanova {
    publishDir "${params.outdir}/stats/permanova", mode: 'copy'

    input:
    path features
    path metadata

    output:
    // the script derives permanova_<feature type>.png alongside permanova.png
    path "permanova*.png", emit: plots

    script:
    def input_files = features.collect { it.toString() }.join(',')
    """
    Rscript \$(python ${projectDir}/bin/scripts/biobakery_bootstrap.py --rscript permanova_hmp2) \\
        '${input_files}' \\
        ${metadata} \\
        permanova.png \\
        --scale ${params.stats_scale} \\
        --min_abundance ${params.stats_min_abundance} \\
        --min_prevalence ${params.stats_min_prevalence} \\
        --permutations ${params.stats_permutations} \\
        --static_covariates ${params.stats_static_covariates}
    """
}
