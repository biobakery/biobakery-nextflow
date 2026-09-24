import csv
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_samplesheet", REPO / "bin" / "build_samplesheet.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class BuildSamplesheetTests(unittest.TestCase):
    def test_local_auto_mode_builds_paired_and_single_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ("A_R1.fastq.gz", "A_R2.fastq.gz", "B.fastq.gz"):
                (root / name).touch()
            rows = MODULE.build_rows(MODULE.local_reads(root, False), "mgx", "auto", MODULE.DEFAULT_PAIR_REGEX)
            self.assertEqual([row["sample"] for row in rows], ["A", "B"])
            self.assertTrue(rows[0]["read_2"].endswith("A_R2.fastq.gz"))
            self.assertEqual(rows[1]["read_2"], "")

    def test_supplied_pair_regex_accepts_sra_mate_names(self):
        reads = [
            MODULE.ReadFile(
                "SRR27200889_1.fastq.gz",
                "dx://project-JBVGpB00Kg1xBf54v05BXj6f:file-JBpKP3Q0Kg1v1kz9PzG48p1J",
            ),
            MODULE.ReadFile(
                "SRR27200889_2.fastq.gz",
                "dx://project-JBVGpB00Kg1xBf54v05BXj6f:file-JBpKP3Q0Kg1YPPFf2P3G2gBz",
            ),
        ]
        sra_pair_regex = (
            r"^(?P<sample>.+)_(?P<mate>[12])\.(?:fastq|fq)\.gz$"
        )
        rows = MODULE.build_rows(reads, "mgx", "paired", sra_pair_regex)
        self.assertEqual(
            rows,
            [
                {
                    "sample": "SRR27200889",
                    "assay": "mgx",
                    "read_1": reads[0].reference,
                    "read_2": reads[1].reference,
                }
            ],
        )

    def test_orphan_mate_is_rejected(self):
        reads = [MODULE.ReadFile("A_R1.fastq.gz", "/reads/A_R1.fastq.gz")]
        with self.assertRaisesRegex(MODULE.SamplesheetError, "missing a mate"):
            MODULE.build_rows(reads, "mgx", "auto", MODULE.DEFAULT_PAIR_REGEX)

    def test_atomic_csv_has_stable_columns(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "samples.csv"
            MODULE.write_samplesheet(
                output,
                [{"sample": "A", "assay": "mgx", "read_1": "/A.fastq.gz", "read_2": ""}],
            )
            with output.open(newline="") as stream:
                reader = csv.DictReader(stream)
                self.assertEqual(tuple(reader.fieldnames), MODULE.FIELDS)
                self.assertEqual(list(reader)[0]["sample"], "A")

    @mock.patch.object(MODULE.shutil, "which", return_value="/usr/bin/dx")
    @mock.patch.object(MODULE.subprocess, "run")
    def test_upload_is_scoped_without_dx_select(self, run, _which):
        run.return_value = subprocess.CompletedProcess([], 0, "file-AbC123\n", "")
        file_id = MODULE.upload_samplesheet(
            Path("samples.csv"), "project-123:/inputs/samplesheets/"
        )
        self.assertEqual(file_id, "project-123:file-AbC123")
        command = run.call_args.args[0]
        self.assertEqual(command[:3], ["dx", "--project-context-id", "project-123"])
        self.assertNotIn("select", command)


if __name__ == "__main__":
    unittest.main()
