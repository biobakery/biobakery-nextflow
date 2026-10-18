#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Stratified pathway barplots for the top significant associations.
// Ports utilities.create_stratified_pathways_plots() (utilities.py 467-508)
// and utilities.run_humann_barplot() (utilities.py 900-936).
//
// This is the one stage that is not a line-by-line translation. AnADAMA decides
// how many barplots to build at DAG-construction time by reading the metadata
// in Python. Nextflow cannot know that when the DAG is built, so the plan is
// emitted as JSON and the workflow fans out over it at runtime.

// Merge the pathway abundances with the metadata and work out which
// (pathway rank, metadata variable) pairs to plot.
process stratified_metadata {
    label 'stats_viz'
    publishDir path: { "${params.outdir}/${db ? "databases/${db}" : ""}/stats/stratified_pathways" }, mode: 'copy', pattern: '*.tsv'

    input:
    tuple val(db), path(pathabundance)
    path metadata

    output:
    tuple val(db), path("merged_data_metadata_input.tsv"), emit: merged
    tuple val(db), path("stratified_plan.json"),           emit: plan

    script:
    def categorical = optionList(params.metadata_categorical, '--metadata-categorical')
    def continuous  = optionList(params.metadata_continuous,  '--metadata-continuous')
    def exclude     = optionList(params.metadata_exclude,     '--metadata-exclude')
    """
    python ${params.reporting_root}/bin/scripts/stats_stratified_metadata.py \\
        --pathabundance ${pathabundance} \\
        --input-metadata ${metadata} \\
        --output merged_data_metadata_input.tsv \\
        --plan stratified_plan.json \\
        --top-pathways ${params.stats_top_pathways} \\
        ${categorical} ${continuous} ${exclude}
    """
}

// One barplot per (pathway rank, metadata variable).
// The plot is deliberately empty when there is no significant association --
// the report template treats a zero-size plot as "no association found".
process stratified_barplot {
    label 'stats_viz'
    tag "${number}_${variable}"
    publishDir path: { "${params.outdir}/${db ? "databases/${db}" : ""}/stats/stratified_pathways" }, mode: 'copy'

    input:
    tuple val(db), val(number), val(variable), val(metadata_end), path(significant_results), path(merged)

    output:
    tuple val(db), path("stratified_pathways_${number}_${variable}.png"), emit: plot

    script:
    """
    python ${params.reporting_root}/bin/scripts/stats_humann_barplot.py \\
        --significant-results ${significant_results} \\
        --merged-data ${merged} \\
        --output stratified_pathways_${number}_${variable}.png \\
        --number ${number} \\
        --variable-name ${variable} \\
        --metadata-end ${metadata_end}
    """
}

// Turn a comma-delimited param into repeated append-style options, matching the
// AnADAMA workflows where these are "action=append" arguments.
def optionList(value, option) {
    if (!value) return ''
    return value.toString().tokenize(',').collect { "${option} '${it.trim()}'" }.join(' ')
}
