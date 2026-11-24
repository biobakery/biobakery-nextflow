# Input checks

A FASTQ that ends early — an interrupted copy, a download cut short, a gzip
stream truncated mid-file — is not noticed until a tool reads to the end of it.
On a large study that is hours into the run, and the error names neither the
problem nor the file:

```
EOFError: Compressed file ended before the end-of-stream marker was reached
```

Under the default `errorStrategy 'finish'` that one task stops the whole run.
So every read-based run (`mgx`, `mtx`, `mgx_mtx`, `assembly`) now starts by
reading each raw FASTQ through once. A bad sample is logged, listed under
`<outdir>/input_check/`, and **left out**, and the run finishes on the rest.

## What is checked

| Check | Catches | Reported as |
|---|---|---|
| File exists | a broken symlink, a missing file | `file not found (broken symlink)` |
| File is readable | permissions that stop the pipeline reading it | `file is not readable (permission denied)` |
| File is not empty | a zero-byte file | `file is empty` |
| Compressed stream is complete | a truncated or corrupt `.gz` / `.bz2` — the usual case | `compressed stream is truncated or corrupt: gzip: …: unexpected end of file` |
| Every record has 4 lines | a plain or gzipped file that ends mid-record | `file ends inside a record (4001 lines, not a multiple of 4)` |
| Header line starts with `@` | a malformed or misaligned record | `line 801: header does not start with '@'` |
| Separator line starts with `+` | the same | `line 803: separator does not start with '+'` |
| Quality length = sequence length | a record cut or corrupted mid-line | `line 404: quality length 10 differs from sequence length 99` |
| At least one read | a valid but empty FASTQ | `no reads` |
| Mates hold the same number of reads | one mate truncated cleanly, or mates from different runs | `mates hold different read counts (250 vs 100)` |
| Every mate has its partner | an R1 whose R2 is missing, or a file the pair identifier does not match | `no mate found: S12_R2.fastq.gz is missing` |

A sample fails if any of its files fails. For a pair, both mates are reported.
The check stops at the first malformed record, because one is enough to drop
the sample.

**Not checked:** read quality, adapters, host content, or whether a file holds
the sample its name says. Those are KneadData's and the analyst's job. The
check also does not look past filenames the run would not pick up. A file the
glob does not match is not read; see `--filepattern`.

Broken symlinks and unpaired mates are never read: Nextflow cannot stage a
link whose target is gone, and a lone mate cannot be run as a pair. They are
named in a warning at startup and listed in the report as FAIL, so the report
holds every file the run left out, whatever the reason.

## Three ways to run it

**1. Automatically, as part of every run** (default, `--check_inputs true`).
Nothing to do. Each sample waits only on its own check, so profiling of the
first good samples starts while the rest are still being checked. The log
says which samples were left out in three places:

```
# as each bad sample is found
WARN: [mgx] Sample S12 failed the input check and is left out: S12_R2.fastq.gz: compressed stream is truncated or corrupt: gzip: S12_R2.fastq.gz: unexpected end of file

# once every sample is checked
WARN: [mgx] 1 of 1600 samples failed the input check and were left out: S12. Details: results/input_check/mgx_input_check.tsv

# and again as the last thing the run prints, so it is not lost hours earlier
WARN: Input check [mgx]: 1 sample(s) were left out of this run:
  S12  --  S12_R2.fastq.gz: compressed stream is truncated or corrupt: gzip: S12_R2.fastq.gz: unexpected end of file
  Full list: /path/to/results/input_check/mgx_failed_samples.txt
  Details:   /path/to/results/input_check/mgx_input_check.tsv
```

A run that left samples out still exits 0, because it did what it was asked
to. To stop the run instead, pass `--fail_on_bad_inputs true`. No sample is
then profiled until every one has passed, and a bad one ends the run with exit
status 1 and the same list.

