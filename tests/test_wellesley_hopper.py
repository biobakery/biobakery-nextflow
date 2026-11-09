"""Resolve Hopper's real profile and example YAML without running analyses."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nextflow'), 'Nextflow is required')
class WellesleyHopperTest(unittest.TestCase):
    def test_local_images_resources_and_reference_modes(self):
        names = ['single_end_kneaddata', 'paired_end_kneaddata', 'kneaddata_read_counts',
                 'metaphlan', 'metaphlan_merge', 'humann', 'humann_join', 'strainphlan', 'baqlava']
        with tempfile.TemporaryDirectory(prefix='hopper-config-') as tmp:
            base = Path(tmp)
            script = []
            for name in names:
                script.append(f'''process {name} {{
    output:
    path 'settings.json'
    exec:
    task.workDir.resolve('settings.json').text = groovy.json.JsonOutput.toJson([
        name: '{name}', container: task.container, cpus: task.cpus,
        memory: task.memory.toGiga(), before: task.beforeScript,
        options: task.containerOptions])
}}
''')
            script.append('workflow {\n' + '\n'.join(f'{name}()' for name in names) + '''
    new File(params.snapshot).text = groovy.json.JsonOutput.toJson([
        qc: params.run_qc, taxonomy: params.run_taxonomic_profiling,
        function: params.run_functional_profiling, strain: params.run_strain_profiling,
        viral: params.run_viral_profiling, reporting: params.run_vis || params.run_stats,
        metaphlan: params.metaphlan_databases, downstream: params.metaphlan_downstream_indices,
        viral_location: params.baqlava_db_location, humann_location: params.humann_db_location,
        strain_location: params.strainphlan_db_location,
        viral_nucleotide: params.baqlava_db_nucleotide, viral_protein: params.baqlava_db_protein,
        depletion: params.baqlava_depletion_db,
        depletion_protein: params.baqlava_depletion_protein_db,
        depletion_mapping: params.baqlava_depletion_mapping_db])
}
''')
            (base / 'main.nf').write_text('\n'.join(script))
            (base / 'test.config').write_text(f"includeConfig '{ROOT}/nextflow.config'\n"
                'timeline.enabled=false\nreport.enabled=false\ntrace.enabled=false\ndag.enabled=false\n')
            result = subprocess.run(['nextflow', '-C', str(base / 'test.config'), 'run', str(base / 'main.nf'),
                '-profile', 'wellesley_hopper', '-params-file', str(ROOT / 'conf/example_yamls/wellesley_hopper.yaml'),
                '--snapshot', str(base / 'params.json'), '-ansi-log', 'false'], cwd=base,
                capture_output=True, text=True, timeout=120,
                env=dict(os.environ, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                    NXF_OPTS=os.environ.get('NXF_OPTS', '') + ' -XX:-UsePerfData'))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            by_name = {p['name']: p for p in [json.loads(f.read_text()) for f in (base / 'work').glob('*/*/settings.json')]}
            self.assertEqual(set(by_name), set(names))
            for name in ['single_end_kneaddata', 'paired_end_kneaddata', 'kneaddata_read_counts']:
                self.assertEqual(by_name[name]['container'], 'kneaddata:latest-hg37dec')
            for name in ['metaphlan', 'metaphlan_merge', 'strainphlan']:
                self.assertEqual(by_name[name]['container'], 'metaphlan:latest-mpa_vOct22_202403')
            for name in ['humann', 'humann_join']:
                self.assertEqual(by_name[name]['container'], 'humann:experimental')
            self.assertEqual(by_name['baqlava']['container'], 'baqlava:4.0.0-r1')
            self.assertEqual(by_name['baqlava']['memory'], 48)
            for name in ['single_end_kneaddata', 'paired_end_kneaddata', 'metaphlan', 'humann', 'strainphlan', 'baqlava']:
                self.assertEqual(by_name[name]['cpus'], 8)
            for settings in by_name.values():
                self.assertFalse(settings['before'])
                self.assertNotIn('DXFUSE', settings['options'] or '')
                self.assertNotIn('.reference-cache', settings['options'] or '')
            params = json.loads((base / 'params.json').read_text())
            for key in ['qc', 'taxonomy', 'function', 'strain']:
                self.assertTrue(params[key])
            self.assertTrue(params['viral'])
            self.assertFalse(params['reporting'])
            self.assertEqual(params['viral_location'], 'host')
            self.assertEqual(params['humann_location'], 'container')
            self.assertEqual(params['strain_location'], 'host')
            self.assertEqual(params['viral_nucleotide'], '/murray/databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.nucleotide')
            self.assertEqual(params['viral_protein'], '/murray/databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.protein')
            for source, target in [('depletion', 'chocophlan'),
                                   ('depletion_protein', 'uniref90_annotated'),
                                   ('depletion_mapping', 'full_mapping')]:
                self.assertIn(params[source], by_name['baqlava']['options'])
                self.assertIn('/Databases/humann/chocophlan-v4-201901/' + target, by_name['baqlava']['options'])
            self.assertNotIn('DEMO', by_name['baqlava']['options'])
            self.assertEqual(by_name['baqlava']['options'].count(':ro'), 3)
            self.assertEqual(len(params['metaphlan']), 2)
            self.assertTrue(all(db['metaphlan_version'] == 'metaphlan_v4' for db in params['metaphlan']))
            self.assertEqual(params['downstream'], ['mpa_vOct22_CHOCOPhlAnSGB_202403'])


if __name__ == '__main__':
    unittest.main()
