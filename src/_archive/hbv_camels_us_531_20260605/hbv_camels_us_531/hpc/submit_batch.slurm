#!/bin/bash
#SBATCH --job-name=hbv531
#SBATCH --partition=hgpu8
#SBATCH --exclude=ngu001,ngu201,ngu202
#SBATCH --array=0-10
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=06:00:00
#SBATCH -o logs/08_hbv_camels_us_531/hbv_%a-%j.out
#SBATCH -e logs/08_hbv_camels_us_531/hbv_%a-%j.err

set -eo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
BASIN_FILE="src/full_531_basins/data/531_basin_list.txt"
OUTPUT_DIR="results/08_hbv_camels_us_531"
N_CHUNKS=11
DATA_ROOT="${DATA_ROOT:-data/CAMELS_US}"
CONDA_ENV="${CONDA_ENV:-nh_final}"

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
echo "[$(date)] Job ${SLURM_JOB_ID} task ${SLURM_ARRAY_TASK_ID} starting on $(hostname)"

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh || \
source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV"

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
export MKL_THREADING_LAYER=GNU

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
echo "[INFO] Python: $(python --version 2>&1)"
echo "[INFO] Basin file: ${BASIN_FILE} ($(wc -l < ${BASIN_FILE}) basins)"
echo "[INFO] Chunk: ${SLURM_ARRAY_TASK_ID}/${N_CHUNKS}"
echo "[INFO] Output: ${OUTPUT_DIR}/chunk_$(printf '%02d' ${SLURM_ARRAY_TASK_ID})"

mkdir -p "logs/08_hbv_camels_us_531"
mkdir -p "${OUTPUT_DIR}"

[ -f "${BASIN_FILE}" ] || { echo "[FATAL] Basin file not found: ${BASIN_FILE}"; exit 1; }

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
python -u -m src.hbv_camels_us_531.scripts.run_hbv_camels_us_531 \
    --basin-file "${BASIN_FILE}" \
    --data-root "${DATA_ROOT}" \
    --output-dir "${OUTPUT_DIR}" \
    --chunk-index "${SLURM_ARRAY_TASK_ID}" \
    --n-chunks "${N_CHUNKS}"

EXIT_CODE=$?
echo "[$(date)] Chunk ${SLURM_ARRAY_TASK_ID} finished (exit: ${EXIT_CODE})"
exit $EXIT_CODE
