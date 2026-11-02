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

    // --check_inputs_only runs the read-based workflow as far as its input
    // check and stops there (see subworkflows/check_inputs.nf). It runs inside
    // the workflow rather than beside it so the check tasks carry the same
    // names, and the run that follows with -resume reuses them.
    if (params.check_inputs_only && !(params.workflow in ['mgx', 'mtx', 'mgx_mtx', 'assembly'])) {
        error "ERROR: --check_inputs_only applies to the read-based workflows " +
              "(mgx | mtx | mgx_mtx | assembly), not '${params.workflow}'."
    }
    if (params.check_inputs_only && !params.check_inputs) {
        error "ERROR: --check_inputs_only true needs --check_inputs true."
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

// Repeat the input check's result as the last thing the run prints. The
// summary CHECK_INPUTS logs comes once the checks finish, which on a large
// study is hours before the end, and is easy to scroll past. Read back from the
// failed-sample lists, which are rewritten every run: one older than this run
// means the run stopped before its checks finished, and is not reported.
workflow.onComplete {
    if (!params.check_inputs) return
    def labels = [mgx: ['mgx'], mtx: ['mtx'], mgx_mtx: ['mgx', 'mtx'], assembly: ['assembly']][params.workflow]
    if (!labels) return

    def checkdir = "${params.outdir}/input_check"
    def started  = workflow.start.toInstant().toEpochMilli()
    labels.each { label ->
        def list = file("${checkdir}/${label}_failed_samples.txt")
        if (!list.exists() || list.lastModified() < started) return
        def failed = list.readLines().findAll { it }
        if (!failed) {
            log.info "Input check [${label}]: no samples were left out."
            return
        }
        def table = file("${checkdir}/${label}_input_check.tsv")
        def why = table.exists()
            ? table.readLines().drop(1).collect { it.split('\t', -1) }.findAll { it[2] != 'PASS' }
                .groupBy { it[0] }.collectEntries { s, rows -> [s, rows.collect { "${it[1]}: ${it[4]}" }.unique().join('; ')] }
            : [:]
        def shown = failed.take(50).collect { "  ${it}  --  ${why[it] ?: ''}" }
        log.warn "Input check [${label}]: ${failed.size()} sample(s) were " +
                 (params.fail_on_bad_inputs ? "bad, and the run was stopped" : "left out of this run") + ":\n" +
                 shown.join('\n') +
                 (failed.size() > 50 ? "\n  ... and ${failed.size() - 50} more" : '') +
                 "\n  Full list: ${list}\n  Details:   ${table}"
    }
}
