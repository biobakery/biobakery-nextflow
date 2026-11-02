#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { check_reads } from '../modules/utils/check_reads/main.nf'

// Drop samples whose raw reads are truncated or corrupt before anything
// profiles them, and say which ones.
//
// Without this a truncated FASTQ is found by whichever tool first reads to its
// end -- KneadData, or MetaPhlAn on pre-cleaned input -- hours into the run,
// and that task's failure stops the whole run under errorStrategy 'finish'.
// Here every sample is read through once up front; a bad one is logged,
// listed under <outdir>/input_check/ and left out, and the run carries on with
// the rest. Each sample is gated only on its own check, so profiling of the
// first good samples starts while the rest are still being checked.
//
// The files read_input could not use at all -- broken symlinks, mates without
// a partner -- arrive marked meta.skipped and go into the same report, so it
// lists everything the run left out. main.nf repeats the list when the run
// ends, since the summary logged here comes hours before that.
//
// --check_inputs false skips the check and passes every sample through.
// --check_inputs_only true runs the check and nothing else: each read-based
// workflow returns straight after it.
// --fail_on_bad_inputs true stops the run instead of leaving samples out; no
// sample is then profiled until every one has passed.
workflow CHECK_INPUTS {

    take:
    reads   // Channel: [ [id: sample, paired_end: bool, skipped?: reason], reads ]
    label   // 'mgx' | 'mtx' | 'assembly': names the report, and the log lines

    main:
    inputs = reads.branch { meta, r ->
        skipped: meta.skipped
        usable:  true
    }

    if (!params.check_inputs) {
        // read_input has already warned about the skipped files.
        passed = inputs.usable
        report = Channel.empty()
    }
    else {
        checked = check_reads(inputs.usable).checked

        verdicts = checked
            .map { meta, r, tsv ->
                def failures = tsv.readLines().drop(1)
                    .collect { it.split('\t', -1) }
                    .findAll { it[2] != 'PASS' }
                    .collect { "${it[1]}: ${it[4]}" }
                [ meta, r, failures ]
            }
            .branch { meta, r, failures ->
                bad:  failures
                good: true
            }

        verdicts.bad.subscribe { meta, r, failures ->
            log.warn "[${label}] Sample ${meta.id} failed the input check and is left out: " +
                     failures.unique().join('; ')
        }

        // One table for the run: the checked files, plus a FAIL row for each
        // file read_input skipped. Rows are joined as text, each with the
        // header that keepHeader expects to strip, and sorted by sample.
        def header = "sample\tfile\tstatus\treads\tproblem\n"
        def checkdir = "${params.outdir}/input_check"
        report = checked
            .map { meta, r, tsv -> tsv.text }
            .mix( inputs.skipped.map { meta, f -> header + "${meta.id}\t${f.name}\tFAIL\t\t${meta.skipped}\n" } )
            .collectFile(name: "${label}_input_check.tsv", keepHeader: true, sort: true, storeDir: checkdir)

        // Written from the whole table rather than from the failures, so a
        // rerun after the bad files are fixed leaves an empty list behind
        // rather than the previous run's.
        verdict = report.map { table ->
            def rows   = table.readLines().drop(1).collect { it.split('\t', -1) }
            def failed = rows.findAll { it[2] != 'PASS' }.collect { it[0] }.unique().sort()
            def total  = rows.collect { it[0] }.unique().size()
            file("${checkdir}/${label}_failed_samples.txt").text = failed ? failed.join('\n') + '\n' : ''
            if (failed && params.fail_on_bad_inputs)
                error "[${label}] ${failed.size()} of ${total} samples failed the input check, and " +
                      "--fail_on_bad_inputs is set: ${failed.take(10).join(', ')}${failed.size() > 10 ? ', ...' : ''}. " +
                      "Details: ${checkdir}/${label}_input_check.tsv"
            if (failed)
                log.warn "[${label}] ${failed.size()} of ${total} samples failed the input check and were " +
                         "left out: ${failed.take(10).join(', ')}${failed.size() > 10 ? ', ...' : ''}. " +
                         "Details: ${checkdir}/${label}_input_check.tsv"
            else
                log.info "[${label}] All ${total} samples passed the input check."
            failed
        }

        // With --fail_on_bad_inputs nothing may start before the verdict, so
        // the good samples wait on it; otherwise each goes as soon as its own
        // check passes, and the verdict is only logged.
        if (params.fail_on_bad_inputs) {
            passed = verdicts.good
                .combine(verdict.map { true })
                .map { meta, r, failures, ok -> [ meta, r ] }
        }
        else {
            verdict.subscribe { }
            passed = verdicts.good.map { meta, r, failures -> [ meta, r ] }
        }
    }

    emit:
    reads  = passed   // Channel: [ [id, paired_end], reads ], the samples that passed
    report = report   // the per-file table, once every sample has been checked
}
