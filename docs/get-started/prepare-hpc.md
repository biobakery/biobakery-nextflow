# 1. Find and load a container runtime

Start by finding out how your system provides **Apptainer, Docker, or Podman**.
On an HPC cluster, software is often supplied through environment modules and
will not appear on `PATH` until its module is loaded.

## Check the module system first

Read your site's software guide. If it uses environment modules, list what is
available:

```bash
module avail
```

Look for Apptainer, Docker, or Podman. On sites using Lmod, `module spider`
can also find modules that require another module to be loaded first:

```bash
module spider apptainer
```

Load the runtime using the name/version reported by your site. For example,
if an `apptainer` module is listed:

```bash
module load apptainer
apptainer --version
```

Use the corresponding Docker or Podman module if that is what your site
supports. Module names vary; these are examples, not names every cluster
provides. If the `module` command is unavailable, check the site's instructions
for initializing it. On a workstation without modules, check the installed
commands directly.

| Runtime | Check after loading its module, if needed |
| --- | --- |
| Apptainer | `apptainer --version` |
| Docker | `docker version` and `docker info` |
| Podman | `podman --version` and `podman info` |

Choose one runtime your site permits on **compute nodes**, and use its examples
throughout this guide. If no runtime is available, ask your support team which
one to use. Record any `module load` commands: you will need them again in
batch jobs, not only in this setup session.

## Choose SLURM or local execution

This guide covers two common arrangements:

| Where you will run | Nextflow executor | What you need |
| --- | --- | --- |
| An HPC cluster managed by SLURM | `slurm` | The partition and, if required, account to use |
| A workstation or an allocated machine without separate task submission | `local` | Enough CPU, memory, and disk for the tasks |

For SLURM, confirm that `sbatch` is available after loading any required modules.
Use your site's guidance for where the Nextflow driver should run. For local
execution on a cluster, use an approved compute allocation rather than a login
node. Other schedulers can be configured through Nextflow, but are outside this
introductory walkthrough.

## Create an installation directory

Choose a location with room for the databases and task files. On a cluster it
must be visible to the driver and workers. Replace the example root below with
your shared group/project directory; on a workstation, use a suitable local path.

```bash
export BB_ROOT=/shared/YOUR_GROUP/biobakery
mkdir -p "$BB_ROOT"/{containers,databases,config,data/test,runs/smoke}
```

Keep `BB_ROOT` set when following the remaining commands. The `containers/`
directory holds Apptainer SIF files; Docker/Podman use their own image stores.
The other directories hold references, configuration, inputs, and run outputs.
Ask your site which node should be used for large downloads.

## Prepare Nextflow

Load the site's Java and Nextflow modules, if provided. This guide uses
**Java 21** and **Nextflow 25.10.4**:

```bash
export NXF_VER=25.10.4
export NXF_SYNTAX_PARSER=v1
java -version
nextflow -version
```

Initialize that Nextflow release where downloads are permitted before running
offline. If it is not installed, follow Nextflow's
[installation guide](https://www.nextflow.io/docs/latest/install.html).
The analysis tools themselves will come from the containers.

Obtain the pipeline and record the revision:

```bash
git clone https://github.com/biobakery/biobakery-nextflow.git "$BB_ROOT/pipeline"
git -C "$BB_ROOT/pipeline" rev-parse HEAD > "$BB_ROOT/config/pipeline-commit.txt"
```

Continue with [downloading the container images](obtain-images.md).
