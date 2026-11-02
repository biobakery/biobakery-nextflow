#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Capture tool versions, database paths, and workflow parameters for reproducibility
//
// The tool versions come from the steps themselves. Every process that runs a
// tool declares an output
//
//     tuple val("${task.process}"), val('<tool>'), eval('<tool> --version ...'), topic: versions
//
// so the version is read in the environment that step actually ran in -- its
// own module, container or conda env -- rather than in one environment for the
// whole run. On harvard_rc that matters: KneadData's bowtie2 is 2.2.3 and the
// assembly stack's is 2.2.9, and a single `bowtie2 --version` would report one
// of them for both. software_versions() collects that topic into one table.
//
// Topic channels are a preview feature in Nextflow 24.10; main.nf enables them
// with nextflow.preview.topic. They are stable from 25.04.

// The block that opens the run: pipeline version, where and how it ran, and the
// databases. main.nf prints it when the run starts, so it heads the console
// output and .nextflow.log, and version_log writes it at the top of
// pipeline_log.txt.
def run_header() {
    def rule = '=' * 72
    def wf   = params.workflow
    def read_based = wf in ['mgx', 'mtx', 'mgx_mtx', 'assembly', '16s']
    def rna        = wf in ['mtx', 'mgx_mtx']

    // [name, value, used by this run]
    def dbs = [
        ['host_genome',        params.host_genome,        read_based && params.run_qc],
        ['host_transcriptome', params.host_transcriptome, rna && params.run_qc],
        ['rrna_db',            params.rrna_db,            rna && params.run_qc],
        ['metaphlan_db',       params.metaphlan_db,       read_based && params.run_taxonomic_profiling],
        ['metaphlan_index',    params.metaphlan_index,    read_based && params.run_taxonomic_profiling],
        ['humann_db',          params.humann_db,          read_based && params.run_functional_profiling],
        ['strainphlan_db',     params.strainphlan_db ?: 'auto-resolved from metaphlan_db',
                                                          read_based && params.run_strain_profiling],
        ['baqlava_db',         params.baqlava_db ?: 'default (bundled)',
                                                          read_based && params.run_viral_profiling],
        ['phylophlan_path',    params.phylophlan_path,    wf == 'assembly'],
    ]
    def db_lines = dbs.collect { name, value, used ->
        "    ${name.padRight(20)}${value ?: '-'}${used ? '' : '   (not used by this run)'}"
    }

    return ([
        rule,
        "  ${workflow.manifest.name} ${workflow.manifest.version}   (commit ${pipeline_commit()})",
        rule,
        "  Workflow:     ${wf}",
        "  Profile:      ${workflow.profile}",
        "  Run name:     ${workflow.runName}   (session ${workflow.sessionId})",
        "  Launched:     ${workflow.start.format('yyyy-MM-dd HH:mm:ss xxx')} by ${workflow.userName}",
        "  Resumed:      ${workflow.resume ? 'yes' : 'no'}",
        "  Nextflow:     ${nextflow.version}",
        "  Pipeline:     ${workflow.projectDir}",
        "  Launch dir:   ${workflow.launchDir}",
        "  Output dir:   ${params.outdir}",
        "",
        "  Databases",
    ] + db_lines + [rule]).join('\n')
}

// The commit the pipeline source came from. A `nextflow run <repo>` knows it;
// a deployed copy has no .git, so the deploy writes it to COMMIT; a checkout
// is asked directly, and marked -dirty if it has uncommitted changes.
def pipeline_commit() {
    if (workflow.commitId) return workflow.commitId.take(7)
    def stamp = file("${projectDir}/COMMIT")
    if (stamp.exists()) return stamp.text.trim()
    try {
        def git = { args -> ['git', '-C', projectDir.toString()] + args }
        def head = git(['rev-parse', '--short', 'HEAD']).execute()
        def sha  = head.text.trim()
        if (head.waitFor() != 0 || !sha) return 'unknown'
        def dirty = git(['status', '--porcelain', '--untracked-files=no']).execute().text.trim()
        return sha + (dirty ? '-dirty' : '')
    } catch (Exception e) {
        return 'unknown'
    }
}

// The run header as a file, for version_log to stage.
def run_header_file() {
    Channel.value(run_header()).collectFile(name: 'run_header.txt', newLine: true)
}

