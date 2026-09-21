#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { single_end_kneaddata } from '../modules/kneaddata/main.nf'
include { paired_end_kneaddata } from '../modules/kneaddata/main.nf'
include { kneaddata_read_counts } from '../modules/kneaddata/main.nf'

// Quality control subworkflow: host decontamination + trimming via KneadData
workflow QUALITY_CONTROL {

    take:
    reads    // Channel: [ [id: sample, paired_end: bool], reads ]
    dbs      // List of KneadData reference database paths
    subdir   // '' or a trailing-slash output subfolder, e.g. 'whole_metatranscriptome_shotgun/'

    main:
    // A metagenome run decontaminates against the host genome only; a
    // metatranscriptome run additionally removes host mRNA and rRNA, which is
    // why the database set is a parameter rather than params.host_genome.
    def db_paths = (dbs instanceof List ? dbs : [dbs]).findAll { it }
    if (!db_paths) {
        error "ERROR: no KneadData reference database configured. Set --host_genome " +
              "(and --host_transcriptome / --rrna_db for metatranscriptome input)."
    }
    // Pre-formed argument string: see the note in modules/kneaddata/main.nf on
    // why a List must not be handed to a process val input.
    def db_args = db_paths.collect { "--reference-db ${it}" }.join(' ')

    // Split channel by library type
    paired_reads = reads
        .filter  { meta, r -> meta.paired_end }
        .map     { meta, r -> tuple(meta.id, r) }

    single_reads = reads
        .filter  { meta, r -> !meta.paired_end }
        .map     { meta, r -> tuple(meta.id, r) }

    paired_out = paired_end_kneaddata(paired_reads, db_args, subdir)
    single_out = single_end_kneaddata(single_reads, db_args, subdir)

    // Re-attach meta map so downstream subworkflows get consistent channel shape
    cleaned_paired = paired_out.kneads.map { sample, reads -> [ [id: sample, paired_end: true],  reads ] }
    cleaned_single = single_out.kneads.map { sample, reads -> [ [id: sample, paired_end: false], reads ] }

    all_cleaned = cleaned_paired.mix(cleaned_single)
    all_logs    = paired_out.log.mix(single_out.log)

    // One read count table for the run, which is what the vis report's quality
    // control section reads.
    read_counts_out = kneaddata_read_counts(all_logs.map { sample, l -> l }.collect(), subdir)

    // The four separate KneadData outputs, for consumers that need the pairing
    // rather than the concatenated file: assembly runs MEGAHIT in paired mode
    // (-1/-2 plus the unmatched reads as single-end), matching the anadama2
    // assembly workflow.
    paired_parts = paired_out.paired1
        .join(paired_out.paired2)
        .join(paired_out.unpaired1)
        .join(paired_out.unpaired2)
        .map { sample, p1, p2, u1, u2 -> tuple(sample, [p1, p2, u1, u2]) }

    emit:
    reads = all_cleaned  // Channel: [ [id, paired_end], cleaned_reads ]
    // named "logs", not "log": Nextflow already binds "log" to its own logger,
    // so emitting that name fails at runtime with "No such variable: log"
    logs  = all_logs
    read_counts = read_counts_out.counts
    // Channel: [ sample, [paired_1, paired_2, unmatched_1, unmatched_2] ]
    paired_reads = paired_parts
}
