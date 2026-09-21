# Release history

Newest first. Hand-written, not generated — read the code at a deployment for
the authoritative list of what it contains.

> There are no `v0.0.x` git tags (`v0.1` and `v0.2` belong to the older AWS-era
> work and don't correspond). The `0.0.x` numbers are hutlab deployment
> numbers, and the commit boundaries below were reconstructed from deployment
> dates, so treat them as close rather than exact.

---

## Unreleased — the cleanup

On `feature/standard-biobakery-workflow`. Housekeeping, not features: 14
deletions and 17 renames.

- One home per setting, so config stops being layered guesswork.
- Diagrams and step tables are now generated — `bin/make_diagrams.py`, and
  `--check` fails CI when they drift from the code.
- `bin/check_profile_resources.py` added, after a site profile's `withName:`
  block quietly replaced `base.config`'s resource requests and OOM-killed
  seventeen checks in one go.
- `test/` and `tests/` merged; the vestigial `processes/` directory and the
  dead `engaging` profile removed.
- Fixed: the site profile deleting resources it never meant to override.
- Fixed: the repo root came from `BASH_SOURCE` instead of the submit directory.
- Still red, and not ours: the shared `rocky8/halla/0.8.20` install lost numpy,
  scipy, pandas and matplotlib on 16 Sep 2026, so `STATS:halla` fails on import
  and test 12 can't pass. 37/39 green on 17 Sep 2026.

## 0.0.4 — 2 September 2026

Everything else in upstream 3.2. ~8,500 lines, 61 new files.

- `vis` and `stats` ported from `biobakery_workflows` 3.2 — the bulk of it.
- anadama2's document layer vendored rather than rewritten, which is why
  `bin/lib/` exists.
- `bin/scripts/` filled with Python 3 replacements for upstream scripts that
  never worked on py3 (`norm_ratio` being the memorable one).
- MTX and MGX+MTX ported. This is what makes `subworkflows/` earn its keep:
  `mgx_mtx` runs QC, taxonomic and functional profiling twice over two read
  sets, and aliased includes are the only way to do that once.
- `vis` became chained — it runs at the end of the read-based workflows instead
  of needing its own invocation.
- Made to survive real input: single-end and multi-sample assembly, pairs
  merged when QC is bypassed, the single-end glob fallback when `filepattern`
  carries a pair identifier, HUMAnN columns named for the sample on one-sample
  runs, and small or sparse studies no longer taking the vis report down.
- Every workflow except 16s now tested in both library layouts.
- Deployed twice — the 31 Aug tree is still sitting there as
  `0.0.4.superseded-20260902`, which is the fingerprint of a release that
  needed a second pass.

## 0.0.3 — 6 August 2026

The shakedown. Small on paper (687 insertions, nearly all modifications) and
more important than it looks: things that had never been run properly got run
properly, and broke.

- `quality_control` emitted a channel named `log`, but Nextflow binds `log` to
  its own logger in a workflow body — so `mgx`, `mtx`, `mgx_mtx` and `assembly`
  all died with `No such variable: log` before submitting a single task.
  Nothing consumed the emit; renaming it to `logs` fixed all four.
- Assembly brought in line with upstream 3.2 and finally given its per-sample
  abundance stage.
- `metaphlan_merge` and `metaphlan_bzip` got module environments they had been
  silently borrowing.
- Viral flag standardised on `run_viral_profiling`.
- Template params trimmed to real `lab_storage` paths.
- Stray `metaphlanstart.nf` deleted from the repo root.

This is where the pipeline stopped working only on the machine it was written
on.

## 0.0.2 — 9 July 2026

"Standard repo" — the repository gets a shape. ~8,800 lines, 74 of them new
files.

- The `modules/` + `subworkflows/` + `workflows/` layout laid down, every tool
  call moved into its own module directory.
- First real tree under `tools/`, so the module loads a deployment instead of
  pointing at someone's home directory.
- Assembly workflow appears, in draft — it took two more releases to actually
  produce MAGs on real input.

## 0.0.1 — June 2026

The first thing anyone else could load. A metagenomics pipeline and nothing
more.

- KneadData, MetaPhlAn 4, HUMAnN **3**, plus the BAQLaVa viral step, running on
  Harvard FASRC.
- No code directory under `tools/` — only a modulefile, putting Nextflow
  24.10.4 and the HUMAnN 3 database paths on your environment. You ran it out
  of a personal checkout.
- A working pipeline, not yet a shipped one.
