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
//   plus one [ [id, paired_end: false, skipped: reason], file ] per file the run
//   cannot use (a broken symlink, a mate without its partner). CHECK_INPUTS
//   reports and removes those, so every workflow takes this through it.
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

    // Files the run cannot use. Each is warned about here, and also travels
    // down the channel marked meta.skipped, so CHECK_INPUTS lists it in the
    // input_check report alongside the files that failed the check: the report
    // is then every file the run left out, not just the corrupt ones.
    def skipped = [:]   // file -> reason
    def mate = use_paired ? mate_pattern(params.filepattern ? null : params.pair_identifier) : null

    // A broken symlink -- common in a folder of links gathered from several
    // studies -- matches no glob, so it would vanish from the run unremarked.
    def link_glob = java.nio.file.FileSystems.getDefault()
        .getPathMatcher("glob:${use_paired ? paired_glob : single_glob}")
    def broken = (file(readsdir).listFiles() ?: [])
        .findAll { java.nio.file.Files.isSymbolicLink(it) && !it.exists() && link_glob.matches(it.fileName) }
    broken.each { skipped[it] = 'file not found (broken symlink)' }
    if (broken) {
        def names = broken.collect { it.name }.sort()
        log.warn "[${label}] ${names.size()} read file(s) in ${readsdir} are broken symlinks and will be " +
                 "skipped: ${names.take(10).join(', ')}${names.size() > 10 ? ', ...' : ''}"
    }

    def reads
    if (use_paired) {
        reads = Channel
            .fromFilePairs("${readsdir}/${paired_glob}", checkIfExists: true)
            .map { sample, files -> [ [id: sample, paired_end: true], files ] }

        // Any read file that did not pair up is reported: fromFilePairs silently
        // drops singletons, which makes a naming mixup very easy to miss. That
        // is both a file the paired glob does not match at all, and a mate the
        // glob does match whose partner is missing -- an R1 with no R2, say.
        def paired_names = pair_files.collect { it.name }
        file("${readsdir}/${single_glob}").findAll { !(it.name in paired_names) }.each {
            skipped[it] = "no mate found: name does not match the pair identifier '${params.pair_identifier}'"
        }
        if (mate) {
            pair_files.each { f ->
                def m = f.name =~ mate.regex
                if (!m.matches()) return
                def partner = m.group(1) + mate.before + (m.group(2) == mate.one ? mate.two : mate.one) + mate.after + m.group(3)
                if (!(partner in paired_names))
                    skipped[f] = "no mate found: ${partner} is missing"
            }
        }
        def orphans = skipped.findAll { f, why -> why.startsWith('no mate found') }.keySet().collect { it.name }.sort()
        if (orphans) {
            log.warn "[${label}] ${orphans.size()} read file(s) in ${readsdir} did not match a mate and " +
                     "will be skipped: ${orphans.take(10).join(', ')}" +
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

    if (skipped) {
        // Named as fromFilePairs would name the sample, so the two halves of a
        // broken pair are reported as one sample.
        def sample_of = { f ->
            def m = mate ? (f.name =~ mate.regex) : null
            m && m.matches() ? m.group(1) : f.name.replaceFirst(/(\.fastq|\.fq)(\.gz|\.bz2)?$/, '')
        }
        reads = reads.mix(Channel.fromList(skipped.collect { f, why ->
            [ [id: sample_of(f), paired_end: false, skipped: why], f ]
        }))
    }

    return reads
}

// '_R{1,2}' -> how to find a mate's partner by name: a regex capturing
// (prefix, mate, suffix), and the pieces to rebuild the partner's name. null
// when the identifier is not of that form, or when --filepattern overrides it.
def mate_pattern(pair_identifier) {
    def m = pair_identifier ? (pair_identifier =~ /^(.*)\{(\w),(\w)\}(.*)$/) : null
    if (!m || !m.matches()) return null
    def (before, one, two, after) = [m.group(1), m.group(2), m.group(3), m.group(4)]
    def q = { java.util.regex.Pattern.quote(it) }
    return [regex: /^(.*?)${q(before)}(${q(one)}|${q(two)})${q(after)}(.*)$/,
            before: before, one: one, two: two, after: after]
}
