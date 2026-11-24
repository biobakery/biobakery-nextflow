# Implementing bioBakery on your own infrastructure

[bioBakery](https://github.com/biobakery/biobakery/wiki) brings together tools for
studying microbial communities from sequencing data. A typical metagenomic
analysis removes host and low-quality reads with KneadData, identifies community
members with MetaPhlAn, and estimates gene families and pathways with HUMAnN.
Related workflows support metatranscriptomes, strain and viral profiling,
genome assembly, visualization, and statistical analysis.

These analyses become more demanding as a study grows. A successful command on
one sample is a useful beginning, but a study also needs consistent software,
matching reference databases, a record of analytical choices, and a practical
way to process many samples. Changes to any of these can affect the results.

This project expresses the analysis as Nextflow workflows. Nextflow tracks task
dependencies, submits work to the selected execution environment, and records
the inputs and commands used by each task. Independent samples can run
concurrently, while downstream tasks wait for the files they need. Successful
tasks can be reused when resuming an interrupted analysis, provided their cached
results and execution state are retained.

The goal is to make an analysis repeatable and manageable at study scale.
Containers capture tool environments; versioned databases capture the reference
material; configuration files record where the work runs and what it should do.
Together, they provide a stronger basis for reproducibility than a collection of
commands assembled separately for each sample. They still require deliberate
version choices and biological validation: a reproducible run can reproduce an
inappropriate reference choice just as reliably as an appropriate one.

## What you will set up

By the end of this guide, you will have a shared software/reference directory,
a reusable configuration for your cluster, a YAML describing a small test run,
and the results and execution records from that run.

Begin by checking which container runtimes your site provides, including
software available through **environment modules**. Choose Apptainer, Docker,
or Podman, download the images, then use those containers to install their
databases. The guide provides a small configuration example for each runtime
and two execution choices: **SLURM** or **local**.

If your environment already has a profile, start with its
[environment page](../environments/index.md) and use this guide for the shared
setup steps.

| Step | Outcome |
| --- | --- |
| [1. Find and load a runtime](prepare-hpc.md) | Discover site modules, load the chosen runtime, and prepare Nextflow and storage |
| [2. Download images](obtain-images.md) | Pull the tool images with Apptainer, Docker, or Podman |
| [3. Install databases](containers-and-databases.md) | Use the downloaded containers and each tool's installation instructions; prepare test inputs |
| [4. Configure your site and test run](site-configuration.md) | Copy a minimal runtime example, choose SLURM or local, and supply paths and a test YAML |
| [5. Run and inspect a first analysis](first-run.md) | Submit the prepared QC-only test, check results, and extend the analysis |

The [supported-environment pages](../environments/index.md) are also part of
Get started. They provide the profile-specific settings and setup notes for
existing installations.

## Three configuration responsibilities

The same pipeline code can be used on different infrastructure and for different
studies because those choices are recorded separately:

| File | Responsibility | When it changes |
| --- | --- | --- |
| `nextflow.config` | The pipeline's canonical configuration; loads shared defaults and named profiles | With the pipeline release |
| `my-cluster-resources.config` | Your executor, queue, resource requests, container assignments, and local reference paths | When the site environment changes |
| `my-study.yaml` | The inputs, output destination, workflow, and analysis choices for one run | For each study or run |

For a custom site, a launch has this form:

```bash
nextflow -c /shared/YOUR_GROUP/biobakery/config/my-cluster-resources.config \
  run /shared/YOUR_GROUP/biobakery/pipeline/main.nf \
  -params-file /shared/YOUR_GROUP/biobakery/config/my-study.yaml \
  -w /shared/YOUR_GROUP/biobakery/runs/my-study/work
```

Nextflow discovers `nextflow.config` beside `main.nf`. The `-c` option adds your
site file, and `-params-file` supplies the run's YAML. A site filename has no
special meaning: `smith-lab-resources.config` is equally valid when passed with
`-c`.

Within this repository, the canonical config loads common parameters, default
resources, and execution-report settings from `conf/`. Existing named profiles
load their runtime and database files when selected with `-profile`. A new HPC
installation does **not** require editing that central configuration: keep your
site file outside the checkout and pass it explicitly.

Study YAML overrides parameter defaults; command-line `--parameter value`
arguments override YAML. Executor settings such as `process.queue` belong in
the site config, not in the parameter YAML. The
[site-configuration chapter](site-configuration.md) explains this distinction.

Continue with [preparing your HPC environment](prepare-hpc.md).
