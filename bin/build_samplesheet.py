#!/usr/bin/env python3
"""Build a bioBakery read samplesheet and optionally upload it to DNAnexus.

The script is deliberately independent of Nextflow. It can discover FASTQ
files in a local directory or query a DNAnexus project folder with dx-toolkit.
Generation is local-only unless --upload-to is explicitly supplied.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_PAIR_REGEX = (
    r"^(?P<sample>.+)_R(?P<mate>[12])(?:_001)?\.(?:fastq|fq)\.gz$"
)
FASTQ_SUFFIXES = (".fastq.gz", ".fq.gz")
SAFE_SAMPLE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
FIELDS = ("sample", "assay", "read_1", "read_2")


class SamplesheetError(RuntimeError):
    """A user-facing samplesheet construction error."""


@dataclass(frozen=True)
class ReadFile:
    name: str
    reference: str


def is_fastq(name: str) -> bool:
    return name.lower().endswith(FASTQ_SUFFIXES)


def strip_fastq_suffix(name: str) -> str:
    lowered = name.lower()
    for suffix in FASTQ_SUFFIXES:
        if lowered.endswith(suffix):
            return name[: -len(suffix)]
    raise SamplesheetError(f"Unsupported read filename: {name}")


def local_reads(folder: Path, recursive: bool) -> list[ReadFile]:
    if not folder.is_dir():
        raise SamplesheetError(f"Local reads directory not found: {folder}")
    iterator: Iterable[Path] = folder.rglob("*") if recursive else folder.iterdir()
    reads = [
        ReadFile(path.name, str(path.resolve()))
        for path in iterator
        if path.is_file() and is_fastq(path.name)
    ]
    return sorted(reads, key=lambda item: (item.name, item.reference))


def _dx_records(payload: object) -> list[dict]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        for key in ("results", "objects", "data"):
            value = payload.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]
    raise SamplesheetError("Unexpected JSON returned by `dx find data`.")


def dnanexus_reads(scope: str, recursive: bool) -> list[ReadFile]:
    if ":" not in scope:
        raise SamplesheetError(
            "--dx-folder must be PROJECT:/folder, for example project-xxxx:/reads"
        )
    project, _ = scope.split(":", 1)
    if not project.startswith("project-"):
        raise SamplesheetError("--dx-folder must use a stable project-... ID.")
    if not shutil.which("dx"):
        raise SamplesheetError("dx-toolkit is required for --dx-folder.")

    command = [
        "dx",
        "find",
        "data",
        "--class",
        "file",
        "--json",
        "--path",
        scope,
        "--name",
        "*.fastq*",
    ]
    if not recursive:
        command.append("--norecurse")
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    try:
        records = _dx_records(json.loads(completed.stdout))
    except json.JSONDecodeError as exc:
        raise SamplesheetError("`dx find data` did not return valid JSON.") from exc

    reads: list[ReadFile] = []
    for record in records:
        describe = record.get("describe") if isinstance(record.get("describe"), dict) else {}
        file_id = record.get("id") or describe.get("id")
        name = record.get("name") or describe.get("name")
        record_project = record.get("project") or describe.get("project") or project
        if not file_id or not name or not is_fastq(str(name)):
            continue
        reads.append(ReadFile(str(name), f"dx://{record_project}:{file_id}"))
    return sorted(reads, key=lambda item: (item.name, item.reference))


def build_rows(
    reads: list[ReadFile], assay: str, layout: str, pair_regex: str
) -> list[dict[str, str]]:
    if not reads:
        raise SamplesheetError("No .fastq.gz or .fq.gz files were found.")
    try:
        matcher = re.compile(pair_regex)
    except re.error as exc:
        raise SamplesheetError(f"Invalid --pair-regex: {exc}") from exc
    if not {"sample", "mate"}.issubset(matcher.groupindex):
        raise SamplesheetError(
            "--pair-regex must define named groups (?P<sample>...) and (?P<mate>...)."
        )

    paired: dict[str, dict[str, ReadFile]] = {}
    unmatched: list[ReadFile] = []
    for read in reads:
        match = matcher.match(read.name) if layout != "single" else None
        if not match:
            unmatched.append(read)
            continue
        sample = match.group("sample")
        mate = match.group("mate")
        if mate not in {"1", "2"}:
            raise SamplesheetError(f"Pair regex produced mate {mate!r} for {read.name}.")
        sample_reads = paired.setdefault(sample, {})
        if mate in sample_reads:
            raise SamplesheetError(
                f"Sample {sample!r} has more than one read_{mate}: "
                f"{sample_reads[mate].name}, {read.name}"
            )
        sample_reads[mate] = read

    if layout == "paired" and unmatched:
        names = ", ".join(item.name for item in unmatched[:10])
        raise SamplesheetError(f"Files do not match --pair-regex in paired mode: {names}")

    rows: list[dict[str, str]] = []
    for sample, mates in sorted(paired.items()):
        if set(mates) != {"1", "2"}:
            present = ", ".join(f"read_{mate}" for mate in sorted(mates)) or "none"
            raise SamplesheetError(
                f"Sample {sample!r} is missing a mate; found only {present}."
            )
        rows.append(
            {
                "sample": sample,
                "assay": assay,
                "read_1": mates["1"].reference,
                "read_2": mates["2"].reference,
            }
        )

    for read in unmatched:
        sample = strip_fastq_suffix(read.name)
        rows.append(
            {
                "sample": sample,
                "assay": assay,
                "read_1": read.reference,
                "read_2": "",
            }
        )

    rows.sort(key=lambda row: row["sample"])
    sample_ids: set[str] = set()
    references: set[str] = set()
    for row in rows:
        sample = row["sample"]
        if not SAFE_SAMPLE.fullmatch(sample):
            raise SamplesheetError(
                f"Unsafe sample ID {sample!r}; use letters, numbers, dot, underscore, or dash."
            )
        if sample in sample_ids:
            raise SamplesheetError(f"Duplicate sample ID after pairing: {sample}")
        sample_ids.add(sample)
        for key in ("read_1", "read_2"):
            reference = row[key]
            if not reference:
                continue
            if reference in references:
                raise SamplesheetError(f"Read is assigned more than once: {reference}")
            references.add(reference)
    return rows


def write_samplesheet(output: Path, rows: list[dict[str, str]]) -> None:
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent, text=True
    )
    try:
        with os.fdopen(handle, "w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=FIELDS, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        os.replace(temporary_name, output)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def parse_upload_target(target: str) -> tuple[str, str]:
    if ":" not in target:
        raise SamplesheetError(
            "--upload-to must be PROJECT:/folder/ or PROJECT:/folder/name.csv"
        )
    project, destination = target.split(":", 1)
    if not project.startswith("project-") or not destination.startswith("/"):
        raise SamplesheetError(
            "--upload-to must include a project-... ID and absolute project folder path."
        )
    return project, destination


def upload_samplesheet(output: Path, target: str) -> str:
    if not shutil.which("dx"):
        raise SamplesheetError("dx-toolkit is required for --upload-to.")
    project, destination = parse_upload_target(target)
    command = [
        "dx",
        "--project-context-id",
        project,
        "upload",
        str(output.resolve()),
        "--path",
        destination,
        "--brief",
        "--no-progress",
    ]
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    file_id = completed.stdout.strip()
    if not re.fullmatch(r"file-[A-Za-z0-9]+", file_id):
        raise SamplesheetError(f"Unexpected output from `dx upload`: {file_id!r}")
    return f"{project}:{file_id}"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    source = result.add_mutually_exclusive_group(required=True)
    source.add_argument("--reads-dir", type=Path, help="Local directory of FASTQ files.")
    source.add_argument(
        "--dx-folder", help="DNAnexus PROJECT:/folder containing FASTQ file objects."
    )
    result.add_argument("--output", type=Path, required=True, help="Output CSV path.")
    result.add_argument(
        "--assay", choices=("mgx", "mtx", "assembly"), default="mgx"
    )
    result.add_argument(
        "--layout", choices=("auto", "paired", "single"), default="auto"
    )
    result.add_argument(
        "--pair-regex",
        default=DEFAULT_PAIR_REGEX,
        help=(
            "Regex describing paired filenames; it must define named groups "
            "'sample' and 'mate'. The default recognizes _R1/_R2 names."
        ),
    )
    result.add_argument(
        "--recursive", action="store_true", help="Search child folders recursively."
    )
    result.add_argument(
        "--upload-to",
        metavar="PROJECT:/FOLDER/",
        help="Explicitly upload the completed sheet and print its file ID.",
    )
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.reads_dir:
            reads = local_reads(args.reads_dir, args.recursive)
        else:
            reads = dnanexus_reads(args.dx_folder, args.recursive)
        rows = build_rows(reads, args.assay, args.layout, args.pair_regex)
        write_samplesheet(args.output, rows)
        print(f"Wrote {len(rows)} sample(s) to {args.output.resolve()}", file=sys.stderr)
        if args.upload_to:
            file_id = upload_samplesheet(args.output, args.upload_to)
            print(file_id)
        return 0
    except (SamplesheetError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
