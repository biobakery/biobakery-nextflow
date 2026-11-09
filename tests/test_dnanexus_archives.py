"""Exercise profile-generated archive staging with real tar and a mocked SDK."""
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

import test_dnanexus_dxfuse_config as probes


@unittest.skipUnless(shutil.which('nextflow') and shutil.which('tar'), 'Nextflow and tar are required')
class DnanexusArchiveTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='dnanexus-archives-')
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.project = self.base / 'project'
        self.tarballs = self.project / 'tarballs'
        self.tarballs.mkdir(parents=True)
        self.tools = self.base / 'bin'
        self.tools.mkdir()
        dx = self.tools / 'dx'
        dx.write_text('''#!/usr/bin/env python3
import json, os, shutil, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['CAPTURE_DOWNLOAD'], 'a') as stream:
    stream.write(json.dumps(args) + '\\n')
if os.environ.get('MOCK_DOWNLOAD_FAIL') == '1':
    sys.exit(1)
assert args[:2] == ['download', '--no-progress'], args
assert '--recursive' not in args, args
remote = args[2]
assert remote.startswith("project-Archives123:/Study's Databases/"), remote
relative = remote.split(":/Study's Databases/", 1)[1]
source = Path(os.environ['MOCK_PROJECT']) / relative
shutil.copyfile(source, args[args.index('--output') + 1])
''')
        dx.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.tools) + os.pathsep + os.environ['PATH'],
            MOCK_PROJECT=str(self.project), CAPTURE_DOWNLOAD=str(self.base / 'calls.jsonl'),
            DX_SECURITY_CONTEXT='credential-must-not-appear')

    def bundle(self, name, members, compressed=True):
        with tarfile.open(self.tarballs / name, 'w:gz' if compressed else 'w') as archive:
            for filename, content in members.items():
                data = content.encode()
                member = tarfile.TarInfo('./' + filename)
                member.size = len(data)
                member.mode = 0o644
                archive.addfile(member, io.BytesIO(data))

    def settings(self, **overrides):
        values = dict(dnanexus_reference_project='project-Archives123',
                      dnanexus_reference_folder="/Study's Databases",
                      dnanexus_reference_archives=[
                          dict(archive='tarballs/mpa_vOct22_202403.tar.gz', extract_to='metaphlan/mpa_vOct22_202403'),
                          dict(archive='tarballs/chocophlan-v4-201901.tar.gz', extract_to='humann/chocophlan-v4-201901')])
        values.update(overrides)
        return probes.DnanexusDxfuseConfigTest.probe(self, overrides=values,
            profile='dnanexus_dxfuse_full', mappings=[dict(database_location='container',
                group_mapping_database='/Databases/custom/groups.tsv')])[0]

    def run_stage(self, task, name, **env):
        scratch = self.base / name
        scratch.mkdir()
        result = subprocess.run(['bash', '-e', '-c', task['before'] + '\ntouch analysis-started'],
            cwd=scratch, env=dict(self.env, NXF_SCRATCH=str(scratch), **env),
            capture_output=True, text=True, timeout=15)
        self.assertNotIn('credential-must-not-appear', result.stdout + result.stderr)
        return scratch, result

    def test_bundles_extract_to_tool_paths_once_and_keep_uncovered_file_downloads(self):
        self.bundle('mpa_vOct22_202403.tar.gz', {
            'mpa_vOct22_202403_default/index.bt2l': 'metaphlan index',
            'mpa_vOct22_202403_default/metadata.pkl': 'metaphlan metadata'})
        self.bundle('chocophlan-v4-201901.tar.gz', {
            'chocophlan/SGB123.fna.gz': 'nucleotide',
            'uniref90_annotated/protein.dmnd': 'protein',
            'full_mapping/ecs.tsv': 'mapping'})
        (self.project / 'custom').mkdir()
        (self.project / 'custom/groups.tsv').write_text('custom grouping')
        settings = self.settings()
        for stage, path, expected in [
            ('metaphlan', 'metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default/index.bt2l', 'metaphlan index'),
            ('humann', 'humann/chocophlan-v4-201901/chocophlan/SGB123.fna.gz', 'nucleotide')]:
            with self.subTest(stage=stage):
                scratch, result = self.run_stage(settings[stage], stage)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((scratch / '.reference-cache/Databases' / path).read_text(), expected)
                self.assertTrue((scratch / 'analysis-started').exists())
                self.assertFalse(list(scratch.glob('.reference-archive.*')))
                log = (scratch / '.reference-download.log').read_text()
                self.assertIn('archive download completed in', log)
                self.assertIn('archive extraction completed in', log)
                if stage == 'humann':
                    self.assertTrue((scratch / '.reference-cache/Databases/humann/chocophlan-v4-201901/full_mapping/ecs.tsv').exists())
                    self.assertTrue((scratch / '.reference-cache/Databases/custom/groups.tsv').exists())
        calls = [json.loads(line) for line in (self.base / 'calls.jsonl').read_text().splitlines()]
        sources = [call[2] for call in calls]
        self.assertEqual(sum(path.endswith('/mpa_vOct22_202403.tar.gz') for path in sources), 1)
        self.assertEqual(sum(path.endswith('/chocophlan-v4-201901.tar.gz') for path in sources), 1)
        self.assertEqual(sum(path.endswith('/custom/groups.tsv') for path in sources), 1)
        self.assertEqual(len(calls), 3)

    def test_bad_download_extraction_and_layout_never_start_analysis(self):
        task = self.settings()['metaphlan']
        archive = self.tarballs / 'mpa_vOct22_202403.tar.gz'
        for name in ['download-failure', 'corrupt-archive', 'wrong-layout', 'traversal']:
            with self.subTest(failure=name):
                if name == 'wrong-layout':
                    self.bundle(archive.name, {'wrong/index': 'wrong root'})
                elif name == 'traversal':
                    self.bundle(archive.name, {'../escaped': 'must not escape'})
                else:
                    archive.write_bytes(b'not a tar archive')
                scratch, result = self.run_stage(task, name,
                    MOCK_DOWNLOAD_FAIL='1' if name == 'download-failure' else '0')
                self.assertEqual(result.returncode, 74, result.stdout + result.stderr)
                self.assertFalse((scratch / 'analysis-started').exists())
                self.assertFalse((scratch / '.reference-cache/Databases/metaphlan/mpa_vOct22_202403').exists())
                self.assertFalse(list(scratch.rglob('escaped')))

    def test_plain_tar_and_real_nextflow_scratch_wrapper(self):
        self.bundle('meta.tar', {'mpa_vOct22_202403_default/index.bt2l': 'plain tar index'}, compressed=False)
        archives = [dict(archive='tarballs/meta.tar', extract_to='metaphlan/mpa_vOct22_202403')]
        task = self.settings(dnanexus_reference_archives=archives)['metaphlan']
        scratch, result = self.run_stage(task, 'plain-tar')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((scratch / '.reference-cache/Databases/metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default/index.bt2l').exists())
        (self.base / 'archive.nf').write_text('''process metaphlan {
    input:
    val db
    output:
    path 'staged.txt'
    script:
    """
    cat .reference-cache/Databases/metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default/index.bt2l > staged.txt
    """
}
workflow { metaphlan([metaphlan_db: params.metaphlan_db]) }
''')
        (self.base / 'wrapper.config').write_text(
            f"includeConfig '{probes.ROOT}/nextflow.config'\n"
            "process.scratch=true\nprocess { withName: metaphlan { cpus=1; memory='1.GB' } }\n"
            'timeline.enabled=false\nreport.enabled=false\ntrace.enabled=false\ndag.enabled=false\n')
        (self.base / 'params.json').write_text(json.dumps(dict(
            dnanexus_reference_project='project-Archives123',
            dnanexus_reference_folder="/Study's Databases", dnanexus_reference_archives=archives)))
        result = subprocess.run(['nextflow', '-C', str(self.base / 'wrapper.config'), 'run',
            str(self.base / 'archive.nf'), '-profile', 'dnanexus_dxfuse_full', '-without-docker',
            '-params-file', str(self.base / 'params.json'), '-ansi-log', 'false'],
            cwd=self.base, capture_output=True, text=True, timeout=120,
            env=dict(self.env, NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                     NXF_OPTS=os.environ.get('NXF_OPTS', '') + ' -XX:-UsePerfData'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        outputs = list((self.base / 'work').glob('*/*/staged.txt'))
        self.assertEqual(len(outputs), 1)
        self.assertEqual(outputs[0].read_text(), 'plain tar index')

    def test_strain_and_viral_tasks_stage_matching_references_and_images(self):
        index = 'mpa_vOct22_CHOCOPhlAnSGB_202403'
        self.bundle('mpa_vOct22_202403.tar.gz', {
            'mpa_vOct22_202403_default/' + index + '.pkl': 'metadata',
            'mpa_vOct22_202403_default/' + index + '.1.bt2l': 'index'})
        self.bundle('chocophlan-v4-201901.tar.gz', {'chocophlan/SGB.fna.gz': 'depletion'})
        self.bundle('viral.tar.gz', {'nucleotide/index': 'viral', 'protein/index': 'protein',
                                    'nuc.tsv': 'mapping', 'prot.tsv': 'mapping'})
        archives = [dict(archive='tarballs/mpa_vOct22_202403.tar.gz', extract_to='metaphlan/mpa_vOct22_202403'),
                    dict(archive='tarballs/chocophlan-v4-201901.tar.gz', extract_to='humann/chocophlan-v4-201901'),
                    dict(archive='tarballs/viral.tar.gz', extract_to='baqlava')]
        depletion = '/Databases/humann/chocophlan-v4-201901/chocophlan'
        refs = [dict(flag='--nucdb', path='/Databases/baqlava/nucleotide', type='directory'),
                dict(flag='--protdb', path='/Databases/baqlava/protein', type='directory'),
                dict(flag='--nucindex', path='/Databases/baqlava/nuc.tsv', type='file'),
                dict(flag='--protindex', path='/Databases/baqlava/prot.tsv', type='file'),
                dict(flag=None, path=depletion, type='directory')]
        settings, params = probes.DnanexusDxfuseConfigTest.probe(self,
            profile='dnanexus_dxfuse_full', extra_names=['strainphlan', 'baqlava'], references=refs,
            overrides=dict(dnanexus_reference_project='project-Archives123',
                dnanexus_reference_folder="/Study's Databases", dnanexus_reference_archives=archives,
                dnanexus_baqlava_container='example.invalid/baqlava:test', baqlava_depletion_db=depletion))
        self.assertTrue(params['run_strain_profiling'])
        self.assertTrue(params['run_viral_profiling'])
        self.assertEqual(settings['strainphlan']['container'], settings['metaphlan']['container'])
        self.assertEqual(settings['baqlava']['container'], 'example.invalid/baqlava:test')
        for name in ['strainphlan', 'baqlava']:
            self.assertEqual(settings[name]['cpus'], 8 if name == 'strainphlan' else 16)
            self.assertEqual(settings[name]['machine'], 'mem3_ssd2_v3_x16')
            self.assertIn(':ro', settings[name]['options'])
            self.assertNotIn('DX_SECURITY_CONTEXT', settings[name]['options'])
            scratch, result = self.run_stage(settings[name], name)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            if name == 'strainphlan':
                self.assertTrue((scratch / '.reference-cache/Databases/metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default' / (index + '.pkl')).exists())
            else:
                self.assertTrue((scratch / '.reference-cache/Databases/baqlava/nuc.tsv').exists())
                self.assertTrue((scratch / '.reference-cache/Databases/humann/chocophlan-v4-201901/chocophlan/SGB.fna.gz').exists())
        sources = [json.loads(line)[2] for line in (self.base / 'calls.jsonl').read_text().splitlines()]
        self.assertEqual(len(sources), 3)
        self.assertEqual(sum(s.endswith('/viral.tar.gz') for s in sources), 1)


if __name__ == '__main__':
    unittest.main()
