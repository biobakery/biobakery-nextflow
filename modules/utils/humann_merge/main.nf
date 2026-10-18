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
    publishDir path: { "${params.outdir}/${subdir}${db ? "databases/${db}/" : ""}humann/${params.humann_version}/merged" }, mode: 'copy'

    input:
    tuple val(db), val(label), path(tables, stageAs: 'tables/*')
    val subdir

    output:
    tuple val(db), val(label), path("merged_${label}_${params.humann_version}.tsv"), emit: merged

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

