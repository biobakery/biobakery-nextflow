nextflow.enable.dsl=2
include { stage_report_input } from '../modules/utils/report_input/main.nf'

workflow PREPARE_REPORTS {
    take:
    taxonomy
    qc
    tables
    logs
    subdir

    main:
    // Supply an empty list per database even when optional HUMAnN outputs are absent.
    table_groups = taxonomy.map { db, f -> tuple(db, []) }
        .mix(tables.map { db, f -> tuple(db, [f]) })
        .groupTuple().map { db, files -> tuple(db, files.flatten()) }
    count_groups = taxonomy.map { db, f -> tuple(db, []) }
        .mix(logs.map { db, f -> tuple(db, [f]) })
        .groupTuple().map { db, files -> tuple(db, files.flatten()) }
    inputs = taxonomy.join(table_groups).join(count_groups)
    stage_report_input(inputs, qc, subdir)

    emit:
    folder = stage_report_input.out.folder
}
