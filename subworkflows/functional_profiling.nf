#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { database_inputs } from './database_access.nf'

include { humann }                     from '../modules/humann/main.nf'
include { humann_regroup }             from '../modules/utils/humann_regroup/main.nf'
include { humann_rename }              from '../modules/utils/humann_rename/main.nf'
include { humann_renorm }              from '../modules/utils/humann_renorm/main.nf'
include { humann_join }                from '../modules/utils/humann_merge/main.nf'
include { humann_join as humann_join_relab } from '../modules/utils/humann_merge/main.nf'

// HUMAnN native tables and any configured mappings flow through merging
// and relative abundance normalization. No annotation mapping is mandatory.
workflow FUNCTIONAL_PROFILING {

    take:
    reads    // Channel: [ [output_label: sample, paired_end: bool], reads ]
    profiles // Channel: [ database context, sample, metaphlan_profile.tsv ]
    subdir   // '' or a trailing-slash output subfolder

    main:
    def mappings = params.humann_regroups
    if (!(mappings instanceof List))
        error 'humann_regroups must be an array; use [] to disable regrouping'
    mappings = mappings.collect { entry ->
        if (!(entry instanceof Map) || !entry.output_label ||
            !(entry.output_label.toString() ==~ /[A-Za-z0-9][A-Za-z0-9_.-]*/) ||
            entry.output_label in ['genefamilies', 'pathabundance', 'pathcoverage', 'genes', 'paths'] || entry.output_label.toString().endsWith('_relab'))
            error 'Each HUMAnN regroup needs a safe, unique output_label that is not a reserved feature name'
        if ((!entry.groups && !entry.group_mapping_database) || (entry.groups && entry.group_mapping_database))
            error "HUMAnN regroup ${entry.output_label}: supply exactly one of groups or group_mapping_database"
        if (entry.rename != null && !(entry.rename instanceof String))
            error "HUMAnN regroup ${entry.output_label}: rename must be a names scheme string or null"
        if (entry.rename && entry.renaming_database)
            error "HUMAnN regroup ${entry.output_label}: supply rename or renaming_database, not both"
        def location = entry.database_location ?: params.humann_db_location
        if (!(location in ['host', 'container']))
            error "HUMAnN regroup ${entry.output_label}: database_location must be host or container"
        [database_location: location, output_label: entry.output_label.toString(), groups: entry.groups, group_mapping_database: resolve_mapping_database(entry.group_mapping_database, params.humann_db_utilitymapping),
         rename: entry.rename, renaming_database: resolve_mapping_database(entry.renaming_database, params.humann_db_utilitymapping)]
    }
    if (mappings.collect { it.output_label }.unique(false).size() != mappings.size())
        error 'humann_regroups output_label values must be unique'
    if (!params.run_humann_regroup) mappings = []
    def no_mapping = file("${projectDir}/assets/NO_FILE")

    reads_flat = reads.map { meta, r -> tuple(meta.id, r) }

    // combine(by: 0) supports multiple database profiles per sample.
    humann_input = reads_flat.combine(profiles.map { db, s, f -> tuple(s, db, f) }, by: 0)
        .map { sample, reads, db, profile -> tuple(db, sample, reads, profile) }
    humann_out = humann(humann_input,
        Channel.value(database_inputs(params.humann_db_location,
            [params.humann_db_chocophlan, params.humann_db_protein, params.humann_db_utilitymapping], no_mapping)), subdir)

    // Fan out independently for every sample, database context and mapping.
    regroup_input = humann_out.genefamilies.combine(Channel.fromList(mappings))
        .map { db, sample, genes, mapping ->
            tuple(db, sample, mapping, genes,
                mapping.group_mapping_database && mapping.database_location == 'host' ? file(mapping.group_mapping_database, checkIfExists: true) : no_mapping)
        }
    regroup_out = humann_regroup(regroup_input, subdir)
    rename_out = humann_rename(regroup_out.regrouped.filter { db, sample, mapping, f ->
        params.run_humann_rename && (mapping.rename || mapping.renaming_database)
    }.map { db, sample, mapping, f ->
        tuple(db, sample, mapping, f,
            mapping.renaming_database && mapping.database_location == 'host' ? file(mapping.renaming_database, checkIfExists: true) : no_mapping)
    }, subdir)

    // Keep stable mapping identifiers in matrices; renamed tables are optional
    // companion outputs so labels cannot break RNA/DNA feature matching.
    tagged = humann_out.genefamilies.map { db, s, f -> tuple(db, s, 'genefamilies', f) }
        .mix(humann_out.pathabundance.map { db, s, f -> tuple(db, s, 'pathabundance', f) })
        .mix(regroup_out.regrouped.map { db, s, mapping, f -> tuple(db, s, mapping.output_label, f) })

    // ── Merge the RPK tables, one join per feature type ────────────────────
    // groupTuple over the feature tag rather than .collect(), so each join task
    // sees only its own feature type.
    by_feature = tagged.map { db, s, feature, f -> tuple([db, feature], f) }.groupTuple().map { key, fs -> tuple(key[0], key[1], fs) }
    merged_out = humann_join(by_feature, subdir)

    // ── Renormalise each per-sample table to relative abundance, then merge ─
    relab_out = humann_renorm(tagged, subdir)

    by_feature_relab = relab_out.relab
        .map { db, s, feature, f -> tuple([db, "${feature}_relab".toString()], f) }
        .groupTuple().map { key, fs -> tuple(key[0], key[1], fs) }
    merged_relab_out = humann_join_relab(by_feature_relab, subdir)

    // Pick the individual merged tables back out of the keyed channel. These
    // are the RPK tables, which is what the RNA/DNA ratio in mgx_mtx needs.
    merged_genefamilies_ch  = merged_out.merged.filter { db, label, f -> label == 'genefamilies'  }.map { db, label, f -> tuple(db, f) }
    merged_ecs_ch           = merged_out.merged.filter { db, label, f -> label == 'ecs'           }.map { db, label, f -> tuple(db, f) }
    merged_pathabundance_ch = merged_out.merged.filter { db, label, f -> label == 'pathabundance' }.map { db, label, f -> tuple(db, f) }

    emit:
    genefamilies  = humann_out.genefamilies
    pathabundance = humann_out.pathabundance
    pathcoverage  = humann_out.pathcoverage
    regrouped     = regroup_out.regrouped
    renamed       = rename_out.renamed
    // merged RPK tables, one file each
    merged_genefamilies  = merged_genefamilies_ch
    merged_ecs           = merged_ecs_ch
    merged_pathabundance = merged_pathabundance_ch
    // merged relative abundance tables
    merged = merged_out.merged
    merged_relab         = merged_relab_out.merged
    logs = humann_out.log.map { db, sample, f -> tuple(db, f) }
    // Everything a bioBakery-standard report folder wants from HUMAnN, as flat
    // channels of files: see modules/utils/report_input.
    merged_tables = merged_out.merged.map { db, label, f -> tuple(db, f) }
        .mix( merged_relab_out.merged.map { db, label, f -> tuple(db, f) } )
}

// YAML paths are literal strings; resolve relative mapping filenames explicitly.
def resolve_mapping_database(value, root) {
    if (!value) return null
    def path = value.toString()
    if (path.startsWith('/') || path ==~ /^[A-Za-z][A-Za-z0-9+.-]*:.*$/) return path
    if (!root) error 'Relative mapping database filenames require --humann_db_utilitymapping'
    return "${root.toString().replaceAll('/+$', '')}/${path}"
}
