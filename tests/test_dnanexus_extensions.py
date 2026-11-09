"""Exercise strain/viral routing and real command scripts with mocked tools."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nextflow'), 'Nextflow is required')
class DnanexusExtensionsTest(unittest.TestCase):
    def run_pipeline(self, samples=4, overrides=None, marker_format='json', empty=False, fail_tree=False,
                     legacy_cli=False, depletion_config=None, utility_config=None):
        temp = tempfile.TemporaryDirectory(prefix='dnanexus-extensions-')
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        (base / 'bin').mkdir()
        databases = []
        for index in ['alpha', 'beta']:
            folder = base / 'Databases' / index
            folder.mkdir(parents=True)
            (folder / (index + '.pkl')).write_text(index)
            (folder / (index + '.1.bt2l')).write_text('index')
            databases.append(dict(metaphlan_db=str(folder), metaphlan_index=index,
                metaphlan_version='metaphlan_4.0.6_fixed' if legacy_cli else 'metaphlan_v4'))
        for folder in ['viral_nuc', 'viral_prot', 'depletion', 'depletion_protein', 'full_mapping']:
            (base / 'Databases' / folder).mkdir()
        for filename in ['nuc.tsv', 'prot.tsv']:
            (base / 'Databases' / filename).write_text('mapping')
        (base / 'reads.fastq').write_text('@r\nACGT\n+\nIIII\n')
        mock = base / 'bin/mock-tool'
        mock.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args=sys.argv[1:]; tool=Path(sys.argv[0]).name
with open(os.environ['MOCK_CALLS'], 'a') as stream:
 stream.write(json.dumps(dict(tool=tool,args=args,work=str(Path.cwd())))+'\\n')
def opt(name): return args[args.index(name)+1]
def write(name, text):
 p=Path(name); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
if tool=='metaphlan':
 index=opt('-x'); write(opt('-o'), index); write(opt('--mapout'), 'map'); write(opt('--samout'), index)
 assert opt('--nproc')=='1'
elif tool=='merge_metaphlan_tables.py':
 print('\\n'.join(Path(p).read_text() for p in args))
elif tool=='sample2markers.py':
 sam=Path(opt('-i')); database=Path(opt('-d'))
 assert opt('-f')=='sam' and opt('-n')=='1'
 assert database.read_text()==sam.read_text()
 suffix='.pkl' if os.environ['MARKER_FORMAT']=='pkl' else '.json.bz2'
 write(str(Path(opt('-o'))/(sam.stem+suffix)),sam.read_text())
elif tool=='strainphlan':
 assert '--nprocesses' not in args and '--output-dir' not in args and '-t' not in args
 threshold='--marker_in_n_samples' if os.environ['LEGACY_CLI']=='1' else '--marker_in_n_samples_perc'
 assert opt('--nprocs')=='1' and opt(threshold)=='50'
 assert '--non_interactive' in args
 index=Path(opt('--database')).read_text()
 files=args[args.index('--samples')+1:args.index('--database')]
 assert len(files)==4,files
 assert all(Path(p).read_text()==index for p in files),files
 assert all(Path(p).name.startswith('sample_') for p in files)
 folder=Path(opt('--output_dir'))
 if '--print_clades_only' in args:
  rows='' if os.environ.get('EMPTY_CLADES')=='1' else 't__SGB123\\t4\\tall\\nt__SGB456\\t4\\tall\\n'
  write(str(folder/'print_clades_only.tsv'),'Clade\\tNumber_of_samples\\tSamples\\n'+rows)
 else:
  if os.environ.get('FAIL_TREE')=='1': sys.exit(23)
  assert opt('--clade') in ['t__SGB123','t__SGB456']
  write(str(folder/(opt('--clade')+'.tre')),index)
elif tool=='humann_config':
 assert args==['--print']
 print('HUMAnN Configuration ( Section : Name = Value )')
 print('database_folders : nucleotide = '+os.environ['DEPLETION_DB']+'/')
 print('database_folders : protein = '+os.environ['DEPLETION_PROTEIN_DB'])
 print('database_folders : utility_mapping = '+os.environ['UTILITY_DB'])
elif tool=='baqlava':
 assert '--database' not in args
 assert opt('--threads')=='1' and opt('--local-jobs')=='1'
 for flag in ['--nucdb','--protdb']: assert Path(opt(flag)).is_dir()
 for flag in ['--nucindex','--protindex']: assert Path(opt(flag)).is_file()
 write(opt('-o')+'/result.tsv',Path(opt('--taxonomic-profile')).read_text())
elif tool=='mountpoint': sys.exit(0)
else: raise RuntimeError(tool)
''')
        mock.chmod(0o755)
        for name in ['metaphlan', 'merge_metaphlan_tables.py', 'sample2markers.py',
                     'strainphlan', 'baqlava', 'humann_config', 'mountpoint']:
            (base / 'bin' / name).symlink_to(mock)
        script = '\n'.join([
            f"include {{ TAXONOMIC_PROFILING }} from '{ROOT}/subworkflows/taxonomic_profiling.nf'",
            f"include {{ STRAIN_PROFILING }} from '{ROOT}/subworkflows/strain_profiling.nf'",
            f"include {{ VIRAL_PROFILING }} from '{ROOT}/subworkflows/viral_profiling.nf'",
            'workflow {',
            'reads=Channel.of(' + ','.join(f"tuple([id:'sample_{i}'],file('{base}/reads.fastq'))" for i in range(samples)) + ')',
            "TAXONOMIC_PROFILING(reads,'')",
            'if (params.run_strain_profiling) STRAIN_PROFILING(TAXONOMIC_PROFILING.out.markers)',
            'if (params.run_viral_profiling) VIRAL_PROFILING(reads,TAXONOMIC_PROFILING.out.profile)',
            '}'])
        (base / 'main.nf').write_text(script)
        (base / 'test.config').write_text(
            f"includeConfig '{ROOT}/nextflow.config'\n"
            'process.cpus=1\nprocess.memory="1.GB"\n'
            "process { withName: 'metaphlan|strainphlan|baqlava' { cpus=1; memory='1.GB' } }\n"
            'timeline.enabled=false\nreport.enabled=false\ntrace.enabled=false\ndag.enabled=false\n')
        params = dict(outdir=str(base / 'out'), metaphlan_databases=databases,
                      metaphlan_downstream_indices=['alpha','beta'],
                      run_strain_profiling=True, run_viral_profiling=True,
                      dnanexus_baqlava_container='example.invalid/baqlava:test',
                      dnanexus_reference_mode='fuse', dnanexus_reference_diagnostics=False,
                      dnanexus_reference_mountpoint=str(base / 'mount'),
                      baqlava_db_nucleotide=str(base / 'Databases/viral_nuc'),
                      baqlava_db_protein=str(base / 'Databases/viral_prot'),
                      baqlava_nucleotide_mapping=str(base / 'Databases/nuc.tsv'),
                      baqlava_protein_mapping=str(base / 'Databases/prot.tsv'),
                      baqlava_depletion_db=str(base / 'Databases/depletion'),
                      baqlava_depletion_protein_db=str(base / 'Databases/depletion_protein'),
                      baqlava_depletion_mapping_db=str(base / 'Databases/full_mapping'))
        params.update(overrides or {})
        (base / 'params.json').write_text(json.dumps(params))
        env=dict(os.environ, PATH=str(base / 'bin')+os.pathsep+os.environ['PATH'],
                 NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1',
                 NXF_OPTS=os.environ.get('NXF_OPTS','')+' -XX:-UsePerfData',
                 MOCK_CALLS=str(base / 'calls.jsonl'),MARKER_FORMAT=marker_format,
                 LEGACY_CLI='1' if legacy_cli else '0',
                 EMPTY_CLADES='1' if empty else '0',FAIL_TREE='1' if fail_tree else '0',
                 DEPLETION_DB=depletion_config or params['baqlava_depletion_db'],
                 DEPLETION_PROTEIN_DB=params['baqlava_depletion_protein_db'],
                 UTILITY_DB=utility_config or params['baqlava_depletion_mapping_db'])
        result=subprocess.run(['nextflow','-C',str(base/'test.config'),'run',str(base/'main.nf'),
            '-profile','dnanexus_dxfuse_full','-params-file',str(base/'params.json'),
            '-without-docker','-ansi-log','false'],cwd=base,env=env,capture_output=True,text=True,timeout=120)
        return base,result

    def calls(self,base):
        return [json.loads(line) for line in (base/'calls.jsonl').read_text().splitlines()]

    def test_full_profile_keeps_database_identity_and_reuses_metaphlan_allocation(self):
        base,result=self.run_pipeline()
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        calls=self.calls(base)
        for index in ['alpha','beta']:
            root=base/'out/databases'/index
            self.assertEqual(len(list((root/'strainphlan/markers').glob('*.json.bz2'))),4)
            for clade in ['t__SGB123','t__SGB456']:
                self.assertEqual((root/f'strainphlan/all/output/{clade}/{clade}.tre').read_text(),index)
            self.assertEqual((root/'baqlava/sample_0_baqlava/result.tsv').read_text(),index)
        for extraction in [c for c in calls if c['tool']=='sample2markers.py']:
            self.assertTrue(any(c['tool']=='metaphlan' and c['work']==extraction['work'] for c in calls))
        self.assertEqual(sum(c['tool']=='strainphlan' and '--print_clades_only' in c['args'] for c in calls),2)
        for tree in [c for c in calls if c['tool']=='strainphlan' and '--clade' in c['args']]:
            self.assertTrue(any(c['tool']=='strainphlan' and '--print_clades_only' in c['args'] and c['work']==tree['work'] for c in calls))

    def test_selection_explicit_clades_and_legacy_marker_format(self):
        base,result=self.run_pipeline(overrides=dict(metaphlan_downstream_indices=['beta'],
            strainphlan_clades='t__SGB123,t__SGB456',run_viral_profiling=False),marker_format='pkl')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertFalse((base/'out/databases/alpha').exists())
        self.assertEqual(len(list((base/'out/databases/beta/strainphlan/markers').glob('*.pkl'))),4)
        calls=[c for c in self.calls(base) if c['tool']=='strainphlan']
        self.assertEqual(len(calls),2)
        self.assertTrue(all('--print_clades_only' not in c['args'] for c in calls))
        for clade in ['t__SGB123','t__SGB456']:
            self.assertTrue((base/f'out/databases/beta/strainphlan/{clade}/output/{clade}.tre').exists())

    def test_small_cohort_and_empty_discovery_finish_without_fake_trees(self):
        for samples,empty in [(3,False),(4,True)]:
            with self.subTest(samples=samples):
                base,result=self.run_pipeline(samples=samples,empty=empty,
                    overrides=dict(run_viral_profiling=False,metaphlan_downstream_indices=['alpha']))
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertFalse(list((base/'out').rglob('*.tre')))
                self.assertEqual(len(list((base/'out/databases/alpha/strainphlan/markers').glob('*'))),samples)
                if samples==3:
                    self.assertIn('at least four',result.stdout+result.stderr)
                    self.assertFalse(any(c['tool']=='strainphlan' for c in self.calls(base)))
                else:
                    self.assertTrue((base/'out/databases/alpha/strainphlan/all/output/print_clades_only.tsv').exists())

    def test_tree_failure_is_not_hidden(self):
        _,result=self.run_pipeline(fail_tree=True,
            overrides=dict(run_viral_profiling=False,metaphlan_downstream_indices=['alpha']))
        self.assertNotEqual(result.returncode,0)
        self.assertIn('23',result.stdout+result.stderr)

    def test_legacy_cli_and_host_reference_staging(self):
        base,result=self.run_pipeline(legacy_cli=True,marker_format='pkl',overrides=dict(
            run_viral_profiling=False,metaphlan_downstream_indices=['alpha'],
            strainphlan_clades='t__SGB123',strainphlan_db_location='host'))
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue((base/'out/databases/alpha/strainphlan/t__SGB123/output/t__SGB123.tre').exists())

    def test_missing_baqlava_image_fails_before_tools_run(self):
        base,result=self.run_pipeline(overrides=dict(dnanexus_baqlava_container=None))
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Set dnanexus_baqlava_container',result.stdout+result.stderr)
        self.assertFalse((base/'calls.jsonl').exists())

    def test_baqlava_rejects_mismatched_depletion_configuration(self):
        base,result=self.run_pipeline(depletion_config='/wrong/nucleotide/reference',
            overrides=dict(run_strain_profiling=False,metaphlan_downstream_indices=['alpha']))
        self.assertNotEqual(result.returncode,0)
        self.assertIn('78',result.stdout+result.stderr)
        self.assertFalse(any(c['tool']=='baqlava' for c in self.calls(base)))

    def test_baqlava_rejects_demo_utility_configuration_before_analysis(self):
        base,result=self.run_pipeline(utility_config='/mounted/full/data/utility_DEMO/',
            overrides=dict(run_strain_profiling=False,metaphlan_downstream_indices=['alpha']))
        self.assertNotEqual(result.returncode,0)
        self.assertIn('still configures HUMAnN utility_DEMO',result.stdout+result.stderr)
        self.assertFalse(any(c['tool']=='baqlava' for c in self.calls(base)))


if __name__=='__main__':
    unittest.main()
