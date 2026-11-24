# Wellesley HPC

The `wellesley_hpc` profile uses SLURM's `day-long-cpu` partition and existing
Apptainer images. Its configured image and database paths belong to a specific
installation under `/home/gz101/`; they are not paths that every Wellesley user
automatically has access to.

## Verify the installation

Load the site's Java, Nextflow, and Apptainer environment, then confirm access
to the images and references listed in:

- `conf/profiles/wellesley_hpc.config`
- `conf/databases/wellesley_hpc.config`

The core image paths are `/home/gz101/containers/kneaddata.sif`,
`metaphlan.sif`, and `humann.sif`. Obtain the maintained shared paths from the
site administrator or replace those assignments in an additional `-c` file.
Keep work on shared storage visible to the compute nodes.

## Start a study

From the pipeline checkout:

```bash
cp conf/example_yamls/wellesley_hpc.yaml my-study.yaml
# Edit inputs and outdir, and verify the selected reference paths.
nextflow run main.nf -profile wellesley_hpc -params-file my-study.yaml \
  -w /shared/YOUR_GROUP/my-study/work
```

For an initial QC-only check, use the run switches from the
[first-run guide](../get-started/first-run.md) while retaining this site's profile.

## Configured scope

The profile assigns images for KneadData, MetaPhlAn/StrainPhlAn, HUMAnN, and the
relevant profiling helpers. Its references include an Oct22 MetaPhlAn variant
whose index name ends in `_lon_subsp`; keep that exact index paired with the
installed reference files.

BAQLaVa, assembly, and reporting need additional software or images. Host
transcriptome/rRNA and assembly reference paths are not supplied for the broader
workflows. The example YAML disables reporting and host-side version logging.
Resource overrides must fit the actual partition limits; review its configured
20-CPU profiling requests before using a different allocation or queue.
