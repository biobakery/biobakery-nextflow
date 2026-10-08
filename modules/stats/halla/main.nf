#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// HAllA per feature table, against all metadata variables.
// Ports utilities.run_halla_on_input_file_set() (utilities.py 716-759).

// HAllA needs the metadata with samples as columns.
process halla_transpose_metadata {
    input:
    path metadata

    output:
    path "halla_metadata/${metadata.name}", emit: metadata

    script:
    """
    mkdir -p halla_metadata
    python ${projectDir}/bin/scripts/transpose_table.py \\
        --input ${metadata} \\
        --output halla_metadata/${metadata.name}
    """
}

// HAllA — hierarchical all-against-all association between features and metadata.
//
// Gene family tables are skipped upstream, matching the original.
//
// hallagram.png is only produced when there are enough associations to plot, so
// it is optional output; all_associations.txt is always written. The AnADAMA
// task removes a stale output folder first, which is unnecessary here because
// every task gets a fresh work directory.
process halla {
    tag "${feature_type}"
    publishDir "${params.outdir}/stats", mode: 'copy'

    input:
    tuple val(feature_type), path(features)
    path metadata

    output:
    tuple val(feature_type), path("halla_${feature_type}"), emit: results

    script:
    """
    halla \\
        -x ${features} \\
        -y ${metadata} \\
        -o halla_${feature_type} \\
        --plot_file_type='png' \\
        ${params.halla_options}
    """
}
