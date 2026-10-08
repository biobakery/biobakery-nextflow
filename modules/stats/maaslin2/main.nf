#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// MaAsLin2 per feature table, plus the figure tiles shown in the report.
// Ports utilities.run_maaslin_on_input_file_set() (utilities.py 761-786) and
// utilities.generate_tiles_of_maaslin_figures() (utilities.py 704-714).
//
// AnADAMA runs the tiling as a separate task that depends on every MaAsLin2
// task. Here it runs at the end of each MaAsLin2 process instead: the tiles for
// a run only ever depend on that run's own figures, and a separate process
// would have to write into its staged input folder to place them.
process maaslin2 {
    tag "${feature_type}"
    publishDir "${params.outdir}/stats", mode: 'copy'

    input:
    tuple val(feature_type), path(features)
    path metadata

    output:
    tuple val(feature_type), path(out_folder),                          emit: results
    tuple val(feature_type), path("${out_folder}/significant_results.tsv"), emit: significant, optional: true

    script:
    out_folder = "maaslin2_${feature_type == 'taxonomy' ? 'taxa' : feature_type}"
    // the optional args are appended inside the R call, so they must start with
    // a comma to follow the three positional Maaslin2 arguments
    def optional_args = params.maaslin_options ?: ''
    if (optional_args && !optional_args.startsWith(','))
        optional_args = ',' + optional_args
    if (params.stats_transform)
        optional_args += ",transform='${params.stats_transform}'"
    if (params.stats_fixed_effects)
        optional_args += ",fixed_effects='${params.stats_fixed_effects}'"
    if (params.stats_random_effects)
        optional_args += ",random_effects='${params.stats_random_effects}'"
    // MaAsLin2 1.22.0 calls labs("") and dies on ggplot2 4.x once it reaches the
    // first continuous metadata variable; the shim makes that call a no-op again
    def labs_shim = "${projectDir}/assets/Rscripts/ggplot2_labs_shim.R"
    """
    R -e "source('${labs_shim}'); library('Maaslin2'); results <- Maaslin2('${features}','${metadata}','${out_folder}'${optional_args})"

    python ${projectDir}/bin/scripts/maaslin_image_tiles.py \\
        --figures-folder ${out_folder}/figures
    """
}
