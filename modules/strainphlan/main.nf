#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// StrainPhlAn step 1: extract per-sample strain markers from MetaPhlAn SAM output
process sample2markers {
    tag "$sample"
    publishDir "${params.outdir}/strainphlan/markers", mode: 'copy'

    input:
    tuple val(sample), path(sam_bz2)

    output:
    tuple val(sample), path("${sample}.pkl"), emit: markers

    when:
    params.run_strain_profiling

    script:
    """
    sample2markers.py \\
        -i ${sam_bz2} \\
        -o . \\
        -n ${task.cpus}
    """
}

// StrainPhlAn step 2: build strain phylogeny per clade
process strainphlan {
    tag "$clade"
    publishDir "${params.outdir}/strainphlan/${clade}", mode: 'copy'

    input:
    val  clade
    path markers       // collected *.pkl files from all samples
    path db_clade      // clade-specific reference marker file; pass file('NO_DB') if absent

    output:
    path "output/",       emit: results
    path "output/*.tre",  emit: tree,  optional: true
    path "output/*.tsv",  emit: table, optional: true

    when:
    params.run_strain_profiling

    script:
    def db_flag     = (db_clade.name != 'NO_DB')                  ? "--database ${db_clade}"                                          : ""
    def phylo_flag  = params.strainphlan_phylophlan_mode           ? "--phylophlan-mode ${params.strainphlan_phylophlan_mode}"          : ""
    def min_samples = params.strainphlan_marker_in_n_samples       ? "--marker-in-n-samples ${params.strainphlan_marker_in_n_samples}"  : ""
    def extra_args  = params.strainphlan_options ?: ""
    """
    mkdir -p output
    strainphlan.py \\
        --samples ${markers} \\
        $db_flag \\
        --output-dir output/ \\
        --nprocesses ${task.cpus} \\
        -c ${clade} \\
        -t SGB \\
        $phylo_flag \\
        $min_samples \\
        $extra_args
    """
}
