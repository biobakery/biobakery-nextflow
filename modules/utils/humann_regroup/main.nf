#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Regroup HUMAnN gene families to a different annotation scheme.
// Optional, driven by params.humann_regroup_grouping.
process humann_regroup {
    tag "$sample"
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/regrouped" }, mode: 'copy'

    input:
    tuple val(sample), path(genefamilies)
    val subdir

    output:
    tuple val(sample), path("${sample}_${params.humann_regroup_grouping}_${params.humann_version}.tsv"), emit: regrouped

    when:
    params.run_humann_regroup

    script:
    """
    humann_regroup_table \\
        -i ${genefamilies} \\
        -g ${params.humann_regroup_grouping} \\
        -o ${sample}_${params.humann_regroup_grouping}_${params.humann_version}.tsv
    """
}

// Regroup UniRef gene families to level-4 enzyme commission numbers.
//
// Unlike humann_regroup above this is not optional and its grouping is not
// configurable: the ECs table is one of the three feature types the rest of the
// workflow is built on (merged, renormalised, counted, and — in mgx_mtx — fed
// to the RNA/DNA ratio), exactly as in biobakery_workflows 3.2.
process humann_regroup_ecs {
    tag "$sample"
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/regrouped" }, mode: 'copy'

    input:
    tuple val(sample), path(genefamilies)
    val subdir

    output:
    tuple val(sample), path("${sample}_ecs_${params.humann_version}.tsv"), emit: ecs

    script:
    // HUMAnN 4 builds its gene families against UniClust90 rather than UniRef90,
    // so the mapping file it needs is named differently. Matches the humann_v4
    // branch in biobakery_workflows.tasks.shotgun.functional_profile.
    def groups = (params.humann_version == 'humann_v4a') ? 'uniclust90_level4ec' : 'uniref90_level4ec'
    """
    humann_regroup_table \\
        -i ${genefamilies} \\
        -g ${groups} \\
        -o ${sample}_ecs_${params.humann_version}.tsv
    """
}
