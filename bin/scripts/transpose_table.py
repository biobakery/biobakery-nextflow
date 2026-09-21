#!/usr/bin/env python
"""Transpose a tab-delimited table.

Ports the transpose() closure in utilities.run_halla_on_input_file_set()
(utilities.py lines 718-730). HAllA needs the metadata with samples as columns,
so the metadata is transposed first when it is stored with samples as rows.
"""

import argparse


def parse_arguments():
    parser = argparse.ArgumentParser(description="Transpose a tab-delimited table")
    parser.add_argument("--input", required=True, help="the table to transpose")
    parser.add_argument("--output", required=True, help="the table to write")
    return parser.parse_args()


def main():
    args = parse_arguments()

    data = []
    with open(args.input) as file_handle:
        for line in file_handle:
            data.append(line.rstrip().split("\t"))

    with open(args.output, "w") as file_handle:
        for line in list(map(list, zip(*data))):
            file_handle.write("\t".join(line) + "\n")


if __name__ == "__main__":
    main()
