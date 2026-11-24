# Local machine or workstation

The `local` profile, also available as `standard`, runs each task on the machine
that launches Nextflow. It assigns neither software images nor reference paths.
It is appropriate for a workstation, an approved single-node allocation, or a
development environment with the tools installed.

## Prepare the environment

Install Java/Nextflow and make the selected workflow's tools available on
`PATH`, or configure an approved container runtime and explicit per-process
images in a `-c` file. The
[image-download chapter](../get-started/obtain-images.md) covers obtaining
the tool images. Use those containers to [install the databases](../get-started/containers-and-databases.md),
then copy the appropriate [minimal site example](../get-started/site-configuration.md)
for Docker, Apptainer, or Podman. Set its executor to `local` and remove the
SLURM queue/account settings.

For a Docker host already configured like Hopper, use the
[Hopper profile](wellesley-hopper.md) instead of assuming `local` supplies the
same images or mount points.

## Configure a study

```bash
cp conf/example_yamls/local.yaml my-study.yaml
# Set inputs, outdir, and the actual reference paths.
nextflow run main.nf -profile local -params-file my-study.yaml \
  -w /path/to/my-study/work
```

Reduce `max_cpus` and `max_memory` in the YAML to fit your host, for example
`max_cpus: 8` and `max_memory: 32.GB`. These cap shared task defaults; explicit
resource overrides need their own review. Multiple tasks may run concurrently,
subject to the local executor's available CPU and memory budget.

The example disables visualization and statistics until those dependencies are
installed. Keep the driver session alive, retain its work/cache directories for
resume, and begin with a [QC-only test](../get-started/first-run.md). On a shared
cluster, run this profile inside an approved compute allocation rather than
using the login node for analysis.
