#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Archive a report folder.
// Ports workflow.add_archive() as used at the end of vis.py (lines 211-214) and
// stats.py (lines 206-209): an archive named after the output folder, with the
// workflow log removed, and the metadata file included when one was given.
process archive_output {
    tag "${report_type}"
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path report_folder, stageAs: 'report_folder'
    path metadata
    val  report_type

    output:
    path "${report_type}.zip", emit: archive

    script:
    def add_metadata = metadata.name != 'NO_FILE' ? "cp ${metadata} ${report_type}/" : ''
    """
    # dereference so the archive holds real files rather than staged symlinks
    cp -rL report_folder ${report_type}
    ${add_metadata}

    # add_archive(remove_log=True)
    find ${report_type} -name 'anadama.log' -delete

    zip -r ${report_type}.zip ${report_type}
    """
}
