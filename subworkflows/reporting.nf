#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { VIS }   from '../workflows/vis.nf'
include { STATS } from '../workflows/stats.nf'

// Run vis and/or stats at the end of a read-based workflow.
//
// Port decision, not upstream behaviour: `biobakery_workflows` runs wmgx and
// then vis as separate commands. Here vis is chained by default and turned off
// with --run_vis false. stats is opt-in (--run_stats true): it is a study-level
// analysis rather than a report, and on a study too small for MaAsLin2, HAllA
// and the mantel test it fails -- which, chained, would take down an otherwise
// complete profiling run at its last step.
//
// The folder comes from stage_report_input. It holds one assay: vis and stats
// discover their inputs by name at fixed paths and do not walk subdirectories
// (files.py:79), so an mgx_mtx run reports on its metagenome half.
workflow REPORTING {

    take:
    folder_ch   // Channel: the bioBakery-standard folder to report on

    main:

    if (params.run_vis)
        VIS(folder_ch)

    // stats.py requires metadata, and a read-based run has no reason to have
    // been given any. Skip rather than fail the whole run over a report.
    if (params.run_stats) {
        if (params.input_metadata) {
            STATS(folder_ch)
        }
        else {
            log.warn "Skipping the chained stats workflow: --run_stats true needs " +
                     "--input_metadata. Set --run_stats false to silence this, or run " +
                     "--workflow stats separately against the output folder."
        }
    }
}