**2. Check only, then run** (`--check_inputs_only true`). Add the flag to the
command you are about to run. The inputs are found exactly as the real run
finds them, with the same layout detection and pairing, and the run stops
after the check:

```sh
nextflow run $BIOBAKERY_NF_PIPELINE/main.nf -profile harvard_rc \
  -params-file my-params.yaml --workflow mgx \
  --readsdir /path/to/fastqs --outdir results \
  --check_inputs_only true

cat results/input_check/mgx_failed_samples.txt   # one bad sample per line
```

Then fix or remove the bad files and drop the flag. Run the same command again
from the **same launch directory** with `-resume`, and the checks already done
are reused rather than repeated. On the cluster each check is its own small
SLURM job (2 cores, 2 GB), so a large folder is checked in parallel.

**3. Standalone, without Nextflow.** `bin/check_fastq_inputs.py` needs only
Python 3.6+, `gzip` and `awk`, so it runs on any node. It prints one line per
file, writes the table with `--output`, and exits 1 if any sample failed.
Loading the hutlab module puts it on `PATH`, so on FASRC it is just
`check_fastq_inputs.py`; elsewhere, call it by path as below.

```sh
# a whole folder, 16 files at a time, printing only the failures
python3 $BIOBAKERY_NF_PIPELINE/bin/check_fastq_inputs.py \
  --input /path/to/fastqs --threads 16 --output input_check.tsv --quiet

# one sample (one file, or the two mates)
python3 $BIOBAKERY_NF_PIPELINE/bin/check_fastq_inputs.py S12_R1.fastq.gz S12_R2.fastq.gz
```

| Option | Default | Meaning |
|---|---|---|
| `--input DIR` | — | Check every `*.fastq[.gz\|.bz2]` / `*.fq[...]` in this folder |
| `--pattern GLOB` | `*` | Only files matching this glob |
| `--pair-identifier` | `_R{1,2}` | How mates are named, as in the pipeline. Mates are paired and their read counts compared |
| `--single-end` | off | Do not pair mates |
| `--threads N` | `4` | Files checked at once. Each uses about two cores (gzip + awk) |
| `--quick` | off | Only test that each compressed file decompresses to its end. About twice as fast and catches truncation, but not malformed records or mismatched mates |
| `--output FILE` | — | Also write the table to this file |
| `--quiet` | off | Print only failures and the summary |

The script reads every byte, so it takes time. Expect about a minute per 1.5
GB gzipped file at full depth, or half that with `--quick`. Do not run a large
folder on a login node; submit it:

```sh
sbatch -p hsph -c 32 --mem 16G -t 6:00:00 --wrap \
  "python3 $BIOBAKERY_NF_PIPELINE/bin/check_fastq_inputs.py --input /path/to/fastqs --threads 32 --output input_check.tsv --quiet"
```

## Output

```
<outdir>/input_check/
├── <label>_input_check.tsv     # one row per file: sample, file, status, reads, problem
└── <label>_failed_samples.txt  # the samples left out, one per line; empty if none
```

`<label>` is `mgx`, `mtx` or `assembly`. `mgx_mtx` writes one pair of files
per input folder. The failed list is rewritten on every run, so a rerun after
fixing the files leaves it empty rather than stale.

```
sample     file                   status  reads  problem
good       good_R1.fastq.gz       PASS    1000
good       good_R2.fastq.gz       PASS    1000
truncated  truncated_R1.fastq.gz  PASS    1000
truncated  truncated_R2.fastq.gz  FAIL           compressed stream is truncated or corrupt: gzip: truncated_R2.fastq.gz: unexpected end of file
```

## After a sample fails

The sample is simply absent from the merged tables. To bring it back, replace
the file, from the source or by re-running KneadData on the raw reads, and
rerun the same command with `-resume`. Only the replaced sample is checked and
profiled again, plus the merge steps. To run with the check off, for example on
inputs already vetted another way, use `--check_inputs false`.

---

