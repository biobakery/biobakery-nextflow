# bioBakery workflow utilities

Several processes previously invoked scripts supplied by `biobakery_workflows`
by bare filename. These are accessory scripts, rather than HUMAnN or MetaPhlAn
commands. An installation that lacks those executables on `PATH` could run the
profilers successfully and then fail during counts or report preparation.

The pipeline now calls these bundled scripts through Python and an explicit
`${projectDir}/bin/scripts/` path:

| Helper | Used for |
| --- | --- |
| `count_features.py` | MetaPhlAn species counts and HUMAnN feature counts |
| `get_counts_from_humann_logs.py` | HUMAnN read and species summary |
| `create_feature_table.py` | Stats and visualization feature tables |
| `trim_taxonomy.py` | 16S taxonomy table preparation |
| `rna_dna_norm.py` | RNA/DNA normalization, through `rna_dna_norm_py3.py` |

`rna_dna_norm_py3.py` now patches the bundled source instead of searching for an
installed executable. Its existing text-output and empty-input fixes remain.
`permanova_hmp2.R` is also bundled and resolved by `biobakery_bootstrap.py`.

These copies come from bioBakery workflows 3.2, upstream commit
`8e6800689169863b6cc5b52c9d3188c058fffdb2`:
https://github.com/biobakery/biobakery_workflows/tree/8e6800689169863b6cc5b52c9d3188c058fffdb2
The upstream license is retained in `bin/lib/LICENSE-biobakery_workflows`.
The bundled report package includes `utilities`, `visualizations`, `files`,
and report methods text and workflow images. Its resource resolver points at
this repository's patched templates and R scripts. `trim_taxonomy.py` loads the
bootstrap and inserts the taxonomy column instead of overwriting a data column.
The PERMANOVA helper uses `adonis2(..., by="terms")` through an adapter that
retains the table interface required by its block permutation calculations.
Covariate construction joins explicit effects with ` + ` and preserves metadata
order when deriving effects.

Reports and 16S taxonomy trimming use the bundled Python modules; installing
`biobakery_workflows` is no longer required for those paths. Rendering still
requires the existing Python plotting/report dependencies, and R scripts require
their R packages. MetaPhlAn's `merge_metaphlan_tables.py`, `sample2markers.py`, and
`strainphlan.py` still come from MetaPhlAn. HUMAnN's `humann_*` commands come
from HUMAnN itself.

## Hopper Docker execution

The `wellesley_hopper` profile explicitly mounts `bin/scripts`, `bin/lib`,
`bin/Rscripts`, and `assets` read-only at their original absolute paths.
This preserves the layout used by `${projectDir}` and by Python bootstrap
resource discovery. Work directories and published outputs are not included in
these read-only mounts. The Docker daemon must run on a machine that can access
the checkout at those paths.

HUMAnN feature/log counts and RNA/DNA normalization use the HUMAnN container.
Other processes without a container selector in this profile, including most
stats/report processes, still execute in the host environment and need their
Python/R dependencies there. The installed `pipeline-utils:2026` image was
inspected and contains neither Python nor R; it is not a report runtime.
These mounts solve file visibility, not missing software inside an image.
