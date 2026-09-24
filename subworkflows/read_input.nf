#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Build one canonical read channel from either directory discovery or a CSV
// samplesheet. Both modes return [ [id: sample, paired_end: bool], reads ].
//
// Behaviour, following the anadama2 workflow:
//   * look for the pair identifier in the read filenames
//   * if it is never found, warn once and run everything single-end
//   * if it is found, warn again listing any sample that turned up without a
//     mate, since that is almost always a file naming mistake rather than a
//     genuinely single-end sample
//   * --single_end true (or --paired_end false) forces single-end even when
//     pairs are present
//
// This is a function rather than a workflow because the layout detection is
// eager Groovy that globs the input folder: a workflow `take:` input arrives as
// a channel, which cannot be globbed. Being a function also lets mgx_mtx build
// two independent read channels in one run, one per input folder.
//
// Samplesheet columns:
//   sample,assay,read_1,read_2
// assay is optional for single-assay workflows and mandatory for mgx_mtx.
// read_2 is empty for a single-end sample.
def read_input(indir, label, samplesheet, require_assay) {

    def modes = (indir ? 1 : 0) + (samplesheet ? 1 : 0)
    if (modes != 1) {
        error "ERROR: [${label}] choose exactly one input mode: directory discovery or samplesheet."
    }

    if (samplesheet) {
        log.info "[${label}] Reading explicit sample assignments from ${samplesheet}."
        return samplesheet_input(samplesheet, label, require_assay)
    }

    if (!indir) {
        error "ERROR: no input read folder given for ${label}"
    }

    def readsdir = indir.toString() - ~/\/$/

    // Both spellings select single-end. --paired_end false is what the README
    // and conf/harvard_rc.yaml document; --single_end true is the newer flag
    // the layout auto-detection added. Honouring only the latter meant a run
    // that followed the docs matched the paired glob, found no {1,2} capture
    // group in it, and silently produced an empty channel -- the whole run
    // completing with nothing but a version log.
    def force_single = params.single_end || params.paired_end == false

    // Explicit filepattern wins; otherwise derive it from the layout so a
    // single-end run does not have to restate the pattern. The paired glob is
    // built from --pair_identifier rather than being its own parameter, so
    // changing the mate naming convention is one setting and the two cannot
    // disagree.
    def paired_glob = params.filepattern ?: "*${params.pair_identifier}*.fastq.gz"
    def single_glob = params.filepattern ?: params.filepattern_single

    // ...except that a pair-identifier alternation like "*_R{1,2}*.fastq.gz"
    // cannot match anything in single-end mode. conf/harvard_rc.yaml ships
    // exactly such a filepattern, so `--single_end true` with the default
    // params file would otherwise fail with "No files match pattern".
    // Fall back to the single-end default and say so.
    if (force_single && single_glob.contains('{')) {
        log.warn "[${label}] --filepattern '${single_glob}' carries a pair identifier, " +
                 "which cannot match in single-end mode. Using '${params.filepattern_single}' " +
                 "instead; set --filepattern to override."
        single_glob = params.filepattern_single
    }

    // Decide the layout before building any channel, so the warnings are emitted
    // once for the run rather than once per file.
    def pair_files = force_single ? [] : file("${readsdir}/${paired_glob}")
    def use_paired = pair_files.size() > 0

    if (force_single) {
        log.info "[${label}] Running single-end: " +
                 (params.single_end ? "--single_end was set." : "--paired_end false was set.")
    }
    else if (!use_paired) {
        log.warn "[${label}] No files matched the paired-end pattern '${paired_glob}' in ${readsdir}. " +
                 "Running in single-end mode. Set --filepattern if your reads use a different " +
                 "naming convention, or --single_end true to silence this."
    }

    def reads
    if (use_paired) {
        reads = Channel
            .fromFilePairs("${readsdir}/${paired_glob}", checkIfExists: true)
            .map { sample, files -> [ [id: sample, paired_end: true], files ] }

        // Any read file that did not pair up is reported: fromFilePairs silently
        // drops singletons, which makes a naming mixup very easy to miss.
        def all_reads = file("${readsdir}/${single_glob}").collect { it.name }
        def paired_names = pair_files.collect { it.name }
        def orphans = all_reads - paired_names
        if (orphans) {
            log.warn "[${label}] ${orphans.size()} read file(s) in ${readsdir} did not match a mate and " +
                     "will be skipped: ${orphans.sort().take(10).join(', ')}" +
                     (orphans.size() > 10 ? ", ..." : "") +
                     ". Check the pair identifier ('${params.pair_identifier}') and file naming."
        }
    }
    else {
        reads = Channel
            .fromPath("${readsdir}/${single_glob}", checkIfExists: true)
            .map { f ->
                def sample = f.baseName.replaceFirst(/(\.fastq|\.fq)(\.gz)?$/, '')
                [ [id: sample, paired_end: false], f ]
            }
    }

    return reads
}


