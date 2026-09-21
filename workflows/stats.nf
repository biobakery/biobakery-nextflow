#!/usr/bin/env nextflow
nextflow.enable.dsl=2

import groovy.json.JsonSlurper

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
    // A value channel, so every consumer below can read it: Channel.value for a
    // standalone run, and stage_report_input's output for a chained one, which
    // is a value channel because all of its inputs are.
    input_dir_ch    // the bioBakery output folder to analyse

    main:
    def no_file = file("${projectDir}/assets/NO_FILE")

    // stats.py marks --input-metadata as required
    if (!params.input_metadata)
        error "ERROR: --input_metadata is required for the stats workflow."

    if (params.stats_random_effects && !params.stats_static_covariates)
        error "ERROR: Please provide the static covariates when running with longitudinal " +
              "metadata (ie --stats_static_covariates='age,gender')"

    metadata_ch = Channel.value(file(params.input_metadata))

    // ── Identify the input files ───────────────────────────────────────────
    identify_inputs(input_dir_ch, metadata_ch, 'stats')

    manifest_ch = identify_inputs.out.manifest
    info_ch     = manifest_ch.map { json -> new JsonSlurper().parse(json.toFile()) }

    // ── Feature tables ─────────────────────────────────────────────────────
    // create_feature_table_inputs(): taxonomy first, then pathways, then any
    // other data files. The order is preserved so the report sections match.
    // the manifest holds paths relative to the folder, so both travel together
    feature_inputs_ch = info_ch.combine(input_dir_ch).flatMap { m, input_dir ->
        def items = []
        def taxonomy = file("${input_dir}/${m.taxonomic_profile}")

        if (m.study_type == '16s')
            items << [ 'trim', 'taxonomy', taxonomy, '' ]
        else
            items << [ 'feature', 'taxonomy', taxonomy,
                       "--sample-tag-column '_taxonomic_profile' --reduce-stratified-species-only" ]

        if (m.pathabundance)
            items << [ 'feature', 'pathways', file("${input_dir}/${m.pathabundance}"),
                       "--sample-tag-column '_Abundance' --remove-stratified" ]

        (m.other_data_files ?: [:]).each { path, type ->
            items << [ 'feature', type, file("${input_dir}/${path}"),
                       "--sample-tag-column '_Abundance' --remove-stratified" ]
        }
        return items
    }

    // published to stats/features, as create_feature_table_inputs() does
    features_ch = feature_table(
            feature_inputs_ch.filter { it[0] == 'feature' }.map { [ it[1], it[2], it[3], true ] }
        ).features
        .mix(
            trim_taxonomy(
                feature_inputs_ch.filter { it[0] == 'trim' }.map { [ it[1], it[2], true ] }
            ).features)

    // the report needs the types in the original order, so derive them from the
    // manifest rather than from the (unordered) process outputs
    feature_types_ch = info_ch.map { m ->
        def types = [ 'taxonomy' ]
        if (m.pathabundance) types << 'pathways'
        (m.other_data_files ?: [:]).each { path, type -> types << type }
        types.join(',')
    }

    taxonomy_profile_ch = info_ch.combine(input_dir_ch)
        .map { m, input_dir -> file("${input_dir}/${m.taxonomic_profile}") }

    // ── Mantel tests ───────────────────────────────────────────────────────
    // Only run when there is more than one data set to compare.
    mantel_input_ch = features_ch.map { type, features -> features }
        .collect()
        .filter { it.size() > 1 }

    mantel_ch = mantel_test(mantel_input_ch, metadata_ch).plot.ifEmpty([])

    // ── MaAsLin2 ───────────────────────────────────────────────────────────
    if (!params.stats_bypass_maaslin) {
        maaslin2(features_ch, metadata_ch)
        maaslin_ch = maaslin2.out.results.map { type, folder -> folder }.collect().ifEmpty([])
    } else {
        maaslin_ch = Channel.value([])
    }

    // ── HAllA ──────────────────────────────────────────────────────────────
    if (!params.stats_bypass_halla) {
        // HAllA needs samples as columns
        halla_metadata_ch = info_ch
            .filter { m -> !m.samples_as_columns }
            .map { m -> file(params.input_metadata) }

        transposed_ch = halla_transpose_metadata(halla_metadata_ch).metadata

        // gene family tables are skipped, matching run_halla_on_input_file_set()
        halla(features_ch.filter { type, features -> !type.contains('gene') },
              transposed_ch.mix(
                  info_ch.filter { m -> m.samples_as_columns }.map { file(params.input_metadata) }
              ).first())

        halla_ch = halla.out.results.map { type, folder -> folder }.collect().ifEmpty([])
    } else {
        halla_ch = Channel.value([])
    }

    // ── Stratified pathway barplots ────────────────────────────────────────
    if (!params.stats_bypass_maaslin) {
        pathabundance_ch = info_ch.combine(input_dir_ch)
            .filter { m, input_dir -> m.pathabundance && m.study_type == 'wmgx' }
            .map    { m, input_dir -> file("${input_dir}/${m.pathabundance}") }

        stratified_metadata(pathabundance_ch, metadata_ch)

        plan_ch = stratified_metadata.out.plan.map { json -> new JsonSlurper().parse(json.toFile()) }

        barplot_input_ch = plan_ch
            .combine(maaslin2.out.significant.filter { type, results -> type == 'pathways' }
                                             .map { type, results -> results })
            .combine(stratified_metadata.out.merged)
            .flatMap { plan, significant, merged ->
                plan.plots.collect { plot ->
                    [ plot.number, plot.variable, plan.metadata_end, significant, merged ]
                }
            }

        stratified_ch = stratified_barplot(barplot_input_ch).plot.collect().ifEmpty([])
    } else {
        stratified_ch = Channel.value([])
    }

    // ── Beta diversity or PERMANOVA ────────────────────────────────────────
    // stats.py runs the PERMANOVA for longitudinal studies (random effects set)
    // and beta diversity otherwise.
    if (params.stats_random_effects) {
        permanova(features_ch.map { type, features -> features }.collect(), metadata_ch)
        permanova_ch = permanova.out.plots.collect().ifEmpty([])
        beta_ch      = Channel.value([])
        covariate_ch = Channel.value('')
    } else {
        covariate_json_ch = covariate_equation(manifest_ch).json
            .map { json -> new JsonSlurper().parse(json.toFile()) }

        beta_input_ch = features_ch.combine(covariate_json_ch)
            .flatMap { type, features, covariate ->
                def runs = [ [ type, features, 'univariate', '' ] ]
                if (covariate.run_multivariate)
                    runs << [ type, features, 'multivariate', covariate.covariate_equation ]
                if (covariate.run_pairwise)
                    runs << [ type, features, 'pairwise', '' ]
                return runs
            }

        beta_ch      = beta_diversity(beta_input_ch, metadata_ch).plot.collect().ifEmpty([])
        permanova_ch = Channel.value([])
        covariate_ch = covariate_json_ch.map { it.covariate_equation }
    }

    // ── Report and archive ─────────────────────────────────────────────────
    stats_report(
        taxonomy_profile_ch,
        features_ch.map { type, features -> features }.collect(),
        maaslin_ch,
        halla_ch,
        mantel_ch,
        beta_ch,
        permanova_ch,
        stratified_ch,
        feature_types_ch,
        covariate_ch)

    archive_output(stats_report.out.report_folder, metadata_ch, 'stats')

    emit:
    report  = stats_report.out.report
    archive = archive_output.out.archive
}
