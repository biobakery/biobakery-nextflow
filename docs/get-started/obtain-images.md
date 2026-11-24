# 2. Download the container images

With your chosen runtime loaded, obtain images for KneadData, MetaPhlAn, and
HUMAnN. Each image packages the tool and its dependencies, so you can use the
same environment for installing its database and later processing samples.

The examples below use database-free images already used by this project.
They target Linux **x86-64**; the HUMAnN image contains an experimental HUMAnN 4
build. If your site supplies a different stack, use matching references and
adjust the image assignments in your site config accordingly.

## Pull the images with your chosen runtime

Run downloads on the node your site permits. Set these identifiers once in
this shell; the database-installation commands in the next chapter reuse them:

```bash
export KNEADDATA_IMAGE=public.ecr.aws/klepac-ceraj-lab/kneaddata:0.12.1-nodb-dnanexus-r1
export METAPHLAN_IMAGE=public.ecr.aws/klepac-ceraj-lab/metaphlan:4.2.5-nodb-dnanexus-r1
export HUMANN_IMAGE=public.ecr.aws/klepac-ceraj-lab/humann:4.0.0-experimental-nodb-dnanexus-r1
```

Select the tab for your runtime. You only need one of these sets of commands.

=== "Apptainer"

    ```bash
    apptainer pull "$BB_ROOT/containers/kneaddata.sif" "docker://$KNEADDATA_IMAGE"
    apptainer pull "$BB_ROOT/containers/metaphlan.sif" "docker://$METAPHLAN_IMAGE"
    apptainer pull "$BB_ROOT/containers/humann.sif" "docker://$HUMANN_IMAGE"
    ```

    Apptainer converts registry images to SIF files; `docker://` does not
    require a Docker daemon. Keep these files on shared storage readable by
    compute nodes. If conversion needs more space, use site-approved locations
    for `APPTAINER_CACHEDIR` and `APPTAINER_TMPDIR`.

=== "Docker"

    ```bash
    docker pull "$KNEADDATA_IMAGE"
    docker pull "$METAPHLAN_IMAGE"
    docker pull "$HUMANN_IMAGE"
    ```

    Pull using the daemon that will run the containers. On a cluster, ask how
    images are made available to worker daemons: pulling on a login node does
    not populate every worker's image store.

=== "Podman"

    ```bash
    podman pull "$KNEADDATA_IMAGE"
    podman pull "$METAPHLAN_IMAGE"
    podman pull "$HUMANN_IMAGE"
    ```

    Pull as the account that will run the containers. On a cluster, follow
    the site's image-distribution procedure for workers. The examples use
    rootless Podman with `--userns=keep-id` when writing to host storage.

The historical `nodb-dnanexus` names identify image variants. These examples
use ordinary host database directories and disable the images' mount helper
with `DXFUSE_ENABLED=false`; no DNAnexus credentials or FUSE mount are needed.

## Check the programs

Run the checks where your site allows container execution, preferably in a
compute-node allocation on HPC:

=== "Apptainer"

    ```bash
    apptainer exec --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/kneaddata.sif" kneaddata --version
    apptainer exec --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/metaphlan.sif" metaphlan --version
    apptainer exec --env DXFUSE_ENABLED=false \
      "$BB_ROOT/containers/humann.sif" humann --version
    ```

=== "Docker"

    ```bash
    docker run --rm --env DXFUSE_ENABLED=false "$KNEADDATA_IMAGE" kneaddata --version
    docker run --rm --env DXFUSE_ENABLED=false "$METAPHLAN_IMAGE" metaphlan --version
    docker run --rm --env DXFUSE_ENABLED=false "$HUMANN_IMAGE" humann --version
    ```

=== "Podman"

    ```bash
    podman run --rm --env DXFUSE_ENABLED=false "$KNEADDATA_IMAGE" kneaddata --version
    podman run --rm --env DXFUSE_ENABLED=false "$METAPHLAN_IMAGE" metaphlan --version
    podman run --rm --env DXFUSE_ENABLED=false "$HUMANN_IMAGE" humann --version
    ```

Record the reported versions. For a study, also retain SIF checksums or registry
digests alongside the workflow revision, so a mutable image tag does not become
your only record of the software used.

Continue with [installing databases through these containers](containers-and-databases.md).
