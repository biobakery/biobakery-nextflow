# Export HUMAnN nucleotide-unaligned reads

To retain HUMAnN's nucleotide-unaligned reads for downstream analysis, add this
to your run YAML:

```yaml
run_functional_profiling: true
humann_save_unaligned_reads: true
```

`humann_save_unaligned_reads` defaults to `false` and works across execution
profiles with HUMAnN 3.7 and the supported HUMAnN 4 stack. The existing HUMAnN
task exports the file after profiling finishes, using the same allocation and
container. No additional process or image is required.

## Which reads are exported?

Following the channel proposed in [PR #35](https://github.com/biobakery/biobakery-nextflow/pull/35),
this exports `<sample>_bowtie2_unaligned.fa` from HUMAnN's temporary directory.
These reads failed the nucleotide search against the selected ChocoPhlAn
pangenomes. Some can subsequently align during HUMAnN's translated protein
search. The FASTA therefore represents the nucleotide-search remainder.

Only this FASTA is exported. Other temporary files stay within the HUMAnN task.

## Published files

For a single-database MGX or MTX run:

```text
<outdir>/humann/<humann_version>/unaligned_reads/<sample>_bowtie2_unaligned.fa
```

For a run using multiple MetaPhlAn database configurations, the files retain
their database context:

```text
<outdir>/databases/<index>/humann/<humann_version>/unaligned_reads/<sample>_bowtie2_unaligned.fa
```

In `mgx_mtx`, these paths also begin with `whole_metagenome_shotgun/` or
`whole_metatranscriptome_shotgun/` beneath `outdir`, keeping the assays separate.

## Channels for a parent workflow

A pipeline including these workflows can consume the exported files through
the following channels:

| Workflow | Output channel |
| --- | --- |
| `FUNCTIONAL_PROFILING` | `.out.unaligned_reads` |
| `MGX` | `.out.unaligned_reads` |
| `MTX` | `.out.unaligned_reads` |
| `MGX_MTX` | `.out.mgx_unaligned_reads` and `.out.mtx_unaligned_reads` |

Each item is `(database_context, sample, fasta_path)`. The database context is
the index for multi-database runs and an empty string for the legacy
single-database layout. Consume the channel path directly for downstream task
inputs; publication to `outdir` happens independently.

## When the channel is empty

The channel is empty when the flag is false or functional profiling is
disabled. Files are optional even when requested: HUMAnN can omit this FASTA
when no pangenomes are selected, nucleotide search is bypassed, or
`humann_options` includes `--remove-temp-output`. The task logs a message if the
flag is enabled but the file is absent, and profiling outputs still complete.
An existing empty FASTA is retained as a valid zero-read result.

The flag exports a file produced by HUMAnN; it does not force a nucleotide
search or reconstruct reads after temporary output has been removed. Keep
nucleotide search enabled and omit `--remove-temp-output` when you need these
reads.
