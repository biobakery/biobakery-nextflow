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

    // Validate required params for read-based workflows. mgx_mtx is the
    // exception: it takes two input folders instead of one, and validates them
    // itself, mirroring wmgx_wmtx.py replacing --input with --input-metagenome
    // and --input-metatranscriptome.
    if (!params.readsdir && params.workflow in ['mgx', 'mtx', '16s', 'assembly']) {
        error "ERROR: --readsdir is required. Example: --readsdir /path/to/fastqs"
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
