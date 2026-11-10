#!/usr/bin/env python3
"""Render the README overview with nf-metro; --check detects stale SVGs."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DIAGRAMS = ROOT / 'docs/diagrams'
SOURCE = DIAGRAMS / 'biobakery.metro.mmd'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='compare without updating files')
    args = parser.parse_args()
    command = [sys.executable, '-m', 'nf_metro']
    subprocess.run(command + ['validate', str(SOURCE)], check=True)
    stale = []
    with tempfile.TemporaryDirectory(prefix='biobakery-metro-') as tmp:
        for mode in ['light', 'dark']:
            name = f'biobakery-metro-{mode}.svg'
            output = Path(tmp) / name
            subprocess.run(command + [
                'render', str(SOURCE), '--theme', f'nfcore-{mode}',
                '--no-chrome-css', '--strict', '-o', str(output),
            ], check=True)
            svg = output.read_text()
            # Give the standalone SVG an accessible name as well as the README alt text.
            start = svg.index('>', svg.index('<svg')) + 1
            svg = svg[:start] + (
                '\n<title>bioBakery Nextflow workflow overview</title>'
                '\n<desc>Routes from DNA or RNA reads through quality control, '
                'taxonomic and functional profiling, optional strain and viral '
                'analysis, paired RNA/DNA normalization, MAG assembly and reports.</desc>'
            ) + svg[start:]
            target = DIAGRAMS / name
            if args.check:
                if not target.exists() or target.read_text() != svg:
                    stale.append(str(target.relative_to(ROOT)))
            else:
                target.write_text(svg)
    if stale:
        sys.exit('Out of date: ' + ', '.join(stale) + '. Run python3 bin/render_metro.py.')
    print('README metro maps are current.' if args.check else 'Updated README metro maps.')


if __name__ == '__main__':
    main()
