#!/bin/bash
#SBATCH --job-name=biobakery-nf-tests
#SBATCH --partition=hsph
#SBATCH --mem=24G
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=4
#SBATCH --output=tests/results/slurm_%j.out
#SBATCH --error=tests/results/slurm_%j.err

# Run tests/run_tests.sh as a SLURM job, from the repo root:
#
#   cd /path/to/biobakery-nextflow
#   mkdir -p tests/results && sbatch tests/submit_tests.sh
#
# The --output paths above are relative to the submitting directory, which is
# why this has to be submitted from the repo root. tests/results must exist
# first: SLURM will not create it, and the job fails silently if it is missing.
#
# The repo root comes from SLURM_SUBMIT_DIR for the same reason: sbatch runs a
# spool copy of this script, so $BASH_SOURCE points at /var/spool/slurmd/... and
# not at the checkout. The BASH_SOURCE fallback is for running it directly.
#
# The suite runs about a dozen nextflow drivers at once, each its own JVM, which
# is what the memory and cpu requests are for. The drivers only submit and wait;
# the real work happens in the SLURM jobs they spawn.

set -euo pipefail

if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
    REPO_ROOT="${SLURM_SUBMIT_DIR}"
else
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ ! -f "${REPO_ROOT}/tests/run_tests.sh" ]]; then
    echo "Not a biobakery-nextflow checkout: ${REPO_ROOT}" >&2
    echo "Submit this from the repo root: cd <repo> && sbatch tests/submit_tests.sh" >&2
    exit 2
fi

source /n/lab_storage/huttenhower_lab/tools/hutlab/src/hutlabrc_rocky8.sh
module use /n/lab_storage/huttenhower_lab/tools/hutlab/src/modules_rocky8
module load jdk/21.0.2-fasrc01
export PATH="/n/lab_storage/huttenhower_lab/tools/nextflow/24.10.4/bin:${PATH}"

nextflow -version

cd "${REPO_ROOT}"
bash tests/run_tests.sh
