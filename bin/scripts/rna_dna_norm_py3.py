#!/usr/bin/env python
"""
Run biobakery_workflows' rna_dna_norm.py under Python 3.

`rna_dna_norm.py` in biobakery_workflows 3.2 carries two Python-2-era defects
that make the wmgx_wmtx "norm_ratio" step unusable on the Python 3.10 install
this pipeline runs on. Both are patched here, in memory, so the shared
biobakery_workflows install stays untouched -- the same approach
assets/Rscripts/ggplot2_labs_shim.R takes for MaAsLin2.

  1. write_file() opens its output with open(file, "wb") and then writes str.
     On Python 3 this raises
         TypeError: a bytes-like object is required, not 'str'
     on the very first write, so the step can never produce output at all,
     for any input. Fixed by opening in text mode.

  2. divide_by_sample_total_abundance() indexes data[0] without checking that
     data is non-empty. When a sample set has no classified, species-stratified
     features -- which happens whenever MetaPhlAn calls no species, e.g. on
     low-biomass or heavily host-dominated libraries -- the "only classified"
     set is empty and it raises
         IndexError: list index out of range
     Fixed by returning early, which leaves the empty table empty. That is the
     correct degenerate result: with no features there is nothing to normalise.

Neither patch changes the arithmetic on any input that upstream could already
process. Arguments are passed through unchanged, so this is a drop-in
replacement for `rna_dna_norm.py`.
"""

import os
import shutil
import sys

UPSTREAM = "rna_dna_norm.py"


def find_upstream():
    """Locate the upstream script on PATH."""
    path = shutil.which(UPSTREAM)
    if not path:
        sys.exit(
            "ERROR: {0} not found on PATH. It ships with biobakery_workflows; "
            "load the module that provides it (rocky8/biobakeryworkflows/3.2) "
            "before running this step.".format(UPSTREAM)
        )
    return path


def patch(source, path):
    """Apply the two fixes described above to the upstream source text."""

    # 1. text-mode output
    binary_open = 'with open(file, "wb") as file_handle:'
    text_open = 'with open(file, "w") as file_handle:'
    if binary_open in source:
        source = source.replace(binary_open, text_open)
    elif text_open not in source:
        sys.exit(
            "ERROR: could not find the output-file open() in {0}. The upstream "
            "script has changed; re-check whether this shim is still needed.".format(path)
        )

    # 2. empty-input guard
    marker = "def divide_by_sample_total_abundance(data):"
    if marker not in source:
        sys.exit(
            "ERROR: could not find divide_by_sample_total_abundance() in {0}. The "
            "upstream script has changed; re-check whether this shim is still "
            "needed.".format(path)
        )
    guard = marker + '\n    if not data:\n        return\n'
    source = source.replace(marker, guard, 1)

    return source


def main():
    path = find_upstream()
    with open(path) as handle:
        source = handle.read()

    source = patch(source, path)

    # Run it as though it were invoked directly, so its own
    # `if __name__ == "__main__": main()` fires and argv passes straight through.
    globals_dict = {
        "__name__": "__main__",
        "__file__": path,
        "__doc__": None,
    }
    exec(compile(source, path, "exec"), globals_dict)


if __name__ == "__main__":
    main()
