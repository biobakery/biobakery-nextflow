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
# The suite runs about a dozen nextflow drivers at once, each its own JVM, which
# is what the memory and cpu requests are for. The drivers only submit and wait;
# the real work happens in the SLURM jobs they spawn.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source /n/lab_storage/huttenhower_lab/tools/hutlab/src/hutlabrc_rocky8.sh
module use /n/lab_storage/huttenhower_lab/tools/hutlab/src/modules_rocky8
module load jdk/21.0.2-fasrc01
export PATH="/n/lab_storage/huttenhower_lab/tools/nextflow/24.10.4/bin:${PATH}"

nextflow -version

cd "${REPO_ROOT}"
bash tests/run_tests.sh
