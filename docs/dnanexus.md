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
| MetaPhlAn, consensus markers, StrainPhlAn and profile merging | `public.ecr.aws/j5i5h1i5/metaphlan:4.2.5-mpa_vOct22_202403` | `dnanexus_metaphlan_container` |
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

## Database-free profiling with dxfuse

The `dnanexus_dxfuse` profile currently runs only database-free KneadData and its
read-count aggregation. MetaPhlAn and HUMAnN are disabled. Image references are
parameters in `conf/profiles/dnanexus_dxfuse.config`:

| Parameter | Tasks using the image |
| --- | --- |
| `dnanexus_container` | KneadData and read-count helpers |
| `dnanexus_metaphlan_container` | Unset: MetaPhlAn is disabled |
| `dnanexus_humann_container` | Unset: HUMAnN is disabled |

KneadData uses `public.ecr.aws/j5i5h1i5/kneaddata:0.12.1-nodb-dnanexus-r1`.
The two disabled tools' image parameters are explicitly null because cache
discovery sees imported processes even when disabled. This profile therefore
caches exactly one tool image. The image provides a mount entrypoint implementing
`DXFUSE_ENABLED` and `DX_REFERENCE_*` as described below. The default reference mode
is now `download`: the worker stages project files on local SSD before starting
Docker and disables the image's FUSE entrypoint hook. The existing image is
unchanged; rebuild source using the existing project image cache:

```bash
bash dxbuild.sh --profile dnanexus_dxfuse
```

