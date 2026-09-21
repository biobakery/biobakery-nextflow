#!/usr/bin/env python
"""Plot a stratified pathway barplot for one significant association.

Ports utilities.run_humann_barplot() (utilities.py lines 900-936), including
gather_top_N_associations_maaslin2_results(). AnADAMA runs this as a task
closure per (pathway rank, metadata variable) pair; here Nextflow fans out over
the pairs and each task runs this script once.

As in the original, an empty plot file is produced when there is no significant
association or the pathways are not stratified -- the report template treats a
zero-size plot as "no association found".
"""

import argparse
import subprocess
import sys

# must come before biobakery_workflows, which imports anadama2 at module scope
import biobakery_bootstrap

from biobakery_workflows.utilities import gather_top_N_associations_maaslin2_results


def parse_arguments():
    parser = argparse.ArgumentParser(description="Plot a stratified pathway barplot")
    parser.add_argument("--significant-results", required=True,
                        help="the MaAsLin2 significant_results.tsv for pathways")
    parser.add_argument("--merged-data", required=True,
                        help="the merged data/metadata table from stats_stratified_metadata.py")
    parser.add_argument("--output", required=True, help="the plot to write")
    parser.add_argument("--number", required=True, type=int,
                        help="the rank of the association to plot")
    parser.add_argument("--variable-name", required=True,
                        help="the metadata variable to focus on")
    parser.add_argument("--metadata-end", required=True,
                        help="the last metadata row in the merged table")
    return parser.parse_args()


def main():
    args = parse_arguments()

    try:
        original_selected_pathway, metadata_focus = \
            gather_top_N_associations_maaslin2_results(
                args.significant_results, args.number, args.variable_name)
    except IndexError:
        original_selected_pathway, metadata_focus = "", ""

    # humann_barplot errors on unstratified input, so check first
    stratified_pathways = False
    with open(args.merged_data) as file_handle:
        for line in file_handle:
            if "|" in line.split("\t")[0]:
                stratified_pathways = True
                break

    if not (original_selected_pathway and stratified_pathways):
        open(args.output, "w").close()
        return

    # recover the pathway name MaAsLin2 mangled into an R-safe column name
    selected_pathway = original_selected_pathway
    if not "-" in selected_pathway:
        selected_pathway = "-".join(original_selected_pathway.split(".")[0:2])

    if not "pwy" in selected_pathway.lower():
        split_pathway = original_selected_pathway.split("..")
        selected_pathway = "-".join(split_pathway[0].split("."))

    # check for the X MaAsLin2 prepends to names starting with a digit
    if selected_pathway[1].isdigit() and selected_pathway[0].lower() == "x":
        selected_pathway = selected_pathway[1:]

    command = ["humann_barplot",
               "--input", args.merged_data,
               "--focal-feature", selected_pathway,
               "--output", args.output,
               "--last-metadata", args.metadata_end,
               "--focal-metadata", metadata_focus,
               "--sort", "metadata",
               "--scaling", "logstack"]

    print(" ".join(command))
    sys.exit(subprocess.call(command))


if __name__ == "__main__":
    main()
