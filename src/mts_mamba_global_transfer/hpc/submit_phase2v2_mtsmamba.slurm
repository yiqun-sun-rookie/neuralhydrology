#!/usr/bin/env bash
# =============================================================================
# Phase 2v2 MTSMamba — 10 basins, full forcing, train + evaluate
#
# Q3: Can Mamba replace LSTM in multi-timescale architecture?
# Baseline: MTSLSTM test NSE=0.768 (Phase 2v2)
#
# 使用:
# 1. sed -i 's/\r$//' src/mts_mamba_global_transfer/hpc/submit_phase2v2_mtsmamba.slurm
# 2. sbatch src/mts_mamba_global_transfer/hpc/submit_phase2v2_mtsmamba.slurm
# =============================================================================
#SBATCH -J t41-p2v2-mtsmamba
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:1
#SBATCH --mem=32G
#SBATCH -t 24:00:00
#SBATCH --signal=TERM@300
#SBATCH -o logs/41_mts_mamba_global_transfer/phase2v2-mtsmamba-%j.out
#SBATCH -e logs/41_mts_mamba_global_transfer/phase2v2-mtsmamba-%j.err
#SBATCH --exclude=ngu001,ngu201,ngu202

set -eo pipefail

# =============================================================================
# 1. 项目配置
# =============================================================================
IDEA_NAME="41_mts_mamba_global_transfer"
TASK_ROOT="src/mts_mamba_global_transfer"
CONFIG_FILE="${TASK_ROOT}/configs/phase2v2_mtsmamba_camelsh_10b.yml"
TASK_NAME="Phase 2v2 MTSMamba — 10 basins"
CONDA_ENV="${CONDA_ENV:-nh_final}"
EVAL_EPOCH=10

# =============================================================================
# 2. 环境初始化
# =============================================================================
echo "=========================================="
echo "[$(date)] Task: $TASK_NAME"
echo "=========================================="
echo "[INFO] Job ID: $SLURM_JOB_ID"
echo "[INFO] Node:   $(hostname)"
echo "[INFO] GPU:    ${CUDA_VISIBLE_DEVICES:-N/A}"
echo "[INFO] Config: $CONFIG_FILE"

# 激活 Conda (fallback chain)
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh || \
source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV" || { echo "[FATAL] Failed to activate $CONDA_ENV"; exit 1; }

# MKL 兼容性
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID

# 工作目录
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

# 创建日志和结果目录
mkdir -p "logs/${IDEA_NAME}" "results/${IDEA_NAME}"

# =============================================================================
# 3. Pre-flight 检查
# =============================================================================
echo ""
echo "[$(date)] Pre-flight checks..."

# Python & PyTorch
echo "[INFO] Python: $(python --version 2>&1)"
python -c "import torch; print(f'[INFO] PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')"

# Mamba backend
python -c "
backend = None
try:
    from mamba_ssm import Mamba
    backend = 'mamba_ssm'
    print('[INFO] Mamba backend: mamba_ssm (CUDA kernel)')
except ImportError:
    pass
if backend is None:
    try:
        from transformers import MambaConfig, MambaModel
        backend = 'transformers'
        print('[INFO] Mamba backend: transformers (HuggingFace)')
    except ImportError:
        pass
if backend is None:
    print('[FATAL] No Mamba backend available!')
    exit(1)
"

# Config & data files
[ -f "$CONFIG_FILE" ] || { echo "[FATAL] Config not found: $CONFIG_FILE"; exit 1; }
BASIN_FILE="${TASK_ROOT}/data/phase2_camelsh_10basins.txt"
[ -f "$BASIN_FILE" ] || { echo "[FATAL] Basin file not found: $BASIN_FILE"; exit 1; }
echo "[INFO] Basins: $(wc -l < $BASIN_FILE)"

# CAMELS-H data
DATA_DIR="./data/camelsh"
[ -d "$DATA_DIR" ] || { echo "[FATAL] CAMELS-H data not found: $DATA_DIR"; exit 1; }

# MTSMamba model file
[ -f "neuralhydrology/modelzoo/mtsmamba.py" ] || { echo "[FATAL] mtsmamba.py not found"; exit 1; }

# HourlyCamelsH dataset file (added in local, must be synced)
[ -f "neuralhydrology/datasetzoo/hourlycamelsh.py" ] || { echo "[FATAL] hourlycamelsh.py not found — sync full neuralhydrology/ package"; exit 1; }

# GPU info
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "[WARN] nvidia-smi failed"

echo "[INFO] All checks passed."

# =============================================================================
# 4. Stage 1/2: 训练
# =============================================================================
echo ""
echo "[$(date)] [STAGE 1/2] Training..."

srun python -u -m neuralhydrology.nh_run train \
    --config-file "${CONFIG_FILE}" \
    --gpu 0

TRAIN_EXIT=$?
echo "[$(date)] Training finished (exit: $TRAIN_EXIT)"
if [ $TRAIN_EXIT -ne 0 ]; then
    echo "[FATAL] Training failed with exit code $TRAIN_EXIT"
    exit $TRAIN_EXIT
fi

# =============================================================================
# 5. Stage 2/2: 评估
# =============================================================================

# 找到最新的 run directory
RUN_DIR=$(find "results/${IDEA_NAME}" \
    -maxdepth 1 -type d -name "41_phase2v2_mtsmamba_camelsh_10b_*" \
    -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2)

if [ -z "${RUN_DIR}" ]; then
    echo "[FATAL] Cannot find run directory after training." >&2
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
echo "[DONE] Training + evaluation complete."
echo "[INFO] Results: ${RUN_DIR}/test/model_epoch0${EVAL_EPOCH}/"
echo "=========================================="
exit $EVAL_EXIT