// Parse and validate the complete sheet before emitting any samples. Waiting
// for the small manifest channel to close lets us reject duplicate samples and
// duplicate file assignments deterministically rather than failing mid-run.
def samplesheet_input(samplesheet, label, require_assay) {

    return Channel
        .fromPath(samplesheet, checkIfExists: true)
        .splitCsv(header: true)
        .collect()
        .flatMap { rows ->
            if (!rows) {
                error "ERROR: samplesheet is empty: ${samplesheet}"
            }

            def headers = rows[0].keySet() as Set
            def missing = ['sample', 'read_1'].findAll { !headers.contains(it) }
            if (missing) {
                error "ERROR: samplesheet ${samplesheet} is missing required column(s): " +
                      missing.join(', ')
            }

            def assay_values = rows.collect { (it.assay ?: '').toString().trim() }
            def has_assays = assay_values.any { it }
            if (require_assay && (!headers.contains('assay') || !has_assays)) {
                error "ERROR: samplesheet mode for mgx_mtx requires an assay column " +
                      "with mgx and mtx values."
            }
            def invalid_assays = assay_values.findAll {
                it && !(it in ['mgx', 'mtx', 'assembly'])
            }.unique()
            if (invalid_assays) {
                error "ERROR: unsupported assay value(s) in ${samplesheet}: " +
                      invalid_assays.join(', ')
            }

            def selected = has_assays
                ? rows.findAll { (it.assay ?: '').toString().trim() == label }
                : rows
            if (!selected) {
                error "ERROR: samplesheet ${samplesheet} has no rows for assay '${label}'."
            }

            def seen_samples = [] as Set
            def seen_reads = [] as Set
            selected.collect { row ->
                def sample = (row.sample ?: '').toString().trim()
                def read1 = (row.read_1 ?: '').toString().trim()
                def read2 = (row.read_2 ?: '').toString().trim()

                if (!(sample ==~ /[A-Za-z0-9][A-Za-z0-9_.-]*/)) {
                    error "ERROR: invalid sample ID '${sample}' in ${samplesheet}; use only " +
                          "letters, numbers, dot, underscore, or dash."
                }
                if (!seen_samples.add(sample)) {
                    error "ERROR: duplicate sample ID '${sample}' for assay '${label}' in ${samplesheet}."
                }
                if (!read1) {
                    error "ERROR: sample '${sample}' has no read_1 in ${samplesheet}."
                }
                if (read2 && read1 == read2) {
                    error "ERROR: sample '${sample}' assigns the same file to read_1 and read_2."
                }
                for (reference in [read1, read2].findAll { it }) {
                    if (!seen_reads.add(reference)) {
                        error "ERROR: read '${reference}' is assigned more than once for assay '${label}'."
                    }
                }

                def first = file(read1, checkIfExists: true)
                if (read2) {
                    def second = file(read2, checkIfExists: true)
                    return [ [id: sample, paired_end: true], [first, second] ]
                }
                return [ [id: sample, paired_end: false], first ]
            }
        }
}
