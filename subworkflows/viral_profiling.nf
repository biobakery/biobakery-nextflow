#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { database_inputs } from './database_access.nf'
include { baqlava } from '../modules/viral/baqlava/main.nf'

// Viral profiling subworkflow: BAQLaVa
workflow VIRAL_PROFILING {

    take:
    reads    // Channel: [ [id: sample, paired_end: bool], reads ]
    profiles // Channel: [ database context, sample, metaphlan_profile.tsv ]

    main:
    reads_flat = reads.map { meta, r -> tuple(meta.id, r) }

    baqlava_input = reads_flat.combine(profiles.map { db, s, f -> tuple(s, db, f) }, by: 0)
        .map { sample, reads, db, profile -> tuple(db, sample, reads, profile) }
    baqlava_out = baqlava(baqlava_input, Channel.value(database_inputs(params.baqlava_db_location,
        params.baqlava_db, file("${projectDir}/assets/NO_FILE"))))

    emit:
    results = baqlava_out.results
}
