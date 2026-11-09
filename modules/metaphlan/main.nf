#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// MetaPhlAn — taxonomic profiling and SAM compression in one per-sample task
process metaphlan {
    tag "${sample}:${db.metaphlan_index}"
    publishDir path: { "${params.outdir}/${subdir}metaphlan/${db.metaphlan_index}" }, mode: 'copy', saveAs: { name -> name.endsWith('.sam.bz2') || name.startsWith('strain_markers/') ? null : name }
    publishDir path: { "${params.outdir}/${subdir}metaphlan/${params.metaphlan_databases != null ? db.metaphlan_index + '/' : ''}bzip" }, mode: 'copy', pattern: '*.sam.bz2'
    // Keep unselected variants' empty publication targets in the existing
    // MetaPhlAn folder; they must not create downstream database directories.
    publishDir path: { db.strain_enabled
        ? "${params.outdir}/${subdir}${params.metaphlan_databases != null ? 'databases/' + db.metaphlan_index + '/' : ''}strainphlan/markers"
        : "${params.outdir}/${subdir}metaphlan/${db.metaphlan_index}" },
        enabled: params.run_strain_profiling, mode: 'copy', pattern: 'strain_markers/*', saveAs: { name -> name.tokenize('/').last() }

    input:
    tuple val(db), val(sample), path(kneads), path(reference_files)
    val subdir

    output:
    tuple val(db), val(sample), path("${sample}_${db.metaphlan_index}_profile.tsv"),   emit: profile
    tuple val(db), val(sample), path("${sample}_${db.metaphlan_index}_bowtie2.tsv"),   emit: bowtie2
    tuple val(db), val(sample), path("${sample}_${db.metaphlan_index}.sam"),            emit: sam
    tuple val(db), val(sample), path("${sample}_${db.metaphlan_index}.sam.bz2"),        emit: sam_bzip
    tuple val(db), val(sample), path('strain_markers/*'), emit: markers, optional: true

    when:
    params.run_taxonomic_profiling

    script:

    def db_directory = params.metaphlan_db_location == 'host' ? reference_files[0] : db.metaphlan_db
    def extra_args = params.metaphlan_options ?: ""
    // Resolve CLI flag differences between MetaPhlAn versions
    def db_arg  = (db.metaphlan_version == '4.1')
                    ? "--bowtie2db ${db_directory}  --index ${db.metaphlan_index}"
                    : "--db_dir ${db_directory} -x ${db.metaphlan_index}"        // DEFAULT should always be the most current version
    def mapout_arg = (db.metaphlan_version == '4.1')
                    ? "--bowtie2out ${sample}_${db.metaphlan_index}_bowtie2.tsv"
                    : "--mapout ${sample}_${db.metaphlan_index}_bowtie2.tsv"        // DEFAULT should always be the most current version
    // Reuse the already-initialized image/database and uncompressed SAM. Each
    // invocation still handles one sample; this does not introduce batching.
    def marker_commands = db.strain_enabled ? """
    mkdir strain_markers
    sample2markers.py -i '${sample}_${db.metaphlan_index}.sam' -f sam \\
        -o strain_markers -d '${db_directory}/${db.metaphlan_index}.pkl' -n ${task.cpus}
    # 4.2 emits json.bz2; older MetaPhlAn releases emit pkl. Preserve sample IDs.
    shopt -s nullglob
    marker_files=(strain_markers/*.json.bz2 strain_markers/*.pkl)
    if [ "\${#marker_files[@]}" -ne 1 ]; then
        echo 'ERROR: expected exactly one sample2markers output.' >&2
        exit 65
    fi
    case "\${marker_files[0]}" in
        *.json.bz2) mv -- "\${marker_files[0]}" 'strain_markers/${sample}.json.bz2' ;;
        *.pkl) mv -- "\${marker_files[0]}" 'strain_markers/${sample}.pkl' ;;
    esac
    """ : ''
    """
    ${task.ext.get('reference_check') ?: ''}
    metaphlan $kneads \\
        --input_type fastq \\
        -o ${sample}_${db.metaphlan_index}_profile.tsv \\
        -t ${params.metaphlan_analysis_type} \\
        $mapout_arg \\
        --samout ${sample}_${db.metaphlan_index}.sam \\
        --read_min_len ${params.metaphlan_read_min_len} \\
        --nproc ${task.cpus} \\
        $db_arg \\
        $extra_args

    ${marker_commands}

    bzip2 -c -- '${sample}_${db.metaphlan_index}.sam' > '${sample}_${db.metaphlan_index}.sam.bz2'
    """
}

// Merge per-sample MetaPhlAn profiles into a single table
process metaphlan_merge {
    publishDir path: { "${params.outdir}/${subdir}metaphlan/${params.metaphlan_databases != null ? db.metaphlan_index : ""}" }, mode: 'copy'

    input:
    tuple val(db), path(profiles)
    val subdir

    output:
    tuple val(db), path("merged_metaphlan_profiles.tsv"), emit: merged

    script:
    """
    merge_metaphlan_tables.py $profiles > merged_metaphlan_profiles.tsv
    """
}

