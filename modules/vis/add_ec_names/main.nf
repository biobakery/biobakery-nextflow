#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Add EC names to the EC abundance table when they are missing.
// Ports visualizations.add_ec_names() (visualizations.py 37-61).
//
// The original inspects the file in Python and only adds the rename task when
// the first data row has no ":" in it. That check happens here in the script so
// the process stays a plain file-to-file transform: when the names are already
// present the input is passed through unchanged.
process add_ec_names {
    label 'stats_viz'
    publishDir path: { "${params.outdir}/${db ? "databases/${db}" : ""}/vis/ecs" }, mode: 'copy'

    input:
    tuple val(db), path(ecsabundance)

    output:
    tuple val(db), path("ecs/${ecsabundance.name}"), emit: ecs

    script:
    """
    mkdir -p ecs

    if head -n 2 ${ecsabundance} | tail -n 1 | grep -q ":"; then
        # names are already present
        cp ${ecsabundance} ecs/${ecsabundance.name}
    else
        humann_rename_table \\
            --input ${ecsabundance} \\
            --output ecs/${ecsabundance.name} \\
            --names ec
    fi
    """
}
