# Supported environments

These pages belong to **Get started**. Use them when your installation matches
an existing profile; use the step-by-step setup guide when preparing a new site.

A named profile reuses an environment definition already present in the
repository. Select it with `-profile`; supply your study's inputs and analysis
choices with `-params-file`. Check the page for your environment before copying
commands, because available software and reference releases differ between
sites.

| Environment | Profile | Execution and software | Scope and prerequisites |
| --- | --- | --- | --- |
| [New HPC installation](../get-started/index.md) | Your own `-c` file | SLURM or local, with Apptainer, Docker, or Podman where permitted | Load a runtime, pull images, install databases through the containers, configure, then test QC |
| [Harvard FASRC / Cannon](harvard-rc.md) | `harvard_rc` | SLURM and hutlab modules | Broadest configured tool stack; requires access to the lab modules and shared references |
| [Wellesley HPC](wellesley-hpc.md) | `wellesley_hpc` | SLURM and Apptainer | Core profiling/strain images; paths are installation-specific; other stages need setup |
| [Wellesley Hopper](wellesley-hopper.md) | `wellesley_hopper` | Local executor and Docker | Named local images and Hopper references; additional stages need their environments |
| [Tufts HPC](tufts.md) | `tufts_hpc` | SLURM; Apptainer enabled | No images assigned by default; supply software and preserve the site's HUMAnN 3.7 pairing |
| [Local machine or workstation](local.md) | `local` / `standard` | Local executor | Tools and references are supplied by the user; containers require explicit configuration |
| [DNAnexus](dnanexus.md) | `dnanexus` / `dnanexus_download` | Platform executor and cached Docker images | Build a platform executable and supply project inputs; distinct from an HPC launch |
| [AWS Batch](aws-batch.md) | `amazon` | AWS Batch | Incomplete porting profile; requires additional environment configuration |

These are configuration entry points, not interchangeable certifications of
every tool/reference combination. Verify permissions, paths, software versions,
and the enabled stages at your installation. In particular, a database path
from one site should not be combined with another site's software version
without checking compatibility.

For an existing profile, copy its YAML from `conf/example_yamls/`, edit the
inputs and output location, and select the profile by its exact name. YAML
does not expand shell variables. Use an additional `-c` file for resource or
container overrides. The [configuration chapter](../get-started/site-configuration.md)
explains how those responsibilities fit together.
