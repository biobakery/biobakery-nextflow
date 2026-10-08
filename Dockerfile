# biobakery-nextflow — combined tool image (no databases)
# Compatible stack: KneadData 0.12 + MetaPhlAn 4.0.6 (vOct22_CHOCOPhlAnSGB_202403) + HUMAnN 3.9
# Databases must be mounted at runtime (e.g. -v /path/to/dbs:/databases)
#
# Build:  docker build -t biobakery-nextflow .
# Run:    nextflow run main.nf -profile standard \
#           --host_genome /databases/kneaddata/hg38 \
#           --metaphlan_db /databases/metaphlan/mpa_vOct22_CHOCOPhlAnSGB_202403 \
#           --metaphlan_index mpa_vOct22_CHOCOPhlAnSGB_202403 \
#           --humann_db /databases/humann3

FROM mambaorg/micromamba:1.5.8

USER root

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        procps \
        pigz \
    && rm -rf /var/lib/apt/lists/*

# Install biobakery tools via conda channels
RUN micromamba install -y -n base \
        -c biobakery \
        -c conda-forge \
        -c bioconda \
        "kneaddata>=0.12" \
        "metaphlan=4.0.6" \
        "humann>=3.9,<4" \
    && micromamba clean -afy

ENV PATH="/opt/conda/bin:${PATH}"

WORKDIR /data
CMD ["bash"]
