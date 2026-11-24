# 3. Install the reference databases

Use the containers you just downloaded to run each tool's own database
installer. You do not need another KneadData, MetaPhlAn, or HUMAnN installation
on the host. The bind/volume options below let the container write databases
into your shared installation, where later tasks can read them.

Keep `BB_ROOT` and the image variables from step 2 set in this shell. Load your
container module again if you started a new session. Use a site-approved node
with network access, sufficient storage, and resources for database extraction
and index building. This installation is done once, before analysis jobs run.

```bash
mkdir -p "$BB_ROOT/databases"/{kneaddata,metaphlan/mpa_vOct22_202403,humann}
```

## KneadData: choose the host reference

Follow the [KneadData database instructions](https://github.com/biobakery/kneaddata#download-the-database).
The example below lists the references available in your image, then downloads
the advertised human Bowtie2 reference. For another host, choose the relevant
entry from that list.

=== "Apptainer"

    ```bash
    apptainer exec --bind "$BB_ROOT:$BB_ROOT" --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/kneaddata.sif" kneaddata_database --available
    apptainer exec --bind "$BB_ROOT:$BB_ROOT" --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/kneaddata.sif" kneaddata_database --download human_genome bowtie2 "$BB_ROOT/databases/kneaddata"
    ```

=== "Docker"

    ```bash
    docker run --rm --user "$(id -u):$(id -g)" --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$KNEADDATA_IMAGE" kneaddata_database --available
    docker run --rm --user "$(id -u):$(id -g)" --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$KNEADDATA_IMAGE" kneaddata_database --download human_genome bowtie2 "$BB_ROOT/databases/kneaddata"
    ```

=== "Podman"

    ```bash
    podman run --rm --userns=keep-id --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$KNEADDATA_IMAGE" kneaddata_database --available
    podman run --rm --userns=keep-id --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$KNEADDATA_IMAGE" kneaddata_database --download human_genome bowtie2 "$BB_ROOT/databases/kneaddata"
    ```

Record the actual reference release printed by the installer. Its name and
extracted directory depend on the image version. Locate the Bowtie2 index
files and use their containing directory as `host_genome` in your site config:

```bash
find "$BB_ROOT/databases/kneaddata" -name '*.1.bt2*'
```

## MetaPhlAn: install a specific marker database

Use the [MetaPhlAn database instructions](https://github.com/biobakery/MetaPhlAn/wiki/MetaPhlAn-4.2#database-installation).
This example explicitly selects the Oct22/202403 index used by this project's
HUMAnN 4 setup. Specifying the index avoids silently installing the newest
default reference.

=== "Apptainer"

    ```bash
    apptainer exec --bind "$BB_ROOT:$BB_ROOT" --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/metaphlan.sif" metaphlan --install --index mpa_vOct22_CHOCOPhlAnSGB_202403 \
      --db_dir "$BB_ROOT/databases/metaphlan/mpa_vOct22_202403"
    ```

=== "Docker"

    ```bash
    docker run --rm --user "$(id -u):$(id -g)" --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$METAPHLAN_IMAGE" metaphlan --install --index mpa_vOct22_CHOCOPhlAnSGB_202403 \
      --db_dir "$BB_ROOT/databases/metaphlan/mpa_vOct22_202403"
    ```

=== "Podman"

    ```bash
    podman run --rm --userns=keep-id --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$METAPHLAN_IMAGE" metaphlan --install --index mpa_vOct22_CHOCOPhlAnSGB_202403 \
      --db_dir "$BB_ROOT/databases/metaphlan/mpa_vOct22_202403"
    ```

Keep the matching Bowtie2 index and `.pkl` together. The site config will use
this directory and the same `metaphlan_index` value.

## HUMAnN: install nucleotide, protein, and mapping databases

Follow the [HUMAnN database instructions](https://github.com/biobakery/humann#5-download-the-databases)
and [utility-mapping instructions](https://github.com/biobakery/humann#humann_regroup_table).
First inspect `--available` in your image. The commands below use the documented
`full` ChocoPhlAn, `uniref90_diamond`, and `full` mapping build names; choose the
compatible entries advertised by your installed release if those differ.

=== "Apptainer"

    ```bash
    apptainer exec --bind "$BB_ROOT:$BB_ROOT" --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/humann.sif" humann_databases --available
    apptainer exec --bind "$BB_ROOT:$BB_ROOT" --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/humann.sif" humann_databases --download chocophlan full "$BB_ROOT/databases/humann" --update-config no
    apptainer exec --bind "$BB_ROOT:$BB_ROOT" --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/humann.sif" humann_databases --download uniref uniref90_diamond "$BB_ROOT/databases/humann" --update-config no
    apptainer exec --bind "$BB_ROOT:$BB_ROOT" --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/humann.sif" humann_databases --download utility_mapping full "$BB_ROOT/databases/humann" --update-config no
    ```

=== "Docker"

    ```bash
    docker run --rm --user "$(id -u):$(id -g)" --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$HUMANN_IMAGE" humann_databases --available
    docker run --rm --user "$(id -u):$(id -g)" --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$HUMANN_IMAGE" humann_databases --download chocophlan full "$BB_ROOT/databases/humann" --update-config no
    docker run --rm --user "$(id -u):$(id -g)" --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$HUMANN_IMAGE" humann_databases --download uniref uniref90_diamond "$BB_ROOT/databases/humann" --update-config no
    docker run --rm --user "$(id -u):$(id -g)" --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$HUMANN_IMAGE" humann_databases --download utility_mapping full "$BB_ROOT/databases/humann" --update-config no
    ```

=== "Podman"

    ```bash
    podman run --rm --userns=keep-id --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$HUMANN_IMAGE" humann_databases --available
    podman run --rm --userns=keep-id --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$HUMANN_IMAGE" humann_databases --download chocophlan full "$BB_ROOT/databases/humann" --update-config no
    podman run --rm --userns=keep-id --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$HUMANN_IMAGE" humann_databases --download uniref uniref90_diamond "$BB_ROOT/databases/humann" --update-config no
    podman run --rm --userns=keep-id --env DXFUSE_ENABLED=false \
      --volume "$BB_ROOT:$BB_ROOT" "$HUMANN_IMAGE" humann_databases --download utility_mapping full "$BB_ROOT/databases/humann" --update-config no
    ```

`--update-config no` keeps the installer from changing configuration inside
the image. Nextflow will pass the database paths from your site config. Record
the resulting nucleotide, protein, and mapping directories:

```bash
find "$BB_ROOT/databases/humann" -maxdepth 2 -type d
```

## Record the paths for configuration

Use the actual extracted locations rather than renaming databases to fit a
configuration example. Keep a note of each release and source with the
installation, and ensure compute nodes can read the files. Reference releases
must match the software stack; the [Tufts environment](../environments/tufts.md),
for example, uses a different HUMAnN 3.7 stack.

| Site parameter | Value to record |
| --- | --- |
| `host_genome` | Directory containing the selected host's Bowtie2 indexes |
| `metaphlan_db` | Marker database directory from the MetaPhlAn command above |
| `metaphlan_index` | `mpa_vOct22_CHOCOPhlAnSGB_202403` for this example |
| `humann_db_chocophlan` | Extracted ChocoPhlAn directory |
| `humann_db_protein` | Extracted UniRef90 directory containing the DIAMOND database |
| `humann_db_utilitymapping` | Extracted mapping directory |

## Describe the inputs

Place a small, approved paired-end FASTQ dataset in your test-data directory.
Keep both mates synchronized. The files below are examples of the names you
will supply, not files downloaded by the tutorial:

```text
$BB_ROOT/data/test/TEST01_R1.fastq.gz
$BB_ROOT/data/test/TEST01_R2.fastq.gz
```

Copy the [sample CSV](examples/smoke-samples.csv) and edit both paths:

```bash
cp "$BB_ROOT/pipeline/docs/get-started/examples/smoke-samples.csv" \
  "$BB_ROOT/config/smoke-samples.csv"
```

```csv
sample,assay,read_1,read_2
TEST01,mgx,/shared/YOUR_GROUP/biobakery/data/test/TEST01_R1.fastq.gz,/shared/YOUR_GROUP/biobakery/data/test/TEST01_R2.fastq.gz
```

`sample` is the identifier retained in the outputs. `assay` is `mgx` for this
metagenomic example. A single-end sample has a `read_1` path and an empty
`read_2` field. Use absolute paths for this first installation to keep path
resolution unambiguous.

Check that both compressed files are readable:

```bash
gzip -t "$BB_ROOT/data/test/TEST01_R1.fastq.gz" \
        "$BB_ROOT/data/test/TEST01_R2.fastq.gz"
```

Continue with [the minimal site configurations and test YAML](site-configuration.md).
