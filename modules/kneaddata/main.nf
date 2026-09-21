#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// KneadData QC — single-end reads
//
// db_args is a pre-formed "--reference-db A --reference-db B ..." string rather
// than a list: a Groovy List handed to a process `val` input is implicitly
// converted with Channel.from(), which would fan the databases out into one
// task per database instead of one task with several databases.
//
// subdir places the published output under a per-assay folder ('' for a plain
// mgx run, 'whole_metatranscriptome_shotgun/' for the mtx half of mgx_mtx), so
// the two halves of mgx_mtx do not overwrite each other's merged tables.
process single_end_kneaddata {
    tag "$sample"
    publishDir path: { "${params.outdir}/${subdir}kneaddata" }, mode: 'copy'

    input:
    tuple val(sample), path(reads)
    val db_args
    val subdir

    output:
    tuple val(sample), path("${sample}_kneaddata.fastq.gz"),      emit: kneads
    tuple val(sample), path("${sample}_kneaddata.log"),            emit: log
    tuple val(sample), path("${sample}_kneaddata*.fastq.gz"),      emit: others, optional: true

    when:
    params.run_qc

    script:

    def extra_args = params.kneaddata_options ?: ""
    def bypass      = params.kneaddata_bypass_trim               ? "--bypass-trim"                  : ""
    def remove_inter = params.kneaddata_remove_intermediate_files ? "--remove-intermediate-output"   : ""
    """
    kneaddata \\
        --unpaired $reads \\
        $db_args \\
        --output ./ \\
        --threads ${task.cpus} \\
        --output-prefix ${sample}_kneaddata \\
        $bypass \\
        $remove_inter \\
        $extra_args

    for f in *.fastq; do [ -f "\$f" ] && pigz -p ${task.cpus} "\$f"; done
    """
}

// KneadData QC — paired-end reads
process paired_end_kneaddata {
    tag "$sample"
    publishDir path: { "${params.outdir}/${subdir}kneaddata" }, mode: 'copy',
        saveAs: { fn -> fn.endsWith('_concatenated.fastq.gz') ? null : fn }

    input:
    tuple val(sample), path(reads)
    val db_args
    val subdir

    output:
    tuple val(sample), path("${sample}_concatenated.fastq.gz"),       emit: kneads
    tuple val(sample), path("${sample}_kneaddata.log"),                emit: log
    tuple val(sample), path("${sample}_kneaddata_paired_1.fastq.gz"),  emit: paired1,   optional: true
    tuple val(sample), path("${sample}_kneaddata_paired_2.fastq.gz"),  emit: paired2,   optional: true
    tuple val(sample), path("${sample}_kneaddata_unmatched_1.fastq.gz"), emit: unpaired1, optional: true
    tuple val(sample), path("${sample}_kneaddata_unmatched_2.fastq.gz"), emit: unpaired2, optional: true

    when:
    params.run_qc

    script:

    def extra_args = params.kneaddata_options ?: ""
    def bypass       = params.kneaddata_bypass_trim               ? "--bypass-trim"                 : ""
    def remove_inter = params.kneaddata_remove_intermediate_files ? "--remove-intermediate-output"  : ""
    """
    kneaddata \\
        -i1 ${reads[0]} \\
        -i2 ${reads[1]} \\
        $db_args \\
        --output ./ \\
        --processes ${task.cpus} \\
        --output-prefix ${sample}_kneaddata \\
        $bypass \\
        $remove_inter \\
        $extra_args

    for f in *.fastq; do [ -f "\$f" ] && pigz -p ${task.cpus} "\$f"; done

    cat ${sample}_kneaddata_paired_1.fastq.gz \\
        ${sample}_kneaddata_paired_2.fastq.gz \\
        ${sample}_kneaddata_unmatched_1.fastq.gz \\
        ${sample}_kneaddata_unmatched_2.fastq.gz \\
        > ${sample}_concatenated.fastq.gz
    """
}

// Compile the per-sample KneadData logs into one read count table.
//
// Ports shotgun.kneaddata_read_count_table (tasks/shotgun.py:165). The table is
// what the vis report's quality control section is built from, and
// files.ShotGun looks for it by name under kneaddata/merged, so it is published
// there rather than beside the logs.
process kneaddata_read_counts {
    publishDir path: { "${params.outdir}/${subdir}kneaddata/merged" }, mode: 'copy'

    input:
    path logs, stageAs: 'logs/*'
    val subdir

    output:
    path "kneaddata_read_count_table.tsv", emit: counts

    script:
    """
    kneaddata_read_count_table \\
        --input logs \\
        --output kneaddata_read_count_table.tsv
    """
}
