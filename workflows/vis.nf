#!/usr/bin/env nextflow
nextflow.enable.dsl=2

import groovy.json.JsonSlurperClassic
include { prepare_report_summaries } from '../modules/stats/prepare_summaries/main.nf' 

include { identify_inputs }              from '../modules/vis/identify_inputs/main.nf'
include { feature_table; trim_taxonomy } from '../modules/stats/feature_table/main.nf'
include { alpha_diversity }              from '../modules/vis/alpha_diversity/main.nf'
include { add_ec_names }                 from '../modules/vis/add_ec_names/main.nf'
include { vis_report }                   from '../modules/vis/report/main.nf'
include { archive_output }               from '../modules/utils/archive/main.nf'

// Visualization workflow — the Nextflow port of `biobakery_workflows vis`.
//
// Like the AnADAMA workflow this takes a folder of bioBakery output and
// discovers the data files in it by their known names, rather than being handed
// individual files. A chained run is handed the folder stage_report_input
// builds from that run's own channels, so there is a single code path either
// way.
//
// The folder arrives as a channel rather than as a path so that a chained run
// can hand over the folder stage_report_input builds from the profiling
// outputs: that both orders vis after profiling and avoids reading
// params.outdir, which publishDir fills in asynchronously.
workflow VIS {

    take:
    source_dir_ch // [database context, bioBakery output folder]; empty context for standalone runs

    main:
    input_dir_ch = prepare_report_summaries(source_dir_ch).folder
    def no_file = file("${projectDir}/assets/NO_FILE")

    metadata_ch = params.input_metadata
        ? Channel.value(file(params.input_metadata))
        : Channel.value(no_file)

    identify_inputs(input_dir_ch, metadata_ch, 'vis')
    manifest_ch = identify_inputs.out.manifest
    info_ch = manifest_ch.map { db, json -> tuple(db, new JsonSlurperClassic().parse(json.toFile())) }
    contexts = input_dir_ch.map { db, dir -> tuple(db, no_file) }

    taxonomy_ch = info_ch.join(input_dir_ch)
        .map { db, m, dir -> tuple(db, m.study_type, file("${dir}/${m.taxonomic_profile}")) }
    features_ch = feature_table(taxonomy_ch.filter { db, type, f -> type == 'WGX' }
        .map { db, type, f -> tuple(db, 'taxonomy', f, "--sample-tag-column '_taxonomic_profile' --reduce-stratified-species-only", false) }).features
        .mix(trim_taxonomy(taxonomy_ch.filter { db, type, f -> type == '16S' }
            .map { db, type, f -> tuple(db, 'taxonomy', f, false) }).features)
    if (params.input_metadata) {
        alpha_ch = alpha_diversity(features_ch, metadata_ch).plots
    } else {
        alpha_ch = contexts
    }
    ecs_input_ch = info_ch.join(input_dir_ch)
        .filter { db, m, dir -> m.study_type == 'WGX' && m.ecsabundance }
        .map { db, m, dir -> tuple(db, file("${dir}/${m.ecsabundance}")) }
    ecs_ch = contexts.join(add_ec_names(ecs_input_ch).ecs, remainder: true)
        .map { db, sentinel, ecs -> tuple(db, ecs ?: sentinel) }
    report_inputs = input_dir_ch.join(manifest_ch).join(alpha_ch).join(ecs_ch)
    vis_report(report_inputs, metadata_ch)
    archive_output(vis_report.out.report_folder, metadata_ch, 'vis')

    emit:
    report  = vis_report.out.report
    archive = archive_output.out.archive
}
