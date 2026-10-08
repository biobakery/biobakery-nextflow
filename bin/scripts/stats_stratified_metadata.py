#!/usr/bin/env python
"""Prepare the merged data/metadata table for the stratified pathway barplots.

Ports the metadata preparation and create_merged_data_file() portions of
utilities.create_stratified_pathways_plots() (utilities.py lines 473-497).

AnADAMA decides how many barplots to make at DAG-construction time, by reading
the metadata here in Python. Nextflow cannot know that at DAG time, so this
script also emits the plot plan as JSON for the workflow to fan out over.
"""

import argparse
import json

# must come before biobakery_workflows, which imports anadama2 at module scope
import biobakery_bootstrap

from biobakery_workflows import utilities
from biobakery_workflows.utilities import MAX_METADATA_CATEGORIES


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Create the humann_barplot input table and plot plan")
    parser.add_argument("--pathabundance", required=True,
                        help="the pathway abundance file")
    parser.add_argument("--input-metadata", required=True,
                        help="the metadata file")
    parser.add_argument("--output", required=True,
                        help="the merged data/metadata table to write")
    parser.add_argument("--plan", required=True,
                        help="the JSON plot plan to write")
    parser.add_argument("--top-pathways", default=3, type=int,
                        help="the top N significant pathways to plot per variable")
    parser.add_argument("--metadata-categorical", action="append", default=[])
    parser.add_argument("--metadata-continuous", action="append", default=[])
    parser.add_argument("--metadata-exclude", action="append", default=[])
    return parser.parse_args()


def create_merged_data_file(pathabundance, metadata, output, name_addition):
    """ create_merged_data_file() from utilities.py, with explicit paths """

    data = []
    with open(pathabundance) as file_handle:
        samples = [i.split(name_addition)[0]
                   for i in file_handle.readline().rstrip().split("\t")[1:]]
        for line in file_handle:
            data.append(line.rstrip().split("\t"))

    merged_data, metadata_samples = utilities.merge_metadata(metadata, samples, data)

    with open(output, "w") as file_handle:
        file_handle.write("\t".join(["Feature"] + metadata_samples) + "\n")
        for line in merged_data:
            file_handle.write("\t".join(line) + "\n")


def main():
    args = parse_arguments()

    metadata_exclude = list(args.metadata_exclude)

    metadata, samples_missing_metadata = utilities.read_metadata(
        args.input_metadata, args.pathabundance,
        name_addition="_Abundance", ignore_features=metadata_exclude)
    metadata_labels, metadata = utilities.label_metadata(
        metadata, categorical=args.metadata_categorical,
        continuous=args.metadata_continuous)

    # drop continuous variables and sample ids, they are not plotted
    metadata_exclude += [name for name, label in metadata_labels.items() if label == "con"]
    # drop variables with too many categories to plot
    for metadata_row in metadata[1:]:
        if len(list(set(metadata_row[1:]))) > MAX_METADATA_CATEGORIES:
            metadata_exclude += [metadata_row[0]]
    metadata_exclude = list(set(metadata_exclude))

    metadata, samples_missing_metadata = utilities.read_metadata(
        args.input_metadata, args.pathabundance,
        name_addition="_Abundance", ignore_features=metadata_exclude)
    metadata_labels, metadata = utilities.label_metadata(
        metadata, categorical=args.metadata_categorical,
        continuous=args.metadata_continuous)

    create_merged_data_file(args.pathabundance, metadata, args.output, "_Abundance")

    # only the categorical metadata are plotted
    metadata_row_names = [row[0] for row in metadata[1:] if row[0] in metadata_labels.keys()]

    plan = {"metadata_end": metadata_row_names[-1] if metadata_row_names else "",
            "variables": list(metadata_labels.keys()),
            "plots": [{"number": number, "variable": variable}
                      for number in range(int(args.top_pathways))
                      for variable in metadata_labels.keys()]}

    with open(args.plan, "w") as file_handle:
        json.dump(plan, file_handle, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
