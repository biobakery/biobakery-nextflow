nextflow.enable.dsl=2

process humann_rename {
    tag "${sample}:${mapping.output_label}"
    publishDir path: { "${params.outdir}/${subdir}${db ? "databases/${db}/" : ""}humann/${params.humann_version}/renamed/${mapping.output_label}" }, mode: 'copy'

    input:
    tuple val(db), val(sample), val(mapping), path(regrouped), path(custom_names, stageAs: 'names/*')
    val subdir

    output:
    tuple val(db), val(sample), val(mapping), path("${sample}_${mapping.output_label}_named_${params.humann_version}.tsv"), emit: renamed

    script:
    def mapping_file = mapping.database_location == 'container' ? mapping.renaming_database : custom_names
    def names_arg = mapping.renaming_database ? "--custom '${mapping_file}'" : "--names '${mapping.rename}'"
    def check_mapping = mapping.renaming_database
        ? "test -r '${mapping_file}' || { echo 'Mapping database is not readable inside the task: ${mapping_file}' >&2; exit 1; }"
        : ''
    """
    ${check_mapping}
    humann_rename_table \\
        --input '${regrouped}' \\
        ${names_arg} \\
        --output '${sample}_${mapping.output_label}_named_${params.humann_version}.tsv'
    """
}
