#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// The KneadData reference database set for metatranscriptome reads.
//
// wmgx_wmtx.py passes three databases for the wts half — the host genome, the
// host transcriptome and SILVA rRNA — against one (the host genome) for the wms
// half. Removing host mRNA and rRNA matters far more for RNA libraries, where
// they can dominate the reads.
//
// Shared by the mtx workflow and the mtx half of mgx_mtx so the two cannot drift.
def mtx_kneaddata_dbs() {
    def dbs = [params.host_genome, params.host_transcriptome, params.rrna_db].findAll { it }

    def missing = []
    if (!params.host_genome)        missing << '--host_genome (host genome bowtie2 index)'
    if (!params.host_transcriptome) missing << '--host_transcriptome (host mRNA bowtie2 index)'
    if (!params.rrna_db)            missing << '--rrna_db (SILVA rRNA bowtie2 index)'
    if (missing) {
        log.warn "Metatranscriptome QC is missing reference database(s):\n  - " +
                 missing.join("\n  - ") +
                 "\nContinuing with ${dbs.size()} of 3. Set them to remove host mRNA and rRNA."
    }

    return dbs
}
