#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// ── Workflow imports ───────────────────────────────────────────────────────
include { MGX }          from './workflows/mgx.nf'
include { MTX }          from './workflows/mtx.nf'
include { MGX_MTX }      from './workflows/mgx_mtx.nf'
include { SIXTEENS }     from './workflows/sixteens.nf'
include { VIS }          from './workflows/vis.nf'
include { STATS }        from './workflows/stats.nf'
include { ASSEMBLY } from './workflows/assembly.nf'

// ── Router ─────────────────────────────────────────────────────────────────
workflow {

    // Read-based workflows accept exactly one input mode. mgx_mtx validates its
    // two-folder alternative itself because it has two assays.
    if (params.workflow in ['mgx', 'mtx', 'assembly']) {
        def input_modes = (params.readsdir ? 1 : 0) + (params.samplesheet ? 1 : 0)
        if (input_modes != 1) {
            error "ERROR: choose exactly one read input mode: --readsdir or --samplesheet."
        }
    }
    if (params.stop_after_qc && !params.run_qc) {
        error "ERROR: --stop_after_qc requires --run_qc true."
    }
    if (params.workflow == '16s' && !params.readsdir) {
        error "ERROR: the current 16s stub requires --readsdir."
    }

    switch (params.workflow) {

        case 'mgx':
            MGX()
            break

        case 'mtx':
            MTX()
            break

        case 'mgx_mtx':
            MGX_MTX()
            break

        case '16s':
            SIXTEENS()
            break

        case 'vis':
            VIS(Channel.value(report_input_dir(params.vis_input, 'vis')))
            break

        case 'stats':
            STATS(Channel.value(report_input_dir(params.stats_input, 'stats')))
            break

        case 'assembly':
            ASSEMBLY()
            break

        default:
            error "Unknown workflow '${params.workflow}'. Choose: mgx | mtx | mgx_mtx | 16s | vis | stats | assembly"
    }
}

// The folder a standalone vis or stats run reports on. Chained runs get the
// folder stage_report_input builds instead, so this is only for --workflow
// vis|stats.
def report_input_dir(setting, label) {
    def dir = file(setting ?: params.outdir)

    if (!dir.exists())
        error "ERROR: ${label} input folder not found: ${dir}\n" +
              "Set --${label}_input to a bioBakery output folder."

    return dir
}
