"""Resolve FUSE launch options without Docker, credentials or cloud jobs."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
IMAGE = 'public.ecr.aws/j5i5h1i5/kneaddata:0.12.1-nodb-dnanexus-r1'
METAPHLAN_IMAGE = None
HUMANN_IMAGE = None
FULL_METAPHLAN_IMAGE = 'public.ecr.aws/j5i5h1i5/metaphlan:4.2.5-nodb-dnanexus-r1'
FULL_HUMANN_IMAGE = 'public.ecr.aws/j5i5h1i5/humann:4.0.0-experimental-nodb-dnanexus-r1'
FULL_BAQLAVA_IMAGE = 'public.ecr.aws/j5i5h1i5/baqlava:4.0.0-r1'


@unittest.skipUnless(shutil.which('nextflow'), 'Nextflow is required')
class DnanexusDxfuseConfigTest(unittest.TestCase):
    def probe(self, overrides=None, smoke=False, full=False, profile='dnanexus_dxfuse', mappings=None,
              extra_names=None, references=None):
        with tempfile.TemporaryDirectory(prefix='dnanexus-dxfuse-config-') as tmp:
            base = Path(tmp)
            (base / 'mapping_inputs.json').write_text(json.dumps(mappings or []))
            (base / 'reference_inputs.json').write_text(json.dumps(references or []))
            names = ['single_end_kneaddata', 'paired_end_kneaddata',
                     'kneaddata_read_counts', 'metaphlan', 'humann', 'metaphlan_merge', 'humann_join']
            names += extra_names or []
            processes = ['def dockerSettings = getSession().config.docker\n']
            for name in names:
                processes.append(f'''process {name} {{
    input:
    val db
    val reference_db_paths
    val mappings
    val references
    output:
    path 'settings.json'
    exec:
    def docker = new nextflow.container.DockerConfig(dockerSettings)
    def builder = task.container ? new nextflow.container.DockerBuilder(task.container, docker) : null
    if (builder) builder.addRunOptions(task.containerOptions)
    task.workDir.resolve('settings.json').text = groovy.json.JsonOutput.toJson([
        name: '{name}', cpus: task.cpus, memory: task.memory.toGiga(),
        time: task.time.toHours(), machine: task.machineType, container: task.container,
        options: task.containerOptions, command: builder ? builder.build().getRunCommand() : null,
        before: task.beforeScript, reference_check: task.ext.get('reference_check'),
        entrypointOverride: docker.entrypointOverride()])
}}
''')
            processes.append('''workflow {
    def selected_db = params.metaphlan_databases != null ? params.metaphlan_databases[0] : [metaphlan_db: params.metaphlan_db]
    selected_db = new LinkedHashMap(selected_db)
    if (!selected_db.metaphlan_db.startsWith('/')) selected_db.metaphlan_db = params.metaphlan_db_root + '/' + selected_db.metaphlan_db
    selected_db.metaphlan_index = selected_db.metaphlan_index ?: params.metaphlan_index
    selected_db.strainphlan_db = params.strainphlan_db ?: selected_db.metaphlan_db + '/' + selected_db.metaphlan_index + '.pkl'
    def reference_paths = params.host_genome instanceof List ? params.host_genome : [params.host_genome]
    def mapping_inputs = new groovy.json.JsonSlurperClassic().parse(new File('mapping_inputs.json'))
    def reference_inputs = new groovy.json.JsonSlurperClassic().parse(new File('reference_inputs.json'))
''' + '\n'.join(f'{n}(selected_db, reference_paths, mapping_inputs, reference_inputs)' for n in names) + '''
    new File(params.snapshot).text = groovy.json.JsonOutput.toJson([
        samplesheet: params.samplesheet, host_genome: params.host_genome,
        kneaddata_db_location: params.kneaddata_db_location,
        metaphlan_db_location: params.metaphlan_db_location, metaphlan_db: params.metaphlan_db,
        humann_db_location: params.humann_db_location, humann_db_chocophlan: params.humann_db_chocophlan,
        humann_db_protein: params.humann_db_protein, humann_db_utilitymapping: params.humann_db_utilitymapping,
        run_taxonomic_profiling: params.run_taxonomic_profiling,
        run_functional_profiling: params.run_functional_profiling,
        run_strain_profiling: params.run_strain_profiling,
        run_viral_profiling: params.run_viral_profiling,
        archives: params.dnanexus_reference_archives,
        baqlava_db_nucleotide: params.baqlava_db_nucleotide,
        baqlava_db_protein: params.baqlava_db_protein,
        baqlava_depletion_db: params.baqlava_depletion_db,
        baqlava_depletion_protein_db: params.baqlava_depletion_protein_db,
        baqlava_depletion_mapping_db: params.baqlava_depletion_mapping_db,
        stop_after_qc: params.stop_after_qc])
}
''')
            (base / 'probes.nf').write_text('\n'.join(processes))
            (base / 'probe.config').write_text(
                f"includeConfig '{ROOT}/nextflow.config'\n"
                'timeline.enabled=false\nreport.enabled=false\ntrace.enabled=false\ndag.enabled=false\n')
            args = ['nextflow', '-C', str(base / 'probe.config'), 'run',
                    str(base / 'probes.nf'), '-profile', profile,
                    '--snapshot', str(base / 'snapshot.json'), '-ansi-log', 'false']
            if overrides is not None or smoke or full:
                filename = 'dnanexus_dxfuse_smoke.yaml' if smoke else 'dnanexus_dxfuse.yaml'
                yaml = (ROOT / 'conf/example_yamls' / filename).read_text() if smoke or full else ''
                yaml += '\n' + '\n'.join(f'{key}: {json.dumps(value)}' for key, value in (overrides or {}).items())
                (base / 'overrides.yaml').write_text(yaml)
                args += ['-params-file', str(base / 'overrides.yaml')]
            result = subprocess.run(args, cwd=base, capture_output=True, text=True,
                                    timeout=120, env=dict(os.environ, NXF_OFFLINE='true',
                                    NXF_SYNTAX_PARSER='v1',
                                    NXF_OPTS=os.environ.get('NXF_OPTS', '') + ' -XX:-UsePerfData'))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            settings = [json.loads(p.read_text()) for p in (base / 'work').glob('*/*/settings.json')]
            self.assertEqual({s['name'] for s in settings}, set(names))
            return {s['name']: s for s in settings}, json.loads((base / 'snapshot.json').read_text())

    def test_mount_only_on_analysis_tasks_and_preserve_resources(self):
        settings, params = self.probe(dict(dnanexus_reference_mode='fuse'))
        for name in ['single_end_kneaddata', 'paired_end_kneaddata', 'metaphlan', 'humann']:
            task = settings[name]
            options = shlex.split(task['options'])
            image, cpus, hours = (METAPHLAN_IMAGE, 16, 4) if name == 'metaphlan' else (
                (HUMANN_IMAGE, 16, 12) if name == 'humann' else (IMAGE, 8, 8))
            self.assertEqual(task['container'], image)
            self.assertEqual((task['cpus'], task['memory'], task['time']), (cpus, 28, hours))
            self.assertEqual(task['machine'], 'mem3_ssd2_v3_x16')
            self.assertFalse(task['entrypointOverride'])
            for value in ['DXFUSE_ENABLED=true', 'DX_SECURITY_CONTEXT', 'DX_PROJECT_CONTEXT_ID',
                          '/dev/fuse', 'SYS_ADMIN', 'DX_REFERENCE_FOLDER=/Databases',
                          'DX_REFERENCE_MOUNTPOINT=/tmp/dxfuse']:
                self.assertIn(value, options)
            self.assertNotIn('DX_REFERENCE_PROJECT=', task['options'])
            # Per-process root follows the normal profile's --user setting.
            if task['command']:
                self.assertLess(task['command'].index('-u $(id -u):$(id -g)'),
                                task['command'].index('--user 0'))
        self.assertEqual(settings['kneaddata_read_counts']['container'], IMAGE)
        self.assertEqual(settings['kneaddata_read_counts']['cpus'], 1)
        for name in ['kneaddata_read_counts', 'metaphlan_merge', 'humann_join']:
            self.assertEqual(settings[name]['options'], '--env DXFUSE_ENABLED=false')
            self.assertFalse(settings[name]['before'])
            self.assertFalse(settings[name]['reference_check'])
        self.assertEqual(settings['metaphlan_merge']['container'], METAPHLAN_IMAGE)
        self.assertEqual(settings['humann_join']['container'], HUMANN_IMAGE)
        self.assertEqual(settings['metaphlan_merge']['cpus'], 1)
        self.assertEqual(settings['humann_join']['cpus'], 4)
        self.assertEqual(settings['metaphlan']['cpus'], 16)
        self.assertEqual(settings['humann']['cpus'], 16)
        self.assertIsNone(settings['metaphlan']['container'])
        self.assertIsNone(settings['humann']['container'])
        self.assertEqual(params['host_genome'], '/Databases/kneaddata')
        self.assertEqual(params['kneaddata_db_location'], 'container')
        self.assertEqual(params['metaphlan_db_location'], 'container')
        self.assertEqual(params['humann_db_location'], 'container')
        self.assertEqual(params['metaphlan_db'], '/Databases/metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default')
        for key, directory in [('humann_db_chocophlan', 'chocophlan'),
                               ('humann_db_protein', 'uniref90_annotated'),
                               ('humann_db_utilitymapping', 'full_mapping')]:
            self.assertEqual(params[key], '/Databases/humann/chocophlan-v4-201901/' + directory)
        self.assertFalse(params['run_taxonomic_profiling'])
        self.assertFalse(params['run_functional_profiling'])
        self.assertIsNone(params['samplesheet'])

    def test_run_overrides_are_quoted_and_smoke_yaml_disables_downstream(self):
        settings, params = self.probe(dict(
            dnanexus_reference_mode='fuse',
            dnanexus_reference_project='project-ABC123',
            dnanexus_reference_folder="/Study's Databases; $(false)",
            dnanexus_reference_mountpoint='/tmp/custom mount'), smoke=True)
        for name in ['single_end_kneaddata', 'paired_end_kneaddata', 'metaphlan', 'humann']:
            options = shlex.split(settings[name]['options'])
            for value in ['DX_REFERENCE_PROJECT=project-ABC123',
                          "DX_REFERENCE_FOLDER=/Study's Databases; $(false)",
                          'DX_REFERENCE_MOUNTPOINT=/tmp/custom mount']:
                self.assertIn(value, options)
        self.assertFalse(params['run_taxonomic_profiling'])
        self.assertFalse(params['run_functional_profiling'])
        self.assertFalse(params['stop_after_qc'])

    def test_cache_discovery_uses_nodb_image(self):
        with tempfile.TemporaryDirectory(prefix='dnanexus-dxfuse-inspect-') as tmp:
            for profile, expected in [('dnanexus_dxfuse', {IMAGE}),
                                      ('dnanexus_dxfuse_full', {IMAGE, FULL_METAPHLAN_IMAGE, FULL_HUMANN_IMAGE, FULL_BAQLAVA_IMAGE})]:
                with self.subTest(profile=profile):
                    result = subprocess.run(
                        ['nextflow', 'inspect', str(ROOT), '-profile', profile, '-format', 'json'],
                        cwd=tmp, capture_output=True, text=True, timeout=120,
                        env=dict(os.environ, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                                 NXF_OPTS=os.environ.get('NXF_OPTS', '') + ' -XX:-UsePerfData'))
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    images = {p['container'] for p in json.loads(result.stdout)['processes'] if p.get('container')}
                    self.assertEqual(images, expected)

    def test_full_profile_baqlava_uses_canonical_mount_and_all_depletion_references(self):
        root = '/Databases/humann/chocophlan-v4-201901/'
        references = [dict(flag='--nucdb', path='/Databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.nucleotide', type='directory'),
                      dict(flag='--protdb', path='/Databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.protein', type='directory')]
        references += [dict(flag=None, path=root + name, type='directory')
                       for name in ['chocophlan', 'uniref90_annotated', 'full_mapping']]
        settings, params = self.probe(profile='dnanexus_dxfuse_full',
            extra_names=['baqlava'], references=references)
        task = settings['baqlava']
        self.assertTrue(params['run_viral_profiling'])
        self.assertIsNone(params['samplesheet'])
        self.assertEqual(task['container'], FULL_BAQLAVA_IMAGE)
        self.assertIn('"$PWD/.reference-cache/Databases":\'/Databases\':ro', task['options'])
        self.assertNotIn('/tmp/dxfuse', task['options'])
        self.assertNotIn('DX_SECURITY_CONTEXT', task['options'])
        self.assertIn('tarballs/chocophlan-v4-201901.tar.gz', task['before'])
        self.assertIn('baqlava/BAQLaVa_v05/BAQLaVa.V0.5.nucleotide', task['before'])
        self.assertEqual(params['baqlava_db_nucleotide'], references[0]['path'])
        self.assertEqual(params['baqlava_db_protein'], references[1]['path'])
        for key, suffix in [('baqlava_depletion_db', 'chocophlan'),
                            ('baqlava_depletion_protein_db', 'uniref90_annotated'),
                            ('baqlava_depletion_mapping_db', 'full_mapping')]:
            self.assertEqual(params[key], root + suffix)
            self.assertIn(root + suffix, task['reference_check'])
        self.assertNotIn('mpa_vOct22_202403.tar.gz', settings['metaphlan']['before'])
        self.assertIn('dx download --recursive', settings['metaphlan']['before'])
        self.assertEqual(params['archives'], [dict(archive='tarballs/chocophlan-v4-201901.tar.gz',
            extract_to='humann/chocophlan-v4-201901')])

    def test_full_profile_downloads_selected_metaphlan_and_humann_references(self):
        mappings = [
            dict(database_location='container', group_mapping_database='/Databases/humann/chocophlan-v4-201901/full_mapping/ecs.tsv'),
            dict(database_location='container', group_mapping_database='/Databases/custom/groups.tsv', renaming_database='/Databases/custom/names.tsv'),
            dict(database_location='host', group_mapping_database='/already/staged/external.tsv')]
        settings, params = self.probe(profile='dnanexus_dxfuse_full', mappings=mappings,
            overrides=dict(dnanexus_reference_archives=[], dnanexus_reference_project='project-Refs123', metaphlan_databases=[
                dict(metaphlan_db='mpa_vOct22_202403_default', metaphlan_index='primary'),
                dict(metaphlan_db='unused_alternative', metaphlan_index='alternate')]))
        self.assertTrue(params['run_taxonomic_profiling'])
        self.assertTrue(params['run_functional_profiling'])
        self.assertEqual(settings['metaphlan']['container'], FULL_METAPHLAN_IMAGE)
        self.assertEqual(settings['humann']['container'], FULL_HUMANN_IMAGE)
        for name in ['single_end_kneaddata', 'paired_end_kneaddata', 'metaphlan', 'humann']:
            self.assertIn('DXFUSE_ENABLED=false', settings[name]['options'])
            self.assertIn(':ro', settings[name]['options'])
            self.assertNotIn('DX_SECURITY_CONTEXT', settings[name]['options'])
        for name in ['kneaddata_read_counts', 'metaphlan_merge', 'humann_join']:
            self.assertFalse(settings[name]['before'])
            self.assertEqual(settings[name]['options'], '--env DXFUSE_ENABLED=false')
        self.assertNotIn('unused_alternative', settings['metaphlan']['before'])
        with tempfile.TemporaryDirectory(prefix='full-reference-download-') as tmp:
            base = Path(tmp)
            sources, tools = base / 'source', base / 'bin'
            tools.mkdir()
            folders = ['metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default',
                       'humann/chocophlan-v4-201901/chocophlan',
                       'humann/chocophlan-v4-201901/uniref90_annotated',
                       'humann/chocophlan-v4-201901/full_mapping']
            for folder in folders:
                (sources / folder).mkdir(parents=True)
                (sources / folder / 'index').write_text('mock reference')
            (sources / 'humann/chocophlan-v4-201901/full_mapping/ecs.tsv').write_text('mapping')
            (sources / 'custom').mkdir()
            for name in ['groups.tsv', 'names.tsv']:
                (sources / 'custom' / name).write_text('custom mapping')
            dx = tools / 'dx'
            dx.write_text('''#!/usr/bin/env python3
import json, os, shutil, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['CAPTURE_DOWNLOAD'], 'a') as stream:
    stream.write(json.dumps(args) + '\\n')
remote = args[3] if '--recursive' in args else args[2]
assert remote.startswith('project-Refs123:/Databases/'), remote
relative = remote.split(':/Databases/', 1)[1]
source = Path(os.environ['MOCK_SOURCE']) / relative
if '--recursive' in args:
    shutil.copytree(source, Path.cwd() / source.name)
else:
    shutil.copyfile(source, args[args.index('--output') + 1])
''')
            dx.chmod(0o755)
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                       MOCK_SOURCE=str(sources), CAPTURE_DOWNLOAD=str(base / 'calls.jsonl'))
            for stage in ['metaphlan', 'humann']:
                scratch = base / stage
                scratch.mkdir()
                result = subprocess.run(['bash', '-e', '-c', settings[stage]['before']], cwd=base,
                    env=dict(env, NXF_SCRATCH=str(scratch)), capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                expected = folders[:1] if stage == 'metaphlan' else folders[1:]
                for folder in expected:
                    self.assertTrue((scratch / '.reference-cache/Databases' / folder / 'index').exists())
                if stage == 'humann':
                    self.assertTrue((scratch / '.reference-cache/Databases/custom/groups.tsv').exists())
                    self.assertTrue((scratch / '.reference-cache/Databases/custom/names.tsv').exists())
            calls = [json.loads(line) for line in (base / 'calls.jsonl').read_text().splitlines()]
            self.assertEqual(sum('--recursive' in call for call in calls), 4)
            self.assertEqual(sum('--output' in call for call in calls), 2)
            self.assertNotIn('/already/staged', json.dumps(calls))
            self.assertNotIn('ecs.tsv', json.dumps(calls))  # already covered by full_mapping folder

    def test_local_download_is_absent_from_other_profiles(self):
        with tempfile.TemporaryDirectory(prefix='reference-profile-scope-') as tmp:
            for profile in ['local', 'standard', 'harvard_rc', 'wellesley_hpc',
                            'wellesley_hopper', 'tufts_hpc', 'amazon', 'dnanexus']:
                with self.subTest(profile=profile):
                    result = subprocess.run(['nextflow', 'config', str(ROOT), '-profile', profile, '-flat'],
                        cwd=tmp, capture_output=True, text=True, timeout=120,
                        env=dict(os.environ, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                                 NXF_OPTS=os.environ.get('NXF_OPTS', '') + ' -XX:-UsePerfData'))
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    for marker in ['dnanexus_reference_mode', 'dnanexus_reference_archives', 'ext.reference_paths', '.reference-cache', 'dx download']:
                        self.assertNotIn(marker, result.stdout)

    def test_run_yaml_keeps_qc_only_without_preset_samplesheet(self):
        settings, params = self.probe(full=True)
        self.assertFalse(params['run_taxonomic_profiling'])
        self.assertFalse(params['run_functional_profiling'])
        self.assertFalse(params['stop_after_qc'])
        self.assertIsNone(params['samplesheet'])
        for name in ['single_end_kneaddata', 'paired_end_kneaddata']:
            self.assertIn('DXFUSE_ENABLED=false', settings[name]['options'])
            self.assertIn('dx download', settings[name]['before'])
            self.assertIn(':ro', settings[name]['options'])
            self.assertNotIn('DX_SECURITY_CONTEXT', settings[name]['options'])
            self.assertNotIn('/dev/fuse', settings[name]['options'])
            self.assertNotIn('SYS_ADMIN', settings[name]['options'])

    def test_diagnostics_distinguish_missing_mount_and_missing_database(self):
        with tempfile.TemporaryDirectory(prefix='dxfuse-diagnostics-') as tmp:
            base = Path(tmp)
            tools = base / 'bin'
            tools.mkdir()
            mountpoint = tools / 'mountpoint'
            mountpoint.write_text('#!/bin/sh\nexit "${MOCK_MOUNT_STATUS:-0}"\n')
            mountpoint.chmod(0o755)
            findmnt = tools / 'findmnt'
            findmnt.write_text('#!/bin/sh\nprintf "TARGET FSTYPE\\n/mock fuse.dxfuse\\n"\n')
            findmnt.chmod(0o755)
            database = base / "reference's directory"
            settings, _ = self.probe(dict(host_genome=str(database), dnanexus_reference_mode='fuse',
                dnanexus_reference_mountpoint=str(base / 'mount'),
                dnanexus_reference_project='project-Reference123',
                dnanexus_reference_folder='/Reference Data/Databases'))
            script = settings['paired_end_kneaddata']['reference_check']
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                       DX_SECURITY_CONTEXT='credential-must-not-appear')
            for status, create_db, message in [('1', False, 'expected FUSE mount is absent'),
                                              ('0', False, 'database directory missing'),
                                              ('0', True, 'mount and database directories verified')]:
                with self.subTest(status=status, database=create_db):
                    if create_db:
                        database.mkdir()
                    result = subprocess.run(['bash', '-e', '-c', script], capture_output=True,
                        text=True, timeout=10, env=dict(env, MOCK_MOUNT_STATUS=status))
                    self.assertEqual(result.returncode, 0 if create_db else 72, result.stderr)
                    self.assertIn(message, result.stderr)
                    self.assertIn('project-Reference123', result.stderr)
                    self.assertIn('/Reference Data/Databases', result.stderr)
                    self.assertNotIn('credential-must-not-appear', result.stdout + result.stderr)

    def test_download_uses_worker_scratch_and_failure_prevents_analysis(self):
        with tempfile.TemporaryDirectory(prefix='reference-download-') as tmp:
            base = Path(tmp)
            tools, scratch, sources, container = [base / name for name in ['bin', 'scratch', 'source', 'container']]
            for path in [tools, scratch, sources / 'kneaddata', container]:
                path.mkdir(parents=True)
            for suffix in ['1', '2', '3', '4', 'rev.1', 'rev.2']:
                (sources / 'kneaddata' / f'human.{suffix}.bt2').write_text('index part ' + suffix)
            dx = tools / 'dx'
            dx.write_text('''#!/usr/bin/env python3
import json, os, shutil, sys
from pathlib import Path
with open(os.environ['CAPTURE_DOWNLOAD'], 'a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\\n')
if os.environ.get('MOCK_DOWNLOAD_FAIL') == '1':
    sys.exit(1)
assert sys.argv[1:4] == ['download', '--recursive', '--no-progress']
assert sys.argv[4] == "project-Refs123:/Study's Databases/kneaddata"
shutil.copytree(Path(os.environ['MOCK_SOURCE']) / 'kneaddata', Path.cwd() / 'kneaddata')
''')
            dx.chmod(0o755)
            settings, _ = self.probe(dict(
                dnanexus_reference_project='project-Refs123',
                dnanexus_reference_folder="/Study's Databases",
                dnanexus_reference_mountpoint=str(container),
                host_genome=str(container / 'Databases/kneaddata')))
            task = settings['paired_end_kneaddata']
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                       NXF_SCRATCH=str(scratch), MOCK_SOURCE=str(sources),
                       CAPTURE_DOWNLOAD=str(base / 'calls.jsonl'),
                       DX_SECURITY_CONTEXT='credential-must-not-appear')
            # beforeScript starts outside scratch; it must stage into NXF_SCRATCH.
            result = subprocess.run(['bash', '-e', '-c', task['before']], cwd=base,
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            downloaded = scratch / '.reference-cache/Databases/kneaddata'
            self.assertEqual(sorted(p.name for p in downloaded.iterdir()),
                             sorted(p.name for p in (sources / 'kneaddata').iterdir()))
            self.assertFalse((base / '.reference-cache').exists())
            self.assertIn('local SSD download completed in', result.stdout)
            self.assertNotIn('credential-must-not-appear', result.stdout + result.stderr)
            # Simulate the bind mount, then run the actual container-side checks.
            (container / 'Databases').symlink_to(scratch / '.reference-cache/Databases')
            result = subprocess.run(['bash', '-e', '-c', task['reference_check']], cwd=scratch,
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('FUSE is disabled', result.stderr)
            self.assertIn('local SSD download completed in', result.stderr)
            args = shlex.split(task['options'])
            self.assertIn('$PWD/.reference-cache/Databases:' + str(container / 'Databases') + ':ro', args)
            failure_scratch = base / 'failed-scratch'
            failure_scratch.mkdir()
            result = subprocess.run(['bash', '-e', '-c', task['before'] + '\ntouch analysis-started'],
                cwd=base, env=dict(env, NXF_SCRATCH=str(failure_scratch), MOCK_DOWNLOAD_FAIL='1'),
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 74, result.stderr)
            self.assertFalse((base / 'analysis-started').exists())
            self.assertFalse((failure_scratch / '.reference-cache/Databases/kneaddata').exists())
            # Run a real Nextflow Bash wrapper with scratch enabled. This verifies
            # host-side staging happens in the directory later used by the task.
            (base / 'stage.nf').write_text('''process paired_end_kneaddata {
    input:
    val reference_db_paths
    output:
    path 'staged.txt'
    script:
    """
    test -f .reference-cache/Databases/kneaddata/human.1.bt2
    test -f .reference-cache/Databases/kneaddata/human.rev.2.bt2
    echo 'local references available' > staged.txt
    """
}
workflow { paired_end_kneaddata([params.host_genome]) }
''')
            (base / 'wrapper.config').write_text(
                f"includeConfig '{ROOT}/nextflow.config'\n"
                "process.scratch=true\nprocess { withName: paired_end_kneaddata { cpus=1; memory='1.GB' } }\n"
                'timeline.enabled=false\nreport.enabled=false\ntrace.enabled=false\ndag.enabled=false\n')
            (base / 'params.json').write_text(json.dumps(dict(
                dnanexus_reference_project='project-Refs123',
                dnanexus_reference_folder="/Study's Databases")))
            wrapper_env = dict(env, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                               NXF_OPTS=os.environ.get('NXF_OPTS', '') + ' -XX:-UsePerfData')
            wrapper_env.pop('NXF_SCRATCH', None)
            result = subprocess.run(['nextflow', '-C', str(base / 'wrapper.config'), 'run',
                str(base / 'stage.nf'), '-profile', 'dnanexus_dxfuse', '-without-docker',
                '-params-file', str(base / 'params.json'), '-ansi-log', 'false'],
                cwd=base, env=wrapper_env, capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(list((base / 'work').glob('*/*/staged.txt'))), 1)


if __name__ == '__main__':
    unittest.main()
