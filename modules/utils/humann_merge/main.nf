#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Merge all raw and relative-abundance feature tables in one task per database.
process humann_join {
    tag "${db ?: 'default'}"
    publishDir path: { "${params.outdir}/${subdir}${db ? "databases/${db}/" : ""}humann/${params.humann_version}/merged" }, mode: 'copy'

    input:
    tuple val(db), val(records), path(tables, stageAs: 'tables??/*')
    val subdir

    output:
    tuple val(db), path("merged_*_${params.humann_version}.tsv"), emit: merged

    when:
    params.run_humann_merge

    script:
    def files = tables instanceof List ? tables : [tables]
    def quote = { value -> "'" + value.toString().replace("'", "'\"'\"'") + "'" }
    def by_feature = records.withIndex().collect { record, i -> record + [path: files[i]] }
        .groupBy { it.feature }
    def merge_commands = by_feature.sort().collect { feature, entries ->
        def directory = "merge_inputs/${feature}"
        // Bare sample names preserve humann_join_tables' one-sample fallback.
        def links = entries.sort { it.sample }.collect { entry ->
            "ln -s -- \"\$(realpath -- ${quote(entry.path)})\" ${quote("${directory}/${entry.sample}.tsv")}"
        }.join('\n')
        """
        mkdir -p -- ${quote(directory)}
        ${links}
        humann_join_tables \\
            --input ${quote(directory)} \\
            --output ${quote("merged_${feature}_${params.humann_version}.tsv")}
        """
    }.join('\n')
    """
    ${merge_commands}
    """
}
