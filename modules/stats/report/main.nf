#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Render the stats report.
// Ports the document stage of stats.py (lines 166-202).
//
// Every upstream stats process writes into its own work directory, so this
// process first rebuilds the output layout the AnADAMA workflow produces --
// features/, maaslin2_<type>/, halla_<type>/, mantel_test/, beta_diversity/,
// permanova/, stratified_pathways/ -- and the driver derives the template
// variables from it using the same naming rules as the original.
//
// As with vis_report, this is the only process in the stats workflow that
// depends on anadama2.
process stats_report {
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path taxonomic_profile
    path feature_tables
    path maaslin_folders
    path halla_folders
    path mantel_plot
    path beta_plots
    path permanova_plots
    path stratified_plots
    val  feature_types
    val  covariate_equation

    output:
    path "stats",                     emit: report_folder
    path "stats/stats_report.{html,pdf}", emit: report

    script:
    def intro_opt    = params.introduction_text ? "--introduction-text '${params.introduction_text}'" : ''
    def template_opt = params.use_template ? "--use-template ${params.use_template}" : ''
    def header_opt   = params.header_image ? "--header-image ${params.header_image}" : ''
    def bypass_maaslin = params.stats_bypass_maaslin ? '--bypass-maaslin' : ''
    def bypass_halla   = params.stats_bypass_halla   ? '--bypass-halla'   : ''
    """
    # rebuild the AnADAMA output layout from the staged process outputs
    mkdir -p stats/features

    for features in *_features.txt; do
        [ -e "\$features" ] && cp -L "\$features" stats/features/
    done

    for folder in maaslin2_* halla_*; do
        [ -d "\$folder" ] && cp -rL "\$folder" stats/
    done

    if [ -e mantel_plot.png ]; then
        mkdir -p stats/mantel_test
        cp -L mantel_plot.png stats/mantel_test/
    fi

    for plot in *_univariate.png *_multivariate.png *_pairwise.png; do
        [ -e "\$plot" ] || continue
        mkdir -p stats/beta_diversity
        cp -L "\$plot" stats/beta_diversity/
    done

    for plot in permanova*.png; do
        [ -e "\$plot" ] || continue
        mkdir -p stats/permanova
        cp -L "\$plot" stats/permanova/
    done

    for plot in stratified_pathways_*.png; do
        [ -e "\$plot" ] || continue
        mkdir -p stats/stratified_pathways
        cp -L "\$plot" stats/stratified_pathways/
    done

    python ${projectDir}/bin/scripts/biobakery_stats_report.py \\
        --output stats \\
        --taxonomic-profile ${taxonomic_profile} \\
        --feature-types '${feature_types}' \\
        --format ${params.report_format} \\
        --project-name '${params.project_name}' \\
        --author-name '${params.author_name}' \\
        --top-pathways ${params.stats_top_pathways} \\
        --covariate-equation '${covariate_equation}' \\
        ${bypass_maaslin} ${bypass_halla} ${intro_opt} ${template_opt} ${header_opt}
    """
}
