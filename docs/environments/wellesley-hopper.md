# Wellesley Hopper

The `wellesley_hopper` profile runs tasks locally on the Docker host. It is not
a SLURM submission profile. Start it only on a host or allocation where Docker
execution and the requested resources are permitted.

## Verify software and references

The profile expects named local images:

| Stack | Local image name |
| --- | --- |
| KneadData | `kneaddata:0.12.1-hg37dec-r1` |
| MetaPhlAn and StrainPhlAn | `metaphlan:4.2.5-mpa_vOct22_202403-r1` |
| HUMAnN | `humann:4.0.0-experimental-chocophlan-v4-201901-r1` |
| BAQLaVa | `baqlava:4.0.0-r1` |

Check `docker image ls` and the exact assignments in
`conf/profiles/wellesley_hopper.config`. Local aliases must refer to the
intended images; record the image identity for a study, since mutable tags can
change.

KneadData and HUMAnN references are supplied inside their configured images.
MetaPhlAn/StrainPhlAn use the corrected host references under
`/murray/databases/metaphlan/`. BAQLaVa uses separate host references and
read-only binds for its HUMAnN depletion databases. See the
[detailed Hopper reference](../wellesley_hopper.md) before changing that layout.

## Start a study

```bash
cp conf/example_yamls/wellesley_hopper.yaml my-study.yaml
# Edit the inputs and outdir. Review its optional-stage selections.
nextflow run main.nf -profile wellesley_hopper -params-file my-study.yaml \
  -w /path/to/my-study/work
```

The supplied YAML enables viral and strain profiling and selects two MetaPhlAn
references. For a first QC-only check, disable the downstream stages using the
[smoke-run switches](../get-started/first-run.md). Small cohorts retain strain
markers but need at least four samples to proceed to cohort phylogenies.

Reporting needs its dedicated software image and dependencies; assembly also
needs additional software and references. Review the configured Docker mounts
when moving this profile to another host. Its database paths and local aliases
are site settings, not portable defaults for a new cluster.
