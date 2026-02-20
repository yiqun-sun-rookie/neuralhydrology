#!/usr/bin/env bash
# =============================================================================
# Mamba CAMELS-US 全量训练作业 (531 basins, 30 epochs)
# 用法: sbatch src/mamba_camels_us/hpc/submit_mamba_camels_us.slurm
#       或: ./common/submit.sh mamba_camels_us
# =============================================================================
#SBATCH -J nh_mamba_camels_us
#SBATCH -p hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH -t 168:00:00
# 注意: 日志路径由 submit.sh 动态设置，或使用以下默认值
#SBATCH -o logs/mamba_camels_us/%j.out
#SBATCH -e logs/mamba_camels_us/%j.err

set -eo pipefail

# =============================================================================
# 配置变量（可按需修改）
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_clean}"
CONFIG_FILE="src/mamba_camels_us/configs/mamba_daily.yml"
TASK_NAME="Mamba CAMELS-US Full (531 basins, 30 epochs)"

# =============================================================================
# 环境初始化
# =============================================================================
echo "=========================================="
echo "[$(date)] $TASK_NAME"
echo "=========================================="
echo "[INFO] Job ID:     $SLURM_JOB_ID"
echo "[INFO] Node:       $(hostname)"
echo "[INFO] GPU:        ${CUDA_VISIBLE_DEVICES:-N/A}"
echo "[INFO] Config:     $CONFIG_FILE"

# Conda 激活
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh || \
source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV" || { echo "[FATAL] Failed to activate $CONDA_ENV"; exit 1; }

# 工作目录
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs/mamba_camels_us runs

# =============================================================================
# 环境检查
# =============================================================================
echo ""
echo "[INFO] Environment:"
echo "  - Python:  $(python --version 2>&1)"
echo "  - PyTorch: $(python -c 'import torch; print(torch.__version__)')"
echo "  - CUDA:    $(python -c 'import torch; print(torch.cuda.is_available())')"

# Mamba 后端检查
python -c "
try:
    from mamba_ssm import Mamba
    print('  - Mamba:   mamba_ssm (CUDA kernel) ✓')
except ImportError:
    try:
        from transformers import MambaModel
        print('  - Mamba:   transformers (slow) ⚠')
    except ImportError:
        print('  - Mamba:   NOT AVAILABLE ✗')
        exit(1)
"

# =============================================================================
# 训练
# =============================================================================
echo ""
echo "=========================================="
echo "[$(date)] Starting training..."
echo "=========================================="

srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo ""
echo "=========================================="
echo "[$(date)] Training finished (exit: $EXIT_CODE)"
echo "=========================================="
exit $EXIT_CODE
