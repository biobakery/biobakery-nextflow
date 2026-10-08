#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Check one sample's raw reads for truncation and corruption
//
// Reads every file through once with bin/check_fastq_inputs.py: a gzip stream
// that ends early, a record cut short or malformed, an empty or unreadable
// file, mates of different lengths. The task always succeeds and reports the
// verdict in its table instead, so a bad sample is dropped by CHECK_INPUTS
// rather than failing the run -- see subworkflows/check_inputs.nf.
//
// Needs only python3, gzip, bzip2 and awk, which every node has, so no profile
// gives it an environment.
process check_reads {
    tag "$meta.id"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path(reads), path("${meta.id}.input_check.tsv"), emit: checked

    script:
    """
    check_fastq_inputs.py \\
        --sample ${meta.id} \\
        --output ${meta.id}.input_check.tsv \\
        --no-fail \\
        ${reads}
    """
}
