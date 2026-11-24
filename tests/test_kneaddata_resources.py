"""Run both real QC modules with CPU overrides and mocked executables."""
import gzip
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nextflow'), 'Nextflow is required')
class KneaddataResourcesTest(unittest.TestCase):
    def test_both_layouts_use_task_threads_and_one_internal_process(self):
        for cpus in [1, 2]:
            with self.subTest(cpus=cpus), tempfile.TemporaryDirectory(prefix='kneaddata-cpus-') as temporary:
                base = Path(temporary)
                (base / 'bin').mkdir()
                for name in ['ref_a', 'ref_b']:
                    (base / name).mkdir()
                for name in ['single', 'mate1', 'mate2']:
                    (base / (name + '.fastq')).write_text('@read\nACGT\n+\nIIII\n')
                tool = base / 'bin/mock-tool'
                tool.write_text('''#!/usr/bin/env python3
import gzip, json, os, sys
from pathlib import Path
args = sys.argv[1:]
if '--version' in args:
    print('mock version 0.12.1');sys.exit(0)
def opt(flag): return args[args.index(flag) + 1]
expected = int(os.environ['EXPECTED_CPUS'])
if Path(sys.argv[0]).name == 'kneaddata':
    assert args.count('--threads') == 1 and int(opt('--threads')) == expected, args
    assert args.count('--processes') == 1 and opt('--processes') == '1', args
    refs = [args[i + 1] for i, value in enumerate(args) if value == '--reference-db']
    assert len(refs) == 2 and all(Path(ref).is_dir() for ref in refs), args
    if '--unpaired' in args:
        assert Path(opt('--unpaired')).is_file()
        suffixes = ['']
    else:
        assert Path(opt('-i1')).is_file() and Path(opt('-i2')).is_file()
        suffixes = ['_paired_1', '_paired_2', '_unmatched_1', '_unmatched_2']
    prefix = opt('--output-prefix')
    for suffix in suffixes:
        Path(prefix + suffix + '.fastq').write_text('@read\\nACGT\\n+\\nIIII\\n')
    Path(prefix + '.log').write_text(json.dumps(dict(threads=expected, processes=1, args=args)))
else:
    assert opt('-p') == str(expected), args
    source = Path(args[-1])
    with gzip.open(str(source) + '.gz', 'wb') as stream:
        stream.write(source.read_bytes())
    source.unlink()
''')
                tool.chmod(0o755)
                for name in ['kneaddata', 'pigz', 'bowtie2']:
                    (base / 'bin' / name).symlink_to(tool)
                (base / 'main.nf').write_text(f'''
if (nextflow.version < '25.04.0') nextflow.preview.topic = true
include {{ single_end_kneaddata; paired_end_kneaddata }} from '{ROOT}/modules/kneaddata/main.nf'
workflow {{
    refs = Channel.value([file('{base}/ref_a'), file('{base}/ref_b')])
    paths = ['{base}/ref_a', '{base}/ref_b']
    single_end_kneaddata(Channel.of(tuple('single', file('{base}/single.fastq'))), refs, paths, '')
    paired_end_kneaddata(Channel.of(tuple('pair', [file('{base}/mate1.fastq'), file('{base}/mate2.fastq')])), refs, paths, '')
}}
''')
                (base / 'test.config').write_text(
                    f"includeConfig '{ROOT}/conf/params.config'\n"
                    f"params.outdir='{base}/out'\n"
                    f"process.cpus={cpus}\nprocess.memory='128.MB'\nprocess.executor='local'\n")
                env = dict(os.environ, PATH=str(base / 'bin') + os.pathsep + os.environ['PATH'],
                           EXPECTED_CPUS=str(cpus), NXF_OFFLINE='true', NXF_SYNTAX_PARSER='v1')
                result = subprocess.run(['nextflow', '-C', str(base / 'test.config'), 'run',
                    str(base / 'main.nf'), '-ansi-log', 'false'], cwd=base, env=env,
                    capture_output=True, text=True, timeout=90)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                logs = sorted((base / 'out/kneaddata').glob('*.log'))
                self.assertEqual(len(logs), 2)
                for log in logs:
                    recorded = json.loads(log.read_text())
                    self.assertEqual((recorded['threads'], recorded['processes']), (cpus, 1))
                paired = list((base / 'work').glob('*/*/pair_concatenated.fastq.gz'))
                self.assertEqual(len(paired), 1)
                with gzip.open(paired[0], 'rt') as stream:
                    self.assertEqual(stream.read().count('@read\n'), 4)
                self.assertTrue((base / 'out/kneaddata/single_kneaddata.fastq.gz').is_file())


if __name__ == '__main__':
    unittest.main()
