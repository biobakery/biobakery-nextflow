# vis / stats port status — v0.0.4

Working notes for the port of `biobakery_workflows vis` and `stats` (3.2,
AnADAMA2) to Nextflow, on branch `feature/standard-biobakery-workflow`. The tree
is deployed to `lab_storage` as `rocky8/biobakery-workflows-nextflow/0.0.4`; the
commits behind it are not yet pushed to GitHub.

Reference implementation being ported:
`/n/lab_storage/huttenhower_lab/tools/biobakery_workflows/rocky8/v3.2/lib/python3.10/site-packages/biobakery_workflows/`
(`workflows/vis.py`, `workflows/stats.py`, `utilities.py`, `visualizations.py`).

---

## Decisions taken

1. **vis/stats take a folder, not channels.** Same as the AnADAMA workflows: point
   them at a bioBakery output folder and they discover the data files by name and
   by content. One code path for both standalone and chained runs.

2. **vis runs by default at the end of the read-based workflows** (`--run_vis
   false` to skip); **stats is opt-in** (`--run_stats true`). See issue 4 for
   why they differ.

3. **anadama2 is being removed as a dependency**, not just as a workflow engine.
   This is the decision that shapes the rest:
   - The workflow engine was already gone by construction — every
     `workflow.add_task()` became a Nextflow process.
   - `anadama2.document.PweaveDocument` is *also* the plotting library (the
     templates and `visualizations.py` call ~15 methods on it), so it could not
     simply be dropped. It was **vendored** into `bin/lib/biobakery_document.py`.
   - The `.pmd` templates hard-code `from anadama2 import PweaveDocument` on line
     1, so all 18 were **vendored** into `assets/document_templates/` with that
     import swapped.
   - `biobakery_workflows` itself imports anadama2 at module scope
     (`utilities.py:35`, `files.py:30`), so a small stand-in package lives at
     `bin/lib/anadama2_fallback/anadama2/`. It is put *first* on `sys.path`, so
     the real framework is never imported even where it is installed.

4. **Report format defaults to `html`** (`--report_format pdf` still works).
   AnADAMA defaults to pdf; html avoids needing pdflatex at render time.

5. **Full stats parity** — feature tables, mantel, MaAsLin2 (+ figure tiles),
   HAllA, stratified pathway barplots, beta diversity / PERMANOVA, report, archive.

---

6. **The HUMAnN count tables are excluded from the stats feature set.**
   `get_input_files_for_study_type()` sweeps every `.tsv` in the input folder
   that is not the taxonomy or pathway file into `other_data_files`, so
   `humann_feature_counts.tsv` and `humann_read_and_species_count_table.tsv`
   become feature tables and get run through MaAsLin2, HAllA, the mantel test
   and beta diversity. They are per-sample QC summaries, not abundance tables,
   and they are written samples-as-rows while every consumer expects samples as
   columns — MaAsLin2 and `beta_diversity.R` detect the orientation and survive,
   the mantel test and HAllA do not and fail the whole run.

   Upstream already excludes the kneaddata read count table from stats for the
   same reason (`exclude_types`) and simply missed these two, so upstream 3.2
   cannot complete a wmgx stats run on a folder containing them either.
   `biobakery_identify_inputs.exclude_non_abundance_files()` extends the
   exclusion. Stats therefore analyses taxonomy, pathways and ECs.

   Nothing is lost: those tables are exactly what the *vis* report's HUMAnN
   read-count and feature-count sections are built from.

---

7. **Report artifacts are named for this pipeline's vocabulary.** The vis report
   is `mgx_report.html`, not upstream's `wmgx_report.html`, to match the
   pipeline's own workflow names (`mgx | mtx | mgx_mtx | 16s`). Upstream
   *identifiers* are untouched: the `files.ShotGun` type keys
   (`wmgx_taxonomy`, `wmgx_qc_readcounts`, …) and the packaged
   `wmgx_methods.txt` still carry the upstream spelling, because they are that
   API, not our naming.

