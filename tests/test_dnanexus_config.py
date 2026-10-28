"""Resolve DNAnexus resource/container selectors for every real process name.

Uses native Groovy tasks: no Docker, platform connection, tools or databases.
Run: python3 -m unittest discover -s tests -p test_dnanexus_config.py
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
KNEADDATA_IMAGE = 'public.ecr.aws/j5i5h1i5/kneaddata:latest-hg37dec'
METAPHLAN_IMAGE = 'public.ecr.aws/j5i5h1i5/metaphlan:4.2.5-mpa_vOct22_202403'
HUMANN_IMAGE = 'public.ecr.aws/j5i5h1i5/humann:experimental'


@unittest.skipUnless(shutil.which('nextflow'), 'Nextflow is required')
class DnanexusConfigTest(unittest.TestCase):
    def test_process_resources_images_and_study_yaml(self):
        with tempfile.TemporaryDirectory(prefix='dnanexus-config-') as tmp:
            base = Path(tmp)
            # Reuse the real process names/labels without running bioBakery tools.
            processes = {}
            for path in (ROOT / 'modules').rglob('*.nf'):
                for match in re.finditer(r'^process (\w+)\s*\{(.*?)(?=^process |\Z)', path.read_text(), re.M | re.S):
                    name, body = match.groups()
                    processes[name] = bool(re.search(r"label ['\"]stats_viz['\"]", body))
            script = []
            for name, stats_viz in processes.items():
                label = "label 'stats_viz'" if stats_viz else ''
                script.append(f'''process {name} {{
    {label}
    output:
    path 'settings.json'
    exec:
    task.workDir.resolve('settings.json').text = groovy.json.JsonOutput.toJson([
        name: '{name}', machine: task.machineType, cpus: task.cpus,
        memory: task.memory.toGiga(), container: task.container])
}}
''')
            script.append('workflow {\n' + '\n'.join(f'{name}()' for name in processes) + '''
    new File(params.snapshot).text = groovy.json.JsonOutput.toJson([
        host_genome: params.host_genome, humann_db_location: params.humann_db_location,
        metaphlan_databases: params.metaphlan_databases,
        metaphlan_downstream_indices: params.metaphlan_downstream_indices,
        humann_regroups: params.humann_regroups, humann_version: params.humann_version,
        stop_after_qc: params.stop_after_qc, run_vis: params.run_vis,
        log_versions: params.log_versions, samplesheet: params.samplesheet,
        run_taxonomic_profiling: params.run_taxonomic_profiling,
        run_functional_profiling: params.run_functional_profiling])
}
''')
            (base / 'probes.nf').write_text('\n'.join(script))
            (base / 'probe.config').write_text(
                f"includeConfig '{ROOT}/nextflow.config'\n"
                "timeline.enabled=false\nreport.enabled=false\ntrace.enabled=false\ndag.enabled=false\n")
            result = subprocess.run([
                'nextflow', '-C', str(base / 'probe.config'), 'run', str(base / 'probes.nf'),
                '-profile', 'dnanexus', '-params-file', str(ROOT / 'conf/example_yamls/dnanexus.yaml'),
                '--snapshot', str(base / 'params.json'),
                '-ansi-log', 'false',
            ], cwd=base, env=dict(os.environ, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1'),
                capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            settings = [json.loads(p.read_text()) for p in (base / 'work').glob('*/*/settings.json')]
            self.assertEqual({s['name'] for s in settings}, set(processes))
            by_name = {s['name']: s for s in settings}
            for item in settings:
                with self.subTest(process=item['name']):
                    self.assertEqual(item['machine'], 'mem3_ssd2_v3_x16')
                    cores = int(item['machine'].rsplit('x', 1)[1])
                    self.assertLessEqual(item['cpus'], cores)
                    self.assertLess(item['memory'], cores * 4)
                    self.assertGreater(item['memory'], 0)
            self.assertEqual(by_name['humann']['cpus'], 16)
            self.assertEqual(by_name['metaphlan']['cpus'], 16)
            for name in ['humann', 'humann_regroup', 'humann_rename', 'humann_renorm', 'humann_join']:
                self.assertEqual(by_name[name]['container'], HUMANN_IMAGE)
            self.assertEqual(by_name['kneaddata_read_counts']['cpus'], 1)
            self.assertEqual(by_name['kneaddata_read_counts']['container'], KNEADDATA_IMAGE)
            self.assertEqual(by_name['metaphlan']['container'], METAPHLAN_IMAGE)
            self.assertEqual(by_name['metaphlan_merge']['container'], by_name['metaphlan']['container'])
            self.assertNotIn('metaphlan_bzip', by_name)
            self.assertIsNone(by_name['vis_report']['container'])
            params = json.loads((base / 'params.json').read_text())
            self.assertEqual(params['host_genome'], '/Databases/kneaddata/hg37dec')
            self.assertEqual(params['humann_db_location'], 'container')
            self.assertEqual(len(params['metaphlan_databases']), 2)
            self.assertEqual(params['metaphlan_downstream_indices'], ['mpa_vOct22_CHOCOPhlAnSGB_202403'])
            self.assertEqual([g['output_label'] for g in params['humann_regroups']], ['ecs', 'kos', 'pfams'])
            self.assertFalse(params['stop_after_qc'])
            self.assertFalse(params['run_vis'])
            self.assertTrue(params['run_taxonomic_profiling'])
            self.assertTrue(params['run_functional_profiling'])
            self.assertEqual(params['humann_version'], 'humann_v4a')
            self.assertFalse(params['log_versions'])
            self.assertIsNone(params['samplesheet'])

    def test_cache_discovery_contains_all_three_tool_images(self):
        with tempfile.TemporaryDirectory(prefix='dnanexus-inspect-') as tmp:
            result = subprocess.run([
                'nextflow', 'inspect', str(ROOT), '-profile', 'dnanexus', '-format', 'json',
            ], cwd=tmp, env=dict(os.environ, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                                NXF_OPTS=os.environ.get('NXF_OPTS', '') + ' -XX:-UsePerfData'),
                capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            processes = json.loads(result.stdout)['processes']
            by_name = {p['name']: p.get('container') for p in processes}
            self.assertEqual(by_name['metaphlan'], METAPHLAN_IMAGE)
            self.assertEqual(by_name['humann'], HUMANN_IMAGE)
            self.assertEqual({p['container'] for p in processes if p.get('container')},
                             {KNEADDATA_IMAGE, METAPHLAN_IMAGE, HUMANN_IMAGE})

    def run_mocked_pipeline(self, use_yaml=False, qc_only=False, functional=True):
        temp = tempfile.TemporaryDirectory(prefix='dnanexus-profiling-')
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        (base / 'bin').mkdir()
        (base / 'db').mkdir()
        (base / 'mappings').mkdir()
        for filename in ['map_level4ec_uniclust90.txt.gz', 'map_level4ec_name.txt.gz',
                         'map_ko_uniref90.txt.gz', 'map_ko_name.txt.gz',
                         'map_pfam_uniref90.txt.gz', 'map_pfam_name.txt.gz']:
            (base / 'mappings' / filename).write_text('mock mapping\n')
        mock = base / 'bin/mock-tool'
        mock.write_text('''#!/usr/bin/env python3
import gzip
from pathlib import Path
import sys
args = sys.argv[1:]
tool = Path(sys.argv[0]).name
def opt(name):
    return args[args.index(name) + 1]
if tool == 'kneaddata':
    prefix = opt('--output-prefix')
    suffixes = [''] if '--unpaired' in args else ['_paired_1', '_paired_2', '_unmatched_1', '_unmatched_2']
    for suffix in suffixes:
        Path(prefix + suffix + '.fastq').write_text('@read\\nACGT\\n+\\nIIII\\n')
    Path(prefix + '.log').write_text('mock KneadData log\\n')
elif tool == 'pigz':
    source = Path(args[-1])
    with gzip.open(str(source) + '.gz', 'wb') as output:
        output.write(source.read_bytes())
    source.unlink()
elif tool == 'kneaddata_read_count_table':
    logs = sorted(Path(opt('--input')).glob('*.log'))
    assert len(logs) == 2, logs
    Path(opt('--output')).write_text('Sample\\tReads\\n' + ''.join(p.stem + '\\t1\\n' for p in logs))
elif tool == 'metaphlan':
    assert opt('--nproc') == '1', args  # Follow the test's task CPU override.
    reads = Path(args[0])
    assert reads.name in ['single_kneaddata.fastq.gz', 'pair_concatenated.fastq.gz'], reads
    assert reads.exists(), reads
    assert '--db_dir' in args and '--mapout' in args, args
    index = opt('-x')
    assert opt('--db_dir').endswith('_lon_subsp' if index.endswith('_lon_subsp') else '_default'), args
    Path(opt('-o')).write_text(index + '\\n')
    Path(opt('--mapout')).write_text('mapping\\n')
    Path(opt('--samout')).write_text('alignment\\n')
elif tool == 'merge_metaphlan_tables.py':
    profiles = [Path(p) for p in args]
    assert len(profiles) == 2, profiles
    values = [p.read_text().strip() for p in profiles]
    assert len(set(values)) == 1, values
    print('\\n'.join(values))
elif tool == 'humann':
    assert opt('--threads') == '1', args
    sample = opt('--output-basename')
    reads = Path(opt('--input'))
    assert reads.name == ('single_kneaddata.fastq.gz' if sample == 'single' else 'pair_concatenated.fastq.gz'), reads
    assert reads.exists(), reads
    profile = Path(opt('--taxonomic-profile'))
    identity = profile.read_text()
    assert profile.name == sample + '_mpa_vOct22_CHOCOPhlAnSGB_202403_profile.tsv', profile
    assert identity.strip() == 'mpa_vOct22_CHOCOPhlAnSGB_202403', identity
    assert opt('--nucleotide-database') == '/Databases/humann/chocophlan-v4-201901/chocophlan'
    assert opt('--protein-database') == '/Databases/humann/chocophlan-v4-201901/uniref90_annotated'
    assert Path(opt('--utility-database')).is_dir()
    # Emit the actual HUMAnN 4 names so the real module must rename them.
    for suffix in ['_2_genefamilies.tsv', '_3_reactions.tsv', '_4_pathabundance.tsv', '_5_pathcoverage.tsv', '_0.log']:
        Path(sample + suffix).write_text(identity)
elif tool in ['humann_regroup_table', 'humann_rename_table', 'humann_renorm_table']:
    if tool != 'humann_renorm_table':
        assert '--custom' in args, args
        mapping = Path(opt('--custom'))
        assert mapping.is_file(), mapping
        assert mapping.name in ['map_level4ec_uniclust90.txt.gz', 'map_level4ec_name.txt.gz',
                                'map_ko_uniref90.txt.gz', 'map_ko_name.txt.gz',
                                'map_pfam_uniref90.txt.gz', 'map_pfam_name.txt.gz'], mapping
    else:
        assert opt('--units') == 'relab' and opt('--special') == 'n', args
    Path(opt('--output')).write_text(Path(opt('--input')).read_text())
elif tool == 'humann_join_tables':
    tables = sorted(Path(opt('--input')).glob('*.tsv'))
    assert [p.name for p in tables] == ['pair.tsv', 'single.tsv'], tables
    identities = [p.read_text() for p in tables]
    assert len(set(identities)) == 1, identities
    Path(opt('--output')).write_text(''.join(identities))
else:
    raise RuntimeError(tool)
''')
        mock.chmod(0o755)
        for tool in ['kneaddata', 'pigz', 'kneaddata_read_count_table', 'metaphlan', 'merge_metaphlan_tables.py',
                     'humann', 'humann_regroup_table', 'humann_rename_table', 'humann_renorm_table', 'humann_join_tables']:
            (base / 'bin' / tool).symlink_to(mock)
        for name in ['single.fastq', 'pair_1.fastq', 'pair_2.fastq']:
            (base / name).write_text('@read\nACGT\n+\nIIII\n')
        (base / 'samples.csv').write_text(
            f'sample,assay,read_1,read_2\nsingle,mgx,{base}/single.fastq,\n'
            f'pair,mgx,{base}/pair_1.fastq,{base}/pair_2.fastq\n')
        (base / 'test.config').write_text(
            f"includeConfig '{ROOT}/nextflow.config'\n"
            "process { withName: 'MGX:.*' { cpus=1; memory='1.GB' } }\n"
            "timeline.enabled=false\nreport.enabled=false\ndag.enabled=false\n")
        command = [
            'nextflow', '-C', str(base / 'test.config'), 'run', str(ROOT / 'main.nf'),
            '-profile', 'dnanexus',
            '--samplesheet', str(base / 'samples.csv'), '--host_genome', str(base / 'db'),
            '--humann_db_utilitymapping', str(base / 'mappings'),
            '-without-docker', '-with-trace', str(base / 'tasks.tsv'), '-ansi-log', 'false',
        ]
        if use_yaml:
            command += ['-params-file', str(ROOT / 'conf/example_yamls/dnanexus.yaml')]
        if qc_only:
            command += ['--run_taxonomic_profiling', 'false', '--run_functional_profiling', 'false']
        elif not functional:
            command += ['--run_functional_profiling', 'false']
        result = subprocess.run(command, cwd=base, env=dict(os.environ, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                             PATH=str(base / 'bin') + os.pathsep + os.environ['PATH']),
            capture_output=True, text=True, timeout=120)
        return base, result

    def test_qc_only_override_finishes_with_no_downstream_tasks(self):
        base, result = self.run_mocked_pipeline(qc_only=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list((base / 'work').glob('*/*/.command.sh'))), 3)
        trace = (base / 'tasks.tsv').read_text()
        for name in ['single_end_kneaddata', 'paired_end_kneaddata', 'kneaddata_read_counts']:
            self.assertIn(name, trace)
        for name in ['metaphlan', 'humann', 'version_log', 'intentional_stop_after_qc']:
            self.assertNotIn(name, trace)
        self.assertTrue((base / 'results/kneaddata/merged/kneaddata_read_count_table.tsv').exists())

    def test_kneaddata_then_metaphlan_with_defaults_and_optional_yaml(self):
        for use_yaml in [False, True]:
            with self.subTest(use_yaml=use_yaml):
                base, result = self.run_mocked_pipeline(use_yaml=use_yaml, functional=False)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                indices = ['mpa_vOct22_CHOCOPhlAnSGB_202403']
                if use_yaml:
                    indices.append('mpa_vOct22_CHOCOPhlAnSGB_202403_lon_subsp')
                # Two QC tasks, one QC aggregate; per reference: two profiles
                # with in-task SAM compression, and one merged profile table.
                self.assertEqual(len(list((base / 'work').glob('*/*/.command.sh'))), 3 + 3 * len(indices))
                for index in indices:
                    folder = base / 'results/metaphlan' / index
                    merged_folder = folder if use_yaml else base / 'results/metaphlan'
                    self.assertEqual((merged_folder / 'merged_metaphlan_profiles.tsv').read_text().split(), [index, index])
                    for sample in ['single', 'pair']:
                        self.assertTrue((folder / f'{sample}_{index}_profile.tsv').exists())
                        bzip = folder / 'bzip' if use_yaml else base / 'results/metaphlan/bzip'
                        self.assertTrue((bzip / f'{sample}_{index}.sam.bz2').exists())
                trace = (base / 'tasks.tsv').read_text()
                for name in ['humann', 'baqlava', 'strainphlan', 'vis_report', 'stats_report', 'version_log', 'intentional_stop_after_qc']:
                    self.assertNotIn(name, trace)

    def test_full_profiling_through_humann_with_defaults_and_optional_yaml(self):
        primary = 'mpa_vOct22_CHOCOPhlAnSGB_202403'
        for use_yaml in [False, True]:
            with self.subTest(use_yaml=use_yaml):
                base, result = self.run_mocked_pipeline(use_yaml=use_yaml)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                # HUMAnN consumes only the selected primary MetaPhlAn profile,
                # even when the optional YAML runs both MetaPhlAn references.
                folder = base / 'results'
                if use_yaml:
                    folder /= f'databases/{primary}'
                folder /= 'humann/humann_v4a'
                for sample in ['pair', 'single']:
                    for feature in ['genefamilies', 'pathabundance', 'pathcoverage', 'reactions']:
                        self.assertEqual((folder / 'main' / f'{sample}_{feature}_humann_v4a.tsv').read_text().strip(), primary)
                    self.assertTrue((folder / 'main' / f'{sample}_humann_humann_v4a.log').exists())
                    for label in ['ecs', 'kos', 'pfams']:
                        self.assertTrue((folder / 'regrouped' / label / f'{sample}_{label}_humann_v4a.tsv').exists())
                        self.assertTrue((folder / 'renamed' / label / f'{sample}_{label}_named_humann_v4a.tsv').exists())
                for feature in ['genefamilies', 'pathabundance', 'ecs', 'kos', 'pfams']:
                    for suffix in ['', '_relab']:
                        merged = folder / 'merged' / f'merged_{feature}{suffix}_humann_v4a.tsv'
                        self.assertEqual(merged.read_text().split(), [primary, primary])
                self.assertFalse((base / 'results/databases/mpa_vOct22_CHOCOPhlAnSGB_202403_lon_subsp/humann').exists())
                trace = (base / 'tasks.tsv').read_text()
                self.assertEqual(len(list((base / 'work').glob('*/*/.command.sh'))), 12 if use_yaml else 9)
                for name in ['metaphlan_bzip', 'humann_regroup (', 'humann_rename (',
                             'humann_renorm (', 'humann_join_relab']:
                    self.assertNotIn(name, trace)
                for name in ['baqlava', 'strainphlan', 'vis_report', 'stats_report', 'version_log', 'intentional_stop_after_qc']:
                    self.assertNotIn(name, trace)


if __name__ == '__main__':
    unittest.main()