// Every step's tool versions as one table: tool, version, and the steps that
// ran it. One row per tool and version, so a tool two stacks provide in
// different versions shows up twice. Written to pipeline_info/ as it is, and
// NO_FILE when no tool step ran (--check_inputs_only, or every stage off).
def software_versions() {
    Channel.topic('versions')
        .map { proc, tool, version -> [tool, version.toString().trim() ?: 'unknown', proc.tokenize(':').last()] }
        .unique()
        .groupTuple(by: [0, 1])
        .map { tool, version, steps -> "${tool}\t${version}\t${steps.unique().sort().join(', ')}" }
        .collectFile(name: 'software_versions.tsv', seed: "tool\tversion\tsteps",
                     newLine: true, sort: true, storeDir: "${params.outdir}/pipeline_info")
        .ifEmpty(file("${projectDir}/assets/NO_FILE"))
}

// Write the run header, each step's tool versions and the parameters to pipeline_log.txt
process version_log {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    path header
    path versions

    output:
    path "pipeline_log.txt", emit: pipeline_log

    script:
    """
    {
        cat ${header}
        echo ""

        echo "----------------------------------------------------------------"
        echo "  Software Versions (as each step ran them)"
        echo "----------------------------------------------------------------"
        if [ "${versions.name}" = "NO_FILE" ]; then
            echo "  No tool step ran."
        else
            awk -F'\\t' '{ printf "  %-22s %-30s %s\\n", \$1, \$2, \$3 }' ${versions}
        fi
        echo ""

        echo "----------------------------------------------------------------"
        echo "  Workflow Parameters"
        echo "----------------------------------------------------------------"
        echo "workflow:                    ${params.workflow}"
        echo "readsdir:                    ${params.readsdir}"
        echo "input_metagenome:            ${params.input_metagenome ?: '-'}"
        echo "input_metatranscriptome:     ${params.input_metatranscriptome ?: '-'}"
        echo "input_mapping:               ${params.input_mapping ?: '-'}"
        echo "outdir:                      ${params.outdir}"
        echo "paired_end:                  ${params.paired_end}"
        echo "filepattern:                 ${params.filepattern}"
        echo ""
        echo "run_qc:                      ${params.run_qc}"
        echo "  kneaddata_bypass_trim:             ${params.kneaddata_bypass_trim}"
        echo "  kneaddata_remove_intermediate:     ${params.kneaddata_remove_intermediate_files}"
        echo ""
        echo "run_taxonomic_profiling:     ${params.run_taxonomic_profiling}"
        echo "  metaphlan_version:                 ${params.metaphlan_version}"
        echo "  metaphlan_analysis_type:           ${params.metaphlan_analysis_type}"
        echo "  metaphlan_read_min_len:            ${params.metaphlan_read_min_len}"
        echo ""
        echo "run_functional_profiling:    ${params.run_functional_profiling}"
        echo "  humann_version:                    ${params.humann_version}"
        echo "  humann_bypass_prescreen:           ${params.humann_bypass_prescreen}"
        echo "  humann_bypass_nucleotide_search:   ${params.humann_bypass_nucleotide_search}"
        echo "  run_humann_regroup:                ${params.run_humann_regroup}"
        echo "  humann_regroup_grouping:           ${params.humann_regroup_grouping}"
        echo "  run_humann_rename:                 ${params.run_humann_rename}"
        echo "  run_humann_merge:                  ${params.run_humann_merge}"
        echo "  bypass_norm_ratio (mgx_mtx):       ${params.bypass_norm_ratio}"
        echo ""
        echo "run_viral_profiling:         ${params.run_viral_profiling}"
        echo "  baqlava_bypass_depletion:          ${params.baqlava_bypass_depletion}"
        echo ""
        echo "run_strain_profiling:        ${params.run_strain_profiling}"
        echo "  strainphlan_clades:                ${params.strainphlan_clades ?: 'all detected'}"
        echo "  strainphlan_phylophlan_mode:       ${params.strainphlan_phylophlan_mode}"
        echo "  strainphlan_marker_in_n_samples:   ${params.strainphlan_marker_in_n_samples}"
        echo ""
        echo "Resource caps:"
        echo "  max_memory:                ${params.max_memory}"
        echo "  max_cpus:                  ${params.max_cpus}"
        echo "  max_time:                  ${params.max_time}"
        echo ""
        echo "================================================================"

    } > pipeline_log.txt
    """
}
