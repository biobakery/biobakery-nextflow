# Configuration and site setup

Choose one site with `-profile`, copy its YAML from `example_yamls/`, and set
the inputs and output for your study. Paths below are relative to this folder.
The YAML is loaded only with `-params-file`; profiles load their `.config` files
automatically.

| Layer | File | What belongs here |
| --- | --- | --- |
| Common parameters | [`params.config`](params.config) | Workflow, input, analysis and reference-location defaults |
| Common resources | [`base.config`](base.config) | Process CPUs, memory, time and retry policy |
| Execution reports | [`reports.config`](reports.config) | Nextflow timeline, report, trace and DAG |
| Site runtime | `profiles/<site>.config` | Executor, queue, software, mounts, resource overrides and supported-stage defaults |
| Site references | `databases/<site>.config` | Database paths, location modes, matching tool versions and mapping defaults |
| Study parameters | `example_yamls/<profile>.yaml` | Inputs/output, enabled analyses, reference selections and HUMAnN mappings |

Study YAML overrides profile parameters; `--parameter value` overrides YAML.
Use `-c site-overrides.config` for Nextflow directives such as `process.queue`
or `process.container`. These directives do not belong in a parameter YAML.
The root `nextflow_schema.json` describes the DNAnexus applet interface;
`params.config` remains the common default source for other sites/workflows.
These configs use Groovy syntax. With a Nextflow version that defaults to
strict parsing, set `export NXF_SYNTAX_PARSER=v1` before running the commands below.

## Site files

| `-profile` | Runtime | References | Example YAML |
| --- | --- | --- | --- |
| `local` / `standard` | [local](profiles/local.config) | Supply your own | [local](example_yamls/local.yaml) |
| `harvard_rc` | [harvard_rc](profiles/harvard_rc.config) | [harvard_rc](databases/harvard_rc.config) | [harvard_rc](example_yamls/harvard_rc.yaml) |
| `wellesley_hpc` | [wellesley_hpc](profiles/wellesley_hpc.config) | [wellesley_hpc](databases/wellesley_hpc.config) | [wellesley_hpc](example_yamls/wellesley_hpc.yaml) |
| `wellesley_hopper` | [wellesley_hopper](profiles/wellesley_hopper.config) | [wellesley_hopper](databases/wellesley_hopper.config) | [wellesley_hopper](example_yamls/wellesley_hopper.yaml) |
| `tufts_hpc` | [tufts_hpc](profiles/tufts_hpc.config) | [tufts_hpc](databases/tufts_hpc.config) | [tufts_hpc](example_yamls/tufts_hpc.yaml) |
| `amazon` | [amazon](profiles/amazon.config) | Supply your own | [amazon](example_yamls/amazon.yaml) |
| `dnanexus` | [dnanexus](profiles/dnanexus.config) | [dnanexus](databases/dnanexus.config) | [dnanexus](example_yamls/dnanexus.yaml) |
| `dnanexus_download` | dnanexus + [download overlay](profiles/dnanexus_download.config) | dnanexus + [project references](databases/dnanexus_download.config) | [full profiling](example_yamls/dnanexus_download.yaml), [QC smoke run](example_yamls/dnanexus_download_smoke.yaml) |

Harvard's former `harvard_rc-module.config` files are now `harvard_rc.config`;
Wellesley HPC's former `wellesley.config` files are now `wellesley_hpc.config`.
The AWS runtime file `profiles/aws.config` is now `profiles/amazon.config`.
Update any custom `includeConfig` paths that use those old filenames.

## Running a study

Run from the repository root, replacing the example site and paths:

```bash
cp conf/example_yamls/harvard_rc.yaml my-study.yaml
# Edit my-study.yaml: choose samplesheet OR readsdir and set outdir.
nextflow run main.nf -profile harvard_rc -params-file my-study.yaml \
  -w /shared/my-study/work
```

For `mgx`, `mtx` and `assembly`, supply exactly one of `samplesheet` or
`readsdir`. For `mgx_mtx`, use an assay-labelled samplesheet or the
`input_metagenome` / `input_metatranscriptome` folders. Standalone `vis` and
`stats` use `vis_input` / `stats_input`; stats also needs study metadata.
Relative input/output paths use the launch directory, not the YAML's directory.
YAML does not expand shell variables or `${params...}` expressions.

**Local / standard.** Install the tools on `PATH` and supply reference paths;
this profile selects no containers. Lower `max_cpus` and `max_memory` to fit
the machine. The example disables analysis reports until their Python/R
dependencies are installed.

**Harvard FASRC (Cannon).** Initialize hutlab in each shell:

```bash
source /n/lab_storage/huttenhower_lab/tools/hutlab/src/hutlabrc_rocky8.sh
hutlab load rocky8/biobakery-workflows-nextflow/0.0.4
```

Tasks use SLURM `hsph` and load their own tool modules. Keep the work directory
on shared storage visible to compute nodes. Human hg38, transcriptome, rRNA,
HUMAnN 4 and the compatible Oct22 MetaPhlAn references are supplied. The assembly
stack uses the module's CheckM2 database and the configured PhyloPhlAn directory.
See [dependencies](../docs/dependencies.md) before changing the module/version pairing.

**Wellesley HPC.** Make Nextflow, Java and Apptainer available, and verify that
compute nodes can read `/home/gz101/containers/*.sif` and
`/home/gz101/Databases/`. Tasks use SLURM `day-long-cpu`; keep work on shared
storage. The profile supplies QC, MetaPhlAn/StrainPhlAn and HUMAnN images.
BAQLaVa, assembly and reports need additional software; transcriptome, rRNA and
assembly references are unset. The example disables reports and host version
logging. Harvard module commands and its PhyloPhlAn path are no longer used here.

**Wellesley Hopper.** Run on the Docker host with the named local tool images
installed and `/murray/databases/` readable. KneadData and HUMAnN references are
inside images; MetaPhlAn/StrainPhlAn and BAQLaVa references are on the host.
The profile alone selects the primary MetaPhlAn reference. Its example selects
two references, EC/KO/Pfam mappings, and viral/strain profiling, with reports
disabled. Configure assembly software/references separately. See the
[Hopper guide](../docs/wellesley_hopper.md) for image and bind-mount details.

**Tufts HPC.** Load Nextflow and add `/cluster/tufts/bonhamlab/shared/bin` to
`PATH`. Tasks use SLURM `batch`; Apptainer is enabled with `/cluster` bound,
but **no container images are assigned**. Supply tools on `PATH` or add image
assignments through `-c`. The references pair Jun23 MetaPhlAn with HUMAnN 3.7.
Set transcriptome/rRNA references for RNA QC and assembly references/software
before running those workflows. Keep work on shared `/cluster` storage.

**AWS Batch / amazon.** This is an incomplete porting profile. Configure AWS
credentials, region, queues, worker AWS CLI path, images and S3 references;
use `-w s3://BUCKET/work`. Several helpers, BAQLaVa and assembly/report stages
lack images or queues. Reconcile the legacy MetaPhlAn 3.1 image with its
reference/version settings before use. The YAML is a starting template.

**DNAnexus.** Build a platform executable with `bash dxbuild.sh --profile
dnanexus`; add `--refresh-images` when populating/updating the image cache.
Select your uploaded samplesheet at launch. Upload the study YAML and pass it
as `-inextflow_params_file=project-id:file-id`; file references *inside* YAML
use `dx://` URIs. Keep `outdir` relative to the job destination. DNAnexus
supplies the executor; `machineType` in the profile selects task workers.

The `dnanexus` profile uses database-bearing images for QC/taxonomy/function.
`dnanexus_download` uses lean profiling images, viral/strain stages and worker-side
`dx download` transfers. It replaces `dnanexus_dxfuse` and `dnanexus_dxfuse_full`;
remove `dnanexus_reference_mode` and `dnanexus_reference_mountpoint` from old
YAMLs. The smoke YAML disables downstream analyses with the same profile.
Build with the matching profile and ensure the project's `/Databases` layout
matches its reference config. Override `dnanexus_reference_project` and
`dnanexus_reference_folder` for another source location. Reports/assembly require
additional setup. See [DNAnexus instructions](../docs/dnanexus.md), including the
fixed compatibility settings required by the currently cached images.

## References, resources and checks

`<tool>_db_location: host` stages a database as a Nextflow input;
`container` uses its existing path inside the task image or mount. Relative
`metaphlan_db` entries resolve against `metaphlan_db_root`; relative HUMAnN
mapping filenames resolve against `humann_db_utilitymapping`. Keep each tool's
version paired with the corresponding reference release.

`max_cpus`, `max_memory` and `max_time` cap requests from `base.config`.
Explicit site resource overrides, including DNAnexus worker allocations, are
not capped by those parameters. Adjust those directives through `-c` as needed.
An identical `withName` selector in an included profile replaces the base
selector block: retain its CPU, memory and time directives, or use a distinct
selector for environment-only changes.

Check resolved settings and all profiles without running bioBakery tools:

```bash
nextflow config -profile harvard_rc
python3 bin/check_profile_resources.py
python3 -m unittest discover -s tests -p test_site_configs.py
```