---

## What exists

### Nextflow

| File | Contents |
|---|---|
| `workflows/vis.nf` | `VIS` — discovery → taxonomy feature table → alpha diversity → EC names → report → archive |
| `workflows/stats.nf` | `STATS` — discovery → feature tables → mantel / MaAsLin2 / HAllA / stratified barplots / beta diversity or PERMANOVA → report → archive |
| `modules/vis/{identify_inputs,alpha_diversity,add_ec_names,report}/main.nf` | |
| `modules/stats/{feature_table,maaslin2,halla,mantel,beta_diversity,covariate_equation,stratified_pathways,report}/main.nf` | |
| `assets/Rscripts/ggplot2_labs_shim.R` | in-memory patch for MaAsLin2's `ggplot2::labs("")`, sourced by the `maaslin2` module |
| `modules/utils/archive/main.nf` | shared zip archive, ports `workflow.add_archive()` |
| `assets/NO_FILE` | placeholder for optional `path` inputs |

### Python (`bin/scripts/`)

| File | Ports |
|---|---|
| `biobakery_bootstrap.py` | puts the vendored layer on `sys.path` **and** `PYTHONPATH` (pweave runs in a subprocess) |
| `biobakery_identify_inputs.py` | discovery from `vis.py` 76-131 / `stats.py` 85-103 → JSON manifest |
| `biobakery_vis_report.py` | document stage of `vis.py` 94-202 |
| `biobakery_stats_report.py` | document stage of `stats.py` 166-202 |
| `stats_stratified_metadata.py` | metadata prep + `create_merged_data_file()`, emits the barplot plan |
| `stats_humann_barplot.py` | `run_humann_barplot()` (utilities 900-936) |
| `stats_covariate_equation.py` | equation builder from `run_beta_diversity()` (utilities 406-421) |
| `maaslin_image_tiles.py` | `get_maaslin_image_files()` + `generate_tiles_of_maaslin_figures()` |
| `transpose_table.py` | the `transpose()` closure in `run_halla_on_input_file_set()` |

### Vendored (`bin/lib/`)

- `biobakery_document.py` — anadama2 `document.py` (1543 lines) with its only two
  internal imports replaced; `LICENSE-anadama2` alongside it (MIT).
- `biobakery_log.py` — replaces `LoggerReporter.read_log()` for `workflow_info.pmd`.
- `anadama2_fallback/anadama2/` — the stand-in package.

### Vendored (`assets/Rscripts/`)

R scripts are **not** vendored wholesale — most run unmodified and should keep
tracking upstream. Only a patched script lives here, and it shadows the package
copy of the same name via `biobakery_bootstrap.get_rscript()`, which otherwise
falls through to `utilities.get_package_file(name, "Rscript")`. Every module
that runs an R script now goes through that resolver, so patching a second one
later means dropping a file in, not editing a module.

- `alpha_diversity.R` — one line: dropped a no-op `labs("")`. ggplot2 4.x builds
  labels as an S7 object that rejects unnamed labels, so upstream aborts on the
  first continuous metadata variable.
- `beta_diversity.R` — the univariate branch's `adonis()` ported to `adonis2()`,
  which is not a rename: `adonis()` returned a list with the anova table under
  `$aov.tab`, `adonis2()` *is* the table. `adonis` is defunct in vegan 2.7.2.
- `mantel_test.R` — each input table's orientation is now checked against the
  metadata before transposing, the way upstream's own `beta_diversity.R`
  already does. Upstream transposes unconditionally, which empties the distance
  matrix for the samples-as-rows count tables.

---

## Test fixture

The netscratch data this port was previously driven by has been deleted. The
replacement lives outside the repo, under `~/biobakery_vis_stats_test/`:

