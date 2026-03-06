#!/usr/bin/env bash
# =============================================================================
# Phase 2v3: Sequence Length Scaling — parameterized SLURM script
#
# Usage:
#   sbatch --export=CONFIG=seqscale_cudalstm_336h src/mts_mamba_global_transfer/hpc/submit_seqscale.slurm
#
# CONFIG should be the config filename without .yml extension, e.g.:
#   seqscale_cudalstm_336h, seqscale_mamba_4320h, etc.
# =============================================================================
#SBATCH -J t41-seqscale
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:1
#SBATCH -t 24:00:00
#SBATCH --signal=TERM@300
#SBATCH -o logs/41_mts_mamba_global_transfer/seqscale-%j.out
#SBATCH -e logs/41_mts_mamba_global_transfer/seqscale-%j.err
#SBATCH --exclude=ngu001,ngu201,ngu202

set -eo pipefail

# =============================================================================
# 1. Validate CONFIG parameter
# =============================================================================
if [ -z "${CONFIG}" ]; then
    echo "[FATAL] CONFIG not set. Usage: sbatch --export=CONFIG=seqscale_cudalstm_336h ..."
    exit 1
fi

IDEA_NAME="41_mts_mamba_global_transfer"
TASK_ROOT="src/mts_mamba_global_transfer"
CONFIG_FILE="${TASK_ROOT}/configs/seqscale/${CONFIG}.yml"
EVAL_EPOCH=10
CONDA_ENV="${CONDA_ENV:-nh_final}"

echo "=========================================="
echo "[$(date)] Seq-Length Scaling: ${CONFIG}"
echo "=========================================="
echo "[INFO] Job ID: $SLURM_JOB_ID"
echo "[INFO] Node:   $(hostname)"
echo "[INFO] GPU:    ${CUDA_VISIBLE_DEVICES:-N/A}"
echo "[INFO] Config: $CONFIG_FILE"

# =============================================================================
# 2. Environment
# =============================================================================
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh || \
source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV" || { echo "[FATAL] Failed to activate $CONDA_ENV"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

mkdir -p "logs/${IDEA_NAME}" "results/${IDEA_NAME}"

# =============================================================================
# 3. Pre-flight
# =============================================================================
[ -f "$CONFIG_FILE" ] || { echo "[FATAL] Config not found: $CONFIG_FILE"; exit 1; }

echo "[INFO] Python: $(python --version 2>&1)"
python -c "import torch; print(f'[INFO] PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "[WARN] nvidia-smi failed"

# Check Mamba backend if needed
if echo "$CONFIG" | grep -q "mamba"; then
    python -c "
try:
    from mamba_ssm import Mamba; print('[INFO] Mamba backend: mamba_ssm')
except ImportError:
    from transformers import MambaModel; print('[INFO] Mamba backend: transformers')
"
fi

echo "[INFO] All checks passed."

# =============================================================================
# 4. Train
# =============================================================================
echo ""
echo "[$(date)] [STAGE 1/2] Training..."

srun python -u -m neuralhydrology.nh_run train \
    --config-file "${CONFIG_FILE}" \
    --gpu 0

TRAIN_EXIT=$?
echo "[$(date)] Training finished (exit: $TRAIN_EXIT)"
[ $TRAIN_EXIT -eq 0 ] || { echo "[FATAL] Training failed"; exit $TRAIN_EXIT; }

# =============================================================================
# 5. Evaluate
# =============================================================================
EXP_NAME="41_${CONFIG}"
RUN_DIR=$(find "results/${IDEA_NAME}" \
    -maxdepth 1 -type d -name "${EXP_NAME}_*" \
    -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2)

if [ -z "${RUN_DIR}" ]; then
    echo "[FATAL] Cannot find run directory for ${EXP_NAME}" >&2
    exit 1
fi
echo "[INFO] run_dir=${RUN_DIR}"

echo "[$(date)] [STAGE 2/2] Evaluating epoch ${EVAL_EPOCH} on test set..."

srun python -u -m neuralhydrology.nh_run evaluate \
    --run-dir "${RUN_DIR}" \
    --period test \
    --epoch "${EVAL_EPOCH}" \
    --gpu 0

EVAL_EXIT=$?
echo "[$(date)] Evaluation finished (exit: $EVAL_EXIT)"

echo ""
echo "=========================================="
echo "[DONE] ${CONFIG}: Training + evaluation complete."
echo "[INFO] Results: ${RUN_DIR}/test/model_epoch0${EVAL_EPOCH}/"
echo "=========================================="
exit $EVAL_EXIT
