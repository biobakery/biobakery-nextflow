#!/usr/bin/env python
"""Work out the multivariate covariate equation for the beta diversity models.

Ports the equation-building portion of utilities.run_beta_diversity()
(utilities.py lines 406-421). AnADAMA derives this at DAG-construction time to
decide whether the multivariate and pairwise beta diversity tasks are added at
all, so Nextflow needs the same answer before it can build those channels.
"""

import argparse
import collections
import json


def parse_arguments():
    parser = argparse.ArgumentParser(description="Build the covariate equation")
    parser.add_argument("--manifest", required=True,
                        help="the JSON manifest holding the metadata variables")
    parser.add_argument("--output", required=True, help="the JSON to write")
    parser.add_argument("--fixed-effects", default="")
    parser.add_argument("--multivariable-fixed-effects", default="")
    parser.add_argument("--random-effects", default="")
    return parser.parse_args()


def main():
    args = parse_arguments()

    with open(args.manifest) as file_handle:
        manifest = json.load(file_handle)

    metadata_variables = manifest.get("metadata_variables", [])

    # run_beta_diversity() is called with [multivariable_fixed_effects, fixed_effects]
    fixed_effects = [args.multivariable_fixed_effects, args.fixed_effects]

    ordered_fixed_effects = list(
        collections.OrderedDict.fromkeys(",".join(fixed_effects).split(",")).keys())

    # Kept verbatim from run_beta_diversity(), including the missing separator
    # between the first effect and the rest. When only --fixed-effects is given
    # the joined string starts with a comma, so the first entry is "" and the
    # equation still reads "a + b". Dropping the empty entry would silently
    # change that to "ab", so the empty entry is deliberately left in place.
    covariate_equation = ""
    if len(ordered_fixed_effects) > 1:
        covariate_equation = ordered_fixed_effects[0]
        covariate_equation += " + ".join(ordered_fixed_effects[1:])

    # fall back to the metadata variables when no fixed effects were given
    if not covariate_equation and len(metadata_variables) > 1:
        metadata_variables_set = set(metadata_variables)
        metadata_variables_set.discard("subject")
        derived_effects = list(
            metadata_variables_set.difference(set(args.random_effects.split(","))))
        if len(derived_effects) > 1:
            covariate_equation = " + ".join(derived_effects)

    with open(args.output, "w") as file_handle:
        json.dump({"covariate_equation": covariate_equation,
                   # pairwise only runs when fixed effects were explicitly given
                   "run_pairwise": len(ordered_fixed_effects) > 1,
                   "run_multivariate": bool(covariate_equation)},
                  file_handle, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
