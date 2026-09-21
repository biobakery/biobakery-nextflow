#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Build an input read channel, detecting library layout from the filenames
// rather than making the user assert it.
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
// Returns: Channel of [ [id: sample, paired_end: bool], reads ]
def read_input(indir, label) {

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
