#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// MetaBAT2 — bin contigs into Metagenome-Assembled Genomes (MAGs)
process metabat2 {
    tag "$sample"
    publishDir "${params.outdir}/bins/${sample}", mode: 'copy'

    input:
    tuple val(sample), path(contigs)
    tuple val(sample2), path(depths)

    output:
    tuple val(sample), path("bins/"),  emit: bins
    path "bins/*.bin.*.fa",            emit: bin_fastas, optional: true

    script:
    def min_len = params.megahit_min_contig_length ?: 2500
    def extra   = params.metabat_options           ?: ""
    """
    mkdir -p bins

    if [ ! -s ${contigs} ]; then
        # No contigs (empty assembly) — create placeholder files so pipeline continues
        touch bins/${sample}.bin.lowDepth.fa
        touch bins/${sample}.bin.tooShort.fa
        touch bins/${sample}.bin.unbinned.fa
    else
        metabat2 \\
            -i ${contigs} \\
            -a ${depths} \\
            -o bins/${sample}.bin \\
            --unbinned \\
            -m ${min_len} \\
            -t ${task.cpus} \\
            ${extra}

        # Ensure placeholder files exist if metabat2 produced nothing
        if [ -z "\$(ls bins/)" ]; then
            touch bins/${sample}.bin.lowDepth.fa
            touch bins/${sample}.bin.tooShort.fa
            touch bins/${sample}.bin.unbinned.fa
        fi
    fi
    """
}
