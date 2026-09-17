# biobakery-nextflow

> Nextflow implementation of the [bioBakery](https://github.com/biobakery) metagenomics suite,
> ported from the [anadama2 biobakery-workflows](https://github.com/biobakery/biobakery_workflows)
> with multi-cluster support, nf-core-style modules, and an SGB assembly pipeline.

![Static Badge](https://img.shields.io/badge/Author-Kevin_Bonham_PhD-purple)
![Static Badge](https://img.shields.io/badge/Author-Guilherme_Fahur_Bottino_PhD-purple)
![Static Badge](https://img.shields.io/badge/Author-Danielle_Pinto-purple)

---

## Table of Contents

1. [Overview](#overview)
2. [Tools & Versions](#tools--versions)
3. [Installation & Environment Setup](#installation--environment-setup)
   - [Harvard FASRC (Cannon)](#harvard-fasrc-cannon)
   - [Tufts HPC](#tufts-hpc)
   - [AWS Batch](#aws-batch)
   - [Local / Docker](#local--docker)
4. [Quick Start](#quick-start)
5. [Use Cases](#use-cases)
6. [All Parameters](#all-parameters)
7. [Configuration layers](#configuration-layers)
8. [Compute Profiles](#compute-profiles)
9. [Changing Databases](#changing-databases)
10. [Changing Resources](#changing-resources)
11. [Output Structure](#output-structure)
12. [Testing](#testing)
13. [Project Status](#project-status)

---

## Overview

Select a workflow with `--workflow`:

| `--workflow` | Status | Description |
|---|---|---|
| `mgx` *(default)* | ✅ Ready | Whole metagenome shotgun: QC + taxonomy + function |
| `assembly` | ✅ Ready | MAG assembly → binning → SGB clustering (matches `biobakery_workflows assembly`, v3.2) |
| `mgx_mtx` | ✅ Ready | Paired metagenome + metatranscriptome, joined by the RNA/DNA ratio (matches `biobakery_workflows wmgx_wmtx`, v3.2) |
| `mtx` | ✅ Ready | Whole metatranscriptome shotgun: QC + taxonomy + function |
| `16s` | 🔜 Stub | 16S amplicon (DADA2 / QIIME2 planned) |
| `vis` | ✅ Ready | Visualization report — QC, taxonomy, ordination, heatmaps, pathways/ECs (matches `biobakery_workflows vis`, v3.2) |
| `stats` | ✅ Ready | Statistics — feature tables, mantel, MaAsLin2, HAllA, stratified pathways, beta diversity / PERMANOVA (matches `biobakery_workflows stats`, v3.2) |

`vis` and `stats` take a **folder** of bioBakery output rather than channels, exactly
as their AnADAMA counterparts do, so they run standalone against the output of any
bioBakery run. `vis` also runs at the end of `mgx`, `mtx` and `mgx_mtx` by default, over
a bioBakery-standard folder built from that run's own channels — turn that off with
`--run_vis false`, and see use case 14. Chaining `stats` is opt-in
(`--run_stats true` plus `--input_metadata`), because it needs a study large enough
for its analyses to fit. See
[docs/vis_stats_port_status.md](docs/vis_stats_port_status.md) for the full port
status, the upstream defects worked around, and the remaining work.

**[docs/workflow_reference.md](docs/workflow_reference.md) is the map of what
runs where**: one diagram and one step-by-step table per workflow, both
generated from the pipeline itself by `bin/make_diagrams.py`, so they cannot
drift from the code. [docs/dependencies.md](docs/dependencies.md) is the
companion for where each step's software comes from.

---

## Tools & Versions

| Tool | Purpose | Supported versions |
|---|---|---|
| [KneadData](https://github.com/biobakery/kneaddata) | Host decontamination + QC trimming | 0.12+ |
| [MetaPhlAn](https://github.com/biobakery/MetaPhlAn) | Species-level taxonomic profiling | v3.1, v4.0.6, v4.1.1 |
| [HUMAnN](https://github.com/biobakery/humann) | Functional pathway profiling | 3.7, 4.0-alpha |
| [BAQLaVa](https://github.com/biobakery/baqlava) | Viral profiling | 1.2 (`rocky8/baqlava/1.2.0-devel`) |
| [StrainPhlAn](https://github.com/biobakery/MetaPhlAn) | Strain-level profiling (SGB mode) | bundled with MetaPhlAn 4 |
| [MEGAHIT](https://github.com/voutcn/megahit) | De novo metagenome assembly | 1.2+ |
| [MetaBAT2](https://bitbucket.org/berkeleylab/metabat) | MAG binning | 2.15+ |
| [CheckM2](https://github.com/chklovski/CheckM2) | MAG quality assessment | 1.0+ |
| [PhyloPhlAn](https://github.com/biobakery/phylophlan) | Phylogenetic MAG placement | 3.0+ |
| [Mash](https://github.com/marbl/Mash) | Pairwise genome distance (SGB clustering) | 2.0+ |
| [MaAsLin2](https://github.com/biobakery/Maaslin2) | Multivariable association testing (`stats`) | 1.22 |
| [HAllA](https://github.com/biobakery/halla) | Hierarchical all-against-all association (`stats`) | 0.8.20 (`rocky8/halla/0.8.20`) |
| [vegan](https://cran.r-project.org/package=vegan) | Alpha / beta diversity, PERMANOVA (`vis`, `stats`) | 2.7+ |

---

## Installation & Environment Setup

### Harvard FASRC (Cannon)

Tools are pre-installed via the hutlab module system. No containers needed.

```sh
# One-time setup (run once per login shell or add to ~/.bashrc)
source /n/lab_storage/huttenhower_lab/tools/hutlab/src/hutlabrc_rocky8.sh
hutlab load rocky8/biobakery-workflows-nextflow/0.0.4

# Verify Nextflow is available
nextflow -version
```

Database paths are automatically loaded when you use `-profile harvard_rc`
(from `conf/databases/harvard_rc.config`). No params file needed for defaults.

---

### Tufts HPC

Tools are provided via Apptainer containers already configured in the `tufts_hpc` profile.

```sh
# Add Nextflow and shared binaries to PATH
module load nextflow
export PATH="/cluster/tufts/bonhamlab/shared/bin:$PATH"

# Database paths are loaded from conf/databases/tufts.config
```

The profile already sets the executor, the containers and the database paths,
so a run only has to say where the reads are:

```sh
nextflow run main.nf -profile tufts_hpc \
  --readsdir /path/to/my/fastqs --outdir /path/to/results
```

To write those settings down instead, copy the site template — it is a list of
commented-out settings, not a file you have to fill in:

```sh
cp conf/tufts_hpc.yaml my-run.yaml
nextflow run main.nf -profile tufts_hpc -params-file my-run.yaml
```

---

### AWS Batch

Requires prior setup of AMIs, job queues, S3 buckets, and ECR containers.
ECR container URIs are already configured in `conf/profiles/aws.config`.

```sh
nextflow run main.nf -profile amazon -params-file params.yaml
```

See `conf/profiles/aws.config` for queue and container assignments per process.

---

### Local / Docker

Requires all tools installed in your `$PATH` (conda recommended).

```sh
# Install via conda/mamba
mamba create -n biobakery -c biobakery -c conda-forge \
  kneaddata metaphlan=4 humann nextflow
conda activate biobakery

nextflow run main.nf -profile local \
  --readsdir /path/to/fastqs \
  --outdir   /path/to/results \
  --host_genome  /path/to/kneaddata/hg38 \
  --metaphlan_db  /path/to/metaphlan_db \
  --humann_db     /path/to/humann_db
```

> **Note:** MetaPhlAn requires ≥ 15 GB RAM. A 16 GB laptop is often insufficient.
> Prefer HPC or cloud for production runs.

---

## Quick Start

### Minimal MGX run (paired-end)

```sh
nextflow run main.nf \
  --workflow     mgx \
  --readsdir     /path/to/fastqs \
  --outdir       results \
  --host_genome /path/to/kneaddata/hg38 \
  --metaphlan_db /path/to/metaphlan_db \
  --humann_db    /path/to/humann_db
```

### Single-end reads

```sh
nextflow run main.nf --workflow mgx \
  --single_end true \
  --readsdir /path/to/fastqs \
  [other required params]
```

`--paired_end false` means the same thing. Layout is detected from the read
filenames, so neither flag is needed unless you want to force single-end on
reads that do pair up. `--filepattern` is only for a naming convention the
defaults do not match — `*.fastq.gz` for single-end and
`*<pair_identifier>*.fastq.gz` for paired-end.

### Resume an interrupted run

```sh
nextflow run main.nf [same params as original run] -resume
```

### Using a params file (recommended for reproducibility)

```sh
# Copy your site's template and uncomment what you need
cp conf/harvard_rc.yaml my-params.yaml     # or conf/tufts_hpc.yaml
# Edit my-params.yaml ...

nextflow run main.nf -profile harvard_rc -params-file my-params.yaml
```

A params file is for settings that belong to one run. Database paths, tool
modules and resource requests are already defaults of the profile, so they do
not belong in it — see [Configuration layers](#configuration-layers).

---

## Use Cases

### 1. Standard MGX: taxonomy + function only

Default settings. Both MetaPhlAn and HUMAnN run; regroup/rename/merge are on.

```sh
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results
```

---

### 2. Taxonomy only — with MetaPhlAn options

Skip HUMAnN and tune MetaPhlAn output format, alignment length, and database:

```sh
# Marker abundance table instead of relative abundance (default: rel_ab_w_read_stats)
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --run_functional_profiling false \
  --metaphlan_analysis_type marker_ab_table

# Stricter minimum read alignment length (default: 70 bp)
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --run_functional_profiling false \
  --metaphlan_read_min_len 100

# Switch to a different MetaPhlAn database index
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --metaphlan_db   /path/to/other/metaphlan_databases \
  --metaphlan_index mpa_vOct22_CHOCOPhlAnSGB_202403 \
  --metaphlan_version metaphlan_v4
```

> On Harvard FASRC hutlab builds, pass `--metaphlan_version metaphlan_v3` — the hutlab binary uses v3-style CLI flags (`--bowtie2db`) even though it is MetaPhlAn 4.

---

### 3. Functional profiling — HUMAnN options

Tune the regrouping target, skip internal searches, or disable post-processing:

```sh
# KEGG orthologs instead of MetaCyc reactions (default: uniref90_rxn)
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --humann_regroup_grouping uniref90_ko

# Available groupings: uniref90_rxn | uniref90_ko | uniref90_eggnog | uniref90_pfam

# Skip MetaPhlAn prescreen inside HUMAnN (useful when species profile already exists)
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --humann_bypass_prescreen true

# Skip nucleotide search — go straight to translated search (faster, lower sensitivity)
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --humann_bypass_nucleotide_search true

# Disable post-processing (no regroup / rename / merge tables)
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --run_humann_regroup false \
  --run_humann_rename  false \
  --run_humann_merge   false
```

---

### 4. Add viral profiling — BAQLaVa options

```sh
# Standard viral profiling
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --run_viral_profiling true

# Bypass bacterial depletion — needed for test/tiny samples with 0 prescreen species
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --run_viral_profiling true \
  --baqlava_bypass_depletion true

# Use a custom BAQLaVa database (default: bundled db)
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --run_viral_profiling true \
  --baqlava_db /path/to/custom/baqlava_db
```

---

### 5. Add strain-level profiling (StrainPhlAn)

StrainPhlAn runs after MetaPhlAn and uses the compressed SAM output.
By default it profiles all detected clades.

```sh
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --run_strain_profiling true
```

Target specific clades only:

```sh
  --run_strain_profiling true \
  --strainphlan_clades "s__Akkermansia_muciniphila,s__Bacteroides_fragilis"
```

---

### 6. Full MGX with all optional modules

```sh
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/fastqs \
  --outdir   results \
  --run_viral_profiling  true \
  --run_strain_profiling true
```

---

### 7. Assembly (MAG assembly → binning → SGB clustering)

Requires MEGAHIT, MetaBAT2, CheckM2, PhyloPhlAn, Mash, and the PhyloPhlAn database.

```sh
nextflow run main.nf -profile harvard_rc \
  --workflow      assembly \
  --readsdir      /path/to/kneaddata_output \
  --outdir        results \
  --run_qc        false \
  --phylophlan_path /path/to/phylophlan_databases
```

Lower quality thresholds for more permissive binning:

```sh
  --sgb_completeness  30 \
  --sgb_contamination 15
```

Cross-dataset abundance (align reads against all MAGs in the cohort):

```sh
  --sgb_abundance_type by_dataset
```

---

### 8. Skip QC (start from already-cleaned reads)

```sh
nextflow run main.nf -profile harvard_rc \
  --readsdir /path/to/kneaddata_output \
  --outdir   results \
  --run_qc   false
```

With paired input and `--run_qc false`, each pair is concatenated into one file
before profiling, because MetaPhlAn and HUMAnN take a single input file per
sample. This is what `biobakery_workflows` does with `--bypass-quality-control`
(`shotgun.merge_pairs`); when QC runs, KneadData produces the concatenated file
itself.

---

### 9. HUMAnN v4 (alpha)

Switch both the software module and the database:

```sh
nextflow run main.nf -profile harvard_rc \
  --humann_version humann_v4a \
  --humann_db /n/lab_storage/huttenhower_lab/tools/nextflow/databases/humann4 \
  --readsdir /path/to/fastqs \
  --outdir   results
```

> Also update `beforeScript` in `conf/profiles/harvard_rc.config` to load
> `rocky8/humann4/4.0-alpha-1` for the `humann` process.

---

### 10. Mouse / ribosomal RNA decontamination

Change only the KneadData reference; everything else stays the same.

```sh
# Mouse C57BL reference
nextflow run main.nf -profile harvard_rc \
  --host_genome /n/lab_storage/huttenhower_lab/data/kneaddata_databases/mouse_C57BL \
  --readsdir /path/to/fastqs --outdir results

# Ribosomal RNA (for rRNA depletion check)
nextflow run main.nf -profile harvard_rc \
  --host_genome /n/lab_storage/huttenhower_lab/data/kneaddata_databases/ribosomal_RNA/SILVA_128_LSUParc_SSUParc_ribosomal_RNA_v0.2 \
  --readsdir /path/to/fastqs --outdir results
```

---

### 11. Demo run (bundled test sample)

```sh
# Harvard FASRC — single-end demo
nextflow run main.nf -profile harvard_rc \
  --readsdir    tests/data/single_end_rawfastq \
  --paired_end  false \
  --outdir      tests/results

# Same demo + viral profiling
nextflow run main.nf -profile harvard_rc \
  --readsdir    tests/data/single_end_rawfastq \
  --paired_end  false \
  --outdir      tests/results \
  --run_viral_profiling true \
  --baqlava_bypass_depletion true
```

### 12. Visualization report (`vis`)

Point it at a folder of bioBakery output — it discovers the taxonomic profile, QC
and HUMAnN read counts, pathway and EC tables by name and by content, the same way
`biobakery_workflows vis` does. Metadata is optional; without it the alpha diversity
plots and metadata-stratified figures are skipped.

```sh
nextflow run main.nf -profile harvard_rc --workflow vis \
  --vis_input       /path/to/biobakery_output \
  --input_metadata  /path/to/metadata.tsv \
  --outdir          results \
  --project_name    "My study"
```

Produces `results/vis/mgx_report.html` (figures, data and alpha diversity plots
alongside it) and `results/vis.zip`. All links in the report are relative, so the
folder can be moved or shared as a unit.

### 13. Statistics (`stats`)

Metadata is **required**. `--stats_fixed_effects` names the metadata variables to
test.

```sh
nextflow run main.nf -profile harvard_rc --workflow stats \
  --stats_input         /path/to/biobakery_output \
  --input_metadata      /path/to/metadata.tsv \
  --outdir              results \
  --project_name        "My study" \
  --stats_fixed_effects 'diagnosis,age'
```

Produces `results/stats/stats_report.html` and `results/stats.zip`, plus the
per-analysis folders (`features/`, `maaslin2_*/`, `halla_*/`, `mantel_test/`,
`beta_diversity/`, `stratified_pathways/`).

Setting `--stats_random_effects` marks the study longitudinal, which runs a PERMANOVA
in place of beta diversity and additionally requires `--stats_static_covariates`.
Skip the expensive stages with `--stats_bypass_maaslin` / `--stats_bypass_halla`.

> **HAllA needs its own module.** It pins `numpy<2`, while the report rendering needs
> numpy 2, so the two cannot share an environment. On `harvard_rc` this is already
> handled — the `halla` process loads `rocky8/halla/0.8.20` via its own `beforeScript`.
> On other profiles, give that process an environment with HAllA and numpy 1.x.

### 14. Reports at the end of a read-based run (chained `vis` / `stats`)

`mgx`, `mtx` and `mgx_mtx` finish by running vis over their own results.
Nothing extra is needed; pass metadata to get the metadata-driven figures:

```sh
nextflow run main.nf -profile harvard_rc \
  --readsdir       /path/to/fastqs \
  --outdir         results \
  --input_metadata /path/to/metadata.tsv
```

Turn it off with `--run_vis false`.

**stats is opt-in** (`--run_stats true`, plus `--input_metadata`). It is a
study-level analysis rather than a report: MaAsLin2, HAllA and the mantel test
need enough samples to fit anything, and on a small study they fail — which,
chained, would take down an otherwise complete profiling run at its last step.
With `--run_stats true` but no metadata it is skipped with a warning rather
than failing.

The reports are not built from `results/` on disk. A `stage_report_input` step
assembles a bioBakery-standard folder from the run's own output channels —
`metaphlan/merged/metaphlan_taxonomic_profiles.tsv`,
`kneaddata/merged/kneaddata_read_count_table.tsv`,
`humann/merged/*.tsv`, `humann/counts/*.tsv` — which is what `files.ShotGun`
looks for by name. Two reasons:

- `publishDir` is asynchronous, so a step reading `--outdir` mid-run is a race.
- This pipeline's own published names and locations differ from the bioBakery
  layout, so a report pointed at `--outdir` finds only the files that can be
  identified from their contents, and loses its QC read-count, HUMAnN
  read-count and feature-count sections.

`mgx_mtx` reports on its **metagenome half**. `files.ShotGun` looks for each
file at a fixed path and does not walk subdirectories, so a folder holding two
assays is not something vis can read — upstream `biobakery_workflows vis` takes
one assay's output folder too. Report on the other half with
`--workflow vis --vis_input <outdir>/whole_metatranscriptome_shotgun`.

A chained report that fails does **not** fail the run: the profiles and tables
are already written, and vis and stats legitimately fail on a study too small or
too sparse to visualise. The failure is reported in the log. A standalone
`--workflow vis|stats` run is unaffected — there the report is the run.

The staged folder is published as `<outdir>/report_input/`, so you can see what
the report was built from, and point a later standalone run straight at it.

---

## All Parameters

### Workflow & I/O

| Parameter | Default | Description |
|---|---|---|
| `--workflow` | `mgx` | Workflow: `mgx \| mtx \| mgx_mtx \| 16s \| vis \| stats \| assembly` |
| `--readsdir` | *required* | Directory containing input FASTQ files (all workflows except `mgx_mtx`) |
| `--input_metagenome` | *required for `mgx_mtx`* | Folder of raw metagenome reads |
| `--input_metatranscriptome` | *required for `mgx_mtx`* | Folder of raw metatranscriptome reads |
| `--input_mapping` | `null` | `mgx_mtx` only. Tab-delimited `<rna sample>\t<dna sample>` per line, `#` comments allowed. With a mapping, RNA samples reuse the paired DNA sample's MetaPhlAn profile instead of being profiled themselves. |
| `--bypass_norm_ratio` | `false` | `mgx_mtx` only. Skip the RNA/DNA relative expression ratio. |
| `--host_transcriptome` | *set per profile* | Host mRNA bowtie2 index, used by `mtx` QC and the mtx half of `mgx_mtx` |
| `--rrna_db` | *set per profile* | SILVA rRNA bowtie2 index, same |
| `--outdir` | `results` | Output directory |
| `--paired_end` | `true` | `true` for paired-end, `false` for single-end |
| `--filepattern` | `*_R{1,2}*.fastq.gz` | Glob to match reads. Paired-end must use `{1,2}`. |

### Tool toggles

| Parameter | Default | Description |
|---|---|---|
| `--run_qc` | `true` | Run KneadData QC. Set `false` to start from cleaned reads. |
| `--run_taxonomic_profiling` | `true` | Run MetaPhlAn |
| `--run_functional_profiling` | `true` | Run HUMAnN |
| `--run_viral_profiling` | `false` | Run BAQLaVa viral profiling |
| `--run_strain_profiling` | `false` | Run StrainPhlAn SGB mode |
| `--run_vis` | `true` | Run `vis` at the end of `mgx` / `mtx` / `mgx_mtx` |
| `--run_stats` | `false` | Run `stats` at the end of `mgx` / `mtx` / `mgx_mtx`; needs `--input_metadata` and a study large enough for MaAsLin2/HAllA |

### QC options (KneadData)

| Parameter | Default | Description |
|---|---|---|
| `--host_genome` | *required* | KneadData Bowtie2 reference directory (hg38, mouse, rRNA, etc.) |
| `--kneaddata_bypass_trim` | `false` | Skip Trimmomatic trimming step |
| `--kneaddata_remove_intermediate_files` | `true` | Delete intermediate files to save disk |

### Taxonomic profiling options (MetaPhlAn)

| Parameter | Default | Description |
|---|---|---|
| `--metaphlan_db` | *required* | Directory containing MetaPhlAn bowtie2 index + pkl |
| `--metaphlan_index` | `mpa_vJun23_CHOCOPhlAnSGB_202307` | Database index name (must exist inside `metaphlan_db`) |
| `--metaphlan_version` | `metaphlan_v4` | CLI flag style: `metaphlan_v3` (uses `--bowtie2db`) or `metaphlan_v4` (uses `--db_dir`). **Harvard FASRC hutlab builds use `metaphlan_v3`.** |
| `--metaphlan_analysis_type` | `rel_ab_w_read_stats` | `-t` flag: `rel_ab \| rel_ab_w_read_stats \| marker_ab_table` |
| `--metaphlan_read_min_len` | `70` | Minimum read alignment length |

### Functional profiling options (HUMAnN)

| Parameter | Default | Description |
|---|---|---|
| `--humann_db` | *required* | Parent directory; pipeline appends `/chocophlan`, `/uniref`, `/utility_mapping` |
| `--humann_version` | `humann_v37` | Output naming: `humann_v37` or `humann_v4a` |
| `--humann_bypass_prescreen` | `false` | Skip MetaPhlAn-based taxonomic prescreen |
| `--humann_bypass_nucleotide_search` | `false` | Skip nucleotide (ChocoPhlAn) search |
| `--run_humann_regroup` | `true` | Regroup gene families (`humann_regroup_table`) |
| `--humann_regroup_grouping` | `uniref90_rxn` | Target grouping: `uniref90_rxn \| uniref90_ko \| uniref90_eggnog \| uniref90_pfam` |
| `--run_humann_rename` | `true` | Add human-readable names (`humann_rename_table`) |
| `--run_humann_merge` | `true` | Merge per-sample tables into one matrix (`humann_join_tables`) |

### Viral profiling options (BAQLaVa)

| Parameter | Default | Description |
|---|---|---|
| `--run_viral_profiling` | `false` | Enable BAQLaVa |
| `--baqlava_bypass_depletion` | `false` | Bypass bacterial depletion step (needed for test samples with 0 prescreen species) |
| `--baqlava_db` | `null` | Custom BAQLaVa database path; uses bundled db when `null` |

### Strain profiling options (StrainPhlAn)

| Parameter | Default | Description |
|---|---|---|
| `--run_strain_profiling` | `false` | Enable StrainPhlAn |
| `--strainphlan_clades` | `null` | Comma-separated clade list (e.g. `s__Akkermansia_muciniphila`). `null` = all detected. |
| `--strainphlan_phylophlan_mode` | `accurate` | Phylogenetic reconstruction: `accurate \| fast` |
| `--strainphlan_marker_in_n_samples` | `2` | Minimum samples a marker must be present in |
| `--strainphlan_db` | `null` | StrainPhlAn reference db; auto-resolved from `metaphlan_db` when `null` |

### SGB pipeline options

| Parameter | Default | Description |
|---|---|---|
| `--phylophlan_path` | `null` | **Required for `assembly`**. Path to PhyloPhlAn database directory. |
| `--megahit_min_contig_length` | `2500` | Minimum contig length for MEGAHIT and MetaBAT2 `-m` |
| `--megahit_options` | `''` | Extra MEGAHIT flags as a quoted string |
| `--metabat_options` | `''` | Extra MetaBAT2 flags |
| `--checkm_predict_options` | `''` | Extra `checkm2 predict` flags |
| `--checkm_coverage_options` | `''` | Extra `checkm coverage` flags |
| `--phylophlan_metagenomic_options` | `''` | Extra `phylophlan_metagenomic` flags |
| `--mash_sketch_options` | `''` | Extra `mash sketch` flags |
| `--sgb_completeness` | `50` | Minimum MAG completeness % for SGB inclusion |
| `--sgb_contamination` | `10` | Maximum MAG contamination % for SGB inclusion |
| `--sgb_abundance_type` | `by_sample` | Abundance estimation: `by_sample \| by_dataset` |

> Per-bin GC and length statistics are not ported. `--sgb_gc_length_stats`
> existed up to v0.0.4 but nothing read it; it was removed in the cleanup along
> with the orphaned `calculateGC.py`.

### Report options (shared by `vis` and `stats`)

| Parameter | Default | Description |
|---|---|---|
| `--input_metadata` | `null` | Metadata TSV. Required for `stats`, optional for `vis`. |
| `--input_file_type` | `null` | Extra file-type hints, semicolon-delimited `filename,filetype` pairs |
| `--report_format` | `html` | `html \| pdf`. AnADAMA defaults to pdf; html avoids needing pdflatex at render time. |
| `--project_name` | `''` | Project name shown in the report header |
| `--author_name` | `''` | Author name shown in the report header |
| `--header_image` | `''` | Image to place in the report header |
| `--introduction_text` | `''` | Override the generated introduction |
| `--use_template` | `null` | Render an alternative report template |
| `--metadata_categorical` | `''` | Comma-delimited metadata to treat as categorical |
| `--metadata_continuous` | `''` | Comma-delimited metadata to treat as continuous |
| `--metadata_exclude` | `''` | Comma-delimited metadata to ignore |
| `--max_missing` | `20.0` | Max % of samples a metadata variable may be missing in |

### Visualization options (`vis`)

| Parameter | Default | Description |
|---|---|---|
| `--vis_input` | `null` | Folder of bioBakery output to visualize (defaults to `--outdir` when chained) |
| `--vis_min_abundance` | `0.01` | Minimum abundance for a feature to be included |
| `--vis_min_samples` | `3` | Minimum % of samples a feature must appear in |
| `--vis_max_sets_heatmap` | `25` | Max features shown in a heatmap |
| `--vis_max_sets_barplot` | `15` | Max features shown in a barplot |
| `--vis_max_groups_barplot` | `5` | Max metadata groups shown in a barplot |
| `--vis_correlation_threshold` | `0.7` | Spearman threshold for filtering heatmap features |
| `--input_picard` | `null` | Folder of Picard quality metrics to include |
| `--input_picard_extension` | `quality_by_cycle_metrics` | Extension identifying the Picard files |

### Statistics options (`stats`)

| Parameter | Default | Description |
|---|---|---|
| `--stats_input` | `null` | Folder of bioBakery output to analyse (defaults to `--outdir` when chained) |
| `--stats_fixed_effects` | `''` | Comma-delimited metadata variables to test |
| `--stats_multivariable_fixed_effects` | `''` | Variables forced into the multivariable model |
| `--stats_random_effects` | `''` | Setting this marks the study longitudinal: runs PERMANOVA instead of beta diversity, and requires `--stats_static_covariates` |
| `--stats_static_covariates` | `''` | Covariates constant within a subject (required with random effects) |
| `--stats_transform` | `''` | MaAsLin2 transform |
| `--stats_adonis_method` | `bray` | Distance method for adonis |
| `--stats_min_abundance` | `0.0001` | Minimum abundance for a feature |
| `--stats_min_prevalence` | `0.1` | Minimum fraction of samples a feature must appear in |
| `--stats_permutations` | `4999` | Permutations for the mantel test and PERMANOVA |
| `--stats_scale` | `100` | PERMANOVA scale |
| `--stats_top_pathways` | `3` | Number of stratified pathways to plot per variable |
| `--stats_bypass_maaslin` | `false` | Skip MaAsLin2 (and the stratified pathway barplots) |
| `--stats_bypass_halla` | `false` | Skip HAllA |
| `--maaslin_options` | `''` | Extra arguments passed to `Maaslin2()` |
| `--halla_options` | `''` | Extra `halla` flags |

### Resources & logging

| Parameter | Default | Description |
|---|---|---|
| `--max_memory` | `128.GB` | Global memory cap (used by `check_max()` in `conf/base.config`) |
| `--max_cpus` | `32` | Global CPU cap |
| `--max_time` | `240.h` | Global walltime cap |
| `--log_versions` | `true` | Write tool and database versions to `results/pipeline_info/` |

---

## Configuration layers

Each kind of setting has exactly one home. `nextflow.config` is an index that
includes them in order, and later layers win:

| | File | Scope | Change it when |
|---|---|---|---|
| 1 | `conf/params.config` | **global defaults** — every parameter's default value | a default is wrong for everyone |
| 2 | `conf/base.config` | **default resources** — cpus/memory/time per process, and `check_max()` | a process is mis-sized everywhere |
| 3 | `conf/reports.config` | **runtime** — the timeline/report/trace/dag files written next to the output | never, normally |
| 4 | `conf/profiles/<site>.config` | **site runtime** (`-profile`) — executor, queue, containers, tool environment | something about a machine changes |
| 5 | `conf/databases/<site>.config` | **site defaults** (`-profile`) — database paths and the tool versions tied to them | a database moves or is rebuilt |
| 6 | `-params-file my.yaml` | **this run** — `conf/harvard_rc.yaml`, `conf/tufts_hpc.yaml` are templates | you want a run written down |
| 7 | `--flag value` on the CLI | **this run**, highest precedence | one-off |

So: a default for everyone goes in layer 1; a fact about a cluster goes in 4 or
5; a single run changes nothing on disk at all. Nothing in layers 1–3 is
site-specific and nothing in 4–5 is run-specific — that split is the point.

Two consequences worth knowing:

* **A params file should be almost empty.** `conf/harvard_rc.yaml` — the file
  `$BIOBAKERY_NF_PARAMS` points at — is a list of commented-out settings, not a
  configuration you must complete. Everything a FASRC run needs is already a
  default of `-profile harvard_rc`. Restating database paths there is how the
  two drift apart.
* **A site profile should only override what genuinely differs.** Copying
  `base.config`'s resource numbers into a profile means a fix to a figure never
  reaches that site, and a plain `memory = '32.G'` also silently disables the
  retry escalation, because `base.config` scales every request by
  `task.attempt`.

To see what a profile actually resolves to, ask Nextflow:

```sh
nextflow config -profile harvard_rc | less
nextflow config -profile harvard_rc | grep humann
```

---

## Compute Profiles

Use `-profile <name>` to select the execution environment.

| Profile | Environment | Executor | Tool delivery |
|---|---|---|---|
| `standard` / `local` | Laptop / workstation | local | conda / system PATH |
| `tufts_hpc` | Tufts HPC | SLURM `batch` | Apptainer containers |
| `harvard_rc` | Harvard FASRC Cannon | SLURM `hsph` | hutlab module system |
| `amazon` | AWS | AWS Batch | ECR containers — **incomplete**, six processes only |

> The `harvard_rc` and `tufts_hpc` profiles also auto-load their respective `conf/databases/*.config`,
> so database paths are set automatically — override them on the CLI if needed.
>
> The `engaging` profile (MIT Engaging) was removed in v0.0.4: it named processes
> that no longer exist and had not been used since the port.

---

## Changing Databases

Every database path is a named parameter. Override on the command line without editing any file:

```sh
nextflow run main.nf -profile harvard_rc \
  --host_genome /n/lab_storage/huttenhower_lab/data/kneaddata_databases/mouse_C57BL \
  --readsdir /path/to/fastqs --outdir results
```

### Available databases on Harvard FASRC

| Tool | Reference | Path |
|---|---|---|
| KneadData | Human hg38 | `/n/lab_storage/huttenhower_lab/data/kneaddata_databases/hg38` |
| KneadData | Mouse C57BL | `/n/lab_storage/huttenhower_lab/data/kneaddata_databases/mouse_C57BL` |
| KneadData | Ribosomal RNA | `/n/lab_storage/huttenhower_lab/data/kneaddata_databases/ribosomal_RNA/SILVA_128_LSUParc_SSUParc_ribosomal_RNA_v0.2` |
| MetaPhlAn | `mpa_vJun23_CHOCOPhlAnSGB_202307` *(default)* | `/n/lab_storage/huttenhower_lab/tools/metaphlan4/rocky8/v4.1.1/lib/python3.10/site-packages/metaphlan/metaphlan_databases` |
| MetaPhlAn | `mpa_vOct22_CHOCOPhlAnSGB_202403` | `/n/lab_storage/huttenhower_lab/tools/metaphlan4/rocky8/v4.0.6_vOct_fixed/lib/python3.10/site-packages/metaphlan/metaphlan_databases` |
| HUMAnN 3.9 | ChocoPhlAn + UniRef90 | `/n/lab_storage/huttenhower_lab/tools/nextflow/databases/humann3` |
| HUMAnN 4 | nucleotide + protein | `/n/lab_storage/huttenhower_lab/tools/nextflow/databases/humann4` |

### Downloading databases

**KneadData:**
```sh
kneaddata_database --download host_genome bowtie2 /path/to/kneaddata_databases
```

**MetaPhlAn** (do not put multiple indexes in the same directory):
```sh
metaphlan --install --index mpa_vJun23_CHOCOPhlAnSGB_202307 \
  --bowtie2db /path/to/metaphlan_databases
```

**HUMAnN:**
```sh
humann_databases --download chocophlan full      /path/to/humann_db/chocophlan
humann_databases --download uniref uniref90_diamond /path/to/humann_db/uniref
humann_databases --download utility_mapping full /path/to/humann_db/utility_mapping
```

---

## Changing Resources

Per-process defaults live in `conf/base.config`. They scale with `task.attempt` (up to 2 retries).
Override for a specific cluster in the profile config, e.g. `conf/profiles/harvard_rc.config`.

**Edit a profile config** (permanent change for that cluster):

```groovy
// conf/profiles/harvard_rc.config
withName: humann {
    // the reason this site differs, in one line
    memory = { 64.GB * task.attempt }
}
```

Keep the `* task.attempt` form: a plain `memory = '64.G'` also disables the
retry escalation from `conf/base.config`, so a task killed for running out of
memory retries with exactly what killed it. Override only what genuinely
differs, and leave the rest to `base.config` — that way a fix to a resource
figure reaches every site.

**One-off override on the command line** (without editing files):

```sh
nextflow run main.nf -profile harvard_rc \
  --max_memory 64.GB --max_cpus 16 \
  --readsdir /path/to/fastqs --outdir results
```

> `--max_memory` / `--max_cpus` / `--max_time` set global caps applied by `check_max()` in `conf/base.config`.
> They don't set per-process values, but they cap any automatic scaling.

---

## Output Structure

```
results/
├── pipeline_info/
│   ├── versions.txt                               # Tool versions (kneaddata, metaphlan, humann, ...)
│   ├── db_paths.txt                               # Database paths used in this run
│   ├── execution_timeline_YYYY-MM-DD_HH-mm-ss.html
│   ├── execution_report_YYYY-MM-DD_HH-mm-ss.html
│   ├── execution_trace_YYYY-MM-DD_HH-mm-ss.txt
│   └── pipeline_dag_YYYY-MM-DD_HH-mm-ss.svg
│
├── kneaddata/                                     # (run_qc=true)
│   ├── merged/
│   │   └── kneaddata_read_count_table.tsv         # reads surviving each QC step
│   ├── ${SAMPLE}_kneaddata.log
│   ├── ${SAMPLE}_kneaddata_paired_1.fastq.gz      # (paired-end only)
│   ├── ${SAMPLE}_kneaddata_paired_2.fastq.gz
│   ├── ${SAMPLE}_kneaddata_unmatched_1.fastq.gz
│   └── ${SAMPLE}_kneaddata_unmatched_2.fastq.gz
│
├── metaphlan/                                     # (run_taxonomic_profiling=true)
│   ├── ${INDEX}/
│   │   ├── ${SAMPLE}_profile_${INDEX}.tsv         # species relative abundances
│   │   └── ${SAMPLE}_bowtie2_${INDEX}.tsv         # bowtie2 alignment stats
│   ├── bzip/
│   │   └── ${SAMPLE}_${INDEX}.sam.bz2             # compressed SAM (used by StrainPhlAn)
│   ├── merged_metaphlan_profiles.tsv              # all samples merged
│   └── merged/
│       └── metaphlan_species_counts_table.tsv     # species called per sample
│
├── humann/                                        # (run_functional_profiling=true)
│   └── ${H_VERSION}/
│       ├── ${SAMPLE}_genefamilies_${H_VERSION}.tsv
│       ├── ${SAMPLE}_pathabundance_${H_VERSION}.tsv
│       ├── ${SAMPLE}_pathcoverage_${H_VERSION}.tsv   # (humann_v37 only)
│       ├── regroup/                               # (run_humann_regroup=true)
│       │   └── ${SAMPLE}_${GROUPING}_${H_VERSION}.tsv
│       ├── rename/                                # (run_humann_rename=true)
│       │   └── ${SAMPLE}_${GROUPING}_named_${H_VERSION}.tsv
│       ├── merged/                               # (run_humann_merge=true)
│       │   ├── merged_genefamilies_${H_VERSION}.tsv
│       │   ├── merged_pathabundance_${H_VERSION}.tsv
│       │   └── merged_pathcoverage_${H_VERSION}.tsv
│       └── counts/
│           ├── humann_${FEATURE}_relab_counts.tsv     # features above zero, per sample
│           ├── humann_feature_counts.tsv              # the three feature types in one table
│           └── humann_read_and_species_count_table.tsv  # from the HUMAnN logs
│
├── baqlava/                                       # (run_viral_profiling=true)
│   └── ${SAMPLE}_baqlava/
│
├── strainphlan/                                   # (run_strain_profiling=true)
│   ├── markers/
│   │   └── ${SAMPLE}.pkl
│   └── ${CLADE}/
│       └── output/
│           ├── *.tre                              # phylogenetic tree
│           └── *.tsv                             # marker table
│
├── vis/                                           # (--workflow vis)
│   ├── mgx_report.html                            # or .pdf; all links relative
│   ├── figures/
│   ├── data/
│   └── alpha_diversity_plots/                     # (requires --input_metadata)
├── vis.zip                                        # the vis/ folder, archived
│
├── stats/                                         # (--workflow stats)
│   ├── stats_report.html                          # or .pdf; all links relative
│   ├── features/${TYPE}_features.txt              # taxonomy, pathways, ec
│   ├── maaslin2_${TYPE}/                          # taxa, pathways, ec
│   ├── halla_${TYPE}/
│   ├── mantel_test/mantel_plot.png
│   ├── beta_diversity/${TYPE}_{univariate,multivariate,pairwise}.png
│   ├── permanova/                                 # (--stats_random_effects set)
│   ├── stratified_pathways/
│   └── data/
├── stats.zip                                      # the stats/ folder, archived
│
└── [assembly workflow outputs]
    ├── assembly/main/${SAMPLE}/${SAMPLE}.final.contigs.fa
    ├── assembly/contig_depths/${SAMPLE}.contig_depths.txt
    ├── bins/${SAMPLE}/bins/*.bin.*.fa
    ├── checkm/
    │   ├── ${SAMPLE}/quality_report.tsv
    │   ├── merged_quality_report.tsv
    │   ├── n50/mags_n50.tsv
    │   └── qa/checkm_qa_and_n50.tsv
    ├── phylophlan/
    │   ├── phylophlan_out.tsv
    │   └── phylophlan_relab.tsv
    ├── sgbs/
    │   ├── mash/mash_dist_out.tsv
    │   └── sgbs/SGB_info.tsv
    └── final_profile.tsv                          # merged SGB abundance profile
```

---

## Testing

Everything test-related is under `tests/` — see [tests/README.md](tests/README.md).
Up to v0.0.4 it was split between `test/` and `tests/`; the two are now one.

| Directory | Contents |
|---|---|
| `tests/data/rawfastq/` | Two paired-end samples |
| `tests/data/single_end_rawfastq/` | `HD32R1_subsample.fastq.gz` — [bioBakery tutorial](https://github.com/biobakery/biobakery_workflows/tree/master/examples/tutorial/input) demo sample, plus one single-end read file |
| `tests/data/tutorial_output/` | Reference output from the upstream tutorial run |

### Integration suite

`tests/run_tests.sh` runs every workflow except 16s, in both library layouts,
against the real tool stack. On Harvard FASRC, submit it rather than running it
on a login node:

```sh
mkdir -p tests/results && sbatch tests/submit_tests.sh
```

| Test | Workflow | Layout | Covers |
|---|---|---|---|
| 1 | mgx | single | version log only, local executor |
| 2 | mgx | single | KneadData + MetaPhlAn + HUMAnN + chained report staging; `--run_stats true` without metadata skips cleanly |
| 3 | mgx | paired | the same, with metadata |
| 4 | mgx | paired | `--run_qc false`, i.e. pair merging |
| 5 | mtx | single | KneadData with the 3 metatranscriptome databases |
| 6 | mtx | paired | KneadData with the 3 metatranscriptome databases |
| 7 | mgx_mtx | paired | mapping file, both halves, RNA/DNA ratio, chained report staging |
| 8 | mgx_mtx | single | no mapping file, each half profiled separately |
| 9 | assembly | single | every stage runs on the bundled reads (no MAGs — see below) |
| 10 | assembly | paired | the same |
| 11 | vis | — | report from a bioBakery output folder |
| 12 | stats | — | MaAsLin2 / HAllA / mantel / beta diversity + report |
| 13 | assembly | paired | simulated reads: contigs → bins → CheckM2 → PhyloPhlAn → SGBs → profile |
| 14 | assembly | single | the same |
| 15-16 | — | — | the toggle and two-input guards |

The drivers run in parallel, each with its own launch and work directory; logs
and outputs land in `tests/results/<test name>{.log,/}`.

Two fixtures live outside the repository, because they are large and
reproducible from a seed rather than worth committing. Tests that need one are
skipped with a message when it is absent.

**vis / stats** (tests 11-12) — a bioBakery-output folder. Point
`VIS_STATS_FIXTURE` at it, or leave the default and regenerate:

```sh
python ~/biobakery_vis_stats_test/make_fixture.py --output input
```

**assembly** (tests 13-14) — reads simulated from two real genomes
(*Akkermansia muciniphila* and *Limosilactobacillus reuteri*), as two samples
with the mixture reversed so MetaBAT2 has differential coverage to bin on.
Point `ASSEMBLY_FIXTURE` at the folder holding `input_pe/` and `input_se/`, or
leave the default and regenerate:

```sh
cd ~/biobakery_assembly_test
python3 make_fixture.py --output input_pe            # ~620k read pairs
python3 make_fixture.py --output input_se --single
```

The generator downloads the two genomes once (about 1.3 MB) and caches them;
everything after that is deterministic given `--seed`.

The chained reports are asserted through `<outdir>/report_input/` — the
bioBakery-layout folder they are built from — not through the report itself:
two samples of a thousand reads cannot produce an ordination or a heatmap, so
vis legitimately fails on this data, and that failure is ignored by design. A
report with real content needs a real study.

Tests 9 and 10 stay on the bundled reads deliberately: those are host-dominated
enough that KneadData leaves about a thousand per sample, so MEGAHIT assembles
nothing, and they check that every stage runs and that the no-MAG path still
reaches a final profile. Tests 13 and 14 are the ones that exercise binning,
CheckM2, PhyloPhlAn and SGB clustering on actual MAGs.

### What CI checks

CI has no tools, no databases and no cluster, so it cannot run any of the above.
It runs what needs none of them:

```sh
bin/make_diagrams.py --check
```

This rebuilds every workflow's graph with `nextflow run -preview`, which
resolves the configuration and builds the DAG without launching a task, and
fails if `docs/workflow_reference.md` or `docs/diagrams/*.mmd` no longer match
the pipeline. It catches a config that does not parse, a broken `include`, a
channel wired to nothing, and documentation that has drifted from the code.
See `.github/workflows/ci-tests.yml`.

There is no nf-test suite any more. The two case files that used to be here
asserted a four-process pipeline and loaded params files that were not in the
repo, so they had not run since well before v0.0.4; they were removed rather
than rewritten, because what they were trying to assert needs the real tool
stack that `tests/run_tests.sh` already exercises.

---

## Project Status

The port from `biobakery_workflows` 3.2 (AnADAMA2) is **feature complete except
16s**. Every workflow below is verified on the real tool stack for single-end
and paired-end input by `tests/run_tests.sh` — 39 checks over 16 cases, all
green as of 2026-09-02.

> **The v0.0.4 cleanup changed layout, not behaviour.** What CI checks is green
> on the cleaned tree as of 2026-09-17 — all four profiles resolve
> (`nextflow config -profile local|harvard_rc|tufts_hpc|amazon`) and
> `bin/make_diagrams.py --check` reports the step reference and all six diagrams
> up to date — but the integration suite has not been re-run since, so the
> 39/39 figure above still dates from before it. What changed: `processes/` and
> the nf-test cases deleted; `test/` and `tests/` merged; params moved out of
> `nextflow.config` into `conf/params.config`; execution reports into
> `conf/reports.config`; site profiles reduced to real overrides;
> `template-params.yaml` folded into `conf/harvard_rc.yaml`;
> `conf/tufts_hpc.yaml` added; `docs/workflow_reference.md`,
> `docs/diagrams/` and `docs/dependencies.md` added. Re-run
> `sbatch tests/submit_tests.sh` before cutting a new module.

### Complete

| Area | What works |
|---|---|
| `mgx` | QC → taxonomy → function, both layouts, plus optional BAQLaVa and StrainPhlAn |
| `mtx` | the same on the metatranscriptome database set (host genome + host mRNA + rRNA) |
| `mgx_mtx` | both halves profiled and published separately, joined by the RNA/DNA relative expression ratio; with a mapping file the RNA samples reuse the DNA taxonomic profiles |
| `assembly` | MEGAHIT → MetaBAT2 → CheckM2 → PhyloPhlAn → Mash/SGB clustering → per-sample MAG abundance → merged profile |
| `vis` | the full report, standalone or chained onto a read-based run |
| `stats` | mantel, MaAsLin2 (+ figure tiles), HAllA, stratified pathway barplots, beta diversity / PERMANOVA, report and archive |
| Layout handling | detected per sample from the filenames; `--single_end` / `--paired_end false` force single-end; a folder mixing both works |
| QC bypass | `--run_qc false` merges each pair first, as `shotgun.merge_pairs` does upstream |
| Chained reports | built from the run's own channels into a bioBakery-standard folder (`<outdir>/report_input/`), so there is no `publishDir` race and no layout mismatch |
| Environments | every process has resource and module blocks for `-profile harvard_rc`; HAllA gets its own module, because it pins `numpy<2` |
| Deployment | `hutlab load rocky8/biobakery-workflows-nextflow/0.0.4`, verified end to end with the shipped params file |

### Not done

| Item | Notes |
|---|---|
| `16s` | still a stub — `--workflow 16s` errors. DADA2 / QIIME2 planned |
| Parity diff against upstream 3.2 | no section-by-section comparison of the vis/stats output yet. It needs a fresh upstream run first, and upstream 3.2 cannot itself complete a `stats` run on a standard wmgx folder (see [docs/vis_stats_port_status.md](docs/vis_stats_port_status.md), decision 6), so it has to be section by section rather than a diff |
| `--report_format pdf` | not exercised since the report links were made relative |
| Chained `stats` at scale | the chained path is wired and covered for `vis`; chained `stats` needs a study large enough for its analyses to fit, which the test data is not. Standalone `stats` is covered |
| MAG-level assembly test data | tests 13-14 use simulated reads from two genomes. Real multi-species data would exercise SGB clustering harder |
| Non-FASRC profiles | only `harvard_rc` sets a software environment per process. `tufts_hpc` and `local` expect the tools on `PATH`, and `aws` has containers for six processes out of ~59. Resources now come from `conf/base.config` everywhere, so that part is no longer per-profile work |
| Full suite run after the v0.0.4 cleanup | the cleanup is verified by `bin/make_diagrams.py --check`, the four input guards and a real `version_log` run; the 16-case suite has not been re-run since |

---

## Project Structure

```
biobakery-nextflow/
├── main.nf                              # Router: --workflow mgx|assembly|...
├── workflows/
│   ├── mgx.nf                           # MGX: QC → taxonomy → function (+ viral/strain optional)
│   ├── assembly.nf                  # MAG assembly → binning → SGB clustering
│   ├── mtx.nf                           # MTX: QC (3 kneaddata DBs) + taxonomy + function
│   ├── mgx_mtx.nf                       # Paired MGX+MTX + RNA/DNA ratio
│   ├── sixteens.nf                      # 16S stub
│   ├── vis.nf                           # Visualization report
│   └── stats.nf                         # Statistics
├── subworkflows/
│   ├── read_input.nf                    # input channel + per-sample layout detection
│   ├── reporting.nf                     # chained vis/stats at the end of a read run
│   ├── quality_control.nf               # KneadData (single + paired routing)
│   ├── taxonomic_profiling.nf           # MetaPhlAn + bzip + merge
│   ├── functional_profiling.nf          # HUMAnN + regroup + rename + merge
│   ├── viral_profiling.nf               # BAQLaVa
│   └── strain_profiling.nf              # StrainPhlAn (SGB mode)
├── modules/
│   ├── kneaddata/main.nf
│   ├── metaphlan/main.nf                # metaphlan + metaphlan_bzip + metaphlan_merge
│   ├── humann/main.nf
│   ├── strainphlan/main.nf              # sample2markers + strainphlan
│   ├── viral/baqlava/main.nf
│   ├── assembly/megahit/main.nf     # MEGAHIT assembly
│   ├── binning/metabat2/main.nf
│   ├── qc/checkm2/main.nf               # checkm2 + merge + n50 + wrangling
│   ├── phylogenomics/phylophlan_metagenomic/main.nf
│   ├── vis/                             # identify_inputs, alpha_diversity, add_ec_names, report
│   ├── stats/                           # feature_table, maaslin2, halla, mantel,
│   │                                    #   beta_diversity, covariate_equation,
│   │                                    #   stratified_pathways, report
│   └── utils/
│       ├── align_and_depth/main.nf      # Bowtie2 + jgi_summarize_bam_contig_depths
│       ├── archive/main.nf              # zip an output folder (ports workflow.add_archive)
│       ├── humann_merge/main.nf
│       ├── humann_regroup/main.nf
│       ├── humann_rename/main.nf
│       ├── mash/main.nf                 # sketch + paste + dist + sgb_cluster + merge_tax
│       ├── merge_pairs/main.nf          # concatenate a pair when QC is bypassed
│       ├── report_input/main.nf         # build the bioBakery folder vis/stats read
│       └── version_log/main.nf
├── nextflow.config                      # index only: the layering, profiles, manifest
├── conf/
│   ├── params.config                    # GLOBAL DEFAULTS — every parameter's default
│   ├── base.config                      # DEFAULT RESOURCES — per-process cpus/memory/time
│   ├── reports.config                   # RUNTIME — timeline/report/trace/dag files
│   ├── profiles/                        # SITE RUNTIME (-profile): executor, queue, tools
│   │   ├── harvard_rc.config            #   hutlab module system + SLURM hsph
│   │   ├── tufts_hpc.config             #   Apptainer + SLURM batch
│   │   ├── aws.config                   #   AWS Batch + ECR containers (incomplete)
│   │   └── local.config                 #   this machine
│   ├── databases/                       # SITE DEFAULTS (-profile): database paths
│   │   ├── harvard_rc.config            #   MetaPhlAn vOct22 + HUMAnN 4 stack
│   │   └── tufts.config                 #   MetaPhlAn vJun23 + HUMAnN 3.7 stack
│   ├── harvard_rc.yaml                  # THIS RUN — params template ($BIOBAKERY_NF_PARAMS)
│   └── tufts_hpc.yaml                   # THIS RUN — params template
├── bin/
│   ├── make_diagrams.py                 # generates docs/diagrams/ + workflow_reference.md
│   ├── scripts/                         # Python helpers (from anadama2 assembly_tasks/)
│   │   ├── checkm_wrangling.py
│   │   ├── mag_n50_calc.py
│   │   ├── mash_list_inputs.py
│   │   ├── phylophlan_add_tax_assignment.py
│   │   ├── checkm.py, checkm/           # vendored CheckM 1.2.0, coverage+profile only (GPLv3)
│   │   ├── biobakery_bootstrap.py       # puts the vendored layer on sys.path/PYTHONPATH
│   │   ├── biobakery_identify_inputs.py # input discovery → JSON manifest
│   │   ├── biobakery_vis_report.py      # vis report driver
│   │   ├── biobakery_stats_report.py    # stats report driver
│   │   └── ...
│   ├── lib/                             # vendored so the pipeline needs no anadama2
│   │   ├── biobakery_document.py        # anadama2 document.py (also the plotting library)
│   │   ├── biobakery_log.py
│   │   ├── anadama2_fallback/           # import stand-in for `import anadama2`
│   │   └── LICENSE-anadama2             # MIT
│   └── Rscripts/
│       ├── mash_clusters.R
│       └── merge_tax_and_abundance.R
├── assets/
│   ├── diagrams/                        # draw.io source files
│   ├── document_templates/              # vendored .pmd report templates
│   └── Rscripts/                        # only R scripts patched for the current R stack;
│                                        #   these shadow the biobakery_workflows copies
├── docs/
│   ├── workflow_reference.md            # GENERATED — diagram + step table per workflow
│   ├── diagrams/*.mmd                   # GENERATED — Nextflow's own DAG, per workflow
│   ├── dependencies.md                  # which module provides what, and the version pins
│   ├── architecture.md
│   └── vis_stats_port_status.md         # vis/stats port status and known divergences
└── tests/
    ├── run_tests.sh                     # the integration suite (16 cases, 39 checks)
    ├── submit_tests.sh                  # run it as a SLURM job
    └── data/                            # test FASTQ files + reference tutorial output
```

### Processes, modules, subworkflows, workflows

Four words that sound interchangeable, so: a **process** is Nextflow's unit of
execution — one tool invocation. A **module** is a file under `modules/` holding
one or more closely related processes and nothing else; modules are the only
place a `process` is defined. A **subworkflow** under `subworkflows/` wires
modules into a reusable stage (`QUALITY_CONTROL`, `TAXONOMIC_PROFILING`) with
`take:`/`emit:`, and is used by more than one workflow. A **workflow** under
`workflows/` is one entry point, selected by `--workflow`, and `main.nf` is only
the router between them.

There was also a top-level `processes/` directory up to v0.0.4, holding an
earlier flat copy of the KneadData, MetaPhlAn, HUMAnN and BAQLaVa processes. It
had been superseded by `modules/`, was imported by nothing, and is now deleted —
there is one definition of each process again.
