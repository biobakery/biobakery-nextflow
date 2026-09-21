#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Align reads to assembled contigs and compute contig depth with jgi_summarize_bam_contig_depths
process align_and_depth {
    tag "$sample"
    publishDir "${params.outdir}/assembly/contig_depths", mode: 'copy'

    input:
    tuple val(sample), path(contigs)
    tuple val(sample2), path(reads)  // same order as megahit: [r1, r2, u1, u2] or single

    output:
    tuple val(sample), path("${sample}.contig_depths.txt"), emit: depths
    tuple val(sample), path("${sample}.sorted.bam"),        emit: bam,    optional: true

    script:
    def idx = "${sample}_btidx"
    // Branch on the shape actually received, not on params.paired_end. This is
    // fed the concatenated reads when QC ran, the raw pair when it did not, and
    // one file for single-end. Keying off the flag alone passed bowtie2
    // "-2 null -U null,null".
    def nfiles = (reads instanceof List) ? reads.size() : 1

    if (nfiles == 4) {
        """
        if [ ! -s ${contigs} ]; then
            # match the anadama2 workflow: write the header jgi would emit, rather
            # than an empty file, so downstream readers get a parseable table
            touch ${sample}.sorted.bam
            echo -e "contigName\tcontigLen\ttotalAvgDepth\t${sample}.sorted\t${sample}.sorted-var" > ${sample}.contig_depths.txt
        else
            bowtie2-build ${contigs} ${idx}
            bowtie2 -x ${idx} \\
                -1 ${reads[0]} -2 ${reads[1]} \\
                -U ${reads[2]},${reads[3]} \\
                -S ${sample}.sam \\
                -p ${task.cpus} \\
                --very-sensitive-local --no-unal
            samtools view -bS -F 4 ${sample}.sam > ${sample}.unsorted.bam
            samtools sort ${sample}.unsorted.bam -o ${sample}.sorted.bam --threads ${task.cpus}
            jgi_summarize_bam_contig_depths \\
                --outputDepth ${sample}.contig_depths.txt \\
                ${sample}.sorted.bam
        fi
        """
    } else if (nfiles == 2) {
        """
        if [ ! -s ${contigs} ]; then
            # match the anadama2 workflow: write the header jgi would emit, rather
            # than an empty file, so downstream readers get a parseable table
            touch ${sample}.sorted.bam
            echo -e "contigName\tcontigLen\ttotalAvgDepth\t${sample}.sorted\t${sample}.sorted-var" > ${sample}.contig_depths.txt
        else
            bowtie2-build ${contigs} ${idx}
            bowtie2 -x ${idx} \\
                -1 ${reads[0]} -2 ${reads[1]} \\
                -S ${sample}.sam \\
                -p ${task.cpus} \\
                --very-sensitive-local --no-unal
            samtools view -bS -F 4 ${sample}.sam > ${sample}.unsorted.bam
            samtools sort ${sample}.unsorted.bam -o ${sample}.sorted.bam --threads ${task.cpus}
            jgi_summarize_bam_contig_depths \\
                --outputDepth ${sample}.contig_depths.txt \\
                ${sample}.sorted.bam
        fi
        """
    } else {
        """
        if [ ! -s ${contigs} ]; then
            # match the anadama2 workflow: write the header jgi would emit, rather
            # than an empty file, so downstream readers get a parseable table
            touch ${sample}.sorted.bam
            echo -e "contigName\tcontigLen\ttotalAvgDepth\t${sample}.sorted\t${sample}.sorted-var" > ${sample}.contig_depths.txt
        else
            bowtie2-build ${contigs} ${idx}
            bowtie2 -x ${idx} \\
                -U ${reads} \\
                -S ${sample}.sam \\
                -p ${task.cpus} \\
                --very-sensitive-local --no-unal
            samtools view -bS -F 4 ${sample}.sam > ${sample}.unsorted.bam
            samtools sort ${sample}.unsorted.bam -o ${sample}.sorted.bam --threads ${task.cpus}
            jgi_summarize_bam_contig_depths \\
                --outputDepth ${sample}.contig_depths.txt \\
                ${sample}.sorted.bam
        fi
        """
    }
}
