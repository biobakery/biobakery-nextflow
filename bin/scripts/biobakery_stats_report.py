#!/usr/bin/env python
"""Render the bioBakery stats report from the stats template.

Ports the document stage of `biobakery_workflows stats` (stats.py lines 166-202).
Every AnADAMA task that stats.py builds -- feature tables, mantel tests,
MaAsLin2, HAllA, stratified pathway barplots, beta diversity/PERMANOVA -- is a
Nextflow process here. Their outputs are staged into a folder laid out exactly
as the AnADAMA workflow lays out its output directory, so the template variables
are rebuilt from that layout using the same naming rules as
utilities.create_feature_table_inputs() and friends.

The report is rendered with the vendored document class in bin/lib rather than
anadama2's, and from the vendored templates in assets/document_templates, so
the pipeline does not depend on the AnADAMA2 framework.
"""

import argparse
import os

# must come before biobakery_workflows, which imports anadama2 at module scope
import biobakery_bootstrap

from biobakery_document import PweaveDocument

from biobakery_workflows import utilities, visualizations

# feature type -> MaAsLin2/HAllA output subfolder suffix; only taxonomy differs
# from its feature key (utilities.create_feature_table_inputs uses "taxa")
SUBFOLDER_NAME = {"taxonomy": "taxa"}


def parse_arguments():
    parser = argparse.ArgumentParser(description="Render the bioBakery stats report")
    parser.add_argument("--output", required=True,
                        help="the folder holding the staged stats outputs")
    parser.add_argument("--taxonomic-profile", required=True,
                        help="the taxonomic profile the stats were run on")
    parser.add_argument("--feature-types", required=True,
                        help="comma-delimited feature types, eg 'taxonomy,pathways,ec'")
    parser.add_argument("--format", default="html", choices=["pdf", "html"])
    parser.add_argument("--project-name", default="")
    parser.add_argument("--author-name", default="")
    parser.add_argument("--header-image", default="")
    parser.add_argument("--introduction-text", default="")
    parser.add_argument("--top-pathways", default=3)
    parser.add_argument("--covariate-equation", default="")
    parser.add_argument("--bypass-maaslin", action="store_true")
    parser.add_argument("--bypass-halla", action="store_true")
    parser.add_argument("--use-template", default="",
                        help="a report template to use instead of stats")
    return parser.parse_args()


def subfolder(feature_type):
    """ The MaAsLin2/HAllA subfolder name for a feature type """

    return SUBFOLDER_NAME.get(feature_type, feature_type)


def existing(path):
    """ Return the path if it exists, else an empty string.

        The templates check os.path.isfile() themselves, but several steps are
        optional (mantel needs >1 data set, HAllA can find no associations), so
        only report what was actually produced.
    """

    return path if os.path.isfile(path) else ""


def main():
    args = parse_arguments()
    output = os.path.abspath(args.output)

    feature_types = [t for t in args.feature_types.split(",") if t]

    # rebuild feature_tasks_info exactly as create_feature_table_inputs() names it:
    # (feature table, MaAsLin2 heatmap, MaAsLin2 significant results)
    feature_tasks_info = {}
    for feature_type in feature_types:
        maaslin_folder = os.path.join(output, "maaslin2_" + subfolder(feature_type))
        feature_tasks_info[feature_type] = (
            os.path.join(output, "features", feature_type + "_features.txt"),
            os.path.join(maaslin_folder, "figures", "heatmap.png"),
            os.path.join(maaslin_folder, "significant_results.tsv"))

    # mantel tests only run when there is more than one data set
    mantel_plots = []
    mantel_plot = existing(os.path.join(output, "mantel_test", "mantel_plot.png"))
    if mantel_plot:
        mantel_plots = [mantel_plot]

    # HAllA skips gene families, matching run_halla_on_input_file_set()
    halla_tasks_info = {}
    if not args.bypass_halla:
        for feature_type in feature_types:
            if "gene" in feature_type:
                continue
            halla_tasks_info[feature_type] = os.path.join(
                output, "halla_" + feature_type, "hallagram.png")

    # stratified pathway plots are named stratified_pathways_<N>_<metadata>.png;
    # show_stratified_plots() parses the number and metadata name back out
    stratified_pathways_plots = []
    stratified_folder = os.path.join(output, "stratified_pathways")
    if os.path.isdir(stratified_folder):
        stratified_pathways_plots = sorted(
            os.path.join(stratified_folder, name)
            for name in os.listdir(stratified_folder)
            if name.startswith("stratified_pathways_") and name.endswith(".png"))

    # PERMANOVA runs for longitudinal studies, beta diversity otherwise
    permanova_plots = {}
    permanova_folder = os.path.join(output, "permanova")
    if os.path.isdir(permanova_folder):
        permanova_plots["all"] = os.path.join(permanova_folder, "permanova.png")
        for feature_type in feature_types:
            permanova_plots[feature_type] = os.path.join(
                permanova_folder, "permanova_{}.png".format(feature_type))

    beta_diversity_plots = {"univariate": {}, "multivariate": {}, "pairwise": {}}
    beta_folder = os.path.join(output, "beta_diversity")
    if os.path.isdir(beta_folder):
        for analysis in beta_diversity_plots:
            for feature_type in feature_types:
                plot = existing(os.path.join(
                    beta_folder, "{0}_{1}.png".format(feature_type, analysis)))
                if plot:
                    beta_diversity_plots[analysis][feature_type] = plot

    introduction_text = args.introduction_text
    if not introduction_text:
        workflow_vis = visualizations.Stats()
        introduction_text = workflow_vis.captions["intro"]
        if args.bypass_halla:
            introduction_text = workflow_vis.captions["intro_bypass_halla"]

    templates = [biobakery_bootstrap.get_template("stats")]
    if args.use_template:
        templates = [args.use_template]

    taxonomic_profile = os.path.abspath(args.taxonomic_profile)
    report = os.path.join(output, "stats_report." + args.format)

    document = PweaveDocument(
        templates=templates,
        depends=[taxonomic_profile],
        targets=[report],
        vars={"title": "Statistics report",
              "project": args.project_name,
              "author": args.author_name,
              "header_image": args.header_image,
              "introduction_text": introduction_text,
              "taxonomic_profile": taxonomic_profile,
              "mantel_plots": mantel_plots,
              "feature_tasks_info": feature_tasks_info,
              "halla_tasks_info": halla_tasks_info,
              "bypass_maaslin": args.bypass_maaslin,
              "bypass_halla": args.bypass_halla,
              "stratified_pathways_plots": stratified_pathways_plots,
              "top_pathways": args.top_pathways,
              "permanova_plots": permanova_plots,
              "beta_diversity_plots": beta_diversity_plots,
              "covariate_equation": args.covariate_equation,
              "pdf_format": True if args.format == "pdf" else False},
        table_of_contents=True)

    document.create(None)

    biobakery_bootstrap.relativize_report_links(report, output)
    biobakery_bootstrap.remove_render_temp_dirs(output)


if __name__ == "__main__":
    main()
