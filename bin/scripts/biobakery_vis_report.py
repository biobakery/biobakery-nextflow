#!/usr/bin/env python
"""Render the bioBakery visualization report from the universal_vis template.

Ports the document stage of `biobakery_workflows vis` (vis.py lines 94-202).
The AnADAMA tasks that vis.py builds around the document -- the EC rename and
the alpha diversity plots -- are Nextflow processes here, so their outputs are
passed in rather than computed.

The report is rendered with the vendored document class in bin/lib rather than
anadama2's, and from the vendored templates in assets/document_templates, so
the pipeline does not depend on the AnADAMA2 framework. The plotting code is
unchanged, so output stays comparable with `biobakery_workflows vis`.
"""

import argparse
import json
import os
import shutil
import sys

# must come before biobakery_workflows, which imports anadama2 at module scope
import biobakery_bootstrap

from biobakery_document import PweaveDocument

from biobakery_workflows import data, files, utilities, visualizations


def parse_arguments():
    parser = argparse.ArgumentParser(description="Render the bioBakery vis report")
    parser.add_argument("--input", required=True,
                        help="the folder containing the data files")
    parser.add_argument("--manifest", required=True,
                        help="the JSON manifest from biobakery_identify_inputs.py")
    parser.add_argument("--output", required=True,
                        help="the output folder for the report")
    parser.add_argument("--format", default="html", choices=["pdf", "html"],
                        help="the format for the report")
    parser.add_argument("--project-name", default="")
    parser.add_argument("--author-name", default="")
    parser.add_argument("--header-image", default="")
    parser.add_argument("--input-metadata", default="")
    parser.add_argument("--input-picard", default="")
    parser.add_argument("--input-picard-extension", default="quality_by_cycle_metrics")
    parser.add_argument("--metadata-categorical", action="append", default=[])
    parser.add_argument("--metadata-continuous", action="append", default=[])
    parser.add_argument("--metadata-exclude", action="append", default=[])
    parser.add_argument("--min-abundance", default=0.01)
    parser.add_argument("--min-samples", default=3)
    parser.add_argument("--max-sets-heatmap", default=25)
    parser.add_argument("--max-sets-barplot", default=15)
    parser.add_argument("--max-groups-barplot", default=5)
    parser.add_argument("--correlation-threshold", default=0.7)
    parser.add_argument("--introduction-text", default="")
    parser.add_argument("--use-template", default="",
                        help="a report template to use instead of universal_vis")
    # outputs produced by upstream Nextflow processes
    parser.add_argument("--alpha-diversity-plots", default="",
                        help="the folder of alpha diversity plots")
    parser.add_argument("--ecs-file", default="",
                        help="the EC abundance file with names added")
    return parser.parse_args()


def resolve(path, folder):
    """ Turn a manifest-relative path back into an absolute one """

    if not path:
        return ""
    return os.path.abspath(os.path.join(folder, path))


def find_package_image(basename):
    """ Locate a biobakery_workflows image, tolerating the install layout.

        utilities.get_package_file(..., "image") looks for an images folder
        beside site-packages, which is not where every install puts it -- the
        hutlab 3.2 install keeps it at the prefix instead. Fall back to walking
        up from the package before giving up, and return "" rather than raising
        so a missing decorative image cannot fail the whole report.
    """

    try:
        return utilities.get_package_file(basename, "image")
    except (OSError, IOError, IndexError):
        pass

    package_folder = os.path.dirname(os.path.abspath(utilities.__file__))
    for level in range(5):
        package_folder = os.path.dirname(package_folder)
        images_folder = os.path.join(package_folder, "images")
        if not os.path.isdir(images_folder):
            continue
        for name in sorted(os.listdir(images_folder)):
            if basename.lower() in name.lower():
                return os.path.join(images_folder, name)

    print("WARNING: could not locate the '{}' image; the report introduction "
          "will be rendered without it.".format(basename), file=sys.stderr)
    return ""


def stage_package_image(image, output):
    """ Copy a biobakery_workflows image into the report's figures folder.

        The introduction embeds the workflow diagram straight out of the
        install prefix. That path is stable on the cluster but meaningless
        anywhere else, so a report sent to a collaborator loses the diagram.
        Copying it in makes the published folder self-contained.

        The absolute staged path is returned rather than a relative one because
        pandoc has to read the file itself when rendering a PDF, and it runs
        from a temporary directory. relativize_report_links() strips the prefix
        afterwards for HTML.
    """

    if not image or not os.path.isfile(image):
        return image

    figures = os.path.join(output, "figures")
    os.makedirs(figures, exist_ok=True)

    staged = os.path.join(figures, os.path.basename(image))
    if os.path.abspath(image) != os.path.abspath(staged):
        shutil.copy(image, staged)

    return staged


def stage_alpha_diversity_plots(source, output):
    """ Copy the alpha diversity plots into the report folder.

        The plots are produced by their own Nextflow process, so they arrive
        from a different task directory than the report. The templates embed
        them by path, and only paths under the report folder survive
        publishing -- see biobakery_bootstrap.relativize_report_links. This
        also matches the layout `biobakery_workflows vis` writes, which keeps
        alpha_diversity_plots inside the vis output folder.
    """

    if not source or not os.path.isdir(source):
        return ""

    staged = os.path.join(output, "alpha_diversity_plots")
    if os.path.abspath(source) == os.path.abspath(staged):
        return staged

    if os.path.isdir(staged):
        shutil.rmtree(staged)
    shutil.copytree(source, staged)

    return staged


