#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { baqlava } from '../modules/viral/baqlava/main.nf'

// Viral profiling subworkflow: BAQLaVa
workflow VIRAL_PROFILING {

    take:
    reads    // Channel: [ [id: sample, paired_end: bool], reads ]
    profiles // Channel: [ sample, metaphlan_profile.tsv ]

    main:
    reads_flat = reads.map { meta, r -> tuple(meta.id, r) }

    // Join reads with their corresponding MetaPhlAn profile
    baqlava_input  = reads_flat.join(profiles)
    baqlava_reads  = baqlava_input.map { sample, reads, profile -> tuple(sample, reads) }
    baqlava_profile = baqlava_input.map { sample, reads, profile -> tuple(sample, profile) }

    baqlava_out = baqlava(baqlava_reads, baqlava_profile)

    emit:
    results = baqlava_out.results
}
