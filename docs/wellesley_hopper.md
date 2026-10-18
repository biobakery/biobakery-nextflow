# Wellesley Hopper configuration

Three files have separate responsibilities and the same site prefix:

| File | Responsibility |
| --- | --- |
| `conf/profiles/wellesley_hopper.config` | Local executor, Docker runtime, image assignments and helper mounts |
| `conf/databases/wellesley_hopper.config` | Site reference directories, including the MetaPhlAn root and HUMAnN utility mapping root |
| `conf/wellesley_hopper.yaml` | Inputs/output, enabled analyses, reference selections, regrouping and optional renaming |

Run from the repository root:

```bash
NXF_VER=25.10.4 nextflow run main.nf \
  -profile wellesley_hopper \
  -params-file conf/wellesley_hopper.yaml \
  -resume
```

The profile loads both `.config` files. The YAML is loaded only when passed with
`-params-file`. Copy it for each study and change the samplesheet and output
location. The supplied example uses `samplesheet.csv` and `results`, relative
to the launch directory; retain your previous output location when resuming.
Command-line parameter overrides take precedence over the YAML.

The database config contains no mapping lists or analysis switches. Relative
`metaphlan_db` entries in YAML resolve against `metaphlan_db_root`. Relative
`group_mapping_database` and `renaming_database` filenames resolve against
`humann_db_utilitymapping`. Absolute paths and URI paths are passed through.
YAML does not expand `${params...}` expressions; the workflow resolves these
specific relative path fields explicitly.

The supplied YAML selects both existing MetaPhlAn references, with only the
original first reference feeding HUMAnN and other downstream analyses. It
selects EC, KO and Pfam mapping/renaming files using the existing filenames.
Remove entries or set `humann_regroups: []` to skip regrouping; omit
`renaming_database` to skip naming for one entry.

Reports and stats are explicitly disabled in the example while their dedicated
image is pending. Enable them in your study YAML after that image is available;
stats also requires metadata. No image build or container-repository changes
are made by this configuration reorganization.

The old `wellesley_hopper-local.config` filenames are replaced by
`wellesley_hopper.config` in both directories. The public profile name remains
`wellesley_hopper`. The copied Harvard PhyloPhlAn path was removed; configure an
actual Hopper reference before running assembly.

Hopper's HUMAnN mapping paths live inside `humann:experimental`, not on the host.
The database config sets `humann_db_location = 'container'`, so mapping
paths are passed directly to regrouping/renaming and checked inside the image.
No host existence check or staging is attempted for these files. To supply an
external mapping instead, set `database_location: host` on that mapping entry;
the file must then exist on the Nextflow host and will be staged normally.

All database-consuming tools use `<tool>_db_location`, with values `host` or
`container`: `kneaddata`, `metaphlan`, `humann`, `strainphlan`, `baqlava`,
`phylophlan`, and `checkm2`. Host references are declared path inputs and staged;
container references retain their runtime paths. The default is host. The
Hopper database config explicitly declares the locations for each tool.

`humann_db_location` covers the nucleotide, protein and utility mapping
references; an individual regroup may override its mapping files with
`database_location`. `kneaddata_db_location` replaces the earlier
`kneaddata_reference_mode` parameter (`staged` becomes `host`).

Optional databases may remain unset to use the tool's environment default.
Set `checkm2_db` for an explicit CheckM2 database, or `strainphlan_db` for an
explicit StrainPhlAn reference. PhyloPhlAn reference discovery now happens in
the task so image references are visible. Other assembly tools that do not
consume an external reference database need no location selector.
