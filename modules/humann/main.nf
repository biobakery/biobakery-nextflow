#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// HUMAnN — functional profiling
process humann {
    tag "$sample"
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/main" }, mode: 'copy'

    input:
    tuple val(sample),  path(catkneads)
    tuple val(sample2), path(profile)
    val subdir

    output:
    tuple val(sample), path("${sample}_genefamilies_${params.humann_version}.tsv"),   emit: genefamilies
    tuple val(sample), path("${sample}_pathabundance_${params.humann_version}.tsv"),  emit: pathabundance
    tuple val(sample), path("${sample}_pathcoverage_${params.humann_version}.tsv"),   emit: pathcoverage,  optional: true
    tuple val(sample), path("${sample}_reactions_${params.humann_version}.tsv"),      emit: reactions,     optional: true
    tuple val(sample), path("${sample}_humann_${params.humann_version}.log"),         emit: log,           optional: true

    when:
    params.run_functional_profiling

    script:

    def extra_args = params.humann_options ?: ""
    def bypass_prescreen  = params.humann_bypass_prescreen          ? "--bypass-prescreen"         : ""
    def bypass_nucleotide = params.humann_bypass_nucleotide_search   ? "--bypass-nucleotide-search" : ""
    def utility_db        = (params.humann_version == 'humann_v4a') ? "--utility-database ${params.humann_db}/utility_mapping" : ""
    """
    humann \\
        --input $catkneads \\
        --output . \\
        --taxonomic-profile $profile \\
        --nucleotide-database ${params.humann_db}/chocophlan \\
        --protein-database ${params.humann_db}/uniref \\
        $utility_db \\
        --threads ${task.cpus} \\
        --output-basename ${sample} \\
        $bypass_prescreen \\
        $bypass_nucleotide \\
        $extra_args

    # Rename outputs to versioned filenames
    if [ "${params.humann_version}" = "humann_v4a" ]; then
        mv ${sample}_0.log               ${sample}_humann_${params.humann_version}.log        2>/dev/null || true
        mv ${sample}_2_genefamilies.tsv  ${sample}_genefamilies_${params.humann_version}.tsv  2>/dev/null || true
        mv ${sample}_3_reactions.tsv     ${sample}_reactions_${params.humann_version}.tsv     2>/dev/null || true
        mv ${sample}_4_pathabundance.tsv ${sample}_pathabundance_${params.humann_version}.tsv 2>/dev/null || true
        mv ${sample}_5_pathcoverage.tsv  ${sample}_pathcoverage_${params.humann_version}.tsv  2>/dev/null || true
    else
        mv ${sample}_genefamilies.tsv    ${sample}_genefamilies_${params.humann_version}.tsv  2>/dev/null || true
        mv ${sample}_pathabundance.tsv   ${sample}_pathabundance_${params.humann_version}.tsv 2>/dev/null || true
        mv ${sample}_pathcoverage.tsv    ${sample}_pathcoverage_${params.humann_version}.tsv  2>/dev/null || true
    fi
    """
}