| File | What it is |
|---|---|
| `make_fixture.py` | seeded generator; writes a bioBakery-standard folder — 16 samples, 23 species, 20 pathways (stratified), 15 ECs, QC and HUMAnN count tables, metadata with 2 categorical + 2 continuous variables, an AnADAMA-format log |
| `env.sh` | the full hand-run environment (see the recipe at the bottom of this file) |
| `input/` | the generated fixture |
| `nf_vis/`, `nf_stats/` | Nextflow run directories |

Half the samples carry a case effect on a few species and pathways, so MaAsLin2,
PERMANOVA and the mantel test have real signal rather than noise. Regenerate
with `python make_fixture.py --output input`.

`tests/data/tutorial_output` in the repo is **not** usable for vis: it is a single
sample and 29 clades, so `document.read_table()` finds no sample set.

## Verified under -profile harvard_rc

`bash tests/run_tests.sh` (submitted with `sbatch tests/submit_tests.sh`) runs
`VIS` and `STATS` against the generated fixture on SLURM as tests 11 and 12.
Both complete and publish their full output set --
`vis/{mgx_report.html,figures,data,alpha_diversity_plots}` + `vis.zip`, and
`stats/{stats_report.html,features,beta_diversity,mantel_test,maaslin2_*,
halla_*,stratified_pathways,data}` + `stats.zip`.

## Verified so far

Everything below was re-verified on a clean run (no `-resume`, work directories
deleted) against the current working tree.

- All Python helpers compile; all four `assets/Rscripts/*.R` parse.
- `biobakery_workflows` imports with **no real anadama2 present**; `import anadama2`
  resolves to the stand-in.
- `nextflow config` parses; both DAGs build under `-preview`.
- Input discovery finds all six file roles for vis and for stats.
- **The vis report renders end to end**, by hand and through Nextflow: all 45
  chunks, 0 chunk errors, every report section present (QC, taxonomy,
  ordination, heatmaps, barplots, pathways/ECs, features, software versions,
  tasks run).
- **The whole `VIS` Nextflow workflow completes**: `identify_inputs` →
  `feature_table` → `alpha_diversity` → `add_ec_names` → `vis_report` →
  `archive_output`, publishing `outdir/vis/{mgx_report.html,figures,data,
  alpha_diversity_plots}` and `outdir/vis.zip` — and nothing else, in
  particular no `outdir/stats/`.
- **The vis report is correct, not merely rendered**: 74 figures, every one of
  them a relative link that resolves on disk, no error or traceback text.
  Some figure names contain spaces and are percent-encoded in the HTML; that is
  correct and resolves in a browser.
- Published report links are relative, so the folder relocates as a unit.

- **The whole `STATS` Nextflow workflow completes**: `identify_inputs` →
  `feature_table` (3) → `mantel_test` → `maaslin2` (3) →
  `halla_transpose_metadata` → `halla` (3) → `stratified_metadata` →
  `stratified_barplot` (6) → `covariate_equation` → `beta_diversity` (9) →
  `stats_report` → `archive_output`, publishing
  `outdir/stats/{stats_report.html,features,beta_diversity,mantel_test,
  maaslin2_*,halla_*,stratified_pathways,data}` and `outdir/stats.zip`.
  Requires the HAllA environment override — see issue 2.
- **The stats report is correct, not merely rendered**: 16 figures, every one
  of them relative and resolving on disk, no error or traceback text, and every
  section present (mantel, MaAsLin2 heatmap + tiles, HAllA, stratified
  pathways, beta diversity across all three feature types and all three
  analyses).
- `halla_pathways` and `halla_ec` legitimately produce no `hallagram.png` —
  HAllA only draws one when there are associations to plot, which is why the
  module marks it optional output and the report shows only `halla_taxonomy`.

## Not yet verified

