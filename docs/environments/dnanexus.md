# DNAnexus

DNAnexus runs a platform executable rather than a persistent shell command on a
shared HPC filesystem. The platform supplies the Nextflow executor, and the
profile's `machineType` directives select the workers used by individual tasks.

## Choose the deployment model

| Profile | Software and references |
| --- | --- |
| `dnanexus` | Database-bearing images for the core profiling steps |
| `dnanexus_download` | Lean images; references downloaded from the project to each worker's local SSD |

For the download profile, obtain/cache the images during deployment and upload
the versioned reference files or configured archives to the project. The
reference folder must match `conf/databases/dnanexus_download.config`. Workers
use project-resident data; production execution must not depend on public
database downloads or a public registry being reachable.

The old `dnanexus_dxfuse` profile names have been replaced by
`dnanexus_download`. Its supported reference procedure copies data to local SSD;
the existing image tag's historical name does not require a FUSE-mounted run.

## Build and launch

Use the deployment procedure in the [DNAnexus reference](../dnanexus.md) and the
platform's [Nextflow guide](https://documentation.dnanexus.com/user/running-apps-and-workflows/running-nextflow-pipelines).
The `dxbuild.sh` helper discussed there is installation-local and may not be
present in a fresh checkout; obtain the maintained helper from your deployment
owner if using that two-stage cache/runtime build procedure.

Select the uploaded samplesheet when launching the executable. For the first
QC-only test, use the selections in
`conf/example_yamls/dnanexus_download_smoke.yaml`. For the configured full
profiling route, use `conf/example_yamls/dnanexus_download.yaml`. Upload the
selected YAML as a run-parameter file, and keep `outdir` relative to the platform
job destination.

Reference file URIs inside a platform samplesheet/YAML use `dx://` paths. A
local `/shared/...` path from the HPC tutorial does not identify a project file.
Review the image cache and final runtime applet's dependencies: the documented
deployment procedure avoids attaching every tool image to every worker.

Viral/strain analysis, references, and worker settings are described in the
detailed reference. Reports and assembly need additional environment setup.
