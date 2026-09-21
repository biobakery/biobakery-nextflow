#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { read_input }                                     from '../subworkflows/read_input.nf'
include { QUALITY_CONTROL as QC_MGX }                      from '../subworkflows/quality_control.nf'
include { QUALITY_CONTROL as QC_MTX }                      from '../subworkflows/quality_control.nf'
include { TAXONOMIC_PROFILING as TAX_MGX }                 from '../subworkflows/taxonomic_profiling.nf'
include { TAXONOMIC_PROFILING as TAX_MTX }                 from '../subworkflows/taxonomic_profiling.nf'
include { FUNCTIONAL_PROFILING as FUNC_MGX }               from '../subworkflows/functional_profiling.nf'
include { FUNCTIONAL_PROFILING as FUNC_MTX }               from '../subworkflows/functional_profiling.nf'
include { STRAIN_PROFILING }                               from '../subworkflows/strain_profiling.nf'
include { rna_dna_norm }                                   from '../modules/utils/rna_dna_norm/main.nf'
include { version_log }                                    from '../modules/utils/version_log/main.nf'
include { mtx_kneaddata_dbs }                              from '../subworkflows/mtx_common.nf'
include { stage_report_input }                             from '../modules/utils/report_input/main.nf'
include { REPORTING }                                      from '../subworkflows/reporting.nf'
include { merge_pairs as MERGE_MGX }                       from '../modules/utils/merge_pairs/main.nf'
include { merge_pairs as MERGE_MTX }                       from '../modules/utils/merge_pairs/main.nf'

// Paired whole metagenome + metatranscriptome workflow.
// Ported from biobakery_workflows 3.2 workflows/wmgx_wmtx.py.
//
// The two halves are profiled independently and published into separate output
// folders, then joined at the end by the RNA/DNA relative expression ratio.
// The interesting asymmetries, all of them from the upstream script:
//
//   * QC uses different reference database sets (see subworkflows/mtx_common.nf)
//   * with a mapping file, the RNA samples never get their own MetaPhlAn run —
//     they borrow the taxonomic profile of the DNA sample they are paired with,
//     so HUMAnN searches the same pangenomes for both and the ratio is over a
//     common feature space. Without one, each half is profiled on its own.
//   * strain profiling runs on the DNA half only
workflow MGX_MTX {

    main:

    // Upstream replaces --input with two mandatory input folder options.
    if (!params.input_metagenome || !params.input_metatranscriptome) {
        error "ERROR: the mgx_mtx workflow needs both --input_metagenome and " +
              "--input_metatranscriptome (folders of raw reads)."
    }

    // Published under the same folder names biobakery_workflows 3.2 uses, so a
    // downstream vis/stats run finds the two halves where it expects them.
    def no_file = file("${projectDir}/assets/NO_FILE")
    def MGX_DIR = 'whole_metagenome_shotgun/'
    def MTX_DIR = 'whole_metatranscriptome_shotgun/'

    mgx_reads = read_input(params.input_metagenome,        'mgx')
    mtx_reads = read_input(params.input_metatranscriptome, 'mtx')

    // ── Step 1: quality control, one database set per assay ───────────────
    if (params.run_qc) {
        QC_MGX(mgx_reads, [params.host_genome], MGX_DIR)
        QC_MTX(mtx_reads, mtx_kneaddata_dbs(),  MTX_DIR)
        mgx_clean = QC_MGX.out.reads
        mtx_clean = QC_MTX.out.reads
    } else {
        // Upstream bypasses quality control by merging each pair into one file
        // (shotgun.merge_pairs); MetaPhlAn and HUMAnN take a single input file
        // per sample, so handing them the two raw mates passed the second one
        // as a positional argument. Single-end samples pass straight through.
        merged_mgx = MERGE_MGX(
            mgx_reads.filter { meta, r -> meta.paired_end }.map { meta, r -> tuple(meta.id, r) }
        ).merged.map { s, f -> [ [id: s, paired_end: true], f ] }

        mgx_clean = merged_mgx.mix( mgx_reads.filter { meta, r -> !meta.paired_end } )

        merged_mtx = MERGE_MTX(
            mtx_reads.filter { meta, r -> meta.paired_end }.map { meta, r -> tuple(meta.id, r) }
        ).merged.map { s, f -> [ [id: s, paired_end: true], f ] }

        mtx_clean = merged_mtx.mix( mtx_reads.filter { meta, r -> !meta.paired_end } )
    }

    if (!params.run_taxonomic_profiling) {
        error "ERROR: the mgx_mtx workflow requires run_taxonomic_profiling = true; " +
              "both HUMAnN halves are driven by a MetaPhlAn profile."
    }

    // ── Step 2: taxonomic profiling ───────────────────────────────────────
    TAX_MGX(mgx_clean, MGX_DIR)

    def mapping_given = params.input_mapping as boolean

    if (mapping_given) {
        // The RNA samples take the DNA sample's profile, so no MetaPhlAn run here.
        mtx_profiles = map_profiles(mtx_clean, TAX_MGX.out.profile, params.input_mapping)
    } else {
        TAX_MTX(mtx_clean, MTX_DIR)
        mtx_profiles = TAX_MTX.out.profile
    }

    // ── Step 3: functional profiling ──────────────────────────────────────
    if (params.run_functional_profiling) {
        FUNC_MGX(mgx_clean, TAX_MGX.out.profile, MGX_DIR)
        FUNC_MTX(mtx_clean, mtx_profiles,        MTX_DIR)
    }

    // ── Step 4: RNA/DNA relative expression ratio ─────────────────────────
    // Uses the un-normalised (RPK) merged tables from each half; rna_dna_norm.py
    // normalises internally.
    if (params.run_functional_profiling && !params.bypass_norm_ratio) {
        dna_tables = FUNC_MGX.out.merged_genefamilies.map  { f -> tuple('genes', f) }
            .mix( FUNC_MGX.out.merged_ecs.map              { f -> tuple('ecs',   f) } )
            .mix( FUNC_MGX.out.merged_pathabundance.map    { f -> tuple('paths', f) } )

        rna_tables = FUNC_MTX.out.merged_genefamilies.map  { f -> tuple('genes', f) }
            .mix( FUNC_MTX.out.merged_ecs.map              { f -> tuple('ecs',   f) } )
            .mix( FUNC_MTX.out.merged_pathabundance.map    { f -> tuple('paths', f) } )

        mapping_file = mapping_given ? file(params.input_mapping, checkIfExists: true)
                                     : no_file

        rna_dna_norm(dna_tables.join(rna_tables), mapping_file)
    }

    // ── Step 5: strain profiling, on the metagenome half only ─────────────
    if (params.run_strain_profiling) {
        STRAIN_PROFILING(TAX_MGX.out.sam_bzip)
    }

    // ── Reports (vis / stats) ─────────────────────────────────────────────
    // On the metagenome half only, and staged at the root of the folder rather
    // than under whole_metagenome_shotgun/. files.ShotGun.path() looks for
    // <folder>/metaphlan/merged/metaphlan_taxonomic_profiles.tsv and, failing
    // that, <folder>/metaphlan_taxonomic_profiles.tsv -- search_for_file does
    // not walk subdirectories (files.py:79). A folder holding both assays is
    // therefore not something vis can read, which is consistent with upstream:
    // `biobakery_workflows vis` takes one assay's output folder.
    //
    // The metatranscriptome half is not reported. With a mapping file it has no
    // taxonomic profile of its own at all, and without one it is a second assay
    // needing its own report; either way `--workflow vis --vis_input
    // <outdir>/whole_metatranscriptome_shotgun` runs it separately.
    if (params.run_vis || params.run_stats) {
        REPORTING(
            stage_report_input(
                TAX_MGX.out.merged,
                TAX_MGX.out.species_counts,
                params.run_qc ? QC_MGX.out.read_counts : Channel.value(no_file),
                params.run_functional_profiling ? FUNC_MGX.out.merged_tables.collect() : Channel.value([]),
                params.run_functional_profiling ? FUNC_MGX.out.count_tables.collect()  : Channel.value([]),
                ''
            ).folder
        )
    }

    if (params.log_versions) {
        version_log()
    }
}

