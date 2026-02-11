#!/usr/bin/env bash
# =============================================================================
# Mamba CAMELS-US 续训 (从 Bus error 中断处继续)
# 位置: src/mamba_camels_us/hpc/submit_mamba_resume.slurm
# 用法: sbatch src/mamba_camels_us/hpc/submit_mamba_resume.slurm
# =============================================================================
#SBATCH -J nh_mamba_02_resume
#SBATCH -p hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH -t 48:00:00
#SBATCH --exclude=ngu001,ngu201,ngu202
#SBATCH -o logs/02_mamba_camels_us/resume_%j.out
#SBATCH -e logs/02_mamba_camels_us/resume_%j.err

set -eo pipefail

# =============================================================================
# 配置变量
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_final}"
RUN_DIR="results/02_mamba_camels_us/mamba_daily_benchmark_2026_0129_2132_ep30"
CONFIG_FILE="src/mamba_camels_us/configs/mamba_daily.yml"
TASK_NAME="02 Mamba CAMELS-US Resume"

# =============================================================================
# 环境初始化 (与 submit_mamba.slurm 一致)
# =============================================================================
echo "=========================================="
echo "[$(date)] $TASK_NAME"
echo "=========================================="
echo "[INFO] Job ID: $SLURM_JOB_ID"
echo "[INFO] Node:   $(hostname)"
echo "[INFO] RunDir: $RUN_DIR"

# Conda 激活 (与 submit_mamba.slurm 一致)
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh || \
source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV" || { echo "[FATAL] Failed to activate $CONDA_ENV"; exit 1; }

# 修复 PyTorch/MKL 兼容性
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

# 工作目录：使用提交目录，与 submit_mamba.slurm 一致
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
mkdir -p logs/02_mamba_camels_us results/02_mamba_camels_us

# =============================================================================
# 续训
# =============================================================================
echo "[$(date)] Starting continue_training..."
srun python -u -m neuralhydrology.nh_run continue_training \
    --run-dir "$RUN_DIR" \
    --config-file "$CONFIG_FILE" \
    --gpu 0

EXIT_CODE=$?
echo "[$(date)] Finished (exit: $EXIT_CODE)"
exit $EXIT_CODE
