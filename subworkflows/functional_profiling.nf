#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { humann }                     from '../modules/humann/main.nf'
include { humann_regroup }             from '../modules/utils/humann_regroup/main.nf'
include { humann_regroup_ecs }         from '../modules/utils/humann_regroup/main.nf'
include { humann_rename }              from '../modules/utils/humann_rename/main.nf'
include { humann_renorm }              from '../modules/utils/humann_renorm/main.nf'
include { humann_join }                from '../modules/utils/humann_merge/main.nf'
include { humann_join as humann_join_relab } from '../modules/utils/humann_merge/main.nf'
include { humann_count_features }      from '../modules/utils/humann_merge/main.nf'
include { humann_feature_counts_merge } from '../modules/utils/humann_merge/main.nf'
include { humann_log_counts }          from '../modules/utils/humann_merge/main.nf'

// Functional profiling subworkflow: HUMAnN, then the three feature types
// (gene families, ECs, pathway abundances) through merge → renormalise →
// merge → feature counts, following biobakery_workflows 3.2
// tasks/shotgun.py:functional_profile.
workflow FUNCTIONAL_PROFILING {

    take:
    reads    // Channel: [ [id: sample, paired_end: bool], reads ]
    profiles // Channel: [ sample, metaphlan_profile.tsv ]
    subdir   // '' or a trailing-slash output subfolder

    main:
    reads_flat = reads.map { meta, r -> tuple(meta.id, r) }

    // Each sample's reads must be paired with its MetaPhlAn profile
    humann_input = reads_flat.join(profiles)

    humann_reads   = humann_input.map { sample, reads, profile -> tuple(sample, reads) }
    humann_profile = humann_input.map { sample, reads, profile -> tuple(sample, profile) }

    humann_out = humann(humann_reads, humann_profile, subdir)

    // ── ECs: regroup gene families to level-4 enzyme commission numbers ────
    ecs_out = humann_regroup_ecs(humann_out.genefamilies, subdir)

    // ── Optional regroup to a user-chosen scheme, plus human-readable names ─
    regroup_out = humann_regroup(humann_out.genefamilies, subdir)
    rename_out  = humann_rename(regroup_out.regrouped, subdir)

    // ── The three feature types, tagged so one process covers all of them ───
    tagged = humann_out.genefamilies.map  { s, f -> tuple(s, 'genefamilies',  f) }
        .mix( ecs_out.ecs.map             { s, f -> tuple(s, 'ecs',           f) } )
        .mix( humann_out.pathabundance.map { s, f -> tuple(s, 'pathabundance', f) } )

    // ── Merge the RPK tables, one join per feature type ────────────────────
    // groupTuple over the feature tag rather than .collect(), so each join task
    // sees only its own feature type.
    by_feature = tagged.map { s, feature, f -> tuple(feature, f) }.groupTuple()
    merged_out = humann_join(by_feature, subdir)

    // ── Renormalise each per-sample table to relative abundance, then merge ─
    relab_out = humann_renorm(tagged, subdir)

    by_feature_relab = relab_out.relab
        .map { s, feature, f -> tuple("${feature}_relab".toString(), f) }
        .groupTuple()
    merged_relab_out = humann_join_relab(by_feature_relab, subdir)

    // ── Feature counts from the merged relative abundance tables ───────────
    // Strip the _relab suffix again so the count files are named for the
    // feature type, as humann_<feature>_relab_counts.tsv upstream.
    counts_in  = merged_relab_out.merged.map { label, f -> tuple(label - ~/_relab$/, f) }
    counts_out = humann_count_features(counts_in, subdir)
    feature_counts_out = humann_feature_counts_merge(
        counts_out.counts.map { label, f -> f }.collect(), subdir)

    // Read and species counts, from the per-sample logs. The log is an optional
    // HUMAnN output, so the filter skips the step rather than running it on an
    // empty folder when no sample produced one.
    log_counts_out = humann_log_counts(
        humann_out.log.map { sample, l -> l }.collect().filter { it.size() > 0 }, subdir)

    // Pick the individual merged tables back out of the keyed channel. These
    // are the RPK tables, which is what the RNA/DNA ratio in mgx_mtx needs.
    merged_genefamilies_ch  = merged_out.merged.filter { label, f -> label == 'genefamilies'  }.map { label, f -> f }
    merged_ecs_ch           = merged_out.merged.filter { label, f -> label == 'ecs'           }.map { label, f -> f }
    merged_pathabundance_ch = merged_out.merged.filter { label, f -> label == 'pathabundance' }.map { label, f -> f }

    emit:
    genefamilies  = humann_out.genefamilies
    pathabundance = humann_out.pathabundance
    pathcoverage  = humann_out.pathcoverage
    ecs           = ecs_out.ecs
    regrouped     = regroup_out.regrouped
    renamed       = rename_out.renamed
    // merged RPK tables, one file each
    merged_genefamilies  = merged_genefamilies_ch
    merged_ecs           = merged_ecs_ch
    merged_pathabundance = merged_pathabundance_ch
    // merged relative abundance tables
    merged_relab         = merged_relab_out.merged
    feature_counts       = feature_counts_out.feature_counts
    log_counts           = log_counts_out.counts
    // Everything a bioBakery-standard report folder wants from HUMAnN, as flat
    // channels of files: see modules/utils/report_input.
    merged_tables = merged_out.merged.map { label, f -> f }
        .mix( merged_relab_out.merged.map { label, f -> f } )
    count_tables  = counts_out.counts.map { label, f -> f }
        .mix( feature_counts_out.feature_counts )
        .mix( log_counts_out.counts )
}
