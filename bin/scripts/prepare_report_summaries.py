#!/usr/bin/env python3
"""Build report-only tables from a completed profiling folder."""
import argparse
import csv
from pathlib import Path
import shutil
import subprocess
import sys

SCRIPTS = Path(__file__).resolve().parent


def helper(name, source, target, *args):
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(SCRIPTS / name), '--input', str(source),
                    '--output', str(target), *args], check=True)


def prepare(source, target, version):
    # Copy tables and logs only: reports do not need reads, alignments or databases.
    for path in source.rglob('*'):
        if path.is_file() and path.suffix in {'.tsv', '.txt', '.log', '.json'}:
            dest = target / path.relative_to(source)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, dest)
    taxonomy = target / 'metaphlan/merged/metaphlan_taxonomic_profiles.tsv'
    if not taxonomy.exists():
        candidates = list(target.glob('metaphlan/**/merged_metaphlan_profiles.tsv'))
        if len(candidates) > 1:
            raise ValueError('Choose a single MetaPhlAn database folder for stats/viz')
        if candidates:
            taxonomy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(candidates[0], taxonomy)
    if taxonomy.exists():
        helper('count_features.py', taxonomy, taxonomy.with_name('metaphlan_species_counts_table.tsv'),
               '--include', 's__', '--filter', 't__', '--reduce-sample-name')

    merged = target / 'humann/merged'
    for path in list(target.glob(f'humann/**/merged_*_{version}.tsv')):
        merged.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, merged / (path.name.removeprefix('merged_').removesuffix(f'_{version}.tsv') + '.tsv'))
    counts = target / 'humann/counts'
    collected = {}
    for table in sorted(merged.glob('*_relab.tsv')):
        feature = table.name.removesuffix('_relab.tsv')
        if table.exists():
            out = counts / f'humann_{feature}_relab_counts.tsv'
            helper('count_features.py', table, out, '--reduce-sample-name',
                   '--ignore-un-features', '--ignore-stratification')
            with out.open() as handle:
                rows = list(csv.reader(handle, delimiter='\t'))
            collected[feature] = dict(rows[1:])
    if collected:
        with (counts / 'humann_feature_counts.tsv').open('w') as handle:
            writer = csv.writer(handle, delimiter='\t', lineterminator='\n')
            samples = sorted(set().union(*(values.keys() for values in collected.values())))
            writer.writerow(['# samples', *(f'humann_{f}_relab_counts' for f in collected)])
            for sample in samples:
                writer.writerow([sample, *(values.get(sample, '0') for values in collected.values())])
    if any((target / 'humann').rglob('*.log')):
        helper('get_counts_from_humann_logs.py', target / 'humann',
               counts / 'humann_read_and_species_count_table.tsv')
    qc = list(target.glob('kneaddata/**/kneaddata_read_count_table.tsv'))
    if qc:
        dest = target / 'kneaddata/merged/kneaddata_read_count_table.tsv'
        if qc[0] != dest:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(qc[0], dest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--humann-version', required=True)
    args = parser.parse_args()
    prepare(args.input, args.output, args.humann_version)
