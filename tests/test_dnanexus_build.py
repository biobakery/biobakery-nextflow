"""Check DNAnexus build/refresh orchestration without uploads or billable jobs."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless((ROOT / 'dxbuild.sh').exists(), 'Local dxbuild.sh is required')
class DnanexusBuildTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='dnanexus-build-test-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        (self.base / 'bin').mkdir()
        mock_dx = self.base / 'bin/dx'
        mock_dx.write_text(f'#!{sys.executable}\n' + '''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['CAPTURE_CALLS'], 'a') as stream:
    stream.write(json.dumps(['dx', *args]) + '\\n')
if args[0] == 'run':
    print('job-Cache123')
    sys.exit(0)
if args[0] == 'wait':
    sys.exit(int(os.environ.get('IMPORTER_STATUS', '0')))
source = Path(args[args.index('--nextflow') + 1] if args[0] == 'build' else args[1])
repo = Path(os.environ['SOURCE_REPOSITORY'])
for name in ['main.nf', 'nextflow.config', 'nextflow_schema.json', 'conf/databases/dnanexus.config', 'assets/NO_FILE', 'bin', 'modules', 'subworkflows', 'workflows']:
    assert (source / name).exists(), name
for name in ['.git', '.nextflow', 'work', 'results', 'containers', 'samplesheet.csv', 'samplesheet-dnanexus.csv', 'tests']:
    assert not (source / name).exists(), name
assert not list(source.rglob('*.pyc'))
assert (source / 'main.nf').read_bytes() == (repo / 'main.nf').read_bytes()
assert (source / 'conf/profiles/dnanexus.config').read_bytes() == (repo / 'conf/profiles/dnanexus.config').read_bytes()
if args[0] == 'build':
    Path(os.environ['CAPTURE_ARGUMENTS']).write_text(json.dumps(args))
''')
        mock_dx.chmod(0o755)
        mock_python = self.base / 'bin/python3'
        mock_python.write_text(f'#!{sys.executable}\n' + '''
import json, os, subprocess, sys
if sys.argv[1].endswith('/dnanexus_finalize_image_cache.py'):
    with open(os.environ['CAPTURE_CALLS'], 'a') as stream:
        stream.write(json.dumps(['finalize-cache', *sys.argv[2:]]) + '\\n')
    sys.exit(int(os.environ.get('FINALIZE_STATUS', '0')))
sys.exit(subprocess.call([sys.executable, *sys.argv[1:]]))
''')
        mock_python.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.base / 'bin') + os.pathsep + os.environ['PATH'],
                        SOURCE_REPOSITORY=str(ROOT), CAPTURE_ARGUMENTS=str(self.base / 'args.json'),
                        CAPTURE_CALLS=str(self.base / 'calls.jsonl'),
                        TMPDIR=str(self.base))
        self.env.pop('DNANEXUS_HEAD_INSTANCE_TYPE', None)
        self.env.pop('DNANEXUS_BUILD_SAMPLESHEET', None)

    def run_build(self, args=()):
        return subprocess.run(['bash', str(ROOT / 'dxbuild.sh'), *args], cwd=ROOT,
                              env=self.env, capture_output=True, text=True, timeout=20)

    def calls(self):
        path = self.base / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_build_uses_project_cache_and_larger_head_without_preset_inputs(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        args = json.loads((self.base / 'args.json').read_text())
        self.assertNotIn('--cache-docker', args)
        self.assertNotIn('--nextflow-pipeline-params', args)
        self.assertFalse(any('samplesheet' in arg.lower() for arg in args))
        self.assertIn('--archive', args)
        self.assertEqual(args[args.index('--profile') + 1], 'dnanexus')
        self.assertEqual(args[args.index('--destination') + 1],
                         'project-JBVGpB00Kg1xBf54v05BXj6f:/Applets/wmgx/')
        extra = json.loads(args[args.index('--extra-args') + 1])
        self.assertEqual(extra['runSpec']['systemRequirements'],
                         {'main': {'instanceType': 'mem1_ssd2_v2_x8'}})
        self.assertFalse(Path(args[args.index('--nextflow') + 1]).exists())

    def test_head_instance_can_be_overridden(self):
        self.env['DNANEXUS_HEAD_INSTANCE_TYPE'] = 'mem3_ssd2_v3_x16'
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        args = json.loads((self.base / 'args.json').read_text())
        extra = json.loads(args[args.index('--extra-args') + 1])
        self.assertEqual(extra['runSpec']['systemRequirements']['main']['instanceType'],
                         'mem3_ssd2_v3_x16')

    def test_refresh_finishes_before_runtime_build_and_uses_separate_instances(self):
        result = self.run_build(['--refresh-images', '--build-instance-type', 'mem1_ssd2_v2_x4',
                                 '--head-instance-type', 'mem3_ssd2_v3_x16',
                                 '--destination', 'project-Test123:/Custom folder/',
                                 '--profile', 'dnanexus', '--nextflow-version', '25.10',
                                 '--docker-secrets', 'project-Test123:file-Secrets'])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertEqual([call[0] if call[0] != 'dx' else call[1] for call in calls],
                         ['upload', 'run', 'wait', 'finalize-cache', 'build'])
        run = calls[1]
        self.assertEqual(run[2], 'nextflow_pipeline_importer')
        self.assertIn('-icache_docker=true', run)
        self.assertIn('-iconfig_profile=dnanexus', run)
        self.assertIn('-inextflow_version=25.10', run)
        self.assertIn('-idocker_secrets=project-Test123:file-Secrets', run)
        self.assertEqual(run[run.index('--instance-type') + 1], 'mem1_ssd2_v2_x4')
        refresh_dest = run[run.index('--destination') + 1]
        self.assertTrue(refresh_dest.startswith('project-Test123:/Custom folder/.cache-refresh/'))
        self.assertIn('-irepository_url=' + refresh_dest + '.nf_source/biobakery-nextflow', run)
        self.assertEqual(calls[2], ['dx', 'wait', 'job-Cache123'])
        self.assertIn('project-Test123', calls[3])
        args = calls[-1]
        self.assertNotIn('--cache-docker', args)
        self.assertEqual(args[args.index('--destination') + 1], 'project-Test123:/Custom folder/')
        extra = json.loads(args[args.index('--extra-args') + 1])
        self.assertEqual(extra['runSpec']['systemRequirements']['main']['instanceType'],
                         'mem3_ssd2_v3_x16')

    def test_cache_docker_alias_still_produces_unbundled_runtime(self):
        result = self.run_build(['--cache-docker'])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls()[1][self.calls()[1].index('--instance-type') + 1],
                         'mem1_ssd2_v2_x8')
        self.assertNotIn('--cache-docker', self.calls()[-1])

    def test_failed_import_or_cache_finalization_prevents_runtime_build(self):
        for failure in ['IMPORTER_STATUS', 'FINALIZE_STATUS']:
            with self.subTest(failure=failure):
                self.env[failure] = '1'
                result = self.run_build(['--refresh-images'])
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.base / 'args.json').exists())
                self.env.pop(failure)

    def test_help_and_invalid_arguments_do_not_start_cloud_operations(self):
        result = self.run_build(['--help'])
        self.assertEqual(result.returncode, 0)
        self.assertIn('--refresh-images', result.stdout)
        for args in [['--head-instance-type'], ['--typo'], ['--destination', 'wrong'],
                     ['--docker-secrets', 'file-Secrets'], ['--', '--cache-docker'],
                     ['--', '--extra-args', '{}']]:
            with self.subTest(args=args):
                result = self.run_build(args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertFalse(self.calls())


@unittest.skipUnless(importlib.util.find_spec('dxpy'), 'dx-toolkit is required')
class DnanexusBuildSpecTest(unittest.TestCase):
    def test_source_only_spec_keeps_runtime_assets_without_docker_bundles(self):
        from dxpy.nextflow.nextflow_builder import prepare_custom_inputs
        from dxpy.nextflow.nextflow_templates import get_nextflow_dxapp
        # Only the asset existence checks need the platform; no API calls in this test.
        with patch('dxpy.describe', return_value={}):
            spec = get_nextflow_dxapp(
                custom_inputs=prepare_custom_inputs(str(ROOT / 'nextflow_schema.json')),
                resources_dir=str(ROOT), region='aws:us-east-1', profile='dnanexus',
                cache_docker=False, nextflow_version='25.10')
        region = spec['regionalOptions']['aws:us-east-1']
        self.assertFalse(region['bundledDepends'])
        self.assertEqual(len(region['assetDepends']), 3)


@unittest.skipUnless(importlib.util.find_spec('dxpy'), 'dx-toolkit is required')
class DnanexusCacheFinalizeTest(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            'finalize_cache', ROOT / 'bin/dnanexus_finalize_image_cache.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.project = 'project-Test123'

    def test_archive_only_superseded_matching_names_after_success(self):
        dxpy = self.module.dxpy
        bundles = [{'id': dxpy.dxlink(file_id)} for file_id in
                   ['file-NewH', 'file-K', 'file-Resources']]
        metadata = {
            'file-NewH': {'folder': '/.cached_docker_images/humann', 'name': 'humann_experimental', 'state': 'closed'},
            'file-K': {'folder': '/.cached_docker_images/kneaddata', 'name': 'kneaddata_release', 'state': 'closed'},
            'file-Resources': {'folder': '/assets', 'name': 'resources.tar.gz', 'state': 'closed'},
        }
        with patch.object(dxpy, 'DXJob') as job, patch.object(dxpy, 'DXApplet') as applet, \
                patch.object(dxpy, 'DXFile') as file, patch.object(dxpy, 'DXProject') as project, \
                patch.object(dxpy, 'find_data_objects') as find:
            job.return_value.describe.return_value = {
                'state': 'done', 'project': self.project,
                'output': {'output_applet': dxpy.dxlink('applet-New')}}
            applet.return_value.describe.return_value = {
                'runSpec': {'bundledDepends': bundles},
                'regionalOptions': {'aws:us-east-1': {'bundledDepends': bundles}}}
            file.side_effect = lambda file_id, **kwargs: type('File', (), {
                'describe': lambda self: metadata[file_id]})()
            find.side_effect = lambda **kwargs: (
                [{'id': 'file-NewH'}, {'id': 'file-OldH'}]
                if kwargs['name'] == 'humann_experimental' else [{'id': 'file-K'}])
            self.module.finalize_cache('job-Importer', self.project, '/refresh/superseded-images')
            project.return_value.new_folder.assert_called_once_with(
                '/refresh/superseded-images/humann', parents=True)
            project.return_value.move.assert_called_once_with(
                destination='/refresh/superseded-images/humann', objects=['file-OldH'])
            self.assertEqual(file.call_count, 3)  # Regional/runSpec duplicates are deduplicated.
            self.assertEqual(find.call_count, 2)
            for call in find.call_args_list:
                self.assertFalse(call.kwargs['recurse'])
                self.assertEqual(call.kwargs['project'], self.project)

    def test_failed_or_wrong_project_importer_cannot_change_cache(self):
        dxpy = self.module.dxpy
        with patch.object(dxpy, 'DXJob') as job, patch.object(dxpy, 'DXProject') as project:
            for description in [{'state': 'failed', 'project': self.project},
                                {'state': 'done', 'project': 'project-Other'}]:
                job.return_value.describe.return_value = description
                with self.assertRaises(ValueError):
                    self.module.finalize_cache('job-Importer', self.project, '/archive')
            project.assert_not_called()


if __name__ == '__main__':
    unittest.main()
