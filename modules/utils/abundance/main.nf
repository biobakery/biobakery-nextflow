#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Per-sample MAG abundance, mirroring the "Calculate by-sample abundance" task of
// the anadama2 assembly workflow: index the alignment, run CheckM coverage and
// profile over the sample's bins, and record mapped and total read counts.
//
// merge_tax_and_abundance.R selects its inputs by globbing for "*.abundance.*",
// so the file naming here matters.
process abundance {
    tag "$sample"
    publishDir "${params.outdir}/abundance_${params.sgb_abundance_type}", mode: 'copy'

    input:
    tuple val(sample), path(bins_dir)
    tuple val(sample2), path(bam)
    tuple val(sample3), path(contigs)
    tuple val(sample4), path(reads)

    output:
    path "${sample}.abundance.tsv",       emit: abundance
    path "${sample}.coverage.tsv",        emit: coverage
    path "${sample}.mapped_read_num.txt", emit: mapped_reads
    path "${sample}.total_read_num.txt",  emit: total_reads

    script:
    def extra = params.checkm_coverage_options ?: ""
    // count reads across however many files this sample has (paired KneadData
    // output, a raw pair, or a single file), gzipped or not
    def read_list = (reads instanceof List) ? reads.join(' ') : "${reads}"
    """
    # find -L, not find: workflow engines stage directory inputs as symlinks and
    # plain find will not descend into them, which made every sample look empty.
    # A sample can legitimately produce no bins, or no contigs at all. Emit the
    # same headers CheckM would so the downstream merge still has a parseable
    # table, rather than failing the run.
    if [ -z "\$(find -L ${bins_dir} -type f -size +0c -print -quit)" ] || [ ! -s ${contigs} ]; then
        echo -e "Sequence Id\\tBin Id\\tSequence length (bp)\\tBam Id\\tCoverage\\tMapped reads" > ${sample}.coverage.tsv
        echo -e "Bin Id\\tBin size (Mbp)\\t${sample}.sorted: mapped reads\\t${sample}.sorted: % mapped reads\\t${sample}.sorted: % binned populations\\t${sample}.sorted: % community" > ${sample}.abundance.tsv
        echo 0 > ${sample}.mapped_read_num.txt
    else
        samtools index ${bam} -@ ${task.cpus}
        python ${projectDir}/bin/scripts/checkm.py coverage \\
            ${bins_dir} ${sample}.coverage.tsv ${bam} \\
            -x fa -t ${task.cpus} -r ${extra}
        python ${projectDir}/bin/scripts/checkm.py profile \\
            ${sample}.coverage.tsv --tab_table -f ${sample}.abundance.tsv
        samtools view -c -F 260 ${bam} -o ${sample}.mapped_read_num.txt
    fi

    # total reads across all input files for this sample
    total=0
    for f in ${read_list}; do
        case "\$f" in
            *.gz) n=\$(( \$(zcat "\$f" | wc -l) / 4 )) ;;
            *)    n=\$(( \$(cat  "\$f" | wc -l) / 4 )) ;;
        esac
        total=\$(( total + n ))
    done
    echo \$total > ${sample}.total_read_num.txt
    """
}
