#!/usr/bin/env bash
# =============================================================================
# 汇总: 等全量跑完后提交，汇总所有 chunk 结果
#
# Usage:
#   sbatch src/xaj_global_pilot/hpc/summarize_benchmark.slurm
#
# 也可以等 array job 完成后自动触发:
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> src/xaj_global_pilot/hpc/summarize_benchmark.slurm
# =============================================================================
#SBATCH -J xaj-summary
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -t 00:10:00
#SBATCH -o logs/10_global_conceptual_model_benchmark/summary-%j.out
#SBATCH -e logs/10_global_conceptual_model_benchmark/summary-%j.err

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}" || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

IDEA="10_global_conceptual_model_benchmark"
OUTPUT_DIR="results/${IDEA}/camels_us_531_v02"

mkdir -p "logs/${IDEA}"

echo "=========================================="
echo "[$(date)] XAJ Benchmark — Summarize"
echo "=========================================="
echo "[INFO] Job: $SLURM_JOB_ID, Node: $(hostname)"

# --- Preflight 检查完整性 ---
echo ""
echo "[$(date)] Running preflight check..."
python -u -m src.xaj_global_pilot.hpc.preflight_conceptual_benchmark_run \
    --output-dir ${OUTPUT_DIR}

# --- 汇总 ---
echo ""
echo "[$(date)] Summarizing results..."
python -u -m src.xaj_global_pilot.hpc.summarize_conceptual_benchmark_run \
    --output-dir ${OUTPUT_DIR}

echo ""
echo "=========================================="
echo "[DONE] Summary written to: ${OUTPUT_DIR}/summary/"
echo "=========================================="
