# Release history

Hand-written. This is the story of how the pipeline got here, not a changelog
generated from commits — for the authoritative list of what a given version
contains, read the code at that deployment.

A note on how these versions are dated: there are no `v0.0.x` git tags. The
only tags in the repo are `v0.1` and `v0.2`, which belong to the original
AWS-era work and do not line up with the `0.0.x` series at all. The `0.0.x`
numbers are *deployment* numbers — the hutlab modulefiles under
`hutlab/src/modules_rocky8/rocky8/biobakery-workflows-nextflow/`, and the
matching trees under `/n/lab_storage/huttenhower_lab/tools/biobakery-workflows-nextflow/`.
The commit boundaries below were reconstructed by matching those deployment
dates against the git log, so treat them as close rather than exact.

---

## 0.0.1 — June 2026, "it runs on FASRC"

The first thing anyone else could load. It was a metagenomics pipeline and
nothing more: KneadData, MetaPhlAn 4, HUMAnN **3**, plus the BAQLaVa viral
step, wired up to run on Harvard FASRC. The modulefile still points at
`humann3_databases/version_3.1/chocophlan`, which dates it precisely.

There is no code directory for 0.0.1 under `tools/`, only a modulefile — you
ran it out of a personal checkout and the module just put Nextflow 24.10.4 and
the HUMAnN 3 database paths on your environment. That is the honest summary of
0.0.1: a working pipeline that wasn't yet a shipped one.

## 0.0.2 — 9 July 2026, the repository gets a shape

The commit is called "Standard repo" and that is exactly what it did. ~8,800
lines arrived, almost all of it new files, because this is where the
`modules/` + `subworkflows/` + `workflows/` layout was laid down and every
tool call was moved into its own module directory. It is also the first
version with a real tree under `tools/`, so the module now loads a *deployment*
rather than pointing at someone's home directory.

The assembly workflow shows up here too, though in draft form — it would take
two more releases to actually produce MAGs on real input.

## 0.0.3 — 6 August 2026, the shakedown

Much smaller on paper — 687 insertions across 40 files, nearly all
modifications — and much more important than it looks. This is the release
where things that had never been run properly were run properly, and broke.

The one worth remembering: `quality_control` emitted a channel called `log`,
but Nextflow already binds `log` to its own logger inside a workflow body, so
declaring it as an emit made `mgx`, `mtx`, `mgx_mtx` and `assembly` all die
with `No such variable: log` before a single task was submitted. Nothing
consumed the emit; renaming it to `logs` fixed all four.

Alongside that: the assembly workflow was brought into line with
upstream `biobakery_workflows` 3.2 and finally given its per-sample abundance
stage, `metaphlan_merge` and `metaphlan_bzip` got module environments they had
been silently borrowing, the viral flag was standardised on
`run_viral_profiling`, the template params file was trimmed to real
`lab_storage` paths, and a stray `metaphlanstart.nf` was deleted from the repo
root.

This is the point where the pipeline stopped working only on the machine it was
written on.

## 0.0.4 — 2 September 2026, everything else in 3.2

The big one: another ~8,500 lines, 61 new files. Three things landed.

**The `vis` and `stats` workflows were ported from `biobakery_workflows` 3.2.**
This is the bulk of it, and it is also where the anadama2 problem had to be
faced — the decision was to vendor the document layer rather than rewrite it,
which is why `bin/lib/` exists. Several upstream scripts simply did not work
on Python 3 (`norm_ratio` being the memorable one), so `bin/scripts/` filled
up with py3 replacements.

**MTX and MGX+MTX were ported.** This is the release that made the
`subworkflows/` layer earn its keep: `mgx_mtx` has to run quality control,
taxonomic profiling and functional profiling twice over two different read
sets, and aliased subworkflow includes are the only way to do that without
three copies of the wiring.

**It was made to survive real input.** Single-end assembly runs, multi-sample
assembly runs, read pairs merged when QC is bypassed, the single-end glob
fallback when `filepattern` carries a pair identifier, merged HUMAnN columns
named for the sample on one-sample runs, and small or sparse studies no longer
taking the vis report down with them. `vis` also became chained — it now runs
at the end of the read-based workflows instead of being a separate invocation.
Every workflow except 16s is now tested in both library layouts.

0.0.4 was deployed twice. The 31 August tree is still sitting there as
`0.0.4.superseded-20260902`, which is the fingerprint of a release that needed
a second pass.

## After 0.0.4 — the cleanup, not yet deployed

Currently on `feature/standard-biobakery-workflow` and not pushed: ~4,000
lines changed, but look at the shape of it — 14 deletions and 17 renames.
This is housekeeping, not features.

The layout was consolidated (`test/` and `tests/` were one directory apart for
no reason; a vestigial `processes/` directory went away; the dead `engaging`
profile was removed), every setting was given exactly one home so config stops
being layered guesswork, and the diagrams and step tables became *generated* —
`bin/make_diagrams.py` produces them and `--check` fails CI if they drift from
the code. `bin/check_profile_resources.py` joined it as a second guard, added
after a site profile's `withName:` block quietly replaced `base.config`'s
resource requests and OOM-killed seventeen checks in one go.

Two bugs were fixed on the way through: the site profile deleting resources it
had not meant to override, and the repo root being taken from `BASH_SOURCE`
instead of the submit directory.

One thing is still red and it is not ours: the shared `rocky8/halla/0.8.20`
install lost numpy, scipy, pandas and matplotlib on 16 September 2026, so
`STATS:halla` fails on import and suite test 12 cannot pass until somebody
reinstalls it. 37 of 39 tests were green on 17 September 2026.
