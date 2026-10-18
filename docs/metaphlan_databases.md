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

Every sample runs once against every database. Profiles, compressed SAM files,
merged tables, and species counts are kept separately under
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