- No parity diff against `biobakery_workflows vis|stats` output yet. The 3.2
  reference output that existed on netscratch was deleted, so this needs an
  upstream run to be redone first. Note that an upstream 3.2 stats run cannot
  currently complete on a standard wmgx folder (see decision 6 and issues 1–2),
  so the comparison will have to be section by section rather than a diff.
- Chained mode (vis/stats at the end of mgx) is **not wired up**.
- `--report_format pdf` has not been exercised since the link changes.

---

## Open issues, in priority order

### ~~1. `beta_diversity.R` uses `adonis`, defunct in vegan 2.7.2~~ — fixed
Vendored and ported to `adonis2(..., by="terms")`, reading row 1 of the returned
anova table in place of `$aov.tab[1,]`. All 12 `STATS:beta_diversity` tasks
(4 feature types × univariate/multivariate/pairwise) now pass, and the
univariate table carries the fixture's seeded case effect (taxonomy R² 46%,
p=0.001).

### ~~2. HAllA cannot load libR through rpy2~~ — fixed, by giving HAllA its own module
The `LD_LIBRARY_PATH` line was the right diagnosis but the wrong scope. Once it
was set, HAllA failed earlier still, in argument parsing:

```
pkg_resources.ContextualVersionConflict: (numpy 2.2.6 (.../assembly_depends/...),
  Requirement.parse('numpy<2,>=1.18'), {'statsmodels'})
```

HAllA pins `numpy<2` through statsmodels and enforces it with
`pkg_resources.require('HAllA')` before it reads `sys.argv`. The
`biobakeryworkflows/3.2` module puts `assembly_depends` — numpy 2.2.6 — ahead of
`depends` on `PYTHONPATH`, deliberately, because the matplotlib in `depends` is
too old for numpy 2 and the report rendering needs the newer one. The two
requirements cannot both be met in one environment.

They do not have to be. There is a standalone HAllA install behind
`rocky8/halla/0.8.20` (`/n/lab_storage/huttenhower_lab/tools/halla/rocky8`) with
numpy 1.26.4, its own `R_LIBS` and R 4.3.3, and it resolves the `libRblas.so`
load too. **The `halla` process must load that module and not
`biobakeryworkflows/3.2`.** Wired up as a `withName: halla` `beforeScript` in
`conf/profiles/harvard_rc.config`; for `-profile local` hand runs the same
environment is set without lmod by
`~/biobakery_vis_stats_test/halla_env.config`, passed with `-c`.

Verified by hand: HAllA runs to completion on `taxonomy_features.txt` under that
environment and writes `hallagram.png` plus a significant association.

### ~~3. Duplicate feature-table names~~ — fixed
`STATS:mantel_test` failed with `input file name collision -- multiple input
files for each of the following file names: counts_features.txt`.

Root cause is upstream: `get_input_files_for_study_type()` types a file by the
last underscore-delimited part of its bioBakery type, so `wmgx_feature_counts`
and `wmgx_humann_counts` both become `counts`. `create_feature_table_inputs()`
then points both at `features/counts_features.txt` and keeps only the last in
`feature_tasks_info` — AnADAMA tolerates two tasks writing one target, Nextflow
does not.

`biobakery_identify_inputs.deduplicate_by_type()` makes that overwrite explicit
(last wins), so the manifest carries one file per type. Both of those files are
now excluded from the stats feature set outright (see the decision below), so
the collision cannot arise; `deduplicate_by_type()` stays as the general
safeguard, since any other pair of types colliding on a suffix would hit it.

### ~~4. Chained mode is not wired~~ — fixed
`mgx`, `mtx` and `mgx_mtx` now finish by running `VIS`, and `STATS` when
`--run_stats true` and `--input_metadata` are both given, over a folder built by a new
`stage_report_input` process (`modules/utils/report_input`). Both problems this
issue recorded are solved by taking the files from **channels** rather than
from the published output folder:

