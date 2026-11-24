nextflow.enable.dsl=2

process humann_regroup {
    tag "${sample}:${mapping.output_label}"
    publishDir path: { "${params.outdir}/${subdir}${db ? "databases/${db}/" : ""}humann/${params.humann_version}/regrouped/${mapping.output_label}" }, mode: 'copy'

    input:
    tuple val(db), val(sample), val(mapping), path(genefamilies), path(custom, stageAs: 'mapping/*')
    val subdir

    output:
    tuple val(db), val(sample), val(mapping), path("${sample}_${mapping.output_label}_${params.humann_version}.tsv"), emit: regrouped

    script:
    def mapping_file = mapping.database_location == 'container' ? mapping.group_mapping_database : custom
    def group_arg = mapping.group_mapping_database ? "--custom '${mapping_file}'" : "--groups '${mapping.groups}'"
    def check_mapping = mapping.group_mapping_database
        ? "test -r '${mapping_file}' || { echo 'Mapping database is not readable inside the task: ${mapping_file}' >&2; exit 1; }"
        : ''
    """
    ${check_mapping}
    humann_regroup_table \\
        --input '${genefamilies}' \\
        ${group_arg} \\
        --output '${sample}_${mapping.output_label}_${params.humann_version}.tsv'
    """
}
