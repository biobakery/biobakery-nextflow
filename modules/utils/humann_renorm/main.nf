#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Renormalise a per-sample HUMAnN table from RPK to relative abundance.
//
// "feature" is one of genefamilies | ecs | pathabundance, and is carried through
// the channel so a single process definition covers all three, as the
// add_task_group in biobakery_workflows 3.2 does.
//
// --special n excludes the UNMAPPED / UNINTEGRATED rows from the sum, so the
// relative abundances are over classified features only.
process humann_renorm {
    tag "${sample}:${feature}"
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/relab/${feature}" }, mode: 'copy'

    input:
    tuple val(sample), val(feature), path(table)
    val subdir

    output:
    tuple val(sample), val(feature), path("${sample}_${feature}_relab_${params.humann_version}.tsv"), emit: relab

    script:
    """
    humann_renorm_table \\
        --input ${table} \\
        --output ${sample}_${feature}_relab_${params.humann_version}.tsv \\
        --units relab \\
        --special n
    """
}
