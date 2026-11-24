"""Run real workflow wiring with mock tools; no containers or databases needed."""
from pathlib import Path
import shutil
import unittest

import test_metaphlan_databases as fixtures


@unittest.skipUnless(shutil.which('nextflow'), 'Nextflow is required')
class HumannUnalignedReadsTest(unittest.TestCase):
    run_pipeline = fixtures.MetaphlanDatabasesTest.run_pipeline

    def run_export(self, workflow='mgx', **overrides):
        params = dict(run_strain_profiling=False, run_viral_profiling=False,
                      humann_regroups=[], bypass_norm_ratio=True)
        params.update(overrides)
        base, result = self.run_pipeline(params, main_workflow=workflow,
                                         capture_unaligned=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        manifest = base / 'forwarded.tsv'
        rows = [line.split('\t') for line in manifest.read_text().splitlines()] if manifest.exists() else []
        return base, rows

    def test_default_does_not_publish_or_forward_temporary_reads(self):
        base, rows = self.run_export()
        self.assertEqual(rows, [])
        self.assertEqual(list((base / 'out').rglob('*_bowtie2_unaligned.fa')), [])
        self.assertEqual(len(list((base / 'work').glob('*/*/*_humann_temp/*_bowtie2_unaligned.fa'))), 4)

    def test_exports_and_forwards_both_versions_and_all_assays(self):
        for workflow, version in [('mgx', 'humann_v37'), ('mtx', 'humann_v4a'),
                                  ('mgx_mtx', 'humann_v4a')]:
            with self.subTest(workflow=workflow, version=version):
                base, rows = self.run_export(workflow, humann_save_unaligned_reads=True,
                                              humann_version=version)
                assays = ['mgx', 'mtx'] if workflow == 'mgx_mtx' else [workflow]
                expected = {(assay, db, sample)
                            for assay in assays for db in ['a', 'b']
                            for sample in (['s1', 's2'] if assay == 'mgx' else ['r1', 'r2'])}
                self.assertEqual({tuple(row[:3]) for row in rows}, expected)
                self.assertEqual(len(rows), len(expected))
                for assay, db, sample, filename in rows:
                    expected_contents = f'>{db}-{sample}\nACGT\n'
                    self.assertEqual(Path(filename).read_text(), expected_contents)
                    prefix = (f'whole_{"metagenome" if assay == "mgx" else "metatranscriptome"}_shotgun/'
                              if workflow == 'mgx_mtx' else '')
                    published = base / f'out/{prefix}databases/{db}/humann/{version}/unaligned_reads/{sample}_bowtie2_unaligned.fa'
                    self.assertEqual(published.read_text(), expected_contents)
                self.assertEqual(len(list((base / 'out').rglob('*_bowtie2_unaligned.fa'))), len(expected))

    def test_legacy_single_database_keeps_existing_layout(self):
        base, rows = self.run_export(humann_save_unaligned_reads=True,
            metaphlan_databases=None, metaphlan_db='/db/legacy',
            metaphlan_index='legacy', metaphlan_downstream_indices=None)
        self.assertEqual({row[1] for row in rows}, {''})
        self.assertEqual(len(rows), 2)
        self.assertTrue((base / 'out/humann/humann_v37/unaligned_reads/s1_bowtie2_unaligned.fa').is_file())

    def test_absent_optional_fasta_does_not_block_profiling(self):
        for options in ['--remove-temp-output', '--mock-empty-pangenome']:
            with self.subTest(options=options):
                base, rows = self.run_export(humann_save_unaligned_reads=True,
                                              humann_options=options)
                self.assertEqual(rows, [])
                self.assertEqual(list((base / 'out').rglob('*_bowtie2_unaligned.fa')), [])
                self.assertEqual(len(list((base / 'out').rglob('s1_genefamilies_humann_v37.tsv'))), 2)

    def test_bypassed_nucleotide_search_emits_no_fasta(self):
        _, rows = self.run_export(humann_save_unaligned_reads=True,
                                  humann_bypass_nucleotide_search=True)
        self.assertEqual(rows, [])

    def test_existing_empty_fasta_is_published_and_forwarded(self):
        base, rows = self.run_export(humann_save_unaligned_reads=True,
                                    humann_options='--mock-empty-unaligned')
        self.assertEqual(len(rows), 4)
        for _, _, _, filename in rows:
            self.assertEqual(Path(filename).stat().st_size, 0)
        self.assertEqual(len(list((base / 'out').rglob('*_bowtie2_unaligned.fa'))), 4)

    def test_disabled_functional_profiling_keeps_output_channel_empty(self):
        _, rows = self.run_export(humann_save_unaligned_reads=True,
                                  run_functional_profiling=False)
        self.assertEqual(rows, [])


if __name__ == '__main__':
    unittest.main()
