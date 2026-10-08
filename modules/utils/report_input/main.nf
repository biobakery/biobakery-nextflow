#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Build a bioBakery-standard output folder for vis and stats to read.
//
// `biobakery_workflows vis|stats` discover their inputs by name and location:
// files.ShotGun expects metaphlan/merged/metaphlan_taxonomic_profiles.tsv,
// kneaddata/merged/kneaddata_read_count_table.tsv,
// humann/merged/{pathabundance_relab,ecs_relab}.tsv and
// humann/counts/humann_{feature_counts,read_and_species_count_table}.tsv.
// This pipeline publishes different names in different places, so a chained run
// pointed at params.outdir found only the files identify_data_files() can sniff
// from their contents, and the report lost its QC read-count, HUMAnN
// read-count and feature-count sections.
//
// Taking the files from channels rather than from the published output folder
// also removes a race: publishDir is asynchronous, so a downstream process is
// not guaranteed to see published files at all.
//
// subdir places the whole tree under a per-assay folder, which is how
// wmgx_wmtx lays its two halves out; identify_data_files() walks subfolders.
process stage_report_input {
    tag "${subdir ?: 'report'}"
    // Published so the folder vis and stats actually read is inspectable, and
    // so a later standalone run can be pointed straight at it.
    publishDir "${params.outdir}", mode: 'copy'

    input:
    // Each optional input is staged under its own name: they share the one
    // assets/NO_FILE sentinel, and two of them are NO_FILE together whenever a
    // stage is skipped -- a mapped mgx_mtx run has no MetaPhlAn output for its
    // metatranscriptome half at all -- which fails the task with "multiple
    // input files for each of the following file names: NO_FILE".
    path taxonomic_profile, stageAs: 'taxonomy/*'   // merged MetaPhlAn profile, or NO_FILE
    path species_counts,    stageAs: 'species/*'    // MetaPhlAn species counts, or NO_FILE
    path kneaddata_counts,  stageAs: 'qc/*'         // KneadData read count table, or NO_FILE
    path humann_tables, stageAs: 'humann_tables/*'   // merged HUMAnN tables
    path humann_counts, stageAs: 'humann_counts/*'   // HUMAnN count tables
    val  subdir                   // '' or 'whole_metagenome_shotgun'

    output:
    path "report_input", emit: folder

    script:
    def base = subdir ? "report_input/${subdir}" : "report_input"
    // NO_FILE is the sentinel for a stage that did not run; a path input cannot
    // be null, which is the same convention rna_dna_norm uses. Test it here on
    // the basename, because stageAs puts each input in its own directory.
    def tax_dst     = "${base}/metaphlan/merged/metaphlan_taxonomic_profiles.tsv"
    def species_dst = "${base}/metaphlan/merged/metaphlan_species_counts_table.tsv"
    def qc_dst      = "${base}/kneaddata/merged/kneaddata_read_count_table.tsv"
    def copy_tax     = taxonomic_profile.name != 'NO_FILE' ? "cp -L ${taxonomic_profile} ${tax_dst}"     : ''
    def copy_species = species_counts.name    != 'NO_FILE' ? "cp -L ${species_counts} ${species_dst}"    : ''
    def copy_qc      = kneaddata_counts.name  != 'NO_FILE' ? "cp -L ${kneaddata_counts} ${qc_dst}"       : ''
    """
    mkdir -p ${base}/metaphlan/merged ${base}/kneaddata/merged \\
             ${base}/humann/merged ${base}/humann/counts

    ${copy_tax}
    ${copy_species}
    ${copy_qc}

    # merged_<feature>_<version>.tsv -> <feature>.tsv, the upstream spelling:
    # genefamilies, ecs, pathabundance and their _relab variants.
    for f in humann_tables/*; do
        [ -e "\$f" ] || continue
        b=\$(basename "\$f")
        case "\$b" in NO_FILE) continue ;; esac
        n=\$(echo "\$b" | sed -e 's/^merged_//' -e 's/_${params.humann_version}\\.tsv\$/.tsv/')
        cp -L "\$f" ${base}/humann/merged/"\$n"
    done

    # the count tables already carry the names files.ShotGun looks for
    for f in humann_counts/*; do
        [ -e "\$f" ] || continue
        b=\$(basename "\$f")
        case "\$b" in NO_FILE) continue ;; esac
        cp -L "\$f" ${base}/humann/counts/"\$b"
    done

    # leave no empty directories behind: identify_data_files() does not mind
    # them, but they make the staged folder harder to read when debugging
    find report_input -type d -empty -delete
    """
}

