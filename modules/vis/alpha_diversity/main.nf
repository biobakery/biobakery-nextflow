#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Alpha diversity plots from the taxonomy feature table.
// Ports utilities.generate_alpha_diversity_plots() (utilities.py 538-553).
//
// The feature table this consumes is built by the shared feature_table process,
// exactly as the original calls create_feature_table_inputs() first. Only runs
// when metadata are provided.
// No publishDir: the report driver copies these plots into the report folder,
// which vis_report publishes as ${params.outdir}/vis. Publishing them here too
// would target that same folder, and vis_report's later publish of the whole
// directory would clobber them.
process alpha_diversity {
    input:
    tuple val(feature_type), path(features)
    path metadata

    output:
    path "alpha_diversity_plots", emit: plots

    script:
    """
    set +e
    Rscript \$(python ${projectDir}/bin/scripts/biobakery_bootstrap.py --rscript alpha_diversity) \\
        ${features} \\
        ${metadata} \\
        alpha_diversity_plots \\
        --max_missing ${params.max_missing} 2> alpha_diversity.err
    status=\$?
    cat alpha_diversity.err >&2
    set -e

    # These plots are one optional section of the report, and the script exits 1
    # when the feature table is too sparse to plot -- "No data remain in the data
    # after filtering for min abundance and prevalence", which a run over a
    # couple of low-biomass samples hits routinely. Losing the whole run at the
    # last step over an optional figure is the wrong trade, so that one case is
    # carried through as "no plots"; every other failure still fails the task.
    if [ "\$status" -ne 0 ]; then
        if grep -q "No data remain in the data after filtering" alpha_diversity.err; then
            echo "alpha diversity: not enough data to plot; continuing without it" >&2
        else
            exit "\$status"
        fi
    fi

    # the report only checks the folder contents, so make sure it exists even
    # when every variable was filtered out for missing values
    mkdir -p alpha_diversity_plots
    """
}
