"""Put the vendored report layer on the import path.

Import this before anything that reaches biobakery_workflows or the document
class. It does two things:

  1. Prepends bin/lib and bin/lib/anadama2_fallback to sys.path, so
     `biobakery_document` resolves and any `import anadama2` inside
     biobakery_workflows hits the local stand-in rather than the real
     framework.

  2. Puts the same directories on PYTHONPATH, because PweaveDocument.create()
     shells out to pweave, and the .pmd templates import biobakery_document
     from inside that subprocess.

Prepending rather than appending is deliberate: the stand-in is used even on a
machine where anadama2 happens to be installed, so behaviour does not depend on
what else is loaded in the environment.
"""

import os
import sys

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
BIN_DIR = os.path.abspath(os.path.join(SCRIPTS_DIR, os.pardir))
REPO_DIR = os.path.abspath(os.path.join(BIN_DIR, os.pardir))

LIB_DIR = os.path.join(BIN_DIR, "lib")
FALLBACK_DIR = os.path.join(LIB_DIR, "anadama2_fallback")
TEMPLATE_DIR = os.path.join(REPO_DIR, "assets", "document_templates")
RSCRIPT_DIR = os.path.join(REPO_DIR, "assets", "Rscripts")


def _bootstrap():
    for path in (FALLBACK_DIR, LIB_DIR):
        while path in sys.path:
            sys.path.remove(path)
        sys.path.insert(0, path)

    python_path = [LIB_DIR, FALLBACK_DIR]
    existing = os.environ.get("PYTHONPATH", "")
    if existing:
        python_path += [p for p in existing.split(os.pathsep)
                        if p and p not in (LIB_DIR, FALLBACK_DIR)]
    os.environ["PYTHONPATH"] = os.pathsep.join(python_path)


_bootstrap()


def get_template(basename):
    """ The vendored replacement for utilities.get_package_file(basename).

        The templates are vendored so their anadama2 imports could be swapped
        for the local document class; they must be loaded from that copy, not
        from the installed biobakery_workflows package.
    """

    template = os.path.join(TEMPLATE_DIR, basename + ".pmd")
    if not os.path.isfile(template):
        raise IOError("Report template not found: {}".format(template))
    return template


def get_rscript(basename):
    """ Resolve an R script, preferring a vendored copy over the installed one.

        Unlike the templates, the R scripts are not vendored wholesale: they run
        unmodified against biobakery_workflows 3.2 and there is no reason to
        fork code that works. Only a script that has been patched lives in
        assets/Rscripts, and it shadows the package copy of the same name; the
        rest still come from the install, so this port keeps tracking upstream.

        Each vendored script carries a header saying what was changed and why.
    """

    vendored = os.path.join(RSCRIPT_DIR, basename + ".R")
    if os.path.isfile(vendored):
        return vendored

    from biobakery_workflows import utilities
    return utilities.get_package_file(basename, "Rscript")


def relativize_report_links(report, folder):
    """ Rewrite absolute figure paths in a rendered report as relative ones.

        The .pmd templates embed figures with document.figures_folder, which is
        an absolute path. Under AnADAMA that folder *is* the final destination,
        so the links resolve; under Nextflow they point into the task's work
        directory, which is transient. A published report would then show a full
        page of broken images as soon as the work directory was cleaned, and
        could never be copied or shared.

        Stripping the report's own folder prefix turns those into paths relative
        to the report, so the whole folder relocates as a unit. Only HTML needs
        this -- pandoc embeds the images when it builds a PDF.
    """

    if not report.lower().endswith(".html") or not os.path.isfile(report):
        return

    prefix = os.path.abspath(folder).rstrip(os.sep) + os.sep

    with open(report) as file_handle:
        contents = file_handle.read()

    if prefix not in contents:
        return

    with open(report, "w") as file_handle:
        file_handle.write(contents.replace(prefix, ""))


def remove_render_temp_dirs(folder):
    """ Remove the render scratch directory left behind in the report folder.

        PweaveDocument.create() renders into a tempfile.mkdtemp() made *inside*
        the report's own folder, and clears it with
        shutil.rmtree(ignore_errors=True). On NFS that call routinely leaves the
        now-empty directory behind: deleting a file that is still open makes the
        server silly-rename it to .nfsXXXX, the rmdir then fails, ignore_errors
        swallows the failure, and the handle closes moments later -- leaving an
        empty tmp* directory.

        Upstream never notices, because there the report folder is just a
        location on disk. Here it is a published artifact, so the stray
        directory ships in outdir/<workflow>/ and inside the zip archive.

        Only empty directories are removed, so a genuine render still in
        progress or a real output folder is never touched.
    """

    if not os.path.isdir(folder):
        return

    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        if not name.startswith("tmp") or not os.path.isdir(path):
            continue
        try:
            os.rmdir(path)
        except OSError:
            # not empty, or gone already -- either way, leave it alone
            pass


if __name__ == "__main__":
    # Command-line resolver, so a process can locate an R script without having
    # bin/scripts on PYTHONPATH:
    #
    #   Rscript $(python .../biobakery_bootstrap.py --rscript alpha_diversity)
    #
    # Running this file by path puts its own directory on sys.path, which a
    # `python -c "import biobakery_bootstrap"` one-liner does not: that form
    # worked only in the hand-run environment, whose PYTHONPATH included
    # bin/scripts, and failed under every profile.
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--rscript", help="print the path of this R script")
    group.add_argument("--template", help="print the path of this .pmd template")
    args = parser.parse_args()

    print(get_rscript(args.rscript) if args.rscript else get_template(args.template))
