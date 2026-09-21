#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Rename HUMAnN output features to human-readable names
process humann_rename {
    tag "$sample"
    publishDir path: { "${params.outdir}/${subdir}humann/${params.humann_version}/renamed" }, mode: 'copy'

    input:
    tuple val(sample), path(regrouped)
    val subdir

    output:
    tuple val(sample), path("${sample}_${params.humann_regroup_grouping}_named_${params.humann_version}.tsv"), emit: renamed

    when:
    params.run_humann_rename

    script:
    // humann_regroup_table and humann_rename_table take different vocabularies:
    // regroup -g wants e.g. uniref90_rxn, rename -n wants one of
    // {kegg-orthology, ec, metacyc-rxn, metacyc-pwy, pfam, eggnog, go,
    // infogo1000, uniref90}. Passing the regroup value straight through made
    // humann_rename_table exit on "invalid choice", so map it here.
    // Verified against humann_regroup_table --help (the -g options) and
    // humann_rename_table --help (the -n options); uniref90_rxn -> metacyc-rxn
    // confirmed on real output, which renamed 3912/3916 features.
    def rename_names = [
        'uniref90_rxn'        : 'metacyc-rxn',
        'uniref90_go'         : 'go',
        'uniref90_ko'         : 'kegg-orthology',
        'uniclust90_level4ec' : 'ec',
        'uniref90_pfam'       : 'pfam',
        'uniref90_eggnog'     : 'eggnog',
    ]
    def names = params.humann_rename_names ?:
                rename_names[params.humann_regroup_grouping] ?:
                params.humann_regroup_grouping
    """
    humann_rename_table \\
        -i ${regrouped} \\
        -n ${names} \\
        -o ${sample}_${params.humann_regroup_grouping}_named_${params.humann_version}.tsv
    """
}
