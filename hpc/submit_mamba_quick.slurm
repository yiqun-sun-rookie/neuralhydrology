#!/usr/bin/env bash
# =============================================================================
# Mamba CAMELS-US 快速验证作业 (100 basins, 5 epochs)
# 用法: sbatch hpc/submit_mamba_quick.slurm
#       或: ./hpc/submit.sh mamba_quick
# =============================================================================
#SBATCH -J nh_mamba_quick
#SBATCH -p hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -t 48:00:00
#SBATCH -o logs/mamba_quick/%j.out
#SBATCH -e logs/mamba_quick/%j.err

set -eo pipefail

# =============================================================================
# 配置变量
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_clean}"
CONFIG_FILE="experiments/camels_us/configs/mamba_daily_quick.yml"
TASK_NAME="Mamba Quick Validation (100 basins, 5 epochs)"

# =============================================================================
# 环境初始化
# =============================================================================
echo "=========================================="
echo "[$(date)] $TASK_NAME"
echo "=========================================="
echo "[INFO] Job ID: $SLURM_JOB_ID"
echo "[INFO] Node:   $(hostname)"
echo "[INFO] GPU:    ${CUDA_VISIBLE_DEVICES:-N/A}"

# Conda 激活
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh || \
source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV" || { echo "[FATAL] Failed to activate $CONDA_ENV"; exit 1; }

# 工作目录
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs/mamba_quick runs

# 环境检查
echo "[INFO] Python: $(python --version 2>&1)"
python -c "
try:
    from mamba_ssm import Mamba
    print('[INFO] Mamba: mamba_ssm (CUDA kernel) ✓')
except ImportError:
    print('[WARN] Mamba: transformers (slow) ⚠')
"

# =============================================================================
# 训练
# =============================================================================
echo ""
echo "[$(date)] Starting quick validation..."
srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo "[$(date)] Finished (exit: $EXIT_CODE)"
exit $EXIT_CODE
