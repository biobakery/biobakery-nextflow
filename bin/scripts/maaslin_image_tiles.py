#!/usr/bin/env python
"""Tile the top MaAsLin2 figures for each metadata variable.

Ports utilities.get_maaslin_image_files() and
utilities.generate_tiles_of_maaslin_figures() (utilities.py lines 677-714).

MaAsLin2 writes one figure per association, named <metadata_variable>_<rank>.png.
These are grouped by metadata variable, ordered by rank, and tiled into a single
<metadata_variable>_tiled.png that the report template displays.

The naming matters: stats_maaslin.pmd looks for the "_tiled.png" suffix.
"""

import argparse
import os
import re
import subprocess
import sys


def parse_arguments():
    parser = argparse.ArgumentParser(description="Tile MaAsLin2 figures")
    parser.add_argument("--figures-folder", required=True,
                        help="the MaAsLin2 figures folder")
    return parser.parse_args()


def get_maaslin_image_files(figures_folder):
    """ Group the ranked MaAsLin2 figures by metadata variable """

    ranked_files = [(filename, re.findall(r'\d+', filename)[-1])
                    for filename in os.listdir(figures_folder)
                    if re.search(r'_\d+.png$', filename)]
    ordered_files = sorted(ranked_files, key=lambda x: int(x[1]))

    metadata_images = {}
    for file_name, rank in ordered_files:
        if file_name.endswith("_{}.png".format(rank)):
            metadata_name = file_name.replace("_{}.png".format(rank), "")
            if not metadata_name in metadata_images:
                metadata_images[metadata_name] = []
            metadata_images[metadata_name].append(
                os.path.join(figures_folder, file_name))

    maaslin_tiles = dict(
        (metadata_name, "{}_tiled.png".format(os.path.join(figures_folder, metadata_name)))
        for metadata_name in metadata_images)

    return metadata_images, maaslin_tiles


def main():
    args = parse_arguments()

    if not os.path.isdir(args.figures_folder):
        # MaAsLin2 produces no figures folder when nothing was significant
        return

    metadata_images, maaslin_tiles = get_maaslin_image_files(args.figures_folder)

    for metadata_name, images in metadata_images.items():
        command = ["create_image_tile.py",
                   "--input", ",".join(images),
                   "--output", maaslin_tiles[metadata_name]]
        print(" ".join(command))
        return_code = subprocess.call(command)
        if return_code != 0:
            sys.exit(return_code)


if __name__ == "__main__":
    main()
