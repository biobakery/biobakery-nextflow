#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Temporary bring-up gate. Consuming the aggregate table makes this task wait
// for every KneadData sample and the read-count aggregation before it fails.
// It is executor-agnostic and disabled by default; the initial DNAnexus profile
// enables it so unsupported downstream stages cannot start accidentally.
process intentional_stop_after_qc {
    tag "KneadData vertical-slice boundary"

    input:
    path read_counts

    script:
    """
    test -s ${read_counts}
    echo 'INTENTIONAL STOP: KneadData completed and its aggregate read-count table was produced.' >&2
    echo 'MetaPhlAn and all later stages are disabled for this deployment slice.' >&2
    exit 86
    """
}