This transfer uses only the worker's installed SDK and project-resident data.
No runtime package installation, public database server, or extra allocation is
involved. DNAnexus [restricted-network environments](https://documentation.dnanexus.com/developer/apps/execution-environment#networking)
retain access to project data and the API. The image must already be cached for
production without outbound access.

After deleting the project cache, rebuild it and the runtime applet with:

```bash
bash dxbuild.sh --profile dnanexus_dxfuse --refresh-images
```

Select your uploaded samplesheet when launching the applet; no YAML is required
for the KneadData-only defaults. Optionally supply
`conf/example_yamls/dnanexus_dxfuse.yaml` to customize the reference project/folder.
Both this YAML and `dnanexus_dxfuse_smoke.yaml` keep downstream profiling disabled.
Leave additional Nextflow config inputs empty. No samplesheet is selected during
the build. The run finishes normally after QC and read-count aggregation.

The opt-in `dnanexus_dxfuse_full` profile enables QC, taxonomic and functional
profiling, plus StrainPhlAn and BAQLaVa, with the same local staging. Its image references match these catalog definitions in
`biobakery-containers`:

| Catalog ID | Image tag (repository:tag) |
| --- | --- |
| `metaphlan-425-nodb-dnanexus` | `metaphlan:4.2.5-nodb-dnanexus-r1` |
| `humann-experimental-nodb-dnanexus` | `humann:4.0.0-experimental-nodb-dnanexus-r1` |
| `baqlava-120` | `baqlava:4.0.0-r1` |

The new contexts are `packages/metaphlan/4.2.5/nodb-dnanexus` and
`packages/humann/4.0.0a-dev/nodb-dnanexus`. They preserve MetaPhlAn 4.2.5 and the
existing HUMAnN `9cb1a82` checkout, with no reference tarball copied into either
image. Both use the same entrypoint and `/Databases` symlink contract as KneadData.
The catalog enables ECR publication and local archiving and leaves GHCR disabled.

Once the images are built/published, cache all four and build the full runtime
applet. The full profile expects the HUMAnN archive listed below and extracted
KneadData, corrected MetaPhlAn and BAQLaVa references to be uploaded and closed
before launch:

```bash
bash dxbuild.sh --profile dnanexus_dxfuse_full --refresh-images
```

Choose your uploaded samplesheet; the optional
`conf/example_yamls/dnanexus_dxfuse_full.yaml` shows full-run overrides. The
KneadData-only YAML deliberately disables profiling, so do not use it for a full
run. Existing `dnanexus_dxfuse` defaults stay QC-only.

If all four images are already cached, the archive-staging code needs only a
source rebuild; no image changes or image refresh are required:

```bash
bash dxbuild.sh --profile dnanexus_dxfuse_full
```

### Archive staging

The full profile supplies these `dnanexus_reference_archives` mappings:

| Archive in the project | Extraction root inside the task |
| --- | --- |
| `/Databases/tarballs/chocophlan-v4-201901.tar.gz` | `/Databases/humann/chocophlan-v4-201901/` |

The HUMAnN archive retains its original internal layout: `chocophlan/`,
`uniref90_annotated/` and `full_mapping/`. Do not add an enclosing directory.
MetaPhlAn and StrainPhlAn instead download the corrected extracted project
folder `metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default/`. The older
MetaPhlAn tarball is deliberately excluded: its duplicate viral references
caused marker extraction failures in the bundled-image run.
BAQLaVa downloads the two extracted folders below `baqlava/BAQLaVa_v05/` and
uses the HUMAnN archive for all three depletion references.

Each analysis allocation downloads only the archive(s) covering its required
references. It downloads each archive once, extracts it with the worker's `tar`
on local SSD, and verifies the required directories and mapping files before
exposing the extracted tree to Docker. HUMAnN's three reference directories and
their mappings share one archive download. The compressed file is deleted after
successful extraction. Allow local disk space for both the archive and its
extracted contents during staging. Plain `.tar` and gzip-compressed archives
are supported; no runtime package installation is needed.

An archive is transferred and extracted in full, including any unselected
databases it contains. Separate MetaPhlAn tasks using the same bundle each stage
their own copy; there is no persistent cache shared across allocations.
References outside the archive mappings retain directory/file downloads.
The QC-only `dnanexus_dxfuse` profile has an empty archive list and preserves its
working KneadData directory download.

Override archive locations in the run YAML, for example:

```yaml
dnanexus_reference_archives:
  - archive: tarballs/chocophlan-v4-201901.tar.gz
    extract_to: humann/chocophlan-v4-201901
```

`archive` is relative to `dnanexus_reference_folder` in the reference project;
`extract_to` is relative to the task's `/Databases` tree. Archive members are
extracted below that root without stripping path components. A supplied list
replaces the profile defaults. Set `dnanexus_reference_archives: []` to use
extracted project directories for every reference. A missing archive, failed
transfer, corrupt archive or missing expected path stops staging with status 74
before analysis starts; there is no automatic fallback to project directories.
FUSE mode ignores archive mappings and requires extracted project directories.

For references without an archive mapping, a worker-side `beforeScript` uses
`dx download --recursive` for directories and `dx download` for individual
mapping files. KneadData uses its actual reference input list
(the host genome for MGX). Each MetaPhlAn task uses its own resolved database
directory, even when the YAML requests several databases in parallel. HUMAnN
uses its nucleotide, protein and utility-mapping directories; custom container
mapping files outside those directories are fetched individually. Mappings
declared as host inputs are already staged by Nextflow and are not downloaded
again. Parent-folder transfers cover any selected files/child folders underneath
them, avoiding duplicate downloads. For the default KneadData path, the transfer
is the six files under project folder `/Databases/kneaddata`.
Files are first downloaded into a temporary directory and
placed in the local reference tree after a successful transfer. A failure exits
with status 74 before Docker or analysis starts. The SDK checks downloaded parts.

The files live under the allocation's scratch directory at
`.reference-cache/Databases/`. Docker mounts that directory read-only at
`/tmp/dxfuse/Databases`; the image's `/Databases` symlink preserves tool paths.
BAQLaVa uses a direct read-only `/Databases` bind because its image has no such
symlink.
The FUSE daemon is disabled, no FUSE device/capabilities are requested, and no
platform credentials are forwarded into the analysis container in download mode.
The read-count merge skips reference staging. Task resources remain inherited
from the existing DNAnexus configuration: one KneadData allocation and one
HUMAnN allocation per sample, with MetaPhlAn per sample/database. HUMAnN
regrouping, renaming and normalization share the mounted profiling allocation.
Merge helpers skip reference staging. No reference files are published with results.

These worker download hooks and reference bind mounts are configured only in
`conf/profiles/dnanexus_dxfuse.config`. It is included by `dnanexus_dxfuse` and
`dnanexus_dxfuse_full` only. The ordinary `dnanexus`, local, AWS Batch, Hopper and
SLURM profiles do not acquire this behavior. The module reference-check hook is
optional and empty in those other profiles. Offline config tests verify that
the staging directives are absent from all eight existing non-staging profiles.

For a controlled comparison, select `dnanexus_reference_mode: fuse` in your run
YAML. That mode forwards the worker's credentials/API context by variable name,
requests the FUSE device/capability and root user, and lets the entrypoint mount
the project folder. The shared FUSE configuration for MetaPhlAn and HUMAnN is
shared with the full profile. In the QC-only profile those tools remain disabled
with no configured images.

Both modes expose the same tool paths:

The QC-only profile uses `host_genome`; the full profile uses all these paths.

| Parameter | Path inside each task container |
| --- | --- |
| `host_genome` | `/Databases/kneaddata` |
| `metaphlan_db` | `/Databases/metaphlan/mpa_vOct22_202403/mpa_vOct22_202403_default` |
| `humann_db_chocophlan` | `/Databases/humann/chocophlan-v4-201901/chocophlan` |
| `humann_db_protein` | `/Databases/humann/chocophlan-v4-201901/uniref90_annotated` |
| `humann_db_utilitymapping` | `/Databases/humann/chocophlan-v4-201901/full_mapping` |
| `baqlava_db_nucleotide` | `/Databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.nucleotide` |
| `baqlava_db_protein` | `/Databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.protein` |

All profiling tools keep `*_db_location = 'container'`, meaning the path is available
inside the task, from either a local bind mount or FUSE. The selected project
folder must contain the configured archives, or the extracted database tree for
references downloaded as directories: KneadData indexes, MetaPhlAn indexes and
metadata, HUMAnN nucleotide/protein references and utility mapping files. Outputs
and scratch files remain outside the read-only reference tree.
The FUSE profile overrides `host_genome` because this project's Bowtie2 files are
directly in `kneaddata/`. The database-bearing image profile retains its nested
`kneaddata/hg37dec` path.

Configure the run YAML with, for example:

```yaml
dnanexus_reference_project: project-YOUR_REFERENCE_PROJECT
dnanexus_reference_folder: /Your/path/Databases
```

Omit the project override to use the worker's `DX_PROJECT_CONTEXT_ID`. The source
folder corresponds to the container's `/Databases` tree. Relative archive paths
or uncovered database paths are appended to that source folder. Only references
needed by the current task are staged. Project, source-folder and archive-mapping
overrides need no rebuild.
Changing `dnanexus_reference_mountpoint` requires updating all applicable tool
database paths to `<mountpoint>/Databases/...`, since the image symlink uses the
default mountpoint. Keep the default `/tmp/dxfuse` unless needed.

In download mode, the worker log reports `[references] local SSD download started`
and `completed in ... seconds`. These timing messages are also copied into the
analysis task's `.command.err`. Archive downloads and extraction also have
separate elapsed-time messages in that log. Container checks then report `local database
directories verified; FUSE is disabled for this task.` After successful KneadData
execution, `[kneaddata] analysis completed in ... seconds` records analysis time
separately from staging. Compression and publication follow afterward.

In FUSE mode, each analysis task's command error output should
contain `DNAnexus references: ready at /tmp/dxfuse/Databases`, followed by tool
execution and published outputs. Config resolution and Docker command construction
are tested locally; local download was also validated by the cloud run below.
[dxfuse](https://github.com/dnanexus/dxfuse) provides
read-only, on-demand access, so a smaller image moves database I/O into execution
rather than eliminating it.

For later source-only rebuilds, keep `--profile dnanexus_dxfuse` and omit
`--refresh-images`. Plain `bash dxbuild.sh` continues selecting `dnanexus`.

Local staging completed successfully in run `job-JFVKg4j0Kg1jK9qYG83pjf7X`
on 2026-10-29. All three samples and the read-count merge succeeded, publishing
20 files (QC outputs, merged counts and pipeline reports). Worker logs recorded:

| Sample | Project-to-SSD download | KneadData analysis |
| --- | --- | --- |
| TEST01 | 11 s | 107 s |
| TEST02 | 13 s | 50 s |
| TEST03 | 10 s | 48 s |

For TEST03, the interval between `Decontaminating ...` and `Running bowtie2 ...`
fell from 1,183 s in direct-FUSE run `job-JFVK3Y00Kg1Q8xY2jJgFyJP4` to 24 s
with local staging, about 49 times faster for that logged phase. Both workers
used the same image digest and instance type, and reported 178,426 cleaned
paired R1 reads. The local-staging workflow took 18m47s from submission to
completion, including allocation and initialization; its reported head-job
runtime was 16m47s. The FUSE workflow was terminated after TEST03 completed, so
these observations do not establish an end-to-end workflow speedup ratio.

### StrainPhlAn and BAQLaVa

`dnanexus_dxfuse_full` enables StrainPhlAn by default. The ordinary `dnanexus`
profile can opt in with `run_strain_profiling: true`; the QC-only profile keeps
it disabled. Batching has not been introduced.

Each selected MetaPhlAn sample/database task now extracts consensus markers from
its uncompressed SAM before compression, using the exact database `.pkl` file.
There is no separate per-sample marker allocation or additional database transfer.
Markers are published under `strainphlan/markers/` (under `databases/<index>/`
when multiple databases are configured). MetaPhlAn 4.2 JSON/BZip2 and earlier
Pickle marker outputs are accepted, with the original sample IDs preserved.

The cohort task runs in the MetaPhlAn image, with the same project-to-SSD archive
staging and read-only reference mount. It uses the originating database metadata
and adjacent Bowtie2 indexes, independently for each selected database. An
optional `strainphlan_db` overrides the `.pkl` path; that file and its indexes must
be present together. No `latest` database resolution or external download is used.

The [StrainPhlAn 4.2.5 implementation](https://github.com/biobakery/MetaPhlAn/blob/4.2.5/metaphlan/strainphlan.py)
requires at least four samples. Smaller cohorts retain their published consensus
markers and log a warning without allocating a phylogeny worker. Four samples
are necessary but do not guarantee enough marker coverage for a tree.
With `strainphlan_clades` unset or `all`, discovery and sequential construction
of eligible clade trees share one cohort allocation and one database staging.
If no clades qualify, the discovery table is published without trees. Explicit
comma-separated clades (or a YAML list) create independent tasks per clade.
Genuine tool failures propagate instead of being reported as successful skips.

`strainphlan_marker_in_n_samples_perc` controls the marker-presence percentage
(default 50). It replaces the ambiguous `strainphlan_marker_in_n_samples`
workflow setting. The module selects the older CLI spelling for the configured
MetaPhlAn 4.0.6 contract. DNAnexus strain workers retain 8 CPUs and 28 GB requested
memory on `mem3_ssd2_v3_x16`.

The full profile enables BAQLaVa in its separate software image,
`public.ecr.aws/j5i5h1i5/baqlava:4.0.0-r1`, through
`dnanexus_baqlava_container`. The ordinary `dnanexus` and QC-only profiles keep
viral profiling disabled. Full-profile defaults include:

```yaml
run_viral_profiling: true
baqlava_db_nucleotide: /Databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.nucleotide
baqlava_db_protein: /Databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.protein
baqlava_depletion_db: /Databases/humann/chocophlan-v4-201901/chocophlan
```

The [BAQLaVa CLI](https://github.com/biobakery/baqlava/blob/master/baqlava/baqlava.py)
uses `--nucdb` and `--protdb`; it has no general `--database` flag. The installed
1.2 image already supplies its annotation tables and does not expose
`--nucindex` / `--protindex`; leave the mapping parameters unset. Those parameters
remain available for older images that support them. `baqlava_db` is an optional shorthand root
containing the upstream `BAQLaVa.V0.5.nucleotide` and `.protein` folders.

BAQLaVa calls HUMAnN internally for bacterial depletion. Its image must include
a compatible HUMAnN installation and configure its nucleotide reference to the
same reference as `baqlava_depletion_db`, either at that path or through a
read-only bind alias. Optional `baqlava_depletion_protein_db` and
`baqlava_depletion_mapping_db` declare additional HUMAnN references required by
the image. The task checks these using `humann_config --print` and directory
identity and exits with status 78 on a mismatch. It does not
modify the installed configuration. `baqlava_bypass_depletion: true` deliberately
skips depletion and its reference requirement; it is not enabled automatically.
BAQLaVa's small utility files and all other dependencies must be installed in
the image before production execution without outbound access.

The worker stages viral references, optional annotation files and the depletion
reference in the same BAQLaVa allocation, using the existing archive mappings
where applicable and directory/file downloads otherwise. Add a BAQLaVa archive
mapping only after uploading its real archive; a supplied archive list replaces
the defaults, so retain the HUMAnN entry. In download mode the worker binds
its staged tree directly at `/Databases` for BAQLaVa. This ordinary Micromamba
image needs neither dxfuse nor the other images' `/Databases` symlink. The
profile's FUSE comparison mode requires images with the FUSE entrypoint; use
`download` for the full profile's BAQLaVa image. All BAQLaVa internal steps share the allocation with
`--local-jobs 1`; requested CPUs are forwarded through `--threads`.
It requests 16 CPUs and 56 GB memory on the existing `mem3_ssd2_v3_x16`, allowing
for the HUMAnN memory requirement already observed on HPC.

After source edits, rebuild with `bash dxbuild.sh --profile dnanexus_dxfuse_full`.
The StrainPhlAn changes reuse the MetaPhlAn image already cached; no image refresh
is needed for that stage. Adding or updating the BAQLaVa image requires an image refresh. No runtime package/database downloads from
external sites are introduced.

### Diagnosing image downloads and missing references

Distinguish the head log from one worker's initialization log. The head prepares
tasks for all three images. Seeing all three cache lookups there does not by
itself show that every worker downloads all three. If an individual worker logs
`Downloading bundled file` for all three tool images, inspect the applet used by
the run: the intermediate cache-import applet bundles images globally, while
`dxbuild.sh` builds a separate final runtime applet without those bundles. Launch
the final applet in the normal destination rather than the intermediate applet
under `.cache-refresh/`. Check the job's actual applet ID, not just its name.

The profile inserts a reference check at the start of each analysis task's
`.command.sh`, inside the container after its entrypoint. It verifies readable
database directories; FUSE mode also verifies the mountpoint.
Missing mounts and missing directories exit with status 72 before tool execution.
By default, `dnanexus_reference_diagnostics: true` also prints the image,
reference project and source folder, `/Databases` symlink and filesystem type to
`.command.err`. It never prints credential values. Set that parameter to false
to suppress the extra details while retaining the checks.

Look for `[dxfuse] mount and database directories verified.` in each analysis
task's `.command.err`. `expected FUSE mount is absent` points to startup or mount
location settings. `database directory missing or unreadable` means the mount
check passed, but the tool paths or selected project/folder need investigation.
These checks verify directories; the tools still validate individual index files.

For FUSE mode, if the image entrypoint itself fails, these checks cannot execute. Read the
entrypoint's error in `.command.err` and its `dxfuse.log` path, if reported. The
proposed entrypoint stores daemon state under `/tmp/dxfuse-state.*` inside the
container; those files are not automatically published by the workflow and can
be lost when it exits. Retaining the daemon log on a startup failure requires
support from the image entrypoint or inspection while the container is alive.

The failed task's `.command.run` shows the actual Docker invocation. Confirm its
selected image and reference settings: download mode has `DXFUSE_ENABLED=false`
and a read-only local volume, while FUSE mode has its device/capability,
`DXFUSE_ENABLED=true`, and forwarded environment variable names. Do not enable shell
`set -x` or dump the environment: that can disclose job credentials.

In run `job-JFVGp4Q0Kg1p0Z6Z2k6GPpv7`, both issues were verified: it launched
intermediate applet `applet-JFV9pG80gZ0Fk62YFZ4VBkv9` under `.cache-refresh/`,
and its KneadData worker downloaded the KneadData, HUMAnN and MetaPhlAn bundles.
The local build log showed that caching succeeded, then a shell syntax error
stopped the final runtime build. `dxbuild.sh` now checks the whole file's syntax
before any cloud operation and prints the final runtime destination on success.
The worker reported a successful FUSE mount, then failed the directory check:
the index files were at `/Databases/kneaddata/hg37dec_v0.1*.bt2`, without the
extra `hg37dec/` directory. The FUSE profile's corrected `host_genome` matches
that layout. At inspection, this project's `/Databases` contained only KneadData;
MetaPhlAn and HUMAnN references must also be supplied for a full run.

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
