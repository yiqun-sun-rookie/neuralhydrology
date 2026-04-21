#!/usr/bin/env bash
# =============================================================================
# Smoke test: 1 chunk (3 basins) x 3 models x 50 trials
# 预计 ~1 分钟完成
#
# Usage:
#   sbatch src/xaj_global_pilot/hpc/smoke_test.slurm
# =============================================================================
#SBATCH -J xaj-smoke
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 00:10:00
#SBATCH -o logs/10_global_conceptual_model_benchmark/smoke-%j.out
#SBATCH -e logs/10_global_conceptual_model_benchmark/smoke-%j.err

set -eo pipefail

# --- 环境 ---
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}" || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

IDEA="10_global_conceptual_model_benchmark"
OUTPUT_DIR="results/${IDEA}/camels_us_531_v02_hpc_smoke"
CHUNK_DIR="results/${IDEA}/camels_us_531_v02/chunks"
DATA_ROOT="data/camels_us"
TRIALS=50

mkdir -p "logs/${IDEA}" "${OUTPUT_DIR}"

# --- Pre-flight ---
echo "=========================================="
echo "[$(date)] XAJ Global Pilot — HPC Smoke Test"
echo "=========================================="
echo "[INFO] Job: $SLURM_JOB_ID, Node: $(hostname)"
echo "[INFO] Python: $(python --version 2>&1)"
echo "[INFO] Trials: ${TRIALS}, Data: ${DATA_ROOT}"

# 验证数据和代码
[ -d "$DATA_ROOT" ] || { echo "[FATAL] Data not found: $DATA_ROOT"; exit 1; }
python -c "from src.xaj_global_pilot.runner import run_single_model_basin; print('[INFO] Import OK')" \
    || { echo "[FATAL] Import failed"; exit 1; }

# --- 用 smoke chunk (3 basins) 跑三个模型 ---
SMOKE_CHUNK="${CHUNK_DIR}/chunk_smoke_001.txt"
[ -f "$SMOKE_CHUNK" ] || { echo "[FATAL] Smoke chunk not found: $SMOKE_CHUNK"; exit 1; }

echo ""
echo "[INFO] Smoke chunk: $SMOKE_CHUNK"
echo "[INFO] Basins: $(cat $SMOKE_CHUNK | tr '\n' ' ')"

for MODEL in xaj_pdd hbv gr4j_pdd; do
    echo ""
    echo "[$(date)] --- Running ${MODEL} ---"
    python -u -m src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk \
        --model ${MODEL} \
        --chunk-file ${SMOKE_CHUNK} \
        --output-dir ${OUTPUT_DIR} \
        --data-root ${DATA_ROOT} \
        --trials ${TRIALS} \
        --skip-existing
    echo "[$(date)] ${MODEL} done (exit: $?)"
done

# --- 汇总验证 ---
echo ""
echo "[$(date)] --- Summarizing ---"
python -u -m src.xaj_global_pilot.hpc.summarize_conceptual_benchmark_run \
    --output-dir ${OUTPUT_DIR}

echo ""
echo "=========================================="
echo "[DONE] Smoke test complete."
echo "[INFO] Results: ${OUTPUT_DIR}/summary/"
echo "=========================================="