// Re-key the metagenome taxonomic profiles onto the metatranscriptome sample
// names, using the RNA-to-DNA mapping file.
//
// Stands in for utilities.match_files in biobakery_workflows 3.2, which pairs
// the two sets by basename prefix. The mapping file is tab delimited, "#"
// comments allowed, one "<rna sample>\t<dna sample>" pair per line.
//
// Returns: Channel of [ mtx_sample, metaphlan_profile.tsv ]
def map_profiles(mtx_reads, mgx_profiles, mapping_path) {

    def mapping = file(mapping_path, checkIfExists: true)

    def rna_to_dna = [:]
    mapping.eachLine { line ->
        if (line.startsWith('#')) return
        def cols = line.trim().split('\t')
        if (cols.size() < 2 || !cols[0] || !cols[1]) return
        def rna = cols[0].trim()
        def dna = cols[1].trim()
        // Upstream rejects names carrying extensions or pair identifiers,
        // because it matches on basename prefix and a '.' makes that ambiguous.
        if (rna.contains('.') || dna.contains('.')) {
            error "ERROR: sample names in ${mapping_path} must not contain '.' " +
                  "(no file extensions or pair identifiers): '${rna}' -> '${dna}'"
        }
        if (rna_to_dna.containsKey(rna)) {
            log.warn "Duplicate mapping for RNA sample '${rna}' in ${mapping_path}; using the last one."
        }
        rna_to_dna[rna] = dna
    }

    if (!rna_to_dna) {
        error "ERROR: no usable RNA-to-DNA pairs found in ${mapping_path}. Expected " +
              "tab-delimited lines of '<rna sample>\\t<dna sample>'."
    }

    // Longest key first, so that with both "S1" and "S10" in the file, sample
    // "S10_x" resolves to "S10" rather than to "S1". This is the tie-break
    // utilities.match_files makes with its "no longer key also matches" filter.
    def keys_by_length = rna_to_dna.keySet().sort { -it.length() }

    // [ dna_sample, rna_sample ] for every RNA sample that resolved
    dna_keyed = mtx_reads
        .map { meta, r ->
            def key = (rna_to_dna.containsKey(meta.id))
                        ? meta.id
                        : keys_by_length.find { meta.id.startsWith(it) }
            if (!key) {
                log.warn "No entry in ${mapping_path} for metatranscriptome sample " +
                         "'${meta.id}'; it will be skipped."
                return null
            }
            tuple(rna_to_dna[key], meta.id)
        }
        .filter { it != null }

    // join drops DNA samples with no RNA partner, which is the intended
    // behaviour: they are still profiled, they just have nothing to pair with.
    return dna_keyed
        .join(mgx_profiles)
        .map { dna_sample, rna_sample, profile -> tuple(rna_sample, profile) }
}