- the `publishDir` race disappears, because nothing reads `params.outdir`;
- the layout mismatch disappears, because the staged folder uses the names
  `files.ShotGun` looks for -- `metaphlan/merged/metaphlan_taxonomic_profiles.tsv`,
  `kneaddata/merged/kneaddata_read_count_table.tsv`, `humann/merged/<feature>.tsv`
  and `humann/counts/*`.

`VIS` and `STATS` take that folder as a channel now, in place of the `ready`
flag; `main.nf` passes `Channel.value(<folder>)` for a standalone run.

`mgx_mtx` reports on its **metagenome half only**. Staging both halves under
`whole_meta*_shotgun/` was tried first and does not work: `files.ShotGun.path()`
falls back to `<folder>/<filename>` and no further (`files.py:79`), so every
named lookup missed and `identify_inputs` exited with the "no data files found"
description. That is consistent with upstream, where `vis` takes one assay's
folder. The metatranscriptome half is reachable with
`--workflow vis --vis_input <outdir>/whole_metatranscriptome_shotgun`.

**A chained report failure is not the run's failure.** `withName: '.*:REPORTING:.*'`
sets `errorStrategy = 'ignore'` in `conf/base.config`: the profiles and tables
are already published, and vis and stats do legitimately fail on a study too
small to visualise -- an ordination of two samples, a heatmap of a handful of
features. Standalone runs carry no `REPORTING:` prefix and still fail loudly.
The staged folder is published as `<outdir>/report_input/`.

Three count tables the report sections are built from did not exist in this
pipeline at all and were ported at the same time, each a one-line upstream
task: `kneaddata_read_counts` (`shotgun.kneaddata_read_count_table`),
`metaphlan_species_counts` (the `metaphlan_count_species` task) and
`humann_log_counts` (`humann_count_alignments_species`). They are published in
the bioBakery locations, so a standalone vis run pointed at this pipeline's own
output folder now finds them too.

**Chained `stats` is opt-in** (`--run_stats true`), which revises decision 2
above. It is a study-level analysis rather than a report: MaAsLin2, HAllA and
the mantel test need enough samples to fit anything, and chained onto a small
study they fail and take an otherwise complete profiling run down with them --
which the two-sample test run demonstrated. `vis` stays on by default. With
`--run_stats true` and no metadata the stats half is skipped with a warning
rather than failing, since `stats.py` requires metadata and a read-based run
has no reason to have been given any.

Four defects surfaced the first time vis ran chained, all invisible to a
standalone run against the fixture:

- `vis_report` staged `metadata`, `alpha_diversity_plots` and `ecs_file` under
  their own basenames, and all three fall back to the same `assets/NO_FILE`
  sentinel -- so any run without metadata failed with "multiple input files for
  each of the following file names: NO_FILE". They now stage into separate
  directories.
- `alpha_diversity` exits 1 with "No data remain in the data after filtering for
  min abundance and prevalence" when the feature table is too sparse, which a
  couple of low-biomass samples produce routinely. That one message is now
  carried through as "no plots" rather than failing the run; every other failure
  still fails the task.
- `stage_report_input` hit the same `NO_FILE` collision as `vis_report`, for the
  same reason, whenever two of its optional inputs were skipped together.
- `taxonomy.pmd` binds `caption` only as the return of `document.show_pcoa()`.
  pweave catches an exception inside a chunk, prints it into the report and
  carries on -- but the inline `<%= caption %>` then raises `NameError` and kills
  the whole render, which is exactly what a study too small to ordinate
  produces. Both captions are now bound before the call.

### ~~6a. No configs for the new processes~~ — fixed
`conf/base.config` now carries resource blocks for every vis/stats process and
`conf/profiles/harvard_rc.config` gives them all
`module load rocky8/biobakeryworkflows/3.2`, which pulls in
`rocky8/anadama2/0.10.0-devel` (pweave, and the R_LIBS that holds vegan),
R 4.5.1 and HUMAnN. `withName: halla` keeps its own module, for the reason in
issue 2. Both workflows now run under `-profile harvard_rc` on SLURM, not only
as `-profile local` hand runs, and are covered by `tests/run_tests.sh` (tests 11
and 12).

