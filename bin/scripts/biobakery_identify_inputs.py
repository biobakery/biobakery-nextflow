#!/usr/bin/env python
"""Discover bioBakery data files in an output folder and write a JSON manifest.

Ports the input-identification stage of `biobakery_workflows vis` (vis.py lines
76-131) and `biobakery_workflows stats` (stats.py lines 85-103) so the Nextflow
vis/stats workflows build their channels from exactly the same file
identification logic as the AnADAMA workflows.

Paths in the manifest are relative to the input folder, so the consuming
Nextflow workflow can re-resolve them against its own staged copy of the folder.
"""

import argparse
import json
import os
import sys

# must come before biobakery_workflows, which imports anadama2 at module scope
import biobakery_bootstrap

from biobakery_workflows import files, utilities


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Identify bioBakery data files and emit a JSON manifest")
    parser.add_argument("--input", required=True,
                        help="the folder containing the data files")
    parser.add_argument("--output", required=True,
                        help="the JSON manifest to write")
    parser.add_argument("--workflow", default="vis", choices=["vis", "stats"],
                        help="the workflow the manifest is for")
    parser.add_argument("--input-metadata", default="",
                        help="the metadata file (excluded from data file discovery)")
    parser.add_argument("--input-file-type", action="append", default=[],
                        help="a file type override formatted as 'filename,filetype'")
    return parser.parse_args()


def relative(path, folder):
    """ Express a discovered path relative to the input folder """

    if not path:
        return ""
    return os.path.relpath(os.path.abspath(path), os.path.abspath(folder))


# bioBakery file types that get_input_files_for_study_type() sweeps into the
# stats feature set even though they are not abundance tables. See
# exclude_non_abundance_files().
STATS_EXCLUDED_TYPES = ("wmgx_feature_counts", "wmgx_humann_counts")


def exclude_non_abundance_files(other_data_files, data_files):
    """ Drop the HUMAnN count tables from the stats feature set.

        get_input_files_for_study_type() collects every .tsv in the input
        folder that is not the taxonomy or pathway file, so the two HUMAnN
        count tables -- humann_feature_counts.tsv and
        humann_read_and_species_count_table.tsv -- become feature tables and
        get run through MaAsLin2, HAllA, the mantel test and beta diversity.

        They are per-sample QC summaries, not abundance tables, and they are
        written samples-as-rows while every consumer expects samples as
        columns. MaAsLin2 and beta_diversity.R detect the orientation and
        survive; the mantel test and HAllA do not, and fail the whole run --
        the mantel test on an empty distance matrix, HAllA on "There don't seem
        to be many overlapping samples between the two datasets".

        Upstream already excludes the kneaddata read count table from stats
        for the same reason (utilities.get_input_files_for_study_type, via
        exclude_types) and simply missed these two, so upstream 3.2 cannot
        complete a wmgx stats run on a folder that contains them either.

        The tables are not lost: they are what the vis report's HUMAnN
        read-count and feature-count sections are built from.
    """

    excluded_paths = set()
    for file_type in STATS_EXCLUDED_TYPES:
        for path in data_files.get(file_type, []):
            excluded_paths.add(os.path.abspath(path))

    return dict((path, file_type)
                for path, file_type in other_data_files.items()
                if os.path.abspath(path) not in excluded_paths)


def deduplicate_by_type(other_data_files):
    """ Keep one file per data type, matching what the AnADAMA workflow uses.

        get_input_files_for_study_type() derives the type from the last
        underscore-delimited part of the bioBakery file type, so distinct files
        collapse onto the same name: both wmgx_feature_counts and
        wmgx_humann_counts become "counts". create_feature_table_inputs() then
        writes both to features/<type>_features.txt and keeps only the last in
        feature_tasks_info, so downstream only ever sees one file per type.

        Nextflow cannot express that -- staging two different files under one
        name fails the task with an input file name collision -- so the
        overwrite is made explicit here. Last one wins, as it does upstream.
    """

    by_type = {}
    for path, file_type in other_data_files.items():
        by_type[file_type] = path

    return dict((path, file_type) for file_type, path in by_type.items())


def main():
    args = parse_arguments()
    folder = os.path.abspath(args.input)

    data_files = utilities.identify_data_files(
        files, folder, args.input_file_type, args.input_metadata)

    if len(data_files.keys()) < 1:
        sys.exit("ERROR: No data files found in the input folder.")

    manifest = {
        "workflow": args.workflow,
        # every discovered file, keyed by bioBakery file type
        "data_files": dict(
            (file_type, [relative(path, folder) for path in paths])
            for file_type, paths in data_files.items()),
        # the workflow log, used for the report introduction text
        "log": relative(
            files.Workflow.path("log", folder, none_if_not_found=True,
                                search_for_file=True) or "", folder),
    }

    if args.workflow == "vis":
        # vis.py distinguishes WGX from 16S by which taxonomy file was found
        if data_files.get("wmgx_taxonomy", ""):
            manifest["study_type"] = "WGX"
        elif "16s_taxonomy_asv" in data_files or "16s_taxonomy_otu" in data_files:
            manifest["study_type"] = "16S"
        else:
            print(utilities.get_vis_input_description(files))
            sys.exit(1)

        if manifest["study_type"] == "WGX":
            # the individual roles the wmgx report template expects
            manifest["taxonomic_profile"] = relative(
                utilities.find_data_file(data_files, "wmgx_taxonomy"), folder)
            manifest["qc_counts"] = relative(
                utilities.find_data_file(data_files, "wmgx_qc_readcounts"), folder)
            manifest["pathabundance"] = relative(
                utilities.find_data_file(data_files, "both_function_pathway"), folder)
            manifest["ecsabundance"] = relative(
                utilities.find_data_file(data_files, "wmgx_function_ec"), folder)
            manifest["read_counts"] = relative(
                utilities.find_data_file(data_files, "wmgx_humann_counts"), folder)
            manifest["feature_counts"] = relative(
                utilities.find_data_file(data_files, "wmgx_feature_counts"), folder)
        else:
            manifest["taxonomic_profile"] = relative(
                utilities.find_data_file(data_files, "16s_taxonomy"), folder)
    else:
        study_type = utilities.get_study_type(data_files)

        taxonomic_profile, pathabundance, other_data_files, study_type = \
            utilities.get_input_files_for_study_type(
                data_files, study_type, workflow="stats")

        other_data_files = exclude_non_abundance_files(other_data_files, data_files)

        manifest["study_type"] = study_type
        manifest["taxonomic_profile"] = relative(taxonomic_profile, folder)
        manifest["pathabundance"] = relative(pathabundance, folder)
        # path -> data type (eg "ec"), the set MaAsLin2/HAllA/beta diversity run on
        manifest["other_data_files"] = dict(
            (relative(path, folder), file_type)
            for path, file_type in deduplicate_by_type(other_data_files).items())

        if args.input_metadata:
            # samples_as_columns decides whether HAllA needs a transposed metadata
            metadata_variables, samples_as_columns = utilities.get_metadata_variables(
                args.input_metadata, taxonomic_profile)
            manifest["metadata_variables"] = metadata_variables
            manifest["samples_as_columns"] = samples_as_columns

    with open(args.output, "w") as file_handle:
        json.dump(manifest, file_handle, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
