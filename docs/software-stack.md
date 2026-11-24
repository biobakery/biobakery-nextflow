# DNAnexus software and reference versions

This is the deployment record to use when reproducing the DNAnexus stack at
another site. The matching image references and manifest digests are recorded
in [dnanexus-software-stack.json](https://github.com/biobakery/biobakery-nextflow/blob/main/resources/dnanexus-software-stack.json).
Tags were checked against public ECR on 2026-11-23; installed package metadata
and commit environment variables were inspected in the existing images.

Image references use the public ECR registry alias `klepac-ceraj-lab`. The
registry alias change preserves the recorded image digests. Refresh the
DNAnexus image cache when switching existing builds to these identifiers.

## Tool versions

| Tool | Installed version | Source or reference |
| --- | --- | --- |
| KneadData | 0.12.1 | Versioned `0.12.1-…-r1` images |
| MetaPhlAn | 4.2.5 | Primary marker index `mpa_vOct22_CHOCOPhlAnSGB_202403` |
| HUMAnN | 4.0.0a2 | [Commit `9cb1a8253e11a0a8ed8f58f85f53e04a690e40a6`](https://github.com/biobakery/humann/commit/9cb1a8253e11a0a8ed8f58f85f53e04a690e40a6) |
| BAQLaVa | 1.2.0.dev0 | [Commit `629c744a553eb534be457050ca8b7b33f177e0da`](https://github.com/biobakery/baqlava/commit/629c744a553eb534be457050ca8b7b33f177e0da) |
| HUMAnN inside BAQLaVa's image | 4.0.0a1 | BAQLaVa's internal processing environment |
| DIAMOND inside BAQLaVa's image | 2.0.15 | Retained for its viral DIAMOND database compatibility |

The BAQLaVa image tag `4.0.0-r1` is a packaging identifier. The installed
BAQLaVa package is `1.2.0.dev0`; its source version metadata was normalized
when building. That image also replaces local `scp` calls with `cp` and admits
the known `BAQLaVa_ORFs_90ID_201901b.dmnd` filename when an annotation mapping is
supplied. These adaptations are part of the image being reproduced.

The `experimental` component in the versioned HUMAnN image names describes
the prerelease software. Runtime defaults use full version/revision tags,
such as `4.0.0-experimental-nodb-dnanexus-r1`, and the deployment record also
contains their immutable digests. Bare `:experimental` and `:latest` aliases
are not runtime defaults.

## Is `_lon_subsp` required?

No. The shared stack can use the primary Oct22/202403 index above. The
`_lon_subsp` reference is an optional project-specific variant illustrated in
the multi-database YAML examples. Harvard does not need it to reproduce the
primary-reference run. Keep its files and index name together if you choose
to enable it.

The existing MetaPhlAn 3 / 4.0.x command-line dialect remains available through
`metaphlan_v3` and `metaphlan_4.0.6_fixed` for sites still using those builds.

## What does `chocophlan-v4-201901` contain?

This is the name of the reference bundle used by this deployment. Its contents
include:

| Directory | Observed contents |
| --- | --- |
| `chocophlan/` | SGB nucleotide pangenomes, named `SGB…_pangenome90.fna.gz` |
| `uniref90_annotated/` | `humann4_protein_database_filtered_v2019_06.dmnd` |
| `full_mapping/` | Utility mappings, including `vOct22_SGB_mapping.tsv`, `map_level4ec_uniclust90.txt.gz`, and `map_level4ec_name.txt.gz` |

Record these contents when transferring the bundle. A directory or tarball
name alone does not identify its nucleotide, protein, and mapping releases.
The pipeline passes all three directories explicitly to HUMAnN. BAQLaVa also
receives all three for its bacterial-depletion stage, alongside its own viral
references. See [reference staging](dnanexus.md#project-references-on-local-ssd).

## EC defaults and site migration

All profiles include an `ecs` regroup by default. HUMAnN 3.7 uses the
`uniref90_level4ec` scheme; HUMAnN 4 uses `uniclust90_level4ec`, reflecting its
`map_level4ec_uniclust90.txt.gz` mapping. DNAnexus's explicit mapping defaults
retain EC, KO, and Pfam outputs. A study YAML can replace these lists, including
`humann_regroups: []` to disable regrouping.

Harvard's installed module paths remain in its site profile until the new
stack is installed there. Coordinate that installation using the versions
above, then update the Harvard module names and reference paths together.
Do not invent replacement module names before the installation exists.

The image-reference updates use already-published images; they require no new
image build. Refresh the DNAnexus image cache for the changed identifiers before
building an applet that uses them.
