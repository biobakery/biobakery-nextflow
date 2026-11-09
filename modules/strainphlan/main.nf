#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Cohort phylogenies. Automatic clade discovery and its trees share one worker
// and one staged database, rather than allocating a worker for discovery alone.
process strainphlan {
    tag "${db.metaphlan_index}:${clade}"
    publishDir path: { "${params.outdir}/${db.context ? 'databases/' + db.context + '/' : ''}strainphlan/${clade}" }, mode: 'copy'

    input:
    tuple val(db), val(clade), path(markers), path(reference_files)

    output:
    tuple val(db.context), path('output/'), emit: results
    tuple val(db.context), path('output/**/*.tre'), emit: tree, optional: true
    tuple val(db.context), path('output/**/*.tsv'), emit: table, optional: true

    when:
    params.run_strain_profiling

    script:
    def quote = { value -> "'" + value.toString().replace("'", "'\"'\"'") + "'" }
    def database = params.strainphlan_db_location == 'host'
        ? "${reference_files[0]}/${db.strainphlan_db.tokenize('/').last()}" : db.strainphlan_db
    def samples = (markers instanceof List ? markers : [markers]).collect(quote).join(' ')
    def threshold_flag = db.metaphlan_version in ['metaphlan_4.0.6_fixed', '4.0', '4.0.6']
        ? '--marker_in_n_samples' : '--marker_in_n_samples_perc'
    def arguments = "--samples ${samples} --database ${quote(database)} --nprocs ${task.cpus}" +
        " --phylophlan_mode ${quote(params.strainphlan_phylophlan_mode)}" +
        " ${threshold_flag} ${params.strainphlan_marker_in_n_samples_perc} --non_interactive"
    def extra_args = params.strainphlan_options ?: ''
    def commands = clade == 'all' ? """
    "\$strainphlan_executable" ${arguments} --output_dir output --print_clades_only ${extra_args}
    test -f output/print_clades_only.tsv
    awk 'NR > 1 { print \$1 }' output/print_clades_only.tsv > output/clades.txt
    if [ ! -s output/clades.txt ]; then
        echo '[strainphlan] No clades meet the marker/sample thresholds; no trees will be built.' >&2
    fi
    while IFS= read -r detected_clade; do
        [[ "\$detected_clade" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*\$ ]] || { echo 'ERROR: unsafe clade ID in discovery output.' >&2; exit 65; }
        mkdir -p -- "output/\$detected_clade"
        "\$strainphlan_executable" ${arguments} --clade "\$detected_clade" --output_dir "output/\$detected_clade" ${extra_args}
    done < output/clades.txt
    """ : """
    "\$strainphlan_executable" ${arguments} --clade ${quote(clade)} --output_dir output ${extra_args}
    """
    """
    ${task.ext.get('reference_check') ?: ''}
    strainphlan_executable=\$(command -v strainphlan || command -v strainphlan.py) || { echo 'ERROR: StrainPhlAn is missing from the configured image/environment.' >&2; exit 127; }
    mkdir -p output
    ${commands}
    """
}
