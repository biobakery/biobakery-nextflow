#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// BAQLaVa — viral profiling
process baqlava {
    tag "$sample"
    publishDir path: { "${params.outdir}/${db ? "databases/${db}/" : ""}baqlava" }, mode: 'copy'

    input:
    tuple val(db), val(sample), path(kneads), path(profile)
    val references
    path reference_files, stageAs: 'references??/*'

    output:
    tuple val(db), val(sample), path("${sample}_baqlava/"), emit: results

    when:
    params.run_viral_profiling

    script:

    def quote = { value -> "'" + value.toString().replace("'", "'\"'\"'") + "'" }
    def staged = reference_files instanceof List ? reference_files : [reference_files]
    def resolved = references.withIndex().collect { reference, i -> reference +
        [path: params.baqlava_db_location == 'host' ? staged[i].toString() : reference.path] }
    def extra_args = params.baqlava_options ?: ""
    // Use taxonomic profile for bacterial depletion, or bypass for test/tiny samples with 0 detected species
    def depletion_flag = params.baqlava_bypass_depletion ? "--bypass-bacterial-depletion" : "--taxonomic-profile $profile"
    def db_flags = resolved.findAll { it.flag }.collect { "${it.flag} ${quote(it.path)}" }.join(' ')
    // BAQLaVa invokes HUMAnN itself without a database option during depletion.
    // Verify the image/site config points at the staged reference. Never rewrite
    // its installed package configuration or fall back to fetching databases.
    // HUMAnN config retains the original site/container path; host inputs also
    // make that source directory available through Nextflow's normal mounts.
    def humann_references = references.findAll { it.flag == null }
    def checks = humann_references.collect { reference ->
        def key = reference.humann_key ?: 'nucleotide'
        """
        configured_reference=\$(sed -n 's/^database_folders : ${key} = //p' .baqlava-humann-config.txt | sed 's:/*\$::')
        # Read-only bind mounts may expose the same directory at two paths.
        if [ "\$configured_reference" != ${quote(reference.path.replaceAll('/+$', ''))} ] && ! [ "\$configured_reference" -ef ${quote(reference.path)} ]; then
            echo 'ERROR: BAQLaVa HUMAnN ${key} database does not match the declared full reference; check the image config or reference mounts.' >&2
            exit 78
        fi
        printf '[baqlava] HUMAnN ${key} reference verified: %s\\n' "\$configured_reference" >&2
        """
    }.join('\n')
    def depletion_check = humann_references ? """
    humann_config --print > .baqlava-humann-config.txt
    configured_utility=\$(sed -n 's/^database_folders : utility_mapping = //p' .baqlava-humann-config.txt | sed 's:/*\$::')
    if [ "\${configured_utility##*/}" = utility_DEMO ]; then
        echo 'ERROR: the BAQLaVa image still configures HUMAnN utility_DEMO. Rebuild it with full-reference HUMAnN defaults before running BAQLaVa.' >&2
        exit 78
    fi
    ${checks}
    """ : ''
    """
    ${task.ext.get('reference_check') ?: ''}
    ${depletion_check}
    baqlava \\
        -i $kneads \\
        $depletion_flag \\
        -o ${sample}_baqlava \\
        --threads ${task.cpus} \\
        --local-jobs 1 \\
        $db_flags \\
        $extra_args
    """
}
