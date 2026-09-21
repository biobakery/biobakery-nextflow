#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// BAQLaVa — viral profiling
process baqlava {
    tag "$sample"
    publishDir "${params.outdir}/baqlava", mode: 'copy'

    input:
    tuple val(sample),  path(kneads)
    tuple val(sample2), path(profile)

    output:
    tuple val(sample), path("${sample}_baqlava/"), emit: results

    when:
    params.run_viral_profiling

    script:

    def extra_args = params.baqlava_options ?: ""
    // Use taxonomic profile for bacterial depletion, or bypass for test/tiny samples with 0 detected species
    def depletion_flag = params.baqlava_bypass_depletion ? "--bypass-bacterial-depletion" : "--taxonomic-profile $profile"
    def db_flag        = params.baqlava_db               ? "--database ${params.baqlava_db}" : ""
    """
    baqlava \\
        -i $kneads \\
        $depletion_flag \\
        -o ${sample}_baqlava \\
        --threads ${task.cpus} \\
        --local-jobs 1 \\
        $db_flag \\
        $extra_args
    """
}
