#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Render the visualization report.
// Ports the document stage of vis.py (lines 94-202).
//
// This is the only process in the vis workflow that depends on anadama2: the
// shipped .pmd templates import PweaveDocument directly, and it doubles as the
// plotting library behind visualizations.py. Keeping that dependency confined
// to this one process means the report engine can be replaced later without
// touching the rest of the workflow.
process vis_report {
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path input_folder, stageAs: 'input_folder'
    path manifest
    // Each optional input is staged under its own name. All three fall back to
    // the same assets/NO_FILE sentinel, and staging two of them at once failed
    // the task with "multiple input files for each of the following file names:
    // NO_FILE" -- which is every run without metadata, since alpha diversity is
    // then skipped too.
    path metadata,              stageAs: 'metadata/*'
    path alpha_diversity_plots, stageAs: 'alpha/*'
    path ecs_file,              stageAs: 'ecs/*'

    output:
    path "vis",                    emit: report_folder
    path "vis/*_report.{html,pdf}", emit: report

    script:
    def metadata_opt   = metadata.name != 'NO_FILE' ? "--input-metadata ${metadata}" : ''
    def alpha_opt      = alpha_diversity_plots.name != 'NO_FILE' ? "--alpha-diversity-plots ${alpha_diversity_plots}" : ''
    def ecs_opt        = ecs_file.name != 'NO_FILE' ? "--ecs-file ${ecs_file}" : ''
    def intro_opt      = params.introduction_text ? "--introduction-text '${params.introduction_text}'" : ''
    def template_opt   = params.use_template ? "--use-template ${params.use_template}" : ''
    def header_opt     = params.header_image ? "--header-image ${params.header_image}" : ''
    def picard_opt     = params.input_picard ? "--input-picard ${params.input_picard}" : ''
    def categorical    = optionList(params.metadata_categorical, '--metadata-categorical')
    def continuous     = optionList(params.metadata_continuous,  '--metadata-continuous')
    def exclude        = optionList(params.metadata_exclude,     '--metadata-exclude')
    """
    mkdir -p vis

    python ${projectDir}/bin/scripts/biobakery_vis_report.py \\
        --input input_folder \\
        --manifest ${manifest} \\
        --output vis \\
        --format ${params.report_format} \\
        --project-name '${params.project_name}' \\
        --author-name '${params.author_name}' \\
        --min-abundance ${params.vis_min_abundance} \\
        --min-samples ${params.vis_min_samples} \\
        --max-sets-heatmap ${params.vis_max_sets_heatmap} \\
        --max-sets-barplot ${params.vis_max_sets_barplot} \\
        --max-groups-barplot ${params.vis_max_groups_barplot} \\
        --correlation-threshold ${params.vis_correlation_threshold} \\
        --input-picard-extension ${params.input_picard_extension} \\
        ${metadata_opt} ${alpha_opt} ${ecs_opt} ${intro_opt} \\
        ${template_opt} ${header_opt} ${picard_opt} \\
        ${categorical} ${continuous} ${exclude}
    """
}

def optionList(value, option) {
    if (!value) return ''
    return value.toString().tokenize(',').collect { "${option} '${it.trim()}'" }.join(' ')
}
