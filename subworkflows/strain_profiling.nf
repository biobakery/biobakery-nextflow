#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { sample2markers } from '../modules/strainphlan/main.nf'
include { strainphlan }    from '../modules/strainphlan/main.nf'

// Strain profiling subworkflow: StrainPhlAn SGB-level
// Extracts per-sample markers from MetaPhlAn SAM output, then runs StrainPhlAn per detected clade.
workflow STRAIN_PROFILING {

    take:
    sam_bzip  // Channel: [ sample, .sam.bz2 ]

    main:
    markers_out = sample2markers(sam_bzip)

    // Collect all .pkl files for joint StrainPhlAn run
    all_markers = markers_out.markers.map { s, pkl -> pkl }.collect()

    // Build clade channel: use user-specified list or fall back to "all"
    if (params.strainphlan_clades) {
        clades_ch = Channel.from(params.strainphlan_clades.tokenize(','))
    } else {
        clades_ch = Channel.value('all')
    }

    // Sentinel file used when no per-clade reference DB is provided
    no_db = file('NO_DB')

    strainphlan_out = strainphlan(clades_ch, all_markers, no_db)

    emit:
    results = strainphlan_out.results
    trees   = strainphlan_out.tree
}
