#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { database_inputs } from './database_access.nf'

include { metaphlan }       from '../modules/metaphlan/main.nf'
include { metaphlan_bzip }  from '../modules/metaphlan/main.nf'
include { metaphlan_merge } from '../modules/metaphlan/main.nf'

// Taxonomic profiling subworkflow: MetaPhlAn per sample + merged table
workflow TAXONOMIC_PROFILING {

    take:
    reads   // Channel: [ [id: sample, paired_end: bool], reads ]
    subdir  // '' or a trailing-slash output subfolder

    main:
    // Keep legacy single-database configuration working when no array is supplied.
    def databases = params.metaphlan_databases != null ? params.metaphlan_databases : [[
        metaphlan_db: params.metaphlan_db,
        metaphlan_index: params.metaphlan_index,
        metaphlan_version: params.metaphlan_version
    ]]
    if (!(databases instanceof List) || !databases) {
        error 'metaphlan_databases must be a non-empty array of objects'
    }
    databases = databases.collect { entry ->
        if (!(entry instanceof Map) || !entry.metaphlan_db || !entry.metaphlan_index) {
            error 'Each metaphlan_databases entry requires metaphlan_db and metaphlan_index'
        }
        if (entry.metaphlan_index.toString() in ['.', '..'] || !(entry.metaphlan_index.toString() ==~ /[A-Za-z0-9_.-]+/)) {
            error 'metaphlan_index must contain only letters, numbers, dots, underscores, or hyphens'
        }
        def db_path = entry.metaphlan_db.toString()
        if (!db_path.startsWith('/') && !(db_path ==~ /^[A-Za-z][A-Za-z0-9+.-]*:.*$/)) {
            if (!params.metaphlan_db_root)
                error 'Relative metaphlan_db entries require --metaphlan_db_root'
            db_path = "${params.metaphlan_db_root.toString().replaceAll('/+$', '')}/${db_path}"
        }
        [metaphlan_db: db_path,
         metaphlan_index: entry.metaphlan_index,
         metaphlan_version: entry.metaphlan_version ?: params.metaphlan_version]
    }
    if (databases.collect { it.metaphlan_index }.unique().size() != databases.size()) {
        error 'metaphlan_databases entries must have unique metaphlan_index values'
    }
    def selected = params.metaphlan_downstream_indices != null ? params.metaphlan_downstream_indices : [databases[0].metaphlan_index]
    if (!(selected instanceof List) || !selected || selected.unique(false).size() != selected.size() ||
        selected.any { index -> !databases.any { it.metaphlan_index == index } }) {
        error 'metaphlan_downstream_indices must be a non-empty array of unique configured metaphlan_index values'
    }
    def context = { db -> params.metaphlan_databases != null ? db.metaphlan_index : '' }
    reads_flat = reads.map { meta, r -> tuple(meta.id, r) }
        .combine(Channel.fromList(databases))
        .map { sample, r, db -> tuple(db, sample, r,
            database_inputs(params.metaphlan_db_location, db.metaphlan_db, file("${projectDir}/assets/NO_FILE"))) }

    metaphlan_out      = metaphlan(reads_flat, subdir)
    metaphlan_bzip_out = metaphlan_bzip(metaphlan_out.sam, subdir)

    // Merge samples only within the same database.
    profiles_collected = metaphlan_out.profile
        .map { db, sample, profile -> tuple(db, profile) }
        .groupTuple()
    merged_out         = metaphlan_merge(profiles_collected, subdir)

    emit:
    // Only selected databases feed downstream steps; keep their identity.
    profile = metaphlan_out.profile.filter { db, s, f -> db.metaphlan_index in selected }
        .map { db, s, f -> tuple(context(db), s, f) }
    sam = metaphlan_out.sam.filter { db, s, f -> db.metaphlan_index in selected }
        .map { db, s, f -> tuple(context(db), s, f) }
    sam_bzip = metaphlan_bzip_out.sam_bzip.filter { db, s, f -> db.metaphlan_index in selected }
        .map { db, s, f -> tuple(context(db), s, f) }
    merged = merged_out.merged.filter { db, f -> db.metaphlan_index in selected }.map { db, f -> tuple(context(db), f) }
    all_profiles = metaphlan_out.profile
    all_merged = merged_out.merged
}
