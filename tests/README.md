# Tests

Everything test-related lives here. Before v0.0.4 it was split between `test/`
(the suite that works, plus the read fixtures) and `tests/` (an nf-test suite
that did not: it asserted a four-process pipeline and loaded params files that
were not in the repo). The nf-test cases are gone and the rest is merged.

```
tests/
├── run_tests.sh              the integration suite — 16 cases, 39 checks
├── submit_tests.sh           run it as a SLURM job
├── data/
│   ├── rawfastq/             two paired-end samples, sub-sampled ECHO reads
│   ├── single_end_rawfastq/  one single-end file, plus the bioBakery tutorial demo sample
│   └── tutorial_output/      reference output from the upstream tutorial run
├── results/                  created by a run — logs, outputs, .status files (gitignored)
└── work/                     created by a run — one Nextflow work dir per case (gitignored)
```

## The integration suite

```bash
cd /path/to/biobakery-nextflow
bash tests/run_tests.sh                      # on a login node, submits SLURM jobs
mkdir -p tests/results && sbatch tests/submit_tests.sh   # or as one batch job
```

It covers every workflow except 16s, in both library layouts:

| Workflow | single-end | paired-end |
|---|---|---|
| `mgx` | QC + taxonomic + functional, chained vis | the same, plus a `--run_qc false` run through `merge_pairs` |
| `mtx` | QC against three databases + taxonomic | the same |
| `mgx_mtx` | both halves, unmapped | both halves, mapped, plus the RNA/DNA ratio |
| `assembly` | full MAG/SGB | full MAG/SGB |
| `vis`, `stats` | folder input — no layout of their own | |

plus the version log and the two input guards. The read-based cases are
independent, so their Nextflow drivers run in parallel, each from its own launch
directory with its own work directory; the checks run once they have all
finished. Every case writes `tests/results/<name>.log` and a `.status` file, so
a failure can be read after the fact.

It needs the hutlab module environment, Java 21, and a FASRC account that can
submit to the `hsph` partition — `-profile harvard_rc`. There is no offline
mode: these tests run the real tools against the real databases.

### Two fixtures live outside the repo

Both are regenerated rather than committed, because they are too big to archive
and cheap to rebuild:

```bash
python  ~/biobakery_vis_stats_test/make_fixture.py --output input     # vis and stats
python3 ~/biobakery_assembly_test/make_fixture.py --output input_pe   # assembly, add --single for input_se
```

Point the suite elsewhere with `VIS_STATS_FIXTURE` and `ASSEMBLY_FIXTURE`. The
cases that need them are skipped with a message if they are absent, so the rest
of the suite still runs.

The assembly fixture is simulated from two real genomes on purpose: the bundled
reads are so host-dominated that KneadData leaves about a thousand reads per
sample, MEGAHIT assembles no contigs, and no MAG is ever produced. Cases 9 and
10 use the bundled reads to check that every stage runs and that the no-MAG path
is carried through to a final profile; cases 13 and 14 use the fixture to check
binning, CheckM2, PhyloPhlAn and SGB clustering on MAGs that exist.

### What the small fixtures can and cannot show

`tests/data/` holds two paired-end samples and two single-end files of a few
thousand reads. That is enough to exercise wiring — which processes run, what
they publish, whether channels join correctly — and not enough to produce a
report with content. A chained vis run on two samples legitimately fails: there
is no ordination of two points and no heatmap of a handful of features. That
failure is ignored by design (`conf/base.config`, `withName '.*:REPORTING:.*'`),
so the suite asserts the folder the report is *built from*, not the report. A
report worth reading needs a real study.

`tests/data/tutorial_output/` is reference output from the upstream bioBakery
tutorial, kept for comparison. It is not usable as a vis input: it is a single
sample, and vis needs a study. See `docs/vis_stats_port_status.md`.

## What CI checks

CI cannot run any of the above — no tools, no databases, no cluster. It runs
what needs none of them:

```bash
bin/make_diagrams.py --check
```

which rebuilds every workflow's DAG with `nextflow run -preview` and fails if
`docs/workflow_reference.md` or `docs/diagrams/*.mmd` no longer match the
pipeline. That catches a config that does not parse, a broken `include`, a
channel wired to nothing, and documentation that has drifted from the code —
which is most of what changes between real test runs.
