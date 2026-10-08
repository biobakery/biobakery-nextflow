#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// MEGAHIT — de novo metagenome assembly
process megahit {
    tag "$sample"
    publishDir "${params.outdir}/assembly/main/${sample}", mode: 'copy'

    input:
    tuple val(sample), path(reads)   // reads may be a single file (single/concatenated) or [r1, r2, u1, u2]

    output:
    tuple val(sample), path("${sample}.final.contigs.fa"), emit: contigs

    script:
    def min_len = params.megahit_min_contig_length ?: 2500
    def extra   = params.megahit_options           ?: ""

    // Branch on the shape actually received, not on params.paired_end: with QC on
    // this is KneadData's [paired_1, paired_2, unmatched_1, unmatched_2]; with QC
    // off it is the raw [R1, R2]; single-end runs give one file. Keying off the
    // flag alone indexed past the end of the list and passed megahit "null".
    def nfiles = (reads instanceof List) ? reads.size() : 1

    if (nfiles == 4) {
        """
        megahit \\
            -1 ${reads[0]} \\
            -2 ${reads[1]} \\
            -r ${reads[2]},${reads[3]} \\
            -o megahit_out \\
            --out-prefix ${sample} \\
            -m 0.99 \\
            -t ${task.cpus} \\
            --continue \\
            --min-contig-len ${min_len} \\
            ${extra}

        mv megahit_out/${sample}.contigs.fa ${sample}.final.contigs.fa
        """
    } else if (nfiles == 2) {
        """
        megahit \\
            -1 ${reads[0]} \\
            -2 ${reads[1]} \\
            -o megahit_out \\
            --out-prefix ${sample} \\
            -m 0.99 \\
            -t ${task.cpus} \\
            --continue \\
            --min-contig-len ${min_len} \\
            ${extra}

        mv megahit_out/${sample}.contigs.fa ${sample}.final.contigs.fa
        """
    } else {
        """
        megahit \\
            -r ${reads} \\
            -o megahit_out \\
            --out-prefix ${sample} \\
            -m 0.99 \\
            -t ${task.cpus} \\
            --continue \\
            --min-contig-len ${min_len} \\
            ${extra}

        mv megahit_out/${sample}.contigs.fa ${sample}.final.contigs.fa
        """
    }
}
