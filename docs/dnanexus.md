# DNAnexus configuration

The platform reference is DNAnexus's [Running Nextflow Pipelines](https://documentation.dnanexus.com/user/running-apps-and-workflows/running-nextflow-pipelines).
In particular, see [Docker caching](https://documentation.dnanexus.com/user/running-apps-and-workflows/running-nextflow-pipelines#built-in-docker-image-caching)
and [instance selection](https://documentation.dnanexus.com/user/running-apps-and-workflows/running-nextflow-pipelines#instance-type-determination).

The configuration follows the same division as Wellesley Hopper:

| File | Responsibility |
| --- | --- |
| `conf/profiles/dnanexus.config` | Docker images, queue size, process `machineType`, CPUs and memory |
| `conf/databases/dnanexus.config` | Reference paths inside the database-bearing images |
| `conf/example_yamls/dnanexus.yaml` | Study inputs, enabled analyses, MetaPhlAn references and HUMAnN mappings |

The `dnanexus` profile loads both config files. The YAML must be supplied separately.
The default run performs KneadData QC and read-count aggregation, then MetaPhlAn
profiling, SAM compression and profile merging, followed by HUMAnN functional
profiling and table processing. Viral and strain profiling, reporting, and
version logging remain disabled. `stop_after_qc` is false so profiling can
proceed and the run finishes normally. MetaPhlAn remains the intermediate stage
that supplies HUMAnN's taxonomic profile.

Without a YAML file, the profile uses the bundled primary Oct22 reference at
`/Databases/metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default`, with index
`mpa_vOct22_CHOCOPhlAnSGB_202403`. These defaults are in the database config.
The optional YAML runs MetaPhlAn against both Hopper reference variants and keeps
their output tables separate. Only the primary reference feeds HUMAnN by default.
HUMAnN's EC/KO/Pfam mappings are enabled in both the profile defaults and YAML.

## Project image cache

The profile has three configured images:

| Processes | Image | Override parameter |
| --- | --- | --- |
| KneadData and its read-count table | `public.ecr.aws/j5i5h1i5/kneaddata:latest-hg37dec` | `dnanexus_container` |
| MetaPhlAn, SAM compression and profile merging | `public.ecr.aws/j5i5h1i5/metaphlan:4.2.5-mpa_vOct22_202403` | `dnanexus_metaphlan_container` |
| HUMAnN and its table-processing steps | `public.ecr.aws/j5i5h1i5/humann:experimental` | `dnanexus_humann_container` |

The images have already been cached as Platform files under
`/.cached_docker_images/` in the destination project. Routine `dxbuild.sh` builds
reuse that cache through Nextaur's per-task lookup and omit `--cache-docker`.
There is no need to enter cache file IDs in the profile or study YAML.

A `--cache-docker` importer build also adds every image as an applet-wide bundled
dependency. That causes every task worker to download all three archives, roughly
182 GB in this deployment, even when it needs only one image. The runtime applet
is therefore built without these global image bundles. Each worker still needs
to download and load its selected database-bearing image.

The MetaPhlAn `4.2.5-mpa_vOct22_202403` image contains both reference variants at
the configured paths; replacement images must preserve those databases. The
`metaphlan_v4` CLI selector uses the supported `--db_dir`, `-x`, and `--mapout`
options for this image.

When populating the project cache, the installed SDK's `DockerImageRef._cache()` runs `docker pull`
on the DNAnexus build worker before `docker save` and upload. The local client
uploads the pipeline source and starts the Nextflow Pipeline Importer; it does
not export images from the workstation's Docker daemon. The supplied public ECR
reference is used directly for the initial test. For later tools, publish the
database-bearing Hopper images to an accessible registry and set their image
parameters. Preserve the internal `/Databases/...` layout. A similarly named upstream tool image without
the bundled databases is not interchangeable. Prefer release tags or digests.
Private registries use the documented `--docker-secrets` option.

To populate the cache or check registry images for updates, run
`bash dxbuild.sh --refresh-images`. The script stages the current source, runs
the cache importer, waits for success, and then builds the runtime applet without
global image bundles. `--cache-docker` is an alias for this complete sequence.
The importer can reuse existing cached files when their digests match.

After a successful import, the script reads the importer's selected image file
IDs and moves older cache files with the same folder/name into the refresh
folder's `superseded-images/` directory. This avoids ambiguous runtime lookup
after updating a mutable tag such as `experimental`. Files are retained by ID,
and unrelated cache names are left in place. An importer failure stops the
script before cache archiving or runtime applet creation. A failure while
archiving stops runtime applet creation; the selected new files remain cached.
Use separate version tags if older applets must continue resolving their
original images by tag. Avoid concurrent refreshes of the same project cache.

Building source alone does not refresh cached image contents. If an image is
absent from the project cache, Nextaur can fall back to the public registry when
outbound access is allowed. Fully qualified `dx://project-id:file-id` tarballs
remain an alternative.

Cache-refresh builds use `nextflow inspect` for discovery, which sees imported
process definitions even when their stages are disabled. The current cache has
KneadData, MetaPhlAn and HUMAnN; `stats_viz_container` remains unset. Supply a
stats/viz image before enabling reporting and rebuilding.
The profile uses `/opt/workflow` for helpers inside the stats/viz
image, matching Hopper. Assembly has instance assignments but still needs its
own tool images and references before it can run, as on Hopper.

## HUMAnN configuration

`public.ecr.aws/j5i5h1i5/humann:experimental` was verified against the local
database-bearing image and reports `humann v4.0.0.alpha.2`. The profile sets
`humann_version = 'humann_v4a'`, which selects its utility-database argument and
numbered output filenames. The databases remain inside the container:

| Parameter | Container path |
| --- | --- |
| `humann_db_chocophlan` | `/Databases/humann/chocophlan-v4-201901/chocophlan` |
| `humann_db_protein` | `/Databases/humann/chocophlan-v4-201901/uniref90_annotated` |
| `humann_db_utilitymapping` | `/Databases/humann/chocophlan-v4-201901/full_mapping` |

Regrouping uses `map_level4ec_uniclust90.txt.gz`, `map_ko_uniref90.txt.gz`, and
`map_pfam_uniref90.txt.gz` from the utility mapping directory. Their corresponding
name mappings are also bundled and enabled. The defaults produce per-sample
gene-family, reaction and pathway tables, EC/KO/Pfam regrouped and renamed tables,
relative abundance tables and merged matrices. These settings need no YAML.

Results are published beneath `results/humann/humann_v4a/` with the default
single reference, or `results/databases/<selected-index>/humann/humann_v4a/` with
the optional multi-reference YAML. Keep prior study YAML overrides aligned with
the new defaults: a supplied `run_functional_profiling: false` disables HUMAnN.

## Process instances

The directive is case-sensitive: `machineType`. All process subjobs use
`mem3_ssd2_v3_x16`, selected for this organization's deployment after the initial
`mem2_ssd2_v2_x8` instance was rejected for missing contractual pricing.
Per-process CPU and container memory limits remain:

| Process group | Task CPUs | Task memory |
| --- | --- | --- |
| Default helpers | 2 | 6 GB |
| Small table/formatting steps | 1 | 6 GB |
| Version log | 1 | 1 GB |
| MetaPhlAn including SAM compression; HUMAnN including per-sample table processing | 16 | 28 GB |
| KneadData, optional viral/strain tools, alignment/binning | 8 | 28 GB |
| HUMAnN cohort table merges, standalone table utilities, assembly summaries, HAllA | 4 | 14 GB |
| Other statistical analyses | 2 | 14 GB |
| Report rendering | 4 | 28 GB |
| MEGAHIT and PhyloPhlAn | 16 | 56 GB |

These are initial AWS sizes from the [DNAnexus instance list](https://documentation.dnanexus.com/developer/api/running-analyses/instance-types),
not measured requirements for this study. Check availability in the destination
project and allow enough scratch space for database image extraction, staged
reads and intermediates. Change the relevant selector in the profile to tune a
process. For example:

```groovy
withName: humann {
    machineType = 'mem3_ssd2_v3_x16'
    cpus = 16
    memory = '28.GB'
    time = '12.h'
}
```

`machineType` chooses the subjob instance; it does not change the head job.
`cpus` still supplies tool thread counts and `memory` still limits the container.
Adjust all three together when resizing. Fixed CPU/memory limits override the
base profile's attempt-based scaling, so retries cannot outgrow their pinned
instances. Time limits and retry policy still come from `conf/base.config`.
The generic `max_*` parameters do not resize these fixed assignments.

## Task boundaries and CPU measurements

All profiles now run SAM compression inside each MetaPhlAn sample/reference
task. Each HUMAnN sample/reference task also performs every configured regroup,
optional rename, and relative-abundance normalization. One subsequent task per
database merges all raw and relative-abundance tables across samples. Samples
remain independent and can run in parallel; published paths and matrix labels
are preserved. Table utilities run sequentially within the task so several
mapping databases do not multiply peak memory.
The Nextflow modules generate these tool commands directly in Groovy and place
them in the task's shell script; there are no intermediate Python wrappers or
JSON command manifests for HUMAnN postprocessing or cohort merging.

For the three-sample, single-reference run `job-JFPggK00Kg1v3KBpkbQGQV05`,
these boundaries reduce the planned task count from 57 to 12: three QC tasks,
one QC count task, three MetaPhlAn tasks, one taxonomy merge, three HUMAnN tasks,
and one functional-table merge. This is a task-count comparison, not a measured
cloud speedup. The bundled tasks have coarser retry/resume boundaries: a failed
table transformation retries that sample's complete HUMAnN task.

The completed run's execution report recorded `--nproc 8` and `--threads 8`.
HUMAnN averaged 756–759% CPU during execution (about 7.6 cores). MetaPhlAn
averaged 183–200% (about two cores). The low whole-worker CPU samples taken
during lengthy initialization do not measure just the tool. For example, the
first MetaPhlAn task had 1m44s of command execution inside a roughly 26-minute
worker job. The generated trace now includes `duration` and `%cpu`, alongside
`realtime` and `cpus`, to distinguish these measurements.

Thread counts are never fixed in the tool commands: they interpolate
`task.cpus`. Tune the relevant site's process selector to change them. The
DNAnexus profile sets both profilers to 16 CPUs on its 16-core instance; other
profiles retain their own resource settings. CPU percentages in Nextflow's
report count one fully occupied core as 100%; a thread setting does not imply
every phase of a tool will occupy every core.

## Cache-refresh worker disk

Separate cache-refresh builds run Docker caching in the Nextflow Pipeline Importer build job. Its default
`mem1_ssd1_v2_x4` worker has 100 GB of disk. This is separate from the generated
pipeline's head job and the process instances selected by `machineType`.

The local KneadData, MetaPhlAn and HUMAnN images total about 213 GB unpacked.
Docker also needs room for image archives and temporary layers. The
`mem1_ssd2_v2_x4` instance has 320 GB; `mem1_ssd2_v2_x8` has 640 GB and provides
more headroom for caching all three. See the
[instance specifications](https://documentation.dnanexus.com/developer/api/running-analyses/instance-types).

The installed SDK's `dx build --nextflow --cache-docker` path does not expose an
importer instance override. `dxbuild.sh --refresh-images` therefore uploads the
staged source and invokes `nextflow_pipeline_importer` directly with
`--instance-type`. The default importer is `mem1_ssd2_v2_x8`, independent of the
runtime head and process workers. To choose another importer:

```bash
bash dxbuild.sh --refresh-images --build-instance-type mem1_ssd2_v2_x4
```

The 320 GB option has less room for archives and temporary layers. Each refresh
uses a unique `.cache-refresh/<timestamp>-<token>/` folder beneath the applet
destination for uploaded source, the intermediate bundled applet, and archived
superseded image files. The final runtime applet is built in the normal
destination. The intermediate applet is not the one to launch for analysis.

## Head-node disk and image-loading failures

Nextaur 1.17 loads cached images on the head node while generating task launchers,
in addition to loading the selected image on each task worker. The default
`mem2_ssd1_v2_x4` head has 150 GB of disk. The cached MetaPhlAn archive is about
74 GB and its unpacked image about 100 GB, so they cannot both fit there.

The runtime's `docker load | sed` pipeline can mask a failed load. An empty load
result can lead to an unfiltered `docker images` lookup and substitute an already
loaded image's digest into another task's launcher. This is consistent with the
observed MetaPhlAn task trying to run the KneadData digest and failing before
MetaPhlAn starts. The terminated run did not retain its task launchers, so the
original `docker load` stderr could not be recovered.

`dxbuild.sh` sets the head's `main` entry point to `mem1_ssd2_v2_x8`: 640 GB disk,
16 GiB RAM and eight cores. Disk capacity drives this choice. The archives total
about 182 GB and the unpacked images about 213 GB before shared-layer savings,
so the 320 GB `mem1_ssd2_v2_x4` is too tight. The head does not need the 128 GiB
RAM of the `mem3_ssd2_v3_x16` task workers. To choose a different head:

```bash
bash dxbuild.sh --head-instance-type mem3_ssd2_v3_x16
```

The `DNANEXUS_HEAD_INSTANCE_TYPE` environment variable remains supported;
the CLI option takes precedence. This changes the runtime head, not the cache-refresh importer. The extensionless
archive unpack warnings occur before Nextaur's Docker-loading step and do not
by themselves establish image corruption. For troubleshooting, enable
`preserve_cache` at launch so generated task wrappers remain available.

## Build and run

Build with the `dnanexus` profile defaults. No samplesheet is required or bound
at build time:

```bash
bash dxbuild.sh
```

Populate or refresh images and build the runtime applet in one command:

```bash
bash dxbuild.sh --refresh-images
```

No applet, uploaded source, or cache wipe is required. Update registry image
references in `conf/profiles/dnanexus.config` before refreshing if using new tags.
To customize both build stages:

```bash
bash dxbuild.sh --refresh-images \
  --build-instance-type mem1_ssd2_v2_x8 \
  --head-instance-type mem1_ssd2_v2_x8 \
  --destination project-JBVGpB00Kg1xBf54v05BXj6f:/Applets/wmgx/
```

`bash dxbuild.sh --help` lists all options, including `--profile`,
`--nextflow-version`, and `--docker-secrets` for private registry credentials
during refresh. Additional `dx build` arguments can follow `--`; options that
would bypass the source-only runtime build are rejected. Refresh mode starts a
billable importer job; ordinary mode does not start an image-cache importer.

Run the script with `bash dxbuild.sh` rather than pasting or sourcing its contents
into your interactive shell. Each build prints a log path under `/tmp` (or
`TMPDIR`) and saves its output there. On failure, an interactive run waits for
Enter before closing; noninteractive runs return the original error status.

`dxbuild.sh` selects the `dnanexus` profile, gives the head sufficient disk, and
builds without global Docker image bundles. Existing applets of the same name
are archived rather than deleted; the new applet is placed in `/Applets/wmgx/`.
The profile supplies the KneadData-to-HUMAnN settings. No run inputs are chosen
during the build.

The script stages the pipeline entrypoint, configuration, modules, subworkflows,
workflows, `bin/`, and `assets/` in a temporary source directory. It includes local
edits and new runtime files, then removes the staging directory after the build.
This avoids the importer's recursive upload of the whole checkout: `.git`, local
samplesheets, tests, container archives, work directories and results are excluded.
The cached-build source upload does not consult `.gitignore`; staging also keeps the routine source-only resource bundle small.

Upload your samplesheet and select it in the applet's launch form. The CLI
equivalent, using the file you choose, is:

```bash
dx run applet-xxxx \
  -isamplesheet=project-xxxx:file-samplesheet \
  -ipreserve_cache=true \
  --destination project-xxxx:/results/
```

Leave **Soft Configuration Files** empty for the default run. The applet already
contains `nextflow.config`, `conf/params.config`, and the DNAnexus profile/database
configs. Uploading these separately relocates each file: a relative include such
as `includeConfig 'conf/params.config'` then resolves beneath the downloaded input
folder instead of the pipeline source, causing a missing-config error. Use soft
configs only for additional, self-contained overrides.

The example YAML is optional. To override analysis selections, upload your copy
and additionally pass `-inextflow_params_file=project-xxxx:file-yaml` at launch.
It contains no default samplesheet.

Per-sample profiles are published under `results/metaphlan/<index>/`. The default
single-reference run publishes `merged_metaphlan_profiles.tsv` directly under
`results/metaphlan/` and compressed SAMs under `results/metaphlan/bzip/`. With the
optional multi-reference YAML, merged tables and `bzip/` folders are published
separately under each index. Only cleaned reads from KneadData enter MetaPhlAn.

Inside YAML and CSV files, Nextflow file paths use project-path URIs such as
`dx://project-xxxx:/inputs/reads/sample_R1.fastq.gz`. The samplesheet generator
uses each FASTQ's project folder and filename to produce these paths. The
`dx://project-xxxx:file-yyyy` object-ID form causes a null-path error in Nextaur's
filesystem parser; regenerate older samplesheets that contain it. Docker tarball
references have separate handling and may still use that object-ID form.
For applet file-class inputs on `dx run`, use `project-xxxx:file-yyyy`.
`outdir` remains relative to the job's output destination. Direct applet inputs
override YAML values. The schema does not expose array parameters: the lists of
MetaPhlAn databases, downstream indices and HUMAnN mappings travel in the YAML.

For a local configuration check, choose a local samplesheet explicitly:

```bash
NXF_VER=25.10.4 nextflow config -profile dnanexus -o json
NXF_VER=25.10.4 nextflow run main.nf -profile dnanexus \
  -params-file my-dnanexus-run.yaml --samplesheet local-samplesheet.csv -preview
```

Preview checks workflow construction and selections. It does not test registry
access, instance availability or execution by DNAnexus.
