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
    // BAQLaVa has separate nucleotide/protein references, not --database.
    // baqlava_db remains a shorthand root for the upstream V0.5 layout.
    def root = params.baqlava_db?.toString()?.replaceAll('/+$', '')
    def references = [
        [flag: '--nucdb', path: params.baqlava_db_nucleotide ?: (root ? "${root}/BAQLaVa.V0.5.nucleotide" : null), type: 'directory'],
        [flag: '--protdb', path: params.baqlava_db_protein ?: (root ? "${root}/BAQLaVa.V0.5.protein" : null), type: 'directory'],
        [flag: '--nucindex', path: params.baqlava_nucleotide_mapping, type: 'file'],
        [flag: '--protindex', path: params.baqlava_protein_mapping, type: 'file'],
        [flag: null, path: params.baqlava_bypass_depletion ? null : params.baqlava_depletion_db, type: 'directory', humann_key: 'nucleotide'],
        [flag: null, path: params.baqlava_bypass_depletion ? null : params.baqlava_depletion_protein_db, type: 'directory', humann_key: 'protein'],
        [flag: null, path: params.baqlava_bypass_depletion ? null : params.baqlava_depletion_mapping_db, type: 'directory', humann_key: 'utility_mapping']
    ].findAll { it.path }.collect { it + [path: it.path.toString()] }
    if (workflow.profile.tokenize(',').any { it.startsWith('dnanexus') }) {
        if (!params.dnanexus_baqlava_container)
            error 'Set dnanexus_baqlava_container before enabling viral profiling on DNAnexus'
        if (!references.any { it.flag == '--nucdb' } || !references.any { it.flag == '--protdb' })
            error 'Set baqlava_db_nucleotide and baqlava_db_protein for DNAnexus viral profiling'
        if (!params.baqlava_bypass_depletion && !params.baqlava_depletion_db)
            error 'Set baqlava_depletion_db to the nucleotide database configured in the BAQLaVa image, or explicitly bypass depletion'
    }
    reads_flat = reads.map { meta, r -> tuple(meta.id, r) }

    baqlava_input = reads_flat.combine(profiles.map { db, s, f -> tuple(s, db, f) }, by: 0)
        .map { sample, reads, db, profile -> tuple(db, sample, reads, profile) }
    baqlava_out = baqlava(baqlava_input, references,
        Channel.value(database_inputs(params.baqlava_db_location,
        references.collect { it.path }, file("${projectDir}/assets/NO_FILE"))))

    emit:
    results = baqlava_out.results
}
