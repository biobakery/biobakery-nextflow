#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { read_input }           from '../subworkflows/read_input.nf'
include { QUALITY_CONTROL }      from '../subworkflows/quality_control.nf'
include { TAXONOMIC_PROFILING }  from '../subworkflows/taxonomic_profiling.nf'
include { FUNCTIONAL_PROFILING } from '../subworkflows/functional_profiling.nf'
include { STRAIN_PROFILING }     from '../subworkflows/strain_profiling.nf'
include { version_log }          from '../modules/utils/version_log/main.nf'
include { stage_report_input }   from '../modules/utils/report_input/main.nf'
include { REPORTING }            from '../subworkflows/reporting.nf'
include { mtx_kneaddata_dbs }    from '../subworkflows/mtx_common.nf'
include { merge_pairs }          from '../modules/utils/merge_pairs/main.nf'

// Whole Metatranscriptome (MTX) workflow.
//
// biobakery_workflows 3.2 has no standalone metatranscriptome script: the
// metatranscriptome half only exists inside wmgx_wmtx.py. This workflow is that
// half run on its own, for the case where there is no paired metagenome — the
// same taxonomic and functional profiling as mgx, but with the metatranscriptome
// KneadData database set (host genome + host mRNA + rRNA) rather than the host
// genome alone.
//
// Without a metagenome to borrow taxonomy from, the MetaPhlAn profile is
// computed from the RNA reads themselves and handed to HUMAnN, which is what
// wmgx_wmtx.py does when --input-mapping is not given.
workflow MTX {

    main:
    def no_file = file("${projectDir}/assets/NO_FILE")

    read_ch = read_input(params.readsdir, 'mtx')

    // ── QC (KneadData, metatranscriptome database set) ────────────────────
    if (params.run_qc) {
        QUALITY_CONTROL(read_ch, mtx_kneaddata_dbs(), '')
        cleaned = QUALITY_CONTROL.out.reads
    } else {
        // Upstream bypasses quality control by merging each pair into one file
        // (shotgun.merge_pairs); MetaPhlAn and HUMAnN take a single input file
        // per sample, so handing them the two raw mates passed the second one
        // as a positional argument. Single-end samples pass straight through.
        merged_pairs = merge_pairs(
            read_ch.filter { meta, r -> meta.paired_end }.map { meta, r -> tuple(meta.id, r) }
        ).merged.map { s, f -> [ [id: s, paired_end: true], f ] }

        cleaned = merged_pairs.mix( read_ch.filter { meta, r -> !meta.paired_end } )
    }

    // ── Taxonomic profiling (MetaPhlAn) ───────────────────────────────────
    if (params.run_taxonomic_profiling) {
        TAXONOMIC_PROFILING(cleaned, '')
    }

    if (!params.run_taxonomic_profiling) {
        def dependents = []
        if (params.run_functional_profiling) dependents << 'run_functional_profiling (HUMAnN needs the MetaPhlAn profile)'
        if (params.run_strain_profiling)     dependents << 'run_strain_profiling (StrainPhlAn needs the MetaPhlAn SAM)'
        if (dependents) {
            error "ERROR: run_taxonomic_profiling = false, but these require it:\n  - " +
                  dependents.join("\n  - ") +
                  "\nEnable run_taxonomic_profiling, or turn the above off."
        }
    }

    // ── Functional profiling (HUMAnN) ─────────────────────────────────────
    if (params.run_functional_profiling) {
        FUNCTIONAL_PROFILING(cleaned, TAXONOMIC_PROFILING.out.profile, '')
    }

    // ── Strain profiling (StrainPhlAn) ────────────────────────────────────
    if (params.run_strain_profiling) {
        STRAIN_PROFILING(TAXONOMIC_PROFILING.out.sam_bzip)
    }


    // ── Reports (vis / stats) ─────────────────────────────────────────────
    // Chained from the profiling channels rather than from params.outdir: see
    // modules/utils/report_input.
    if (params.run_vis || params.run_stats) {
        REPORTING(
            stage_report_input(
                params.run_taxonomic_profiling  ? TAXONOMIC_PROFILING.out.merged                   : Channel.value(no_file),
                params.run_taxonomic_profiling  ? TAXONOMIC_PROFILING.out.species_counts           : Channel.value(no_file),
                params.run_qc                   ? QUALITY_CONTROL.out.read_counts                  : Channel.value(no_file),
                params.run_functional_profiling ? FUNCTIONAL_PROFILING.out.merged_tables.collect() : Channel.value([]),
                params.run_functional_profiling ? FUNCTIONAL_PROFILING.out.count_tables.collect()  : Channel.value([]),
                ''
            ).folder
        )
    }

    if (params.log_versions) {
        version_log()
    }
}
