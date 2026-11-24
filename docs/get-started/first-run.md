# 5. Run and inspect a first analysis

The first run should establish that the scheduler, container, input paths,
reference, and output publication work together. Begin with one small,
representative paired-end sample and QC only. After that succeeds, extend the
same installation to taxonomic and functional profiling.

Before launching, complete the preceding steps: load a runtime, pull the images,
install the databases through those containers, and prepare the site config,
samplesheet, and run YAML.

## Launch the driver where your site permits it

Nextflow is the driver; its SLURM worker jobs perform the analysis. Keep the
driver alive until the run finishes. Use your site's workflow service,
permitted persistent session, or a batch job that is allowed to submit other
jobs. Do not run the analysis on a login node by replacing the SLURM executor
with local execution.

For a driver session already prepared according to your site's policy:

```bash
mkdir -p "$BB_ROOT/runs/smoke"
cd "$BB_ROOT/runs/smoke"
export NXF_VER=25.10.4
export NXF_SYNTAX_PARSER=v1

nextflow -c "$BB_ROOT/config/my-cluster-resources.config" \
  run "$BB_ROOT/pipeline/main.nf" \
  -params-file "$BB_ROOT/config/smoke.yaml" \
  -w "$BB_ROOT/runs/smoke/work"
```

If your site permits a SLURM driver job, a starting batch script is below.
Replace the partition and root, add the required account directive if needed,
and load your site's Java, Nextflow, and chosen container-runtime modules before
the command. The driver partition/time limit may differ from the worker settings.

```bash
#!/usr/bin/env bash
#SBATCH --job-name=biobakery-smoke
#SBATCH --partition=YOUR_PARTITION
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=04:00:00
#SBATCH --output=driver-%j.log

set -euo pipefail
# Add your site's required module initialization/loading here.
export BB_ROOT=/shared/YOUR_GROUP/biobakery
export NXF_VER=25.10.4
export NXF_SYNTAX_PARSER=v1
cd "$BB_ROOT/runs/smoke"

nextflow -c "$BB_ROOT/config/my-cluster-resources.config" \
  run "$BB_ROOT/pipeline/main.nf" \
  -params-file "$BB_ROOT/config/smoke.yaml" \
  -w "$BB_ROOT/runs/smoke/work" "$@"
```

Save your edited script as `$BB_ROOT/config/launch-smoke.sbatch`. From
`$BB_ROOT/runs/smoke`, submit it with:

```bash
sbatch "$BB_ROOT/config/launch-smoke.sbatch"
```

For a workstation or an approved single-node allocation, use the same Nextflow
command with `process.executor = 'local'` in your site file and no SLURM
queue/account settings. Run it directly in that permitted session rather than
submitting the example driver script. The local CPU and memory budget must
accommodate the task requests in your site config.

The expected tasks are one input check, one KneadData task for the sample,
and one read-count merge. Your initial driver job is an additional scheduler job.
Its wall-time limit must cover the complete run, including time waiting for
workers. Review that limit again before extending the test to a full study.

## Check the result

A successful run should publish the following under the configured `outdir`:

```text
results/
├── kneaddata/
│   ├── TEST01_kneaddata.log
│   ├── TEST01_kneaddata_paired_1.fastq.gz
│   ├── TEST01_kneaddata_paired_2.fastq.gz
│   ├── TEST01_kneaddata_unmatched_1.fastq.gz
│   ├── TEST01_kneaddata_unmatched_2.fastq.gz
│   └── merged/kneaddata_read_count_table.tsv
└── pipeline_info/
    ├── execution_report_*.html
    ├── execution_timeline_*.html
    └── execution_trace_*.txt
```

Confirm the Nextflow run completed, then inspect the KneadData log and count
table. Check that the expected input count is present and that retained reads
are plausible for the sample and host reference. Successful task execution is
an operational check; it is not evidence that a biological result is correct.
For paired libraries, the count table records the two mates separately: one
read pair contains two reads.

The HTML report and trace help distinguish allocation time, task execution
time, and resource use. For a failed task, inspect `.nextflow.log` in the launch
directory and the failing work directory's `.command.err` and `.command.sh`.
Typical first-installation problems include an inaccessible reference path,
an image without a required helper executable, or a resource request rejected
by the partition.

## Resume and extend the analysis

After correcting a failed run, repeat the same launch command with `-resume`.
With the batch-script example, pass it through as an argument:

```bash
sbatch "$BB_ROOT/config/launch-smoke.sbatch" -resume
```

Keep the launch directory's `.nextflow/` state and the work directory until you
no longer need to resume. Results alone are not a replacement for that cache.

Once QC succeeds, verify the MetaPhlAn and HUMAnN references and copy the YAML
to a study-specific filename. Change the output directory for that study and
enable:

```yaml
run_taxonomic_profiling: true
run_functional_profiling: true
# Begin with the core outputs; choose regroupings explicitly later.
humann_regroups: []
```

Use the new YAML in a corresponding launch directory. If extending the same
run with `-resume`, retain its original launch/work directories; matching cached
tasks can then be reused. Review the
[database selection guide](../metaphlan_databases.md) before adding multiple
references or custom regroupings. Configure the additional software and data
before enabling strain/viral analysis, assembly, or reports.

Retain the site config, final YAML, samplesheet, workflow commit, image checksums,
reference provenance, and execution reports with the study. This is the record
needed to explain and repeat the analysis.
