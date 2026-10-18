#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// HUMAnN — functional profiling
process humann {
    tag "$sample"
    publishDir path: { "${params.outdir}/${subdir}${db ? "databases/${db}/" : ""}humann/${params.humann_version}/main" }, mode: 'copy'

    input:
    tuple val(db), val(sample), path(catkneads), path(profile)
    path reference_files
    val subdir

    output:
    tuple val(db), val(sample), path("${sample}_genefamilies_${params.humann_version}.tsv"),   emit: genefamilies
    tuple val(db), val(sample), path("${sample}_pathabundance_${params.humann_version}.tsv"),  emit: pathabundance
    tuple val(db), val(sample), path("${sample}_pathcoverage_${params.humann_version}.tsv"),   emit: pathcoverage,  optional: true
    tuple val(db), val(sample), path("${sample}_reactions_${params.humann_version}.tsv"),      emit: reactions,     optional: true
    tuple val(db), val(sample), path("${sample}_humann_${params.humann_version}.log"),         emit: log,           optional: true

    when:
    params.run_functional_profiling

    script:

    def required_databases = ['humann_db_chocophlan', 'humann_db_protein']
    if (params.humann_version == 'humann_v4a')
        required_databases << 'humann_db_utilitymapping'
    required_databases.each { name ->
        if (!params[name]) error "Missing required HUMAnN database parameter: --${name}"
    }

    def nucleotide_db = params.humann_db_location == 'host' ? reference_files[0] : params.humann_db_chocophlan
    def protein_db = params.humann_db_location == 'host' ? reference_files[1] : params.humann_db_protein
    def mapping_db = params.humann_db_location == 'host' && params.humann_db_utilitymapping ? reference_files[2] : params.humann_db_utilitymapping
    def extra_args = params.humann_options ?: ""
    def bypass_prescreen  = params.humann_bypass_prescreen          ? "--bypass-prescreen"         : ""
    def bypass_nucleotide = params.humann_bypass_nucleotide_search   ? "--bypass-nucleotide-search" : ""
    def utility_db        = (params.humann_version == 'humann_v4a') ? "--utility-database '${mapping_db}'" : ""
    """
    humann \\
        --input $catkneads \\
        --output . \\
        --taxonomic-profile $profile \\
        --nucleotide-database '${nucleotide_db}' \\
        --protein-database '${protein_db}' \\
        $utility_db \\
        --threads ${task.cpus} \\
        --output-basename ${sample} \\
        $bypass_prescreen \\
        $bypass_nucleotide \\
        $extra_args

    # Rename outputs to versioned filenames
    if [ "${params.humann_version}" = "humann_v4a" ]; then
        mv ${sample}_0.log               ${sample}_humann_${params.humann_version}.log        2>/dev/null || true
        mv ${sample}_2_genefamilies.tsv  ${sample}_genefamilies_${params.humann_version}.tsv  2>/dev/null || true
        mv ${sample}_3_reactions.tsv     ${sample}_reactions_${params.humann_version}.tsv     2>/dev/null || true
        mv ${sample}_4_pathabundance.tsv ${sample}_pathabundance_${params.humann_version}.tsv 2>/dev/null || true
        mv ${sample}_5_pathcoverage.tsv  ${sample}_pathcoverage_${params.humann_version}.tsv  2>/dev/null || true
    else
        mv ${sample}_genefamilies.tsv    ${sample}_genefamilies_${params.humann_version}.tsv  2>/dev/null || true
        mv ${sample}_pathabundance.tsv   ${sample}_pathabundance_${params.humann_version}.tsv 2>/dev/null || true
        mv ${sample}_pathcoverage.tsv    ${sample}_pathcoverage_${params.humann_version}.tsv  2>/dev/null || true
    fi
    """
}
