#!/usr/bin/env nextflow
nextflow.enable.dsl=2

include { read_input }             from '../subworkflows/read_input.nf'
include { QUALITY_CONTROL }        from '../subworkflows/quality_control.nf'
include { megahit }                from '../modules/assembly/megahit/main.nf'
include { align_and_depth }        from '../modules/utils/align_and_depth/main.nf'
include { metabat2 }               from '../modules/binning/metabat2/main.nf'
include { abundance }              from '../modules/utils/abundance/main.nf'
include { checkm2 }                from '../modules/qc/checkm2/main.nf'
include { checkm2_merge }          from '../modules/qc/checkm2/main.nf'
include { mag_n50 }                from '../modules/qc/checkm2/main.nf'
include { checkm2_wrangling }      from '../modules/qc/checkm2/main.nf'
include { phylophlan_metagenomic } from '../modules/phylogenomics/phylophlan_metagenomic/main.nf'
include { phylophlan_merge }       from '../modules/phylogenomics/phylophlan_metagenomic/main.nf'
include { mash_list_inputs }       from '../modules/utils/mash/main.nf'
include { mash_sketch }            from '../modules/utils/mash/main.nf'
include { mash_paste }             from '../modules/utils/mash/main.nf'
include { mash_dist }              from '../modules/utils/mash/main.nf'
include { sgb_cluster }            from '../modules/utils/mash/main.nf'
include { merge_tax_abundance }    from '../modules/utils/mash/main.nf'
include { version_log }            from '../modules/utils/version_log/main.nf'

// Full MAG assembly → binning → SGB clustering pipeline.
// Ported from anadama2 biobakery-workflows feature/assembly branch.
workflow ASSEMBLY {

    main:

    // ── Build input channel ───────────────────────────────────────────────
    // Layout is detected from the filenames; see subworkflows/read_input.nf
    reads = read_input(params.readsdir, 'assembly')

    // ── Step 1: Host decontamination (KneadData) ──────────────────────────
    // KneadData carries a "when: params.run_qc" guard, so with --run_qc false the
    // QC processes never run and its channels stay empty. Inputs are then already
    // cleaned, so use them directly rather than waiting on an empty channel.
    if (params.run_qc) {
        QUALITY_CONTROL(reads, [params.host_genome], '')
        // concatenated reads: used for alignment and depth
        cleaned_flat = QUALITY_CONTROL.out.reads.map { meta, r -> tuple(meta.id, r) }
        // MEGAHIT gets the pairing rather than the concatenated file, so it can
        // assemble in paired mode the way the anadama2 assembly workflow does.
        // Which samples those are comes from the channel, not params.paired_end:
        // the layout is detected per sample in read_input, so a single-end run
        // left params.paired_end at its default true, selected the (empty)
        // paired channel, and the whole workflow completed having assembled
        // nothing. Mixing the two also handles a folder with both layouts.
        single_flat = QUALITY_CONTROL.out.reads
            .filter { meta, r -> !meta.paired_end }
            .map    { meta, r -> tuple(meta.id, r) }
        assembly_input = QUALITY_CONTROL.out.paired_reads.mix(single_flat)
    } else {
        cleaned_flat   = reads.map { meta, r -> tuple(meta.id, r) }
        assembly_input = cleaned_flat
    }

    // ── Step 2: De novo assembly (MEGAHIT) ────────────────────────────────
    contigs_out = megahit(assembly_input)

    // ── Step 3: Align reads to contigs + contig depth ─────────────────────
    contigs_with_reads = contigs_out.contigs.join(cleaned_flat)
    depth_out = align_and_depth(
        contigs_with_reads.map { s, c, r -> tuple(s, c) },
        contigs_with_reads.map { s, c, r -> tuple(s, r) }
    )

    // ── Step 4: Bin contigs into MAGs (MetaBAT2) ──────────────────────────
    bins_input = contigs_out.contigs.join(depth_out.depths)
    bins_out = metabat2(
        bins_input.map { s, c, d -> tuple(s, c) },
        bins_input.map { s, c, d -> tuple(s, d) }
    )

    // ── Step 5: MAG quality assessment (CheckM2) ──────────────────────────
    checkm_out    = checkm2(bins_out.bins)

    all_n50_input = bins_out.bins.map { s, b -> b }.collect()
    n50_out       = mag_n50(all_n50_input)

    all_reports   = checkm_out.quality.map { s, r -> r }.collect()
    merged_checkm = checkm2_merge(all_reports)
    qa_n50        = checkm2_wrangling(merged_checkm.merged, n50_out.n50)

    // ── Step 6: Phylogenetic placement (PhyloPhlAn metagenomic) ───────────
    phylo_out      = phylophlan_metagenomic(bins_out.bins)
    all_placements = phylo_out.placement.map { s, p -> p }.collect()
    phylo_merged   = phylophlan_merge(all_placements)

    // ── Step 7: SGB clustering (Mash + R) ────────────────────────────────
    all_bins   = bins_out.bins.map { s, b -> b }.collect()
    mag_list   = mash_list_inputs(qa_n50.qa_n50, phylo_merged.relab, all_bins)
    sketch     = mash_sketch(mag_list.filepaths)
    references = mash_paste(sketch.sketch)
    distances  = mash_dist(references.references, sketch.sketch)

    sgbs = sgb_cluster(distances.distances, phylo_merged.relab, qa_n50.qa_n50, mag_list.qc_bins)

    // ── Step 8: Per-sample MAG abundance ──────────────────────────────────
    // The anadama2 workflow computes this with CheckM coverage/profile; without
    // it there are no *.abundance.tsv files for the merge below to read.
    abundance_out = abundance(
        bins_out.bins,
        depth_out.bam,
        contigs_out.contigs,
        assembly_input
    )

    // ── Step 9: Merge abundance + taxonomy → final profile ────────────────
    // Collect the per-sample tables so they are all staged into the merge task's
    // directory, which is then passed as the input folder.
    // merge_tax_and_abundance.R reads three things from this folder: the
    // *.abundance.tsv tables, and the per-sample mapped/total read counts it uses
    // to scale them. Staging only the tables left mapped_props empty and the
    // script failed setting colnames on it.
    abundance_dir = abundance_out.abundance
        .mix(abundance_out.coverage)
        .mix(abundance_out.mapped_reads)
        .mix(abundance_out.total_reads)
        .collect()
    merge_tax_abundance(
        abundance_dir,
        phylo_merged.relab,
        qa_n50.qa_n50,
        sgbs.sgb_info
    )

    // ── Version / DB log ──────────────────────────────────────────────────
    if (params.log_versions) {
        version_log()
    }
}
