#!/usr/bin/env bash
# =============================================================================
# 正式全量: 531 basins x 3 models x 5000 trials
#
# Array job: 33 tasks = 11 chunks x 3 models
#   task 0-10:  xaj_pdd   chunk_001..011
#   task 11-21: hbv       chunk_001..011
#   task 22-32: gr4j_pdd  chunk_001..011
#
# 每个 task 约 50 basins x 5000 trials ≈ 12-14 小时
#
# Usage:
#   sbatch src/xaj_global_pilot/hpc/submit_benchmark_531.slurm
#
# 部分重跑 (例如只重跑 task 5 和 task 18):
#   sbatch --array=5,18 src/xaj_global_pilot/hpc/submit_benchmark_531.slurm
# =============================================================================
#SBATCH -J xaj-bench
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 24:00:00
#SBATCH --array=0-32
#SBATCH -o logs/10_global_conceptual_model_benchmark/bench_%a-%j.out
#SBATCH -e logs/10_global_conceptual_model_benchmark/bench_%a-%j.err

set -eo pipefail

# --- 环境 ---
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}" || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

# --- 参数 ---
IDEA="10_global_conceptual_model_benchmark"
OUTPUT_DIR="results/${IDEA}/camels_us_531_v02"
CHUNK_DIR="${OUTPUT_DIR}/chunks"
DATA_ROOT="data/camels_us"
TRIALS=5000
N_CHUNKS=11

mkdir -p "logs/${IDEA}" "${OUTPUT_DIR}"

# --- 从 array task ID 算出 model + chunk ---
MODELS=(xaj_pdd hbv gr4j_pdd)
MODEL_IDX=$((SLURM_ARRAY_TASK_ID / N_CHUNKS))
CHUNK_IDX=$((SLURM_ARRAY_TASK_ID % N_CHUNKS + 1))
MODEL=${MODELS[$MODEL_IDX]}
CHUNK_FILE="${CHUNK_DIR}/chunk_$(printf '%03d' ${CHUNK_IDX}).txt"

# --- Pre-flight ---
echo "=========================================="
echo "[$(date)] XAJ Benchmark — Task ${SLURM_ARRAY_TASK_ID}/32"
echo "=========================================="
echo "[INFO] Job: $SLURM_JOB_ID, Node: $(hostname)"
echo "[INFO] Model: ${MODEL}, Chunk: ${CHUNK_IDX}/11"
echo "[INFO] Chunk file: ${CHUNK_FILE}"
echo "[INFO] Trials: ${TRIALS}, Data: ${DATA_ROOT}"
echo "[INFO] Python: $(python --version 2>&1)"

[ -d "$DATA_ROOT" ] || { echo "[FATAL] Data not found: $DATA_ROOT"; exit 1; }
[ -f "$CHUNK_FILE" ] || { echo "[FATAL] Chunk file not found: $CHUNK_FILE"; exit 1; }

python -c "from src.xaj_global_pilot.runner import run_single_model_basin; print('[INFO] Import OK')" \
    || { echo "[FATAL] Import failed"; exit 1; }

echo "[INFO] Basins in chunk: $(wc -l < ${CHUNK_FILE})"

# --- 运行 ---
echo ""
echo "[$(date)] Starting ${MODEL} on chunk_$(printf '%03d' ${CHUNK_IDX})..."

python -u -m src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk \
    --model ${MODEL} \
    --chunk-file ${CHUNK_FILE} \
    --output-dir ${OUTPUT_DIR} \
    --data-root ${DATA_ROOT} \
    --trials ${TRIALS} \
    --skip-existing

EXIT_CODE=$?

echo ""
echo "=========================================="
echo "[$(date)] Done: ${MODEL} chunk_$(printf '%03d' ${CHUNK_IDX}) (exit: ${EXIT_CODE})"
echo "=========================================="
exit ${EXIT_CODE}
