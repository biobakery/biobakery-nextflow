"""Exercise database fan-out and downstream isolation with mocked bioBakery tools.

Run: python3 -m unittest discover -s tests -p test_metaphlan_databases.py
Requires Nextflow, Java, bzip2 and zip; no reference databases or bioBakery install.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ['metaphlan', 'merge_metaphlan_tables.py', 'humann', 'humann_join_tables',
         'humann_regroup_table', 'humann_renorm_table', 'humann_rename_table',
         'count_features.py', 'get_counts_from_humann_logs.py', 'baqlava',
         'sample2markers.py', 'strainphlan.py', 'create_feature_table.py', 'trim_taxonomy.py', 'python', 'Rscript', 'R', 'halla']


@unittest.skipUnless(shutil.which('nextflow'), 'Nextflow is required')
class MetaphlanDatabasesTest(unittest.TestCase):
    def run_pipeline(self, overrides=None, reports=False, main_workflow=None, mapped=False):
        temp = tempfile.TemporaryDirectory(prefix='metaphlan-test-')
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        (base / 'bin').mkdir()
        (base / 'assets').symlink_to(ROOT / 'assets')
        tool = base / 'bin/mock-tool'
        shutil.copy(ROOT / 'tests/fixtures/metaphlan_mock_tools.py', tool)
        tool.chmod(0o755)
        for name in TOOLS:
            (base / 'bin' / name).symlink_to(tool)
        (base / 'reads.fastq').touch()
        (base / 'metadata.tsv').write_text('sample\tage\ns1\t1\ns2\t2\n')
        params = dict(outdir=str(base / 'out'), humann_db_chocophlan='/db/humann/chocophlan', humann_db_utilitymapping='/db/humann/utility_mapping', humann_db_protein='/db/humann/uniref',
                      metaphlan_databases=[dict(metaphlan_db='/db/a', metaphlan_index='a'),
                                           dict(metaphlan_db='/db/b', metaphlan_index='b', metaphlan_version='4.1')],
                      metaphlan_db_location='container', humann_db_location='container',
                      humann_regroups=[dict(output_label='ecs', groups='uniref90_rxn', rename='metacyc-rxn')],
                      metaphlan_downstream_indices=['a', 'b'],
                      run_vis=reports, run_stats=reports,
                      run_strain_profiling=True, run_viral_profiling=True,
                      input_metadata=str(base / 'metadata.tsv'))
        if main_workflow:
            for sample in ['s1', 's2', 'r1', 'r2']:
                (base / f'{sample}.fastq').touch()
            (base / 'samples.csv').write_text('sample,assay,read_1,read_2\n' + ''.join(
                f'{sample},{assay},{base}/{sample}.fastq,\n'
                for assay, samples in [('mgx', ['s1', 's2']), ('mtx', ['r1', 'r2'])]
                for sample in samples))
            params.update(workflow=main_workflow, samplesheet=str(base / 'samples.csv'), run_qc=False,
                          log_versions=False, run_strain_profiling=False, run_viral_profiling=False)
            if mapped:
                (base / 'mapping.tsv').write_text('r1\ts1\nr2\ts2\n')
                params['input_mapping'] = str(base / 'mapping.tsv')
        params.update(overrides(base) if callable(overrides) else (overrides or {}))
        (base / 'params.json').write_text(json.dumps(params))
        (base / 'nextflow.config').write_text(f"includeConfig '{ROOT}/conf/params.config'\nprocess.cpus=1\n")
        imports = ['TAXONOMIC_PROFILING', 'FUNCTIONAL_PROFILING', 'VIRAL_PROFILING',
                   'STRAIN_PROFILING', 'PREPARE_REPORTS', 'REPORTING']
        modules = ['taxonomic_profiling', 'functional_profiling', 'viral_profiling',
                   'strain_profiling', 'prepare_reports', 'reporting']
        script = '\n'.join(f"include {{ {name} }} from '{ROOT}/subworkflows/{module}.nf'"
                           for name, module in zip(imports, modules))
        script += f'''
workflow {{
    reads = Channel.of(tuple([id:'s1'],file('{base}/reads.fastq')), tuple([id:'s2'],file('{base}/reads.fastq')))
    TAXONOMIC_PROFILING(reads, '')
    FUNCTIONAL_PROFILING(reads, TAXONOMIC_PROFILING.out.profile, '')
    VIRAL_PROFILING(reads, TAXONOMIC_PROFILING.out.profile)
    STRAIN_PROFILING(TAXONOMIC_PROFILING.out.sam_bzip)
    PREPARE_REPORTS(TAXONOMIC_PROFILING.out.merged,
        Channel.value(file('{ROOT}/assets/NO_FILE')),
        FUNCTIONAL_PROFILING.out.merged_tables, FUNCTIONAL_PROFILING.out.logs, '')
    REPORTING(PREPARE_REPORTS.out.folder)
}}
'''
        (base / 'main.nf').write_text(script)
        env = dict(os.environ, NXF_SYNTAX_PARSER='v1', NXF_OFFLINE='true',
                   PATH=str(base / 'bin') + os.pathsep + os.environ['PATH'])
        result = subprocess.run(['nextflow', '-C', str(base / 'nextflow.config'), 'run',
                                 str(ROOT / 'main.nf' if main_workflow else base / 'main.nf'), '-params-file', str(base / 'params.json'),
                                 '-ansi-log', 'false'], cwd=base, env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        return base, result

    def test_multiple_databases_and_downstream_reports_are_isolated(self):
        base, result = self.run_pipeline(reports=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        for index in ['a', 'b']:
            tax = base / 'out/metaphlan' / index
            self.assertEqual((tax / 'merged_metaphlan_profiles.tsv').read_text().split(), [index, index])
            downstream = base / 'out/databases' / index
            merged = downstream / 'humann/humann_v37/merged/merged_genefamilies_humann_v37.tsv'
            self.assertEqual(merged.read_text().split(), [index, index])
            for path in ['baqlava/s1_baqlava/result.tsv', 'strainphlan/all/output/tree.tre',
                         'vis/vis_report.html', 'stats/stats_report.html', 'vis.zip', 'stats.zip']:
                self.assertTrue((downstream / path).exists(), path)
            for report in ['vis/vis_report.html', 'stats/stats_report.html']:
                self.assertEqual(set((downstream / report).read_text().split()), {index})
        commands = '\n'.join(p.read_text() for p in (base / 'work').glob('*/*/.command.sh'))
        self.assertIn('--db_dir /db/a', commands)
        self.assertIn('--bowtie2db /db/b', commands)

    def test_select_one_database(self):
        base, result = self.run_pipeline(dict(metaphlan_downstream_indices=['b']))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((base / 'out/metaphlan/a/merged_metaphlan_profiles.tsv').exists())
        self.assertTrue((base / 'out/databases/b/humann').exists())
        self.assertFalse((base / 'out/databases/a').exists())

    def test_default_selection_and_optional_report_inputs(self):
        base, result = self.run_pipeline(dict(metaphlan_downstream_indices=None,
            run_functional_profiling=False, input_metadata=None), reports=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((base / 'out/databases/a/vis/vis_report.html').exists())
        self.assertFalse((base / 'out/databases/b').exists())
        self.assertFalse((base / 'out/databases/a/humann').exists())

    def test_legacy_configuration_keeps_output_layout(self):
        base, result = self.run_pipeline(dict(metaphlan_databases=None, metaphlan_db='/db/legacy',
                                             metaphlan_index='legacy', metaphlan_downstream_indices=None))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((base / 'out/metaphlan/merged_metaphlan_profiles.tsv').exists())
        self.assertTrue((base / 'out/humann').exists())
        self.assertFalse((base / 'out/databases').exists())

    def test_host_mapping_files_with_colliding_basenames(self):
        def configure(base):
            mappings = []
            for label in ['ecs', 'kos']:
                paths = []
                for role in ['groups', 'names']:
                    path = base / label / role / "mapping's table.tsv"
                    path.parent.mkdir(parents=True)
                    path.write_text(f'{role}-{label}\n')
                    paths.append(str(path))
                mappings.append(dict(output_label=label, database_location='host',
                    group_mapping_database=paths[0], renaming_database=paths[1]))
            return dict(humann_regroups=mappings, metaphlan_downstream_indices=['a'])
        base, result = self.run_pipeline(configure)
        self.assertEqual(result.returncode, 0, result.stdout)
        for label in ['ecs', 'kos']:
            root = base / 'out/databases/a/humann/humann_v37'
            self.assertTrue((root / f'regrouped/{label}/s1_{label}_humann_v37.tsv').exists())
            self.assertTrue((root / f'renamed/{label}/s1_{label}_named_humann_v37.tsv').exists())
            self.assertTrue((root / f'merged/merged_{label}_relab_humann_v37.tsv').exists())

    def test_optional_humann_transformations_and_merges(self):
        for overrides in [dict(humann_regroups=[]), dict(run_humann_regroup=False),
                          dict(run_humann_rename=False), dict(run_humann_merge=False)]:
            with self.subTest(overrides=overrides):
                base, result = self.run_pipeline(overrides)
                self.assertEqual(result.returncode, 0, result.stdout)
                root = base / 'out/databases/a/humann/humann_v37'
                self.assertTrue((root / 'relab/genefamilies/s1_genefamilies_relab_humann_v37.tsv').exists())
                if 'humann_regroups' in overrides or 'run_humann_regroup' in overrides:
                    self.assertFalse((root / 'regrouped').exists())
                if 'run_humann_rename' in overrides:
                    self.assertFalse((root / 'renamed').exists())
                self.assertEqual((root / 'merged').exists(), overrides.get('run_humann_merge', True))

    def test_mgx_mtx_database_ratios_and_mapped_profiles(self):
        for mapped in [False, True]:
            with self.subTest(mapped=mapped):
                base, result = self.run_pipeline(main_workflow='mgx_mtx', mapped=mapped)
                self.assertEqual(result.returncode, 0, result.stdout)
                for index in ['a', 'b']:
                    for feature in ['genes', 'ecs', 'paths']:
                        ratio = base / f'out/databases/{index}/humann/rna_dna_norm/{feature}/rna_dna_relative_expression.tsv'
                        self.assertEqual(set(ratio.read_text().split()), {index})
                    self.assertTrue((base / f'out/whole_metatranscriptome_shotgun/databases/{index}/humann').exists())
                self.assertEqual((base / 'out/whole_metatranscriptome_shotgun/metaphlan').exists(), not mapped)

    def test_invalid_configuration_fails_early(self):
        for params, message in [
            (dict(metaphlan_databases=[]), 'non-empty array'),
            (dict(metaphlan_databases=[dict(metaphlan_db='/db')]), 'requires metaphlan_db and metaphlan_index'),
            (dict(metaphlan_downstream_indices=['missing']), 'unique configured metaphlan_index'),
            (dict(metaphlan_downstream_indices=[]), 'non-empty array'),
            (dict(metaphlan_downstream_indices=['a','a']), 'unique configured metaphlan_index'),
            (dict(metaphlan_databases=[dict(metaphlan_db='/db/a',metaphlan_index='a')]*2), 'unique metaphlan_index'),
        ]:
            with self.subTest(params=params):
                _, result = self.run_pipeline(params)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stdout)


if __name__ == '__main__':
    unittest.main()
