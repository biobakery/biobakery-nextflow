"""Load site parameter examples with Nextflow, without scheduling tool tasks."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROFILES = re.findall(r'^    (\w+)\s+\{', (ROOT / 'nextflow.config').read_text(), re.M)


@unittest.skipUnless(shutil.which('nextflow'), 'Nextflow is required')
class SiteConfigTest(unittest.TestCase):
    def probe(self, profile, yaml=None, overrides=()):
        with tempfile.TemporaryDirectory(prefix='site-config-') as tmp:
            base = Path(tmp)
            (base / 'probe.nf').write_text('''workflow {
    new File(params.snapshot).text = groovy.json.JsonOutput.toJson([
        workflow: params.workflow, outdir: params.outdir,
        samplesheet: params.samplesheet, readsdir: params.readsdir,
        host_genome: params.host_genome, max_cpus: params.max_cpus,
        humann_version: params.humann_version, metaphlan_db: params.metaphlan_db,
        metaphlan_databases: params.metaphlan_databases,
        taxonomy: params.run_taxonomic_profiling, function: params.run_functional_profiling,
        viral: params.run_viral_profiling, strain: params.run_strain_profiling])
}
''')
            (base / 'probe.config').write_text(
                f"includeConfig '{ROOT}/nextflow.config'\n"
                # This probe reads params only; avoid loading the AWS executor plugin.
                "process.executor='local'\n"
                'timeline.enabled=false\nreport.enabled=false\ntrace.enabled=false\ndag.enabled=false\n')
            command = ['nextflow', '-C', str(base / 'probe.config'), 'run', str(base / 'probe.nf'),
                       '-profile', profile, '--snapshot', str(base / 'params.json'), '-ansi-log', 'false']
            if yaml:
                command += ['-params-file', str(yaml)]
            result = subprocess.run(command + list(overrides), cwd=base, capture_output=True,
                                    text=True, timeout=120,
                                    env=dict(os.environ, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                                             NXF_OPTS=os.environ.get('NXF_OPTS', '') + ' -XX:-UsePerfData'))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return json.loads((base / 'params.json').read_text())

    def test_every_profile_has_a_loadable_example_without_preset_inputs(self):
        for profile in PROFILES:
            with self.subTest(profile=profile):
                example = 'local' if profile == 'standard' else profile
                yaml = ROOT / 'conf/example_yamls' / (example + '.yaml')
                self.assertTrue(yaml.is_file(), str(yaml))
                params = self.probe(profile, yaml, ['--outdir', 'cli-results'])
                self.assertEqual(params['workflow'], 'mgx')
                self.assertEqual(params['outdir'], 'cli-results')
                self.assertIsNone(params['samplesheet'])
                self.assertIsNone(params['readsdir'])
                humann4 = profile in ['harvard_rc', 'wellesley_hpc', 'wellesley_hopper'] or profile.startswith('dnanexus')
                self.assertEqual(params['humann_version'], 'humann_v4a' if humann4 else 'humann_v37')
                for database in params['metaphlan_databases'] or []:
                    self.assertIn(database['metaphlan_version'],
                                  ['metaphlan_v3', 'metaphlan_v4', 'metaphlan_4.0.6_fixed'])
                if profile == 'dnanexus_download':
                    self.assertTrue(all(params[key] for key in ['taxonomy', 'function', 'viral', 'strain']))

    def test_hopper_primary_reference_and_tool_version_do_not_require_yaml(self):
        params = self.probe('wellesley_hopper')
        self.assertEqual(params['humann_version'], 'humann_v4a')
        self.assertIsNone(params['metaphlan_databases'])
        self.assertEqual(params['metaphlan_db'],
                         '/murray/databases/metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default')

    def test_study_yaml_overrides_site_defaults_and_cli_overrides_yaml(self):
        with tempfile.TemporaryDirectory(prefix='site-params-') as tmp:
            yaml = Path(tmp) / 'study.yaml'
            yaml.write_text('host_genome: /study/mouse\nmax_cpus: 3\noutdir: yaml-results\n')
            params = self.probe('harvard_rc', yaml, ['--outdir', 'cli-results'])
            self.assertEqual(params['host_genome'], '/study/mouse')
            self.assertEqual(params['max_cpus'], 3)
            self.assertEqual(params['outdir'], 'cli-results')


if __name__ == '__main__':
    unittest.main()
