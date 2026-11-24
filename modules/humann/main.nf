#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// HUMAnN — profiling, regrouping, naming and normalization in one per-sample task
process humann {
    tag "$sample"
    publishDir path: { "${params.outdir}/${subdir}${db ? "databases/${db}/" : ""}humann/${params.humann_version}" }, mode: 'copy', saveAs: { name ->
        if (name.startsWith('postprocessed/')) return name.substring('postprocessed/'.length())
        if (name.startsWith('unaligned_reads/')) return name
        return "main/${name}"
    }

    input:
    tuple val(db), val(sample), path(catkneads), path(profile)
    path reference_files
    val mappings
    path mapping_files, stageAs: 'mappings??/*'
    val subdir

    output:
    tuple val(db), val(sample), path("${sample}_genefamilies_${params.humann_version}.tsv"),   emit: genefamilies
    tuple val(db), val(sample), path("${sample}_pathabundance_${params.humann_version}.tsv"),  emit: pathabundance
    tuple val(db), val(sample), path("${sample}_pathcoverage_${params.humann_version}.tsv"),   emit: pathcoverage,  optional: true
    tuple val(db), val(sample), path("${sample}_reactions_${params.humann_version}.tsv"),      emit: reactions,     optional: true
    tuple val(db), val(sample), path("${sample}_humann_${params.humann_version}.log"),         emit: log,           optional: true
    tuple val(db), val(sample), path("unaligned_reads/${sample}_bowtie2_unaligned.fa"), emit: unaligned_reads, optional: true
    tuple val(db), val(sample), path('postprocessed/regrouped/*/*.tsv'), emit: regrouped, optional: true
    tuple val(db), val(sample), path('postprocessed/renamed/*/*.tsv'), emit: renamed, optional: true
    tuple val(db), val(sample), path('postprocessed/relab/*/*.tsv'), emit: relab
    tuple val("${task.process}"), val('humann'), eval('humann --version 2>&1 | head -1 | sed "s/^humann v//"'), topic: versions

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
    def staged_files = mapping_files instanceof List ? mapping_files : [mapping_files]
    def resolved_mappings = mappings.collect { mapping ->
        def resolved = new LinkedHashMap(mapping)
        if (mapping.group_file_index != null)
            resolved.group_mapping_database = staged_files[mapping.group_file_index].toString()
        if (mapping.names_file_index != null)
            resolved.renaming_database = staged_files[mapping.names_file_index].toString()
        resolved
    }
    def quote = { value -> "'" + value.toString().replace("'", "'\"'\"'") + "'" }
    // Promote only the requested FASTA to an output. The rest of HUMAnN's
    // temporary directory stays internal, including on remote executors.
    def unaligned_source = "${sample}_humann_temp/${sample}_bowtie2_unaligned.fa"
    def unaligned_commands = params.humann_save_unaligned_reads ? """
        if [ -f ${quote(unaligned_source)} ]; then
            mkdir -p unaligned_reads
            mv -- ${quote(unaligned_source)} ${quote("unaligned_reads/${sample}_bowtie2_unaligned.fa")}
        else
            echo 'HUMAnN nucleotide-unaligned FASTA is absent; skipping export.' >&2
        fi
    """ : ''
    def gene_table = "${sample}_genefamilies_${params.humann_version}.tsv"
    def tables = [genefamilies: gene_table,
                  pathabundance: "${sample}_pathabundance_${params.humann_version}.tsv"]
    // Generate the tool commands here so they remain visible in .command.sh
    // and run sequentially in the same task as profiling.
    def regroup_commands = resolved_mappings.collect { mapping ->
        def label = mapping.output_label
        def directory = "postprocessed/regrouped/${label}"
        def regrouped = "${directory}/${sample}_${label}_${params.humann_version}.tsv"
        def group_arg = mapping.group_mapping_database
            ? "--custom ${quote(mapping.group_mapping_database)}"
            : "--groups ${quote(mapping.groups)}"
        tables[label] = regrouped
        def rename_commands = ''
        if (params.run_humann_rename && (mapping.rename || mapping.renaming_database)) {
            def names_directory = "postprocessed/renamed/${label}"
            def named = "${names_directory}/${sample}_${label}_named_${params.humann_version}.tsv"
            def names_arg = mapping.renaming_database
                ? "--custom ${quote(mapping.renaming_database)}"
                : "--names ${quote(mapping.rename)}"
            rename_commands = """
            mkdir -p -- ${quote(names_directory)}
            humann_rename_table \\
                --input ${quote(regrouped)} \\
                ${names_arg} \\
                --output ${quote(named)}
            """
        }
        """
        mkdir -p -- ${quote(directory)}
        humann_regroup_table \\
            --input ${quote(gene_table)} \\
            ${group_arg} \\
            --output ${quote(regrouped)}
        ${rename_commands}
        """
    }.join('\n')
    // Normalize stable feature IDs; named tables remain companion outputs.
    def renorm_commands = tables.collect { feature, table ->
        def directory = "postprocessed/relab/${feature}"
        def normalized = "${directory}/${sample}_${feature}_relab_${params.humann_version}.tsv"
        """
        mkdir -p -- ${quote(directory)}
        humann_renorm_table \\
            --input ${quote(table)} \\
            --output ${quote(normalized)} \\
            --units relab \\
            --special n
        """
    }.join('\n')
    """
    ${task.ext.get('reference_check') ?: ''}
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

    ${unaligned_commands}

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

    ${regroup_commands}

    ${renorm_commands}
    """
}
