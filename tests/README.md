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

### MetaPhlAn database routing

`python3 -m unittest discover -s tests -p test_metaphlan_databases.py` runs local
Nextflow integration tests with mocked bioBakery executables. It checks multiple
databases, downstream selection and isolation, legacy settings, and validation.
It requires Java, Nextflow, bzip2 and zip, without reference databases or a cluster.

### Site configuration

`python3 bin/check_profile_resources.py` resolves every declared profile and
checks that its base CPU, memory and time directives survive profile merging.
`python3 -m unittest discover -s tests -p test_site_configs.py` loads each site's
example YAML through Nextflow, checks profile reference/version defaults and
CLI precedence, and requires no tools, databases, containers or scheduler.

### Hopper and DNAnexus configuration

`python3 -m unittest discover -s tests -p test_wellesley_hopper.py` resolves
Hopper's Docker image assignments, resources, reference modes and example YAML
using native Nextflow probe tasks. It needs no Docker daemon or databases and
checks that DNAnexus download settings are absent from the local profile.
It also verifies the three full HUMAnN bind targets used by BAQLaVa.

`python3 -m unittest discover -s tests -p test_dnanexus_extensions.py` exercises
MetaPhlAn-to-StrainPhlAn and BAQLaVa routing with mocked tools. It checks
per-database isolation, marker extraction in the MetaPhlAn allocation, JSON and
Pickle naming, current and legacy threshold flags, host reference staging,
automatic clade discovery in the phylogeny allocation, explicit clades, small
cohorts, empty discovery, real error propagation and BAQLaVa's separate reference
arguments and rejection of demo utility configurations. These are local
Nextflow executions without Docker or cloud jobs.

`python3 -m unittest discover -s tests -p test_dnanexus_config.py` resolves the
DNAnexus selectors against every process name using native Groovy probe tasks.
It checks instance/resource compatibility, tool image routing and overrides,
and the KneadData-to-HUMAnN YAML selections. It also checks that cache discovery
finds exactly the three configured tool images and runs both read layouts with
mocked tools. It checks the default primary reference, the optional two-reference
YAML, profiling of cleaned reads, merged profiles and compressed SAM outputs,
HUMAnN 4 output renaming, selected-profile routing, EC/KO/Pfam regrouping and
renaming, relative abundance and merged matrices, and explicit QC/taxonomy-only
overrides. It verifies that profiling/compression and per-sample HUMAnN table
work share tasks, all cohort merges share a task, and tool threads follow task
CPU overrides. It needs Java and Nextflow, without
Docker, reference databases or a DNAnexus connection.

`python3 -m unittest discover -s tests -p test_dnanexus_download_config.py` checks
the project-reference download profile: transfers are limited to analysis tasks,
resources and Micromamba activation are preserved, project/folder overrides are
quoted, and helpers skip reference staging. It verifies the QC-only smoke YAML,
four-image cache discovery, selected MetaPhlAn/HUMAnN/BAQLaVa references, custom
mapping-file downloads and transfer deduplication. Generated Docker commands use
read-only local binds without FUSE privileges or forwarded credentials.
Mocked SDK checks exercise worker scratch staging, transfer failure before
analysis and missing-database diagnostics. A real Nextflow Bash wrapper verifies
the scratch/beforeScript ordering. These tests require no cloud connection,
Docker daemon or reference databases. Other profiles are checked for absence of
these download hooks.

`python3 -m unittest discover -s tests -p test_dnanexus_archives.py` exercises
archive staging with real tar extraction and a mocked worker SDK. It verifies
the MetaPhlAn and HUMAnN extraction roots, one download per required bundle,
uncovered mapping-file downloads, compressed-file cleanup, timing logs, plain
tar and gzip input, and failure before analysis for bad transfers, corrupt
archives, wrong layouts and parent-directory traversal. A real Nextflow process
with scratch enabled verifies archive staging before task execution. No project
connection, large reference data or Docker daemon is required.
It also verifies that strain workers select the MetaPhlAn image and archive,
while BAQLaVa uses its own image and stages only viral/depletion bundles, with
no extra copies for files already covered by an archive.

`python3 -m unittest discover -s tests -p test_dnanexus_build.py` checks the local
build wrapper with a mocked `dx` command: runtime files are staged, inputs are
not preset, global image bundling is omitted, and the head instance is set
independently. It also checks refresh upload/import/wait/archive/build ordering,
separate importer resources, argument validation, and stopping on refresh
failures. Mocked SDK checks verify that only superseded matching cache files
are archived after success. When dx-toolkit is installed it also checks that the generated
source-only applet specification keeps runtime assets without Docker bundles.
These checks do not upload files, create applets or run jobs.
The build wrapper also rejects a syntax error at the end of the file before
uploading source or starting the cache importer.
