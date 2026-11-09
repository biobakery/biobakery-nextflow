#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { database_inputs } from './database_access.nf'
include { strainphlan } from '../modules/strainphlan/main.nf'

// Per-sample extraction shares MetaPhlAn's allocation and reference. Only the
// cohort phylogeny needs a new allocation, with its matching database context.
workflow STRAIN_PROFILING {
    take:
    markers // Channel: [ resolved MetaPhlAn database map, sample, consensus markers ]

    main:
    if (params.strainphlan_marker_in_n_samples != null)
        error 'strainphlan_marker_in_n_samples is retired; use strainphlan_marker_in_n_samples_perc (0-100)'
    def threshold = params.strainphlan_marker_in_n_samples_perc
    if (!(threshold instanceof Number) || threshold < 0 || threshold > 100)
        error 'strainphlan_marker_in_n_samples_perc must be between 0 and 100'
    def clades = params.strainphlan_clades == null ? ['all'] :
        (params.strainphlan_clades instanceof List ? params.strainphlan_clades :
         params.strainphlan_clades.toString().tokenize(',')).collect { it.toString().trim() }
    if (!clades || clades.unique(false).size() != clades.size() ||
        (clades.contains('all') && clades.size() != 1) ||
        clades.any { !(it ==~ /[A-Za-z0-9][A-Za-z0-9_.-]*/) || it in ['.', '..'] })
        error 'strainphlan_clades must contain unique clade IDs, or all by itself'

    def no_db = file("${projectDir}/assets/NO_FILE")
    cohort = markers.map { db, sample, consensus -> tuple(db, consensus) }
        .groupTuple()
        .filter { db, files ->
            if (files.size() < 4)
                log.warn "[strainphlan] Skipping ${db.metaphlan_index}: ${files.size()} samples; StrainPhlAn requires at least four. Consensus markers are still published."
            files.size() >= 4
        }
        .map { db, files ->
            def pkl = params.strainphlan_db ?: "${db.metaphlan_db}/${db.metaphlan_index}.pkl"
            if (!pkl.toString().endsWith('.pkl') || !pkl.toString().contains('/'))
                error 'strainphlan_db must be a path to a MetaPhlAn .pkl database with its adjacent Bowtie2 indexes'
            def resolved = db + [strainphlan_db: pkl.toString(),
                context: params.metaphlan_databases != null ? db.metaphlan_index : '']
            def parent = pkl.toString().substring(0, pkl.toString().lastIndexOf('/'))
            tuple(resolved, files.sort { it.name },
                database_inputs(params.strainphlan_db_location, parent, no_db))
        }
    jobs = cohort.combine(Channel.fromList(clades))
        .map { db, files, references, clade -> tuple(db, clade, files, references) }
    strainphlan_out = strainphlan(jobs)

    emit:
    results = strainphlan_out.results
    trees = strainphlan_out.tree
}
