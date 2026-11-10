# Wellesley Hopper configuration

Three files have separate responsibilities and the same site prefix:

| File | Responsibility |
| --- | --- |
| `conf/profiles/wellesley_hopper.config` | Local executor, Docker runtime, image assignments and helper mounts |
| `conf/databases/wellesley_hopper.config` | Site reference directories, including the MetaPhlAn root and HUMAnN utility mapping root |
| `conf/example_yamls/wellesley_hopper.yaml` | Inputs/output, enabled analyses, reference selections, regrouping and optional renaming |

Run from the repository root:

```bash
NXF_VER=25.10.4 nextflow run main.nf \
  -profile wellesley_hopper \
  -params-file my-hopper-study.yaml \
  -resume
```

The profile loads both `.config` files. Copy
`conf/example_yamls/wellesley_hopper.yaml` to `my-hopper-study.yaml`, set exactly
one of `samplesheet` or `readsdir`, and choose the output location. The YAML is
loaded only with `-params-file`. Relative paths use the launch directory;
retain your previous output location when resuming.
Command-line parameter overrides take precedence over the YAML.

The database config contains no mapping lists or analysis switches. Relative
`metaphlan_db` entries in YAML resolve against `metaphlan_db_root`. Relative
`group_mapping_database` and `renaming_database` filenames resolve against
`humann_db_utilitymapping`. Absolute paths and URI paths are passed through.
YAML does not expand `${params...}` expressions; the workflow resolves these
specific relative path fields explicitly.

The profile alone selects the primary MetaPhlAn reference and HUMAnN 4.
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

The Docker profile remains `wellesley_hopper` (underscore). KneadData and
HUMAnN use their database-bearing images. MetaPhlAn and StrainPhlAn use the
corrected host references under `/murray/databases/metaphlan/mpa_vOct22_202403`.
DNAnexus download hooks are not enabled by this profile. The example now
also enables strain profiling: marker extraction shares the MetaPhlAn task,
and cohort phylogenies use the MetaPhlAn image. Fewer than four samples retain
markers and skip phylogenies.

BAQLaVa uses the dedicated local `baqlava:4.0.0-r1` image, with 8 CPUs and
48 GB requested memory. The example enables viral profiling. Its database-free
image uses these host references from `conf/databases/wellesley_hopper.config`:

| Parameter | Host directory |
| --- | --- |
| `baqlava_db_nucleotide` | `/murray/databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.nucleotide` |
| `baqlava_db_protein` | `/murray/databases/baqlava/BAQLaVa_v05/BAQLaVa.V0.5.protein` |
| `baqlava_depletion_db` | `/murray/databases/humann/chocophlan-v4-201901/chocophlan` |
| `baqlava_depletion_protein_db` | `/murray/databases/humann/chocophlan-v4-201901/uniref90_annotated` |
| `baqlava_depletion_mapping_db` | `/murray/databases/humann/chocophlan-v4-201901/full_mapping` |

`baqlava_db_location = 'host'` lets Nextflow stage and mount these inputs. The
runtime profile binds the three full HUMAnN reference folders read-only under
`/Databases/humann/chocophlan-v4-201901/`, as `chocophlan`,
`uniref90_annotated`, and `full_mapping`. The BAQLaVa Dockerfile configures
HUMAnN to use exactly these paths with `humann_config --update`. Before analysis,
the module checks HUMAnN's effective configuration against the declared full
inputs and rejects `utility_DEMO` even if full data is mounted there: HUMAnN
uses that directory name to activate its demo-size restriction. Override the
host source paths through site config or run parameters.

BAQLaVa 1.2 already ships its annotation mappings; leave the legacy
`baqlava_nucleotide_mapping` and `baqlava_protein_mapping` parameters unset for
this image. Its pinned upstream source uses `scp` for local intermediate-file copies. The
Dockerfile changes those commands to `cp`, avoiding OpenSSH's user lookup when
Docker runs as a numeric host UID absent from `/etc/passwd`. Rebuild the image
after these source/config changes before running viral profiling. No DNAnexus applet build is needed for Hopper.

HUMAnN 4 also applies its UniRef release filename check to BAQLaVa's custom
protein database. `BAQLaVa_ORFs_90ID_201901b.dmnd` is not a UniRef release; its
date need not contain HUMAnN's expected `2019_06`. The BAQLaVa Dockerfile adds
a compatibility exception only for that exact filename when an explicit
`--id-mapping` is supplied. Ordinary UniRef release validation, translated
database format checks and DIAMOND executable checks remain enabled. The viral
database itself is unchanged. Metadata and sequence-ID checks confirmed that
the installed DIAMOND reads it and that its identifiers match the image's
protein annotation table. Rebuild the BAQLaVa image after this Dockerfile change
before resuming the pipeline.
