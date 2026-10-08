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
// --check_inputs false skips the check and passes every sample through.
// --check_inputs_only true runs the check and nothing else: each read-based
// workflow returns straight after it.
workflow CHECK_INPUTS {

    take:
    reads   // Channel: [ [id: sample, paired_end: bool], reads ]
    label   // 'mgx' | 'mtx' | 'assembly': names the report, and the log lines

    main:
    if (!params.check_inputs) {
        passed = reads
        report = Channel.empty()
    }
    else {
        checked = check_reads(reads).checked

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

        passed = verdicts.good.map { meta, r, failures -> [ meta, r ] }

        def checkdir = "${params.outdir}/input_check"
        report = checked
            .map { meta, r, tsv -> tsv }
            .collectFile(name: "${label}_input_check.tsv", keepHeader: true, sort: { it.name }, storeDir: checkdir)

        // Written from the whole table rather than from the failures, so a
        // rerun after the bad files are fixed leaves an empty list behind
        // rather than the previous run's.
        report.subscribe { table ->
            def rows   = table.readLines().drop(1).collect { it.split('\t', -1) }
            def failed = rows.findAll { it[2] != 'PASS' }.collect { it[0] }.unique().sort()
            def total  = rows.collect { it[0] }.unique().size()
            file("${checkdir}/${label}_failed_samples.txt").text = failed ? failed.join('\n') + '\n' : ''
            if (failed)
                log.warn "[${label}] ${failed.size()} of ${total} samples failed the input check and were " +
                         "left out: ${failed.take(10).join(', ')}${failed.size() > 10 ? ', ...' : ''}. " +
                         "Details: ${checkdir}/${label}_input_check.tsv"
            else
                log.info "[${label}] All ${total} samples passed the input check."
        }
    }

    emit:
    reads  = passed   // Channel: [ [id, paired_end], reads ], the samples that passed
    report = report   // the per-file table, once every sample has been checked
}
