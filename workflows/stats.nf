#!/usr/bin/env nextflow
nextflow.enable.dsl=2

import groovy.json.JsonSlurperClassic
include { prepare_report_summaries } from '../modules/stats/prepare_summaries/main.nf' 

include { identify_inputs }                        from '../modules/vis/identify_inputs/main.nf'
include { feature_table; trim_taxonomy }           from '../modules/stats/feature_table/main.nf'
include { maaslin2 }                               from '../modules/stats/maaslin2/main.nf'
include { halla; halla_transpose_metadata }        from '../modules/stats/halla/main.nf'
include { mantel_test }                            from '../modules/stats/mantel/main.nf'
include { beta_diversity; permanova }              from '../modules/stats/beta_diversity/main.nf'
include { covariate_equation }                     from '../modules/stats/covariate_equation/main.nf'
include { stratified_metadata; stratified_barplot } from '../modules/stats/stratified_pathways/main.nf'
include { stats_report }                           from '../modules/stats/report/main.nf'
include { archive_output }                         from '../modules/utils/archive/main.nf'

// Statistics workflow — the Nextflow port of `biobakery_workflows stats`.
//
// The AnADAMA workflow builds a genuinely parallel DAG, which maps directly
// onto Nextflow processes. The one stage that is not a line-by-line
// translation is the stratified pathway barplots: AnADAMA decides how many to
// build at DAG-construction time by reading MaAsLin2's significant_results.tsv
// and the metadata in Python, so here that becomes a runtime fan-out over a
// plan emitted as JSON.
// The folder arrives as a channel for the same reason it does in VIS -- see
// the note there.
workflow STATS {

    take:
    source_dir_ch // [database context, bioBakery output folder]; empty context for standalone runs

    main:
    input_dir_ch = prepare_report_summaries(source_dir_ch).folder
    def no_file = file("${projectDir}/assets/NO_FILE")

    // stats.py marks --input-metadata as required
    if (!params.input_metadata)
        error "ERROR: --input_metadata is required for the stats workflow."

    if (params.stats_random_effects && !params.stats_static_covariates)
        error "ERROR: Please provide the static covariates when running with longitudinal " +
              "metadata (ie --stats_static_covariates='age,gender')"

    metadata_ch = Channel.value(file(params.input_metadata))

    identify_inputs(input_dir_ch, metadata_ch, 'stats')
    manifest_ch = identify_inputs.out.manifest
    info_ch = manifest_ch.map { db, json -> tuple(db, new JsonSlurperClassic().parse(json.toFile())) }
    contexts = input_dir_ch.map { db, dir -> tuple(db, []) }
    feature_inputs_ch = info_ch.join(input_dir_ch).flatMap { db, m, dir ->
        def items = []
        def taxonomy = file("${dir}/${m.taxonomic_profile}")
        items << [db, m.study_type.toLowerCase() == '16s' ? 'trim' : 'feature', 'taxonomy', taxonomy,
            "--sample-tag-column '_taxonomic_profile' --reduce-stratified-species-only"]
        if (m.pathabundance)
            items << [db, 'feature', 'pathways', file("${dir}/${m.pathabundance}"), "--sample-tag-column '_Abundance' --remove-stratified"]
        (m.other_data_files ?: [:]).each { path, type ->
            items << [db, 'feature', type, file("${dir}/${path}"), "--sample-tag-column '_Abundance' --remove-stratified"]
        }
        items
    }
    features_ch = feature_table(feature_inputs_ch.filter { it[1] == 'feature' }
        .map { db, kind, type, f, opts -> tuple(db, type, f, opts, true) }).features
        .mix(trim_taxonomy(feature_inputs_ch.filter { it[1] == 'trim' }
            .map { db, kind, type, f, opts -> tuple(db, type, f, true) }).features)
    all_features = features_ch.map { db, type, f -> tuple(db, f) }.groupTuple()
    feature_types_ch = info_ch.map { db, m ->
        def types = ['taxonomy']
        if (m.pathabundance) types << 'pathways'
        (m.other_data_files ?: [:]).each { path, type -> types << type }
        tuple(db, types.join(','))
    }
    taxonomy_profile_ch = info_ch.join(input_dir_ch)
        .map { db, m, dir -> tuple(db, file("${dir}/${m.taxonomic_profile}")) }

    mantel_ch = report_files_or_empty(contexts,
        mantel_test(all_features.filter { db, fs -> fs.size() > 1 }, metadata_ch).plot)
    if (!params.stats_bypass_maaslin) {
        maaslin2(features_ch, metadata_ch)
        maaslin_ch = report_files_or_empty(contexts, maaslin2.out.results.map { db, type, folder -> tuple(db, folder) })
    } else {
        maaslin_ch = contexts
    }
    if (!params.stats_bypass_halla) {
        transposed_ch = halla_transpose_metadata(info_ch.filter { db, m -> !m.samples_as_columns }
            .map { db, m -> tuple(db, file(params.input_metadata)) }).metadata
        halla_metadata = transposed_ch.mix(info_ch.filter { db, m -> m.samples_as_columns }
            .map { db, m -> tuple(db, file(params.input_metadata)) })
        halla(features_ch.filter { db, type, f -> !type.contains('gene') }.combine(halla_metadata, by: 0))
        halla_ch = report_files_or_empty(contexts, halla.out.results.map { db, type, folder -> tuple(db, folder) })
    } else {
        halla_ch = contexts
    }
    if (!params.stats_bypass_maaslin) {
        pathabundance_ch = info_ch.join(input_dir_ch)
            .filter { db, m, dir -> m.pathabundance && m.study_type.toLowerCase() in ['wmgx', 'wgx'] }
            .map { db, m, dir -> tuple(db, file("${dir}/${m.pathabundance}")) }
        stratified_metadata(pathabundance_ch, metadata_ch)
        plan_ch = stratified_metadata.out.plan.map { db, json -> tuple(db, new JsonSlurperClassic().parse(json.toFile())) }
        barplot_input_ch = plan_ch.join(maaslin2.out.significant.filter { db, type, f -> type == 'pathways' }
                .map { db, type, f -> tuple(db, f) })
            .join(stratified_metadata.out.merged)
            .flatMap { db, plan, significant, merged ->
                plan.plots.collect { plot -> tuple(db, plot.number, plot.variable, plan.metadata_end, significant, merged) }
            }
        stratified_ch = report_files_or_empty(contexts, stratified_barplot(barplot_input_ch).plot)
    } else {
        stratified_ch = contexts
    }
    if (params.stats_random_effects) {
        permanova_ch = report_files_or_empty(contexts, permanova(all_features, metadata_ch).plots)
        beta_ch = contexts
        covariate_ch = contexts.map { db, fs -> tuple(db, '') }
    } else {
        covariate_json_ch = covariate_equation(manifest_ch).json
            .map { db, json -> tuple(db, new JsonSlurperClassic().parse(json.toFile())) }
        beta_input_ch = features_ch.combine(covariate_json_ch, by: 0)
            .flatMap { db, type, features, covariate ->
                def runs = [tuple(db, type, features, 'univariate', '')]
                if (covariate.run_multivariate) runs << tuple(db, type, features, 'multivariate', covariate.covariate_equation)
                if (covariate.run_pairwise) runs << tuple(db, type, features, 'pairwise', '')
                runs
            }
        beta_ch = report_files_or_empty(contexts, beta_diversity(beta_input_ch, metadata_ch).plot)
        permanova_ch = contexts
        covariate_ch = covariate_json_ch.map { db, m -> tuple(db, m.covariate_equation) }
    }
    stats_report(taxonomy_profile_ch.join(all_features).join(maaslin_ch).join(halla_ch)
        .join(mantel_ch).join(beta_ch).join(permanova_ch).join(stratified_ch)
        .join(feature_types_ch).join(covariate_ch))
    archive_output(stats_report.out.report_folder, metadata_ch, 'stats')

    emit:
    report  = stats_report.out.report
    archive = archive_output.out.archive
}

// Seed each database so optional branches always yield one (possibly empty) list.
def report_files_or_empty(contexts, files) {
    contexts.mix(files.map { db, fs -> tuple(db, fs instanceof List ? fs : [fs]) })
        .groupTuple().map { db, fs -> tuple(db, fs.flatten()) }
}
