#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Join per-sample HUMAnN tables of one feature type into a single matrix.
//
// One invocation per feature type ("label"), rather than one invocation that
// greps for three basename patterns: the tables are staged into their own
// directory so humann_join_tables can simply take the whole folder, which is
// what it is built to do. Labels used by the workflow are
// genefamilies | ecs | pathabundance and their _relab variants.
process humann_join {
    tag "$label"
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/merged" }, mode: 'copy'

    input:
    tuple val(label), path(tables, stageAs: 'tables/*')
    val subdir

    output:
    tuple val(label), path("merged_${label}_${params.humann_version}.tsv"), emit: merged

    when:
    params.run_humann_merge

    script:
    """
    # Stage the tables under their bare sample names first. humann_join_tables
    # normally takes the sample name from each table's own header, but falls
    # back to the file basename when every file carries the same header name --
    # a test that is trivially true for a single file (join_tables.py:90). A
    # one-sample run therefore produced a column called
    # "<sample>_<feature>_<version>" while a two-sample run produced "<sample>",
    # and the mgx_mtx RNA/DNA ratio then refused to match the two halves.
    mkdir -p renamed
    for f in tables/*; do
        b=\$(basename "\$f")
        mv "\$f" renamed/"\$(echo "\$b" | sed 's/_${label}_${params.humann_version}\\.tsv\$/.tsv/')"
    done

    humann_join_tables \\
        --input renamed \\
        --output merged_${label}_${params.humann_version}.tsv
    """
}

// Count how many features each sample has above zero, per feature type.
// --ignore-un-features drops UNMAPPED/UNINTEGRATED, --ignore-stratification
// counts community-level features only.
process humann_count_features {
    tag "$label"
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/counts" }, mode: 'copy'

    input:
    tuple val(label), path(merged_relab)
    val subdir

    output:
    tuple val(label), path("humann_${label}_relab_counts.tsv"), emit: counts

    when:
    params.run_humann_merge

    script:
    """
    count_features.py \\
        --input ${merged_relab} \\
        --output humann_${label}_relab_counts.tsv \\
        --reduce-sample-name \\
        --ignore-un-features \\
        --ignore-stratification
    """
}

// Merge the three per-feature-type count tables into one
process humann_feature_counts_merge {
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/counts" }, mode: 'copy'

    input:
    path counts, stageAs: 'counts/*'
    val subdir

    output:
    path "humann_feature_counts.tsv", emit: feature_counts

    when:
    params.run_humann_merge

    script:
    """
    humann_join_tables \\
        --input counts \\
        --output humann_feature_counts.tsv \\
        --file_name _relab_counts.tsv
    """
}

// Read and species counts, taken from the per-sample HUMAnN logs.
//
// Ports the humann_count_alignments_species task of
// shotgun.functional_profile (tasks/shotgun.py:533). The vis report's HUMAnN
// read-count section is built from this, and files.ShotGun looks for it by name
// under humann/counts.
process humann_log_counts {
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/counts" }, mode: 'copy'

    input:
    path logs, stageAs: 'logs/*'
    val subdir

    output:
    path "humann_read_and_species_count_table.tsv", emit: counts

    script:
    """
    get_counts_from_humann_logs.py \\
        --input logs \\
        --output humann_read_and_species_count_table.tsv
    """
}
