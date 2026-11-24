# 4. Configure your site and test run

You now have the software images and their databases. Create one reusable site
file describing those paths and how tasks should run, then a YAML for the
small test analysis. Leave the repository's `nextflow.config` unchanged.

## Copy the example for your runtime

Choose **one** of these self-contained examples:

| Runtime | Minimal example |
| --- | --- |
| Apptainer | [site-apptainer.config](examples/site-apptainer.config) |
| Docker | [site-docker.config](examples/site-docker.config) |
| Podman | [site-podman.config](examples/site-podman.config) |

For example, with Apptainer:

```bash
cp "$BB_ROOT/pipeline/docs/get-started/examples/site-apptainer.config" \
  "$BB_ROOT/config/my-cluster-resources.config"
```

For Docker or Podman, copy `site-docker.config` or `site-podman.config` instead.
Use a site/lab-specific filename if you prefer; pass that name with `-c` when
launching Nextflow.

Edit the copy in your configuration directory:

1. Set `bb_root` to your installation directory.
2. Choose SLURM or local execution as shown below.
3. Replace `HOST_INDEX_DIRECTORY`, `CHOCOPHLAN_DIRECTORY`, `UNIREF_DIRECTORY`,
   and `MAPPING_DIRECTORY` with the actual paths produced by the database
   installers. Confirm the MetaPhlAn directory and index too.
4. Check the image assignments. For Apptainer, these are your shared SIF files;
   for Docker/Podman, they are the registry identifiers you pulled.

The templates cover core QC, taxonomic, and functional profiling, including
their table helpers. Other stages need their own images and references before
you enable them.

## Choose SLURM or local execution

The container engine and task scheduler are separate choices: the same runtime
can be used with either executor where the site permits it.

=== "SLURM"

    Keep these settings in the copied example, replacing the partition and
    adding your account if required:

    ```groovy
    process {
        executor = 'slurm'
        queue = 'YOUR_PARTITION'
        // clusterOptions = '--account=YOUR_ACCOUNT'
    }
    ```

    Nextflow submits each task through SLURM. Load the runtime module in your
    Nextflow launch/batch session so worker jobs can use it; follow your site's
    module initialization rules.

=== "Local"

    Change the executor in the copied example and remove the queue/account
    settings:

    ```groovy
    process.executor = 'local'
    ```

    Nextflow runs tasks on the current machine. Use a workstation or an approved
    compute allocation, and keep task resource requests within that machine's
    capacity.

The examples inherit this pipeline's task resource defaults. `max_cpus`,
`max_memory`, and `max_time` limit those shared defaults; adjust them for your
allocation. If you later add explicit per-process resource requests, review
those separately. `executor.queueSize` controls submission concurrency.

## Keep the database paths in the site file

The templates use `*_db_location = 'host'`: Nextflow stages the reference
directories you downloaded. The runtime's bind/volume settings make the shared
installation visible at the same path inside containers. You do not need a
special `/Databases` mount.

The examples use MetaPhlAn's Oct22/202403 index and HUMAnN 4. Change the
reference paths and version settings together if using another stack. See the
[database guide](../metaphlan_databases.md) for multiple MetaPhlAn references.

## Describe this run in YAML

Copy the [QC run YAML](examples/smoke.yaml), then edit the shared root in its
input and output paths:

```bash
cp "$BB_ROOT/pipeline/docs/get-started/examples/smoke.yaml" \
  "$BB_ROOT/config/smoke.yaml"
```

```yaml
workflow: mgx
samplesheet: /shared/YOUR_GROUP/biobakery/config/smoke-samples.csv
outdir: /shared/YOUR_GROUP/biobakery/runs/smoke/results

run_qc: true
stop_after_qc: false
run_taxonomic_profiling: false
run_functional_profiling: false
run_strain_profiling: false
run_viral_profiling: false
run_vis: false
run_stats: false
log_versions: false
```

YAML paths are literal: `$BB_ROOT` and `${...}` expressions are not expanded.
Relative paths resolve from the launch directory, not from the YAML's directory.
Supply either `samplesheet` or `readsdir` for this workflow, not both.

`stop_after_qc` remains false because this is a normal successful QC-only run.
That development switch intentionally fails a run after QC; disabling the
downstream stages is the appropriate choice here. `log_versions` is off because
the first test focuses on QC. Enable it later to publish the run header and
versions collected from the task environments.

## Check the configuration

```bash
cd "$BB_ROOT/pipeline"
nextflow -c "$BB_ROOT/config/my-cluster-resources.config" config -flat
```

Check the executor, runtime, images, and database paths in the output. This
checks configuration parsing without submitting analysis jobs.

If your environment already has a profile, its [environment page](../environments/index.md)
provides the corresponding site-specific setup.

Continue with [running the first test](first-run.md).
