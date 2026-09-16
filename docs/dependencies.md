# Dependencies

Where every step's software comes from, and which versions are pinned together
on purpose. The companion to [`docs/workflow_reference.md`](workflow_reference.md),
which says what each step *does*; this page says what it needs to run.

The pipeline itself declares no dependencies: a process runs whatever is on
`PATH` when its task starts. What puts it there is site-specific, so it lives in
the profile — `conf/profiles/<site>.config` — and nowhere else.

## How a process gets its software

| Site | `-profile` | Mechanism |
|---|---|---|
| Harvard FASRC (Cannon) | `harvard_rc` | a `beforeScript` per process group, loading hutlab environment modules |
| Tufts HPC | `tufts_hpc` | tools on `PATH`, or Apptainer where a process declares a `container` |
| This machine | `local` | tools on `PATH` |
| AWS Batch | `amazon` | per-process containers — **incomplete**, six processes only |

Harvard is the only site where the whole pipeline is wired up. There, one Groovy
variable per software stack is defined at the top of the profile and referenced
by the process groups, so a version is changed in one line:

| Stack variable | hutlab module | Provides |
|---|---|---|
| `env_kneaddata` | `rocky8/kneaddata/0.12.0-devel` | `kneaddata`, `kneaddata_read_count_table` |
| `env_metaphlan` | `rocky8/metaphlan4/4.0.6_vOct22_fixed` | `metaphlan`, `merge_metaphlan_tables.py`, `sample2markers.py`, `strainphlan` |
| `env_humann` | `rocky8/humann4/4.0-alpha-1-final` | `humann` and its `humann_*_table` helpers; auto-loads MetaPhlAn |
| `env_baqlava` | `rocky8/baqlava/1.2.0-devel` | `baqlava`; auto-loads HUMAnN 4, anadama2, MetaPhlAn |
| `env_biobakery` | `rocky8/biobakeryworkflows/3.2` | everything below |
| `env_halla` | `rocky8/halla/0.8.20` | `halla` — and nothing else, deliberately |

`rocky8/biobakeryworkflows/3.2` carries three unrelated groups of dependencies,
which is why so many processes load it:

1. **The assembly tools** — MEGAHIT, bowtie2, samtools, MetaBAT2,
   `jgi_summarize_bam_contig_depths`, CheckM2, PhyloPhlAn, Mash, FastANI,
   assembly-stats — plus the `CHECKM2DB` and `PHYLOPHLAN_PATH` variables. Taking
   them all from one module keeps the Nextflow assembly workflow on exactly the
   stack `biobakery_workflows assembly` uses.
2. **Scripts that ship with `biobakery_workflows` rather than with a tool**:
   `count_features.py`, `rna_dna_norm.py`, `get_counts_from_humann_logs.py`,
   `humann_join_tables`.
3. **The vis and stats report steps**, because it pulls in
   `rocky8/anadama2/0.10.0-devel` (pweave, and the `R_LIBS` that holds vegan)
   and `R/4.5.1-fasrc01` on top of `biobakery_workflows`, and HUMAnN for
   `add_ec_names`' `humann_rename_table`.

## Two version pins that are not preferences

**The MetaPhlAn / HUMAnN / BAQLaVa triple.** MetaPhlAn `4.0.6_vOct22_fixed` with
`mpa_vOct22_CHOCOPhlAnSGB_202403` is the only combination HUMAnN 4 and BAQLaVa
1.2.0 can both read. HUMAnN 4 cannot yet use the vJan25 database, and
`metaphlan_4/4.2` is built against python3.12, which conflicts with the
python3.10 stack the rest of the profile loads. Change one and all three have to
move. The database halves of the pin are in `conf/databases/harvard_rc.config`;
the module halves are in the profile.

**HAllA must not be given `biobakeryworkflows/3.2`.** HAllA pins `numpy<2`
(through statsmodels) and checks it with `pkg_resources.require()` before parsing
its arguments. The 3.2 module puts `assembly_depends` — numpy 2.2.6 — ahead of
`depends` on `PYTHONPATH`, because the matplotlib in `depends` is too old for
numpy 2 and the report rendering needs the newer one. Under 3.2, HAllA therefore
aborts immediately with a `pkg_resources.ContextualVersionConflict`.
`rocky8/halla/0.8.20` has its own numpy 1.26.4 and its own `R_LIBS`, and
resolves the rpy2 `libRblas.so` load as well. This is why `halla` is the one
process in the stats workflow with its own `beforeScript`.

## There are two CheckMs, and they do different jobs

This is the easiest thing in the repo to get wrong, so it is worth stating
plainly.

| | CheckM2 | CheckM 1.2.0 |
|---|---|---|
| Where from | `rocky8/biobakeryworkflows/3.2`, on `PATH` as `checkm2` | **vendored** in `bin/scripts/checkm/`, run as `bin/scripts/checkm.py` |
| Used by | `checkm2` (MAG completeness and contamination) | `abundance` (per-sample MAG abundance) |
| Subcommands used | `predict` | `coverage`, `profile` |
| Extra arguments param | `--checkm_predict_options` | `--checkm_coverage_options` |
| Database | `CHECKM2DB`, exported by the module | none — these two subcommands need no reference data |

CheckM2 is a rewrite, not a new version: it dropped the `coverage` and `profile`
subcommands, which is the step the anadama2 assembly workflow uses to turn a
sample's BAM and bins into an abundance table. So quality assessment uses
CheckM2 and abundance uses a trimmed copy of CheckM 1. Both are needed; neither
substitutes for the other.

The vendored copy is a subset — enough for `coverage` and `profile` and nothing
else. It is CheckM 1.2.0, GPLv3; see `bin/scripts/checkm/README.md` and
`bin/scripts/checkm/LICENSE`.

## Other vendored code

| Path | What it is | Why it is here |
|---|---|---|
| `bin/lib/biobakery_document.py` | anadama2's `document.py`, and the plotting library the report templates call | the reports are the original pweave `.pmd` templates, which `import anadama2`; anadama2 itself is not installed |
| `bin/lib/anadama2_fallback/anadama2/` | an import stand-in for `import anadama2` | put first on `sys.path` by `bin/scripts/biobakery_bootstrap.py`, so a template's `import anadama2` resolves without anadama2 |
| `bin/lib/biobakery_log.py` | replaces `LoggerReporter.read_log()` for `workflow_info.pmd` | same reason |
| `bin/scripts/checkm/` | CheckM 1.2.0, `coverage` and `profile` only | see above |

See [`docs/vis_stats_port_status.md`](vis_stats_port_status.md) for why the
document layer was vendored rather than rewritten.

## Running the pipeline itself

Nextflow 24.10.4 and a JDK 11 or newer — 21 is what the module loads. Both come
from the hutlab module:

```bash
source /n/lab_storage/huttenhower_lab/tools/hutlab/src/hutlabrc_rocky8.sh
hutlab load rocky8/biobakery-workflows-nextflow/0.0.4
```

`bin/make_diagrams.py` needs Nextflow and a JVM but no tools and no databases:
it uses `nextflow run -preview`, which builds the graph without launching a
task. That is what CI runs, and it is the only part of this repo that can be
checked without the software above.
