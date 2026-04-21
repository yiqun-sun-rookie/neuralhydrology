#!/usr/bin/env bash
# =============================================================================
# Mamba CAMELS-US 全量训练作业 (Rules 规范版)
# 位置: src/mamba_camels_us/hpc/submit_mamba.slurm
# 用法: sbatch src/mamba_camels_us/hpc/submit_mamba.slurm
# =============================================================================
#SBATCH -J nh_mamba_02
#SBATCH -p hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH -t 168:00:00
#SBATCH --exclude=ngu001,ngu201,ngu202  # 避开问题节点 (GPU驱动/OOM问题)
#SBATCH -o logs/02_mamba_camels_us/%j.out
#SBATCH -e logs/02_mamba_camels_us/%j.err

set -eo pipefail

# =============================================================================
# 配置变量
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_final}"
CONFIG_FILE="src/mamba_camels_us/configs/mamba_daily.yml"
TASK_NAME="02 Mamba CAMELS-US Full"

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

# 修复 PyTorch/MKL 兼容性问题 (iJIT_NotifyEvent)
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

# 工作目录
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs/02_mamba_camels_us results/02_mamba_camels_us

# Mamba 后端检查 (与 mamba.py 逻辑一致)
python -c "
backend = None
try:
    from mamba_ssm import Mamba
    backend = 'mamba_ssm'
    print('[INFO] Mamba backend: mamba_ssm (CUDA kernel) ✓')
except ImportError as e:
    print(f'[DEBUG] mamba_ssm unavailable: {e}')

if backend is None:
    try:
        from transformers import MambaConfig, MambaModel
        backend = 'transformers'
        print('[INFO] Mamba backend: transformers (HuggingFace) ✓')
    except ImportError as e:
        print(f'[ERROR] transformers.Mamba unavailable: {e}')
        print('[ERROR] Need transformers>=4.36 for MambaModel!')

if backend is None:
    print('[FATAL] No Mamba backend! Install: pip install transformers>=4.39')
    exit(1)
"

# =============================================================================
# 训练
# =============================================================================
echo ""
echo "[$(date)] Starting training..."
srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo "[$(date)] Finished (exit: $EXIT_CODE)"
exit $EXIT_CODE
