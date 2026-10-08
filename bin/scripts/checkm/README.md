# Vendored CheckM 1.2.0 (partial)

This is a trimmed copy of [CheckM](https://github.com/Ecogenomics/CheckM) 1.2.0,
carrying only what `checkm coverage` and `checkm profile` need. It is invoked
through `bin/scripts/checkm.py`, by the `abundance` process
(`modules/utils/abundance/main.nf`).

## Why it is here

The assembly workflow uses two different CheckMs, for two different jobs:

* **CheckM2** — MAG completeness and contamination, in the `checkm2` process.
  It comes from `rocky8/biobakeryworkflows/3.2` and is not vendored.
* **CheckM 1** — per-sample MAG abundance, here. CheckM2 is a rewrite rather
  than a new version and dropped the `coverage` and `profile` subcommands, which
  is the step the anadama2 assembly workflow uses to turn a sample's BAM and its
  bins into an abundance table. There is no CheckM2 equivalent, so the CheckM 1
  code for those two subcommands is carried along.

Neither substitutes for the other. See `docs/dependencies.md`.

Nothing else in CheckM is included: no `lineage_wf`, no `tree`, no plotting, and
no reference data — `coverage` and `profile` need none.

## Licence

CheckM is distributed under the GNU General Public License v3. Every file here
carries the GPLv3 header; the full text is at <https://www.gnu.org/licenses/gpl-3.0.txt>
and should be added as `LICENSE` in this folder next time the repo has network
access. Copyright the CheckM authors (Donovan Parks et al., Australian Centre
for Ecogenomics). This copy is unmodified except for the removal of unused
modules.

Note that GPLv3 is more restrictive than the licence on the rest of this
repository, and it applies to this folder.