One porting defect surfaced only once they ran outside the hand-run
environment: `alpha_diversity`, `mantel_test` and both `beta_diversity` calls
resolved their R script with
`python -c "import biobakery_bootstrap; ..."`, which works only when
`bin/scripts` is on PYTHONPATH -- true of `env.sh`, true of no profile.
`biobakery_bootstrap.py` grew a `--rscript` / `--template` CLI and those four
call sites now invoke it by path.

### ~~6b. The 0.0.4 modulefile~~ — written
`rocky8/biobakery-workflows-nextflow/0.0.4` exists and needs nothing beyond
what 0.0.3 had plus `KNEADDATA_DB_HUMAN_TRANSCRIPTOME`. The requirement this
issue used to record -- that the modulefile also carry pweave, R 4.5.1 with the
anadama2 `R_LIBS`, `LD_LIBRARY_PATH` and HUMAnN for the report steps -- is
obsolete: those are per-process needs, and they are met by the `beforeScript`
blocks added in issue 6a. The modulefile only has to put Nextflow and a JDK on
`PATH` and point at the pipeline and its params file.

### 6c. Not yet done
- Nothing from issue 6 remains. The README documents the chained mode
  (use case 14), the vis/stats parameters and the bioBakery-standard tables the
  new count steps publish.

---

## Known upstream defects worked around

Each of these is 3.2 code running against the current pinned R/Python stack, not
a porting mistake. They are recorded so the divergences stay deliberate.

