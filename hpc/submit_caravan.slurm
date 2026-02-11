#!/usr/bin/env bash
# =============================================================================
# Caravan 全球日模型训练作业
# 用法: sbatch hpc/submit_caravan.slurm
#       或: ./hpc/submit.sh caravan
# =============================================================================
#SBATCH -J nh_caravan
#SBATCH -p hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH -t 72:00:00
#SBATCH -o logs/caravan/%j.out
#SBATCH -e logs/caravan/%j.err

set -eo pipefail

# =============================================================================
# 配置变量
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_clean}"
CONFIG_FILE="hpc/caravan_hpc.yml"
TASK_NAME="Caravan Global Daily Model"

# =============================================================================
# 环境初始化
# =============================================================================
echo "=========================================="
echo "[$(date)] $TASK_NAME"
echo "=========================================="
echo "[INFO] Job ID: $SLURM_JOB_ID"
echo "[INFO] Node:   $(hostname)"
echo "[INFO] GPU:    ${CUDA_VISIBLE_DEVICES:-N/A}"
echo "[INFO] Config: $CONFIG_FILE"

# Conda 激活
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh || \
source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV" || { echo "[FATAL] Failed to activate $CONDA_ENV"; exit 1; }

# 工作目录
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs/caravan runs

# 环境检查
echo "[INFO] Python: $(python --version 2>&1)"
echo "[INFO] PyTorch CUDA: $(python -c 'import torch; print(torch.cuda.is_available())')"

# =============================================================================
# 训练
# =============================================================================
echo ""
echo "[$(date)] Starting training..."
srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo "[$(date)] Finished (exit: $EXIT_CODE)"
exit $EXIT_CODE
