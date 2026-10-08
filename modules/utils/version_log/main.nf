#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Capture tool versions, database paths, and workflow parameters for reproducibility
process version_log {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    output:
    path "pipeline_log.txt", emit: pipeline_log

    script:
    def baqlava_db_str     = params.baqlava_db     ?: 'default (bundled)'
    def strainphlan_db_str = params.strainphlan_db  ?: 'auto-resolved from metaphlan_db'
    def phylophlan_str     = params.phylophlan_path ?: 'not set'
    """
    {
        echo "================================================================"
        echo "  biobakery-workflows-nextflow — Pipeline Run Log"
        echo "================================================================"
        echo ""
        echo "Date: \$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo ""

        echo "----------------------------------------------------------------"
        echo "  Tool Versions"
        echo "----------------------------------------------------------------"
        kneaddata  --version 2>&1 | head -1 || echo "kneaddata:   not in PATH"
        metaphlan  --version 2>&1 | head -1 || echo "metaphlan:   not in PATH"
        humann     --version 2>&1 | head -1 || echo "humann:      not in PATH"
        if which baqlava >/dev/null 2>&1; then
            baqlava --version 2>&1 | head -1 || echo "baqlava:     (no --version flag)"
        else
            echo "baqlava:     not installed / not in PATH"
        fi
        if which strainphlan.py >/dev/null 2>&1; then
            strainphlan.py --version 2>&1 | head -1 || echo "strainphlan: (no --version flag)"
        else
            echo "strainphlan: not installed / not in PATH"
        fi
        echo ""

        echo "----------------------------------------------------------------"
        echo "  Database Paths"
        echo "----------------------------------------------------------------"
        echo "host_genome:     ${params.host_genome}"
        echo "metaphlan_db:     ${params.metaphlan_db}"
        echo "metaphlan_index:  ${params.metaphlan_index}"
        echo "humann_db:        ${params.humann_db}"
        echo "baqlava_db:       ${baqlava_db_str}"
        echo "strainphlan_db:   ${strainphlan_db_str}"
        echo "phylophlan_path:  ${phylophlan_str}"
        echo ""

        echo "----------------------------------------------------------------"
        echo "  Workflow Parameters"
        echo "----------------------------------------------------------------"
        echo "workflow:                    ${params.workflow}"
        echo "readsdir:                    ${params.readsdir}"
        echo "input_metagenome:            ${params.input_metagenome ?: '-'}"
        echo "input_metatranscriptome:     ${params.input_metatranscriptome ?: '-'}"
        echo "input_mapping:               ${params.input_mapping ?: '-'}"
        echo "outdir:                      ${params.outdir}"
        echo "paired_end:                  ${params.paired_end}"
        echo "filepattern:                 ${params.filepattern}"
        echo ""
        echo "run_qc:                      ${params.run_qc}"
        echo "  host_genome:                       ${params.host_genome ?: '-'}"
        echo "  host_transcriptome:                ${params.host_transcriptome ?: '-'}"
        echo "  rrna_db:                           ${params.rrna_db ?: '-'}"
        echo "  kneaddata_bypass_trim:             ${params.kneaddata_bypass_trim}"
        echo "  kneaddata_remove_intermediate:     ${params.kneaddata_remove_intermediate_files}"
        echo ""
        echo "run_taxonomic_profiling:     ${params.run_taxonomic_profiling}"
        echo "  metaphlan_version:                 ${params.metaphlan_version}"
        echo "  metaphlan_analysis_type:           ${params.metaphlan_analysis_type}"
        echo "  metaphlan_read_min_len:            ${params.metaphlan_read_min_len}"
        echo ""
        echo "run_functional_profiling:    ${params.run_functional_profiling}"
        echo "  humann_version:                    ${params.humann_version}"
        echo "  humann_bypass_prescreen:           ${params.humann_bypass_prescreen}"
        echo "  humann_bypass_nucleotide_search:   ${params.humann_bypass_nucleotide_search}"
        echo "  run_humann_regroup:                ${params.run_humann_regroup}"
        echo "  humann_regroup_grouping:           ${params.humann_regroup_grouping}"
        echo "  run_humann_rename:                 ${params.run_humann_rename}"
        echo "  run_humann_merge:                  ${params.run_humann_merge}"
        echo "  bypass_norm_ratio (mgx_mtx):       ${params.bypass_norm_ratio}"
        echo ""
        echo "run_viral_profiling:         ${params.run_viral_profiling}"
        echo "  baqlava_bypass_depletion:          ${params.baqlava_bypass_depletion}"
        echo ""
        echo "run_strain_profiling:        ${params.run_strain_profiling}"
        echo "  strainphlan_clades:                ${params.strainphlan_clades ?: 'all detected'}"
        echo "  strainphlan_phylophlan_mode:       ${params.strainphlan_phylophlan_mode}"
        echo "  strainphlan_marker_in_n_samples:   ${params.strainphlan_marker_in_n_samples}"
        echo ""
        echo "Resource caps:"
        echo "  max_memory:                ${params.max_memory}"
        echo "  max_cpus:                  ${params.max_cpus}"
        echo "  max_time:                  ${params.max_time}"
        echo ""
        echo "================================================================"

    } > pipeline_log.txt
    """
}