| Where | Symptom | Handling |
|---|---|---|
| `document.show_pcoa()` continuous branch | `pyplot.colorbar(scalarmappaple)` with a detached ScalarMappable → `Unable to determine Axes to steal space for Colorbar` on matplotlib ≥ 3.6, killing the chunk and losing every continuous-metadata PCoA | fixed in the vendored `biobakery_document.py`: `ax=subplot` |
| `Rscripts/alpha_diversity.R` | `labs("")` → `<ggplot2::labels> object is invalid` on ggplot2 4.x, aborting on the first continuous variable | vendored in `assets/Rscripts/`, no-op call dropped |
| `Rscripts/beta_diversity.R` univariate branch | `adonis` defunct in vegan 2.7.2; the pairwise and multivariate branches of the same script already call `adonis2` | vendored in `assets/Rscripts/`, ported to `adonis2(..., by="terms")` and reading row 1 of the returned table instead of `$aov.tab[1,]` |
| `Rscripts/mantel_test.R` | transposes every feature table on the assumption that samples are its columns. `create_feature_table.py` never transposes, so the count tables (`humann_feature_counts.tsv`, `humann_read_and_species_count_table.tsv`) arrive samples-as-rows, transpose to rows named for the count columns, and intersect no other table — `vegdist()` returns an empty distance matrix and ade4 aborts in `bicenter.wt()` with "weights must be non-negative and not all zero" before any test runs | vendored in `assets/Rscripts/`, with the orientation check upstream's own `beta_diversity.R` already does (which is why beta diversity on the same tables succeeds) |
| `get_input_files_for_study_type()` | two files collapse to type `counts`, then `create_feature_table_inputs()` writes both to one target | `deduplicate_by_type()` in the discovery step |
| `get_input_files_for_study_type()` | sweeps the HUMAnN count tables into the stats feature set, though they are samples-as-rows QC summaries rather than abundance tables; `exclude_types` already drops the kneaddata read count table for the same reason and missed these | `exclude_non_abundance_files()` in the discovery step — see decision 6 |
| `Maaslin2:::maaslin2_association_plots` (MaAsLin2 1.22.0) | `ggplot2::labs("")` → `<ggplot2::labels> object is invalid` on ggplot2 4.x, on the first *continuous* metadata variable, after the results tables are already written | `assets/Rscripts/ggplot2_labs_shim.R`, sourced by the `maaslin2` module: rewrites that one function in memory, since the shared install cannot be patched |
| `hclust2` | `ValueError: Invalid vmin or vmax` on degenerate data (seen on the fixture's `ecs_zscore` heatmap only) | already tolerated: `show_hclust2()` catches it and prints "Unable to generate heatmap" |

The vendored `sh()` **raising** on a non-zero exit is *not* a divergence:
upstream `anadama2/util.py:sh` (line 313-321) raises `ShellException` the same
way. This was previously flagged as uncertain; it is settled.

---

## Port-specific fixes worth remembering

- **Report links are relativized.** The `.pmd` templates embed figures by
  absolute `document.figures_folder` path. Under AnADAMA that folder is the
  final destination; under Nextflow it is a work directory, so a published
  report pointed at paths that vanish on cleanup.
  `biobakery_bootstrap.relativize_report_links()` strips the report folder
  prefix from the rendered HTML (PDF needs nothing — pandoc embeds the images).
- **Everything the report references is staged into the report folder first**,
  so there is a prefix to strip: `stage_alpha_diversity_plots()` copies the
  plots in (which is also the layout upstream writes), and
  `stage_package_image()` copies the `wms_workflow` diagram out of the install
  prefix so the folder is self-contained off-cluster.
- **`alpha_diversity` has no `publishDir`.** It used to publish to
  `${params.outdir}/vis`, the same folder `vis_report` publishes wholesale, and
  the later publish clobbered the plots.
- **`feature_table` / `trim_taxonomy` take a `publish` flag** for the same
  reason. Upstream writes the feature tables into whichever output folder called
  `create_feature_table_inputs()`, so stats gets `stats/features/` and vis gets
  `vis/features/`. The shared module published to a fixed `stats/features/`,
  which put a `stats` folder in the output of every vis-only run. vis now passes
  `false`: the table is only an intermediate for the alpha diversity plots
  there, and publishing it into `vis/` would race `vis_report`'s wholesale copy
  exactly as `alpha_diversity` did.
- **The render scratch directory is cleaned up after the report.**
  `PweaveDocument.create()` renders inside a `tempfile.mkdtemp()` made in the
  report folder and clears it with `rmtree(ignore_errors=True)`; on NFS that
  routinely leaves the emptied directory behind, because deleting a still-open
  file makes the server silly-rename it, the `rmdir` then fails, and the error
  is swallowed. Upstream never notices — there the folder is just a location on
  disk. Here it is a published artifact, so the stray `tmp*` directory shipped
  in `outdir/<workflow>/` and inside the zip.
  `biobakery_bootstrap.remove_render_temp_dirs()` removes it, and only if empty.

---

## Running the report drivers by hand

Use `~/biobakery_vis_stats_test/env.sh`, which is the recipe below kept in one
place:

```bash
source ~/biobakery_vis_stats_test/env.sh
```

The module environment is fiddly. `PYTHONPATH` order matters: `matplotlib` in
`depends/` is too old for numpy 2.x, so `assembly_depends/` must come first.

```bash
T=/n/lab_storage/huttenhower_lab/tools/biobakery_workflows/rocky8
A=/n/lab_storage/huttenhower_lab/tools/anadama2/rocky8/v0.10.0
H=/n/lab_storage/huttenhower_lab/tools/humann4/rocky8
R_HOME_DIR=/n/sw/helmod-rocky8/apps/Core/R/4.5.1-fasrc01
REPO=/n/home04/smaharjan/biobakery-nextflow

export PATH=$R_HOME_DIR/bin:$T/v3.2/bin:$T/assembly_depends/bin:$T/depends/bin:$T/conda/pandoc_env/bin:$A/bin:$H/v4_alpha_1_final/bin:$H/depends:/n/sw/Mambaforge-22.11.1-4/bin:$PATH
export LD_LIBRARY_PATH=$T/depends/lib:$R_HOME_DIR/lib64/R/lib:$LD_LIBRARY_PATH
export PYTHONPATH=$T/v3.2/lib/python3.10/site-packages:$T/assembly_depends/lib/python3.10/site-packages:$T/depends/lib/python3.10/site-packages:$T/depends/lib:$A/lib/python3.10/site-packages:$H/v4_alpha_1_final/lib/python3.10/site-packages
export R_LIBS=$A/../R_LIBS:$T/R_LIBS:$T/assembly_depends/R_LIBS
export MPLBACKEND=Agg
export PATH=$REPO/bin/scripts:$PATH
export PYTHONPATH=$REPO/bin/scripts:$PYTHONPATH
```

Three of these were missing from the earlier version of this recipe and each
cost a failed run:

- **R on `PATH`.** `document.compute_pcoa()` runs `subprocess.Popen(["R", ...])`;
  with no R it raises `FileNotFoundError` and kills the chunk. This was the
  long-standing "PCoA chunk failure".
- **`R_LIBS` including the *anadama2* one.** `vegan` is there, not in the R
  module (base packages only) and not in biobakery's `R_LIBS`.
- **`$R_HOME/lib64/R/lib` on `LD_LIBRARY_PATH`** for HAllA's rpy2.

`$A/lib/python3.10/site-packages` is needed **only for pweave**; the bootstrap
still forces `import anadama2` to the stand-in. HUMAnN's site-packages goes last
so it cannot disturb the numpy/matplotlib resolution order.

For Nextflow itself, JDK 11+ is required (the login shell default is Java 8):

```bash
export JAVA_HOME=/n/sw/helmod-rocky8/apps/Core/jdk/21.0.2-fasrc01
export PATH=$JAVA_HOME/bin:/n/lab_storage/huttenhower_lab/tools/nextflow/24.10.4/bin:$PATH

```

The two runs used to get here, verbatim (drop `-resume` whenever a driver in
`bin/` changed — see issue 5):

```bash
source ~/biobakery_vis_stats_test/env.sh
cd ~/biobakery_vis_stats_test/nf_vis

nextflow run $REPO/main.nf --workflow vis -profile local -w $PWD/work \
  --vis_input   ~/biobakery_vis_stats_test/input \
  --input_metadata ~/biobakery_vis_stats_test/input/metadata.tsv \
  --outdir $PWD/out --project_name "vis nf test"

cd ~/biobakery_vis_stats_test/nf_stats

nextflow run $REPO/main.nf --workflow stats -profile local \
  -c ~/biobakery_vis_stats_test/halla_env.config -w $PWD/work \
  --stats_input ~/biobakery_vis_stats_test/input \
  --input_metadata ~/biobakery_vis_stats_test/input/metadata.tsv \
  --outdir $PWD/out --project_name "stats nf test" \
  --stats_fixed_effects 'diagnosis,age'
```

The `-c ~/biobakery_vis_stats_test/halla_env.config` is **required** for stats:
env.sh cannot host HAllA, which pins numpy < 2, alongside the report rendering,
which needs numpy 2. That file gives the `halla` process its own environment
without lmod, and is the hand-run equivalent of the `withName: halla`
`beforeScript` in `conf/profiles/harvard_rc.config`. See issue 2.

## Next session, in order

1. `--report_format pdf`, which has not been exercised since the link changes.
2. Section-by-section comparison against a fresh upstream 3.2 run. This is the
   one substantive item left: an upstream run has to be produced first, and an
   upstream 3.2 stats run cannot complete on a standard wmgx folder (decision 6),
   so the comparison has to be section by section rather than a diff.
3. The chained reports are covered by `tests/run_tests.sh` for mgx and mgx_mtx;
   `mtx` chaining runs the same code and is not separately tested.
