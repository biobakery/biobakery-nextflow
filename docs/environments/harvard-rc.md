# Harvard FASRC / Cannon

The `harvard_rc` profile uses SLURM's `hsph` partition and the Huttenhower Lab's
hutlab modules. It is the main example of an installation that supplies tool
environments through modules rather than containers. Those managed modules
are the intended software source for this profile; enabling Apptainer alone
does not reproduce that environment.

## Prepare the environment

Initialize the lab module environment in the shell that launches Nextflow:

```bash
source /n/lab_storage/huttenhower_lab/tools/hutlab/src/hutlabrc_rocky8.sh
hutlab load rocky8/biobakery-workflows-nextflow/0.0.4
```

This requires access to the lab's module and reference directories. Keep the
driver and work directory on approved infrastructure, with the work directory
visible to compute nodes. Follow FASRC's policy for a persistent driver and
SLURM submissions.

## Configure a study

From your pipeline checkout:

```bash
cp conf/example_yamls/harvard_rc.yaml my-study.yaml
# Edit my-study.yaml: set samplesheet OR readsdir, and outdir.
nextflow run main.nf -profile harvard_rc -params-file my-study.yaml \
  -w /shared/YOUR_GROUP/my-study/work
```

The profile loads `conf/profiles/harvard_rc.config` and
`conf/databases/harvard_rc.config`. Tasks initialize their own tool modules;
loading a different tool into the driver shell does not automatically change
the modules selected for tasks.

## Site-specific considerations

- The configured profiling stack uses the fixed Oct22 MetaPhlAn module with
  HUMAnN 4 and the corresponding reference paths. Change the stack as a unit.
- HAllA uses its own module environment because its dependency requirements
  differ from those of the rest of the reporting stack.
- The module environment also supplies assembly dependencies. Optional analyses
  still need suitable data and their required run parameters.
- The example can chain visualization. For the first operational test, apply
  the QC-only switches from the [first-run guide](../get-started/first-run.md).

See [Software dependencies](../dependencies.md) for the module/version rationale
and the [configuration reference](https://github.com/biobakery/biobakery-nextflow/blob/main/conf/README.md)
for the complete site layout.
