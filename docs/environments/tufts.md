# Tufts HPC

The `tufts_hpc` profile selects SLURM's `batch` partition and enables Apptainer
with a `/cluster` bind. It does **not** assign container images. The analysis
programs must therefore already be available on task `PATH`, or you must add
image assignments through a site override file.

## Prepare the software

Use the documented Tufts Java/Nextflow environment and the lab's maintained
software installation. The existing configuration expects tools through
`/cluster/tufts/bonhamlab/shared/bin` or explicit containers. Confirm their
availability in a batch job, not only in an interactive shell.

If adopting containers, select a mutually compatible image/reference stack and
add `process.container` assignments using `-c`. Enabling Apptainer without
those assignments does not obtain images or replace host software.

## Preserve the reference pairing

The configured site defaults are MetaPhlAn 4 with the Jun23/202307 marker
reference and HUMAnN 3.7. They differ from the HUMAnN 4 example in the generic
HPC walkthrough. Retain the Tufts pairing, or deliberately update the software,
reference paths, and version settings together.

Review `conf/databases/tufts_hpc.config`. Transcriptome/rRNA and assembly
reference settings are incomplete; supply them before enabling those workflows.

## Start a study

```bash
cp conf/example_yamls/tufts_hpc.yaml my-study.yaml
# Edit samplesheet OR readsdir, outdir, and any missing references.
nextflow run main.nf -profile tufts_hpc -params-file my-study.yaml \
  -w /cluster/tufts/YOUR_GROUP/my-study/work
```

Keep the work directory on shared `/cluster` storage. For the first installation
check, use the QC-only selections from the
[first-run guide](../get-started/first-run.md). Optional reporting and additional
analyses require their own complete environments.
