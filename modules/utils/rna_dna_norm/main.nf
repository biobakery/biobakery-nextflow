#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// RNA/DNA relative expression ratio for one feature type.
//
// Ported from shotgun.norm_ratio in biobakery_workflows 3.2. The inputs are the
// merged tables from each half of the mgx_mtx run *before* the relab
// renormalisation — the script normalises internally, so handing it the relab
// tables would double-normalise.
//
// Caveat, not a porting artefact: upstream calls these the "RPK" tables, and
// under HUMAnN 3 they are. HUMAnN 4.0.0.alpha.1 instead emits "Adjusted CPMs"
// (check the header of merged_genefamilies_*.tsv), so with
// humann_version = humann_v4a the inputs are already depth-normalised. The
// ratio is still computed the same way and `biobakery_workflows wmgx_wmtx`
// would behave identically on a HUMAnN 4 stack, but the values are a
// CPM-over-CPM ratio rather than the RPK-over-RPK one the 3.2 docs describe.
//
// The DNA and RNA tables are staged into separate directories because they have
// identical basenames (both halves produce merged_<feature>_<version>.tsv).
//
// Invoked through bin/scripts/rna_dna_norm_py3.py rather than rna_dna_norm.py
// directly: the upstream 3.2 script cannot write its output at all under
// Python 3 (it opens the file in binary mode and writes str). See that script
// for the two defects it patches in memory.
process rna_dna_norm {
    tag "$feature"
    publishDir path: { "${params.outdir}/humann/rna_dna_norm" }, mode: 'copy'

    input:
    tuple val(feature), path(dna, stageAs: 'dna/*'), path(rna, stageAs: 'rna/*')
    path mapping

    output:
    tuple val(feature), path("${feature}/rna_dna_relative_expression_unstratified.tsv"),   emit: unstratified
    tuple val(feature), path("${feature}/rna_dna_relative_expression.tsv"),                 emit: stratified
    tuple val(feature), path("${feature}/rna_dna_relative_expression_no_unclassifed.tsv"),  emit: no_unclassified

    script:
    // assets/NO_FILE is the sentinel for "no mapping file", since a path
    // input cannot be null.
    def mapping_opt = mapping.name != 'NO_FILE' ? "--mapping ${mapping}" : ''
    """
    python ${projectDir}/bin/scripts/rna_dna_norm_py3.py \\
        --input-dna ${dna} \\
        --input-rna ${rna} \\
        --output ${feature} \\
        --reduce-sample-name \\
        $mapping_opt
    """
}
