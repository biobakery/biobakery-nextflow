#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { metaphlan }       from '../modules/metaphlan/main.nf'
include { metaphlan_bzip }  from '../modules/metaphlan/main.nf'
include { metaphlan_merge } from '../modules/metaphlan/main.nf'
include { metaphlan_species_counts } from '../modules/metaphlan/main.nf'

// Taxonomic profiling subworkflow: MetaPhlAn per sample + merged table
workflow TAXONOMIC_PROFILING {

    take:
    reads   // Channel: [ [id: sample, paired_end: bool], reads ]
    subdir  // '' or a trailing-slash output subfolder

    main:
    reads_flat = reads.map { meta, r -> tuple(meta.id, r) }

    metaphlan_out      = metaphlan(reads_flat, subdir)
    metaphlan_bzip_out = metaphlan_bzip(metaphlan_out.sam, subdir)

    // Collect all per-sample profiles and merge
    profiles_collected = metaphlan_out.profile.map { s, f -> f }.collect()
    merged_out         = metaphlan_merge(profiles_collected, subdir)
    species_counts_out = metaphlan_species_counts(merged_out.merged, subdir)

    emit:
    profile  = metaphlan_out.profile       // per-sample: [ sample, profile.tsv ]
    sam      = metaphlan_out.sam           // per-sample: [ sample, .sam ]
    sam_bzip = metaphlan_bzip_out.sam_bzip // per-sample: [ sample, .sam.bz2 ]
    merged   = merged_out.merged           // single merged table
    species_counts = species_counts_out.counts
}
