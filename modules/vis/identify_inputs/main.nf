#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Identify the bioBakery data files in an input folder.
// Ports the discovery stage of vis.py (lines 76-131) and stats.py (lines 85-103).
//
// Both the vis and stats workflows take a folder rather than individual files,
// matching how the AnADAMA workflows are run. The manifest this emits is what
// the Nextflow workflows build their channels from.
process identify_inputs {
    tag "${report_type}"
    publishDir "${params.outdir}/${report_type}", mode: 'copy'

    input:
    path input_folder, stageAs: 'input_folder'
    path metadata
    val  report_type

    output:
    path "${report_type}_inputs.json", emit: manifest

    script:
    def metadata_opt = metadata.name != 'NO_FILE' ? "--input-metadata ${metadata}" : ''
    def file_types = optionList(params.input_file_type, '--input-file-type')
    """
    python ${projectDir}/bin/scripts/biobakery_identify_inputs.py \\
        --input input_folder \\
        --output ${report_type}_inputs.json \\
        --workflow ${report_type} \\
        ${metadata_opt} ${file_types}
    """
}

// Semicolon-delimited here: each entry is itself a "filename,filetype" pair.
def optionList(value, option) {
    if (!value) return ''
    return value.toString().tokenize(';').collect { "${option} '${it.trim()}'" }.join(' ')
}
