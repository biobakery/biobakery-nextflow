#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Merge a paired sample into a single read file.
//
// Ports shotgun.merge_pairs (biobakery_workflows 3.2, tasks/shotgun.py:386),
// which is what upstream does with paired input when quality control is
// bypassed: MetaPhlAn, HUMAnN and BAQLaVa all take one input file per sample,
// so with --run_qc false the two raw mates have to be concatenated first. When
// QC runs, paired_end_kneaddata already emits the concatenated file and this is
// not used.
process merge_pairs {
    tag "$sample"

    input:
    tuple val(sample), path(reads)

    output:
    tuple val(sample), path("${sample}_merged.fastq*"), emit: merged

    script:
    // Concatenated gzip members are themselves valid gzip, so the pair can be
    // joined without decompressing; upstream gunzips only because it wants a
    // plain-text target. Mixed compression is not a case upstream handles either.
    def gzipped = reads[0].name.endsWith('.gz')
    def out     = gzipped ? "${sample}_merged.fastq.gz" : "${sample}_merged.fastq"
    """
    cat ${reads[0]} ${reads[1]} > ${out}
    """
}
