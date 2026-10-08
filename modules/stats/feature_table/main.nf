#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Build the feature tables that MaAsLin2, HAllA, mantel and beta diversity all
// consume. Ports utilities.create_feature_table_inputs() (utilities.py 788-827).
//
// The taxonomy table is built differently per study type: mgx profiles go
// through create_feature_table.py, while 16s profiles are reformatted with
// trim_taxonomy.py to move the taxonomy column and sum for species.

// Both processes take a `publish` flag rather than publishing unconditionally.
//
// Upstream writes the feature tables into whichever output folder called
// create_feature_table_inputs(), so stats gets stats/features/ and vis gets
// vis/features/. Publishing to a fixed stats/features/ here put a `stats`
// folder in the output of vis-only runs.
//
// vis passes false instead of vis/features, for the same reason
// alpha_diversity has no publishDir: vis_report publishes the whole `vis`
// folder wholesale, so a second process publishing into it races with that
// copy. The table is only an intermediate for the alpha diversity plots there.

// Build one feature table (taxonomy, pathways or any other data file).
process feature_table {
    tag "${feature_type}"
    publishDir path: "${params.outdir}/stats/features", mode: 'copy', enabled: { publish }

    input:
    tuple val(feature_type), path(data_file), val(options), val(publish)

    output:
    tuple val(feature_type), path("${feature_type}_features.txt"), emit: features

    script:
    """
    create_feature_table.py \\
        --input ${data_file} \\
        --output ${feature_type}_features.txt \\
        ${options}
    """
}

// Reformat a 16s taxonomy profile into a feature table.
process trim_taxonomy {
    tag "${feature_type}"
    publishDir path: "${params.outdir}/stats/features", mode: 'copy', enabled: { publish }

    input:
    tuple val(feature_type), path(data_file), val(publish)

    output:
    tuple val(feature_type), path("${feature_type}_features.txt"), emit: features

    script:
    """
    trim_taxonomy.py \\
        --input ${data_file} \\
        --output ${feature_type}_features.txt \\
        --end-taxonomy-column 0
    """
}
