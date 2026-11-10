# README metro map

The main README embeds light and dark SVGs rendered with
[nf-metro](https://github.com/seqeralabs/nf-metro). Edit
[`biobakery.metro.mmd`](biobakery.metro.mmd) to change the overview, then regenerate
both themes from the repository root:

```bash
python3 -m venv /tmp/biobakery-metro
/tmp/biobakery-metro/bin/python -m pip install -r docs/diagrams/requirements.txt
/tmp/biobakery-metro/bin/python bin/render_metro.py
/tmp/biobakery-metro/bin/python bin/render_metro.py --check
```

Python 3.11 or newer is required. Rendering validates the source and runs
nf-metro's strict geometry checks. The pinned renderer produces static SVGs
without scripts or external assets; GitHub selects the theme through `<picture>`.

This is a curated overview of supported analysis routes, with related operations
grouped into stations. It shows optional strain/viral branches and marks statistics
as opt-in with metadata. `mgx_mtx` profiles both assays before calculating RNA/DNA
ratios; `vis` and `stats` can also consume existing bioBakery output independently.
Assembly groups Bowtie2/MetaBAT2 as alignment/binning and CheckM2/PhyloPhlAn as
quality/placement. The `16s` stub is omitted.

The process-level Mermaid DAGs and architecture map in this folder are generated
separately by `python3 bin/make_diagrams.py`; see the
[workflow reference](../workflow_reference.md). When workflow behavior changes,
update the overview as needed and regenerate its SVGs rather than editing them.