def main():
    args = parse_arguments()
    folder = os.path.abspath(args.input)

    with open(args.manifest) as file_handle:
        manifest = json.load(file_handle)

    workflow_type = manifest["study_type"]

    if not os.path.isdir(args.output):
        os.makedirs(args.output)

    templates = [biobakery_bootstrap.get_template("universal_vis")]
    if args.use_template:
        templates = [args.use_template]

    log_file = resolve(manifest.get("log", ""), folder)
    alpha_diversity_plots = stage_alpha_diversity_plots(
        os.path.abspath(args.alpha_diversity_plots) if args.alpha_diversity_plots else "",
        os.path.abspath(args.output))

    if workflow_type == "16S":
        # rehydrate the discovered files so the 16S variable helper can be reused
        data_files = dict(
            (file_type, [resolve(path, folder) for path in paths])
            for file_type, paths in manifest["data_files"].items())

        template_variables, template_depends, method, otu_table = \
            utilities.set_variables_for_16s_workflow_based_on_input(args, data_files)

        metadata = None
        metadata_labels = None
        if args.input_metadata:
            metadata, samples_missing_metadata = utilities.read_metadata(
                args.input_metadata, otu_table,
                ignore_features=args.metadata_exclude, otu_table=True)
            metadata_labels, metadata = utilities.label_metadata(
                metadata, categorical=args.metadata_categorical,
                continuous=args.metadata_continuous)

        if not args.introduction_text:
            template_variables["log"] = log_file
            if not log_file:
                sys.exit("When running the workflow without a log file, please provide "
                         "the introduction text with the option '--introduction-text <txt>'")
            template_variables["introduction_text"] = \
                visualizations.Sixteen_S.compile_default_intro(template_variables)
        else:
            template_variables["introduction_text"] = args.introduction_text

        report_name = "16S_report." + args.format
    else:
        introduction_text = args.introduction_text
        if not introduction_text:
            with open(data.get_file("wmgx_methods.txt")) as file_handle:
                intro_methods = file_handle.readlines()[0]
            workflow_image = stage_package_image(
                find_package_image("wms_workflow"), os.path.abspath(args.output))
            introduction_text = intro_methods
            if workflow_image:
                introduction_text = "![](" + workflow_image + \
                    "){#id .class width=675px height=505px}\n\n" + intro_methods

        qc_counts = resolve(manifest.get("qc_counts", ""), folder)
        taxonomic_profile = resolve(manifest["taxonomic_profile"], folder)
        pathabundance = resolve(manifest.get("pathabundance", ""), folder)
        read_counts = resolve(manifest.get("read_counts", ""), folder)
        feature_counts = resolve(manifest.get("feature_counts", ""), folder)

        # the EC rename runs as its own process; fall back to the discovered file
        ecsabundance = os.path.abspath(args.ecs_file) if args.ecs_file \
            else resolve(manifest.get("ecsabundance", ""), folder)

        metadata = None
        metadata_labels = None
        if args.input_metadata:
            metadata, samples_missing_metadata = utilities.read_metadata(
                args.input_metadata, taxonomic_profile,
                name_addition="_taxonomic_profile",
                ignore_features=args.metadata_exclude)
            metadata_labels, metadata = utilities.label_metadata(
                metadata, categorical=args.metadata_categorical,
                continuous=args.metadata_continuous)

        template_depends = [taxonomic_profile]
        template_variables = {
            "title": "Metagenome Report",
            "project": args.project_name,
            "introduction_text": introduction_text,
            "dna_read_counts": qc_counts,
            "is_paired": utilities.is_paired_table(qc_counts) if qc_counts else False,
            "taxonomic_profile": taxonomic_profile,
            "dna_pathabundance": pathabundance,
            "dna_ecabundance": ecsabundance,
            "read_counts": read_counts,
            "feature_counts": feature_counts,
            "log": log_file,
            "metadata": metadata,
            "metadata_labels": metadata_labels,
        }

        # named for this pipeline's own workflow vocabulary (mgx | mtx | 16s),
        # not biobakery_workflows' "wmgx"; the file is otherwise the same report
        report_name = "mgx_report." + args.format

    template_variables["alpha_diversity_plots"] = alpha_diversity_plots
    template_variables["author"] = args.author_name
    template_variables["header_image"] = args.header_image
    template_variables["study_type"] = workflow_type

    template_variables["pdf_format"] = True if args.format == "pdf" else False
    template_variables["min_abundance"] = float(args.min_abundance)
    template_variables["min_samples"] = int(args.min_samples)
    template_variables["max_sets_heatmap"] = int(args.max_sets_heatmap)
    template_variables["max_sets_barplot"] = int(args.max_sets_barplot)
    template_variables["max_groups_barplot"] = int(args.max_groups_barplot)
    template_variables["correlation_threshold"] = float(args.correlation_threshold)

    template_variables["metadata"] = metadata
    template_variables["metadata_labels"] = metadata_labels
    template_variables["log"] = log_file

    report = os.path.join(os.path.abspath(args.output), report_name)

    document = PweaveDocument(
        templates=templates,
        depends=template_depends,
        targets=[report],
        vars=template_variables,
        table_of_contents=True)

    document.create(None)

    biobakery_bootstrap.relativize_report_links(report, args.output)
    biobakery_bootstrap.remove_render_temp_dirs(args.output)


if __name__ == "__main__":
    main()
