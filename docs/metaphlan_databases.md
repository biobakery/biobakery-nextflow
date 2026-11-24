# MetaPhlAn databases

Configure one or more MetaPhlAn databases in a site database config:

```groovy
params {
    metaphlan_databases = [
        [
            metaphlan_db: '/Databases/metaphlan/oct22',
            metaphlan_index: 'mpa_vOct22_CHOCOPhlAnSGB_202403',
            metaphlan_version: 'metaphlan_4.0.6_fixed'
        ],
        [
            metaphlan_db: '/Databases/metaphlan/jun23',
            metaphlan_index: 'mpa_vJun23_CHOCOPhlAnSGB_202307',
            metaphlan_version: 'metaphlan_v4'
        ]
    ]
    metaphlan_downstream_indices = ['mpa_vOct22_CHOCOPhlAnSGB_202403']
}
```

When more than one database is configured, every sample runs once against every database, compressing its SAM in the same
task. Profiles, compressed SAM files and merged tables are kept separately under
`metaphlan/<metaphlan_index>/`. Index names must be unique, safe directory names.

`metaphlan_downstream_indices` selects which databases feed HUMAnN, BAQLaVa,
StrainPhlAn, and chained vis/stats reports. Supply a non-empty list of configured
index names. To use multiple databases downstream, list each index. If omitted,
the first configured database is selected. The existing `run_*` switches still
control which stages execute.

Each selected database has its own downstream results under
`databases/<metaphlan_index>/`, with unchanged sample names. HUMAnN merges,
StrainPhlAn marker collections, report inputs and RNA/DNA ratios stay within the
same database. In mgx_mtx, mapped RNA samples inherit each selected DNA profile;
RNA/DNA ratios match both database and feature type.

`metaphlan_version` is optional per entry and falls back to the global parameter.
It selects the existing CLI dialect: `metaphlan_v4` uses `--db_dir` and `--mapout`;
other values use `--bowtie2db` and `--bowtie2out`. It does not install a tool or
switch container images. The profile's tool environment must support the
configured databases, and downstream tools must support the selected profiles.

HUMAnN runs profiling, all selected regroup/name operations and per-sample
normalization in one task for each sample/database pair. Cohort merging uses
one task per database for all feature types and their relative-abundance
tables. These boundaries apply to every execution profile and retain the
existing published file paths and downstream feature labels.

The same settings can be passed using `-params-file` with YAML arrays:

```yaml
metaphlan_databases:
  - metaphlan_db: /Databases/metaphlan/oct22
    metaphlan_index: mpa_vOct22_CHOCOPhlAnSGB_202403
    metaphlan_version: metaphlan_4.0.6_fixed
  - metaphlan_db: /Databases/metaphlan/jun23
    metaphlan_index: mpa_vJun23_CHOCOPhlAnSGB_202307
metaphlan_downstream_indices:
  - mpa_vOct22_CHOCOPhlAnSGB_202403
  - mpa_vJun23_CHOCOPhlAnSGB_202307
```

A one-entry `metaphlan_databases` array retains the legacy single-database
layout too: merged taxonomy and `bzip/` are directly under `metaphlan/`, and
downstream outputs have no `databases/<index>/` prefix. `_lon_subsp` is an
optional project reference variant, not a requirement for the primary Oct22
index or HUMAnN.

For older configurations, leaving `metaphlan_databases` unset uses the existing
`metaphlan_db`, `metaphlan_index`, and `metaphlan_version` parameters and retains
the previous output layout. An explicit empty database or selection array is an
error.

Run the database routing tests with:

```bash
python3 -m unittest discover -s tests -p test_metaphlan_databases.py
```

These run Nextflow against mocked bioBakery executables, checking task fan-out,
CLI arguments, separate merges, downstream selection, report routing, legacy
configuration, and invalid input. They do not validate real biological results.
