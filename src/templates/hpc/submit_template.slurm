#!/usr/bin/env bash
# =============================================================================
# NeuralHydrology HPC 提交模板 (Standard Template)
#
# 使用指南:
# 1. 复制此文件到 src/<idea>/hpc/submit_<name>.slurm
# 2. 修改 CONFIG_FILE 和 TASK_NAME 变量
# 3. 确保 WinSCP 同步完成
# 4. 在 HPC 上执行: sed -i 's/\r$//' <script>  (修复 Windows 换行符)
# 5. 提交: sbatch <script>
# =============================================================================
#SBATCH -J nh_task_name       # 作业名 (请修改)
#SBATCH -p hgpu8              # 分区 (hgpu8 较稳定)
#SBATCH --gres=gpu:1          # GPU 数量
#SBATCH --cpus-per-task=8     # CPU 核心数
#SBATCH -t 168:00:00          # 时间限制 (7天)
#SBATCH --exclude=ngu001      # 避开已知坏节点
#SBATCH -o logs/%j.out        # 日志 (会被脚本动态重定向，保留此行作为 fallback)
#SBATCH -e logs/%j.err

set -eo pipefail

# =============================================================================
# 1. 项目配置 (用户修改区)
# =============================================================================
# 对应 src/<idea>/configs/ 下的配置文件名
IDEA_NAME="03_new_idea"
CONFIG_FILE="src/${IDEA_NAME}/configs/config.yml"
TASK_NAME="New Idea Description"

# Conda 环境 (默认 nh_final)
CONDA_ENV="${CONDA_ENV:-nh_final}"

# =============================================================================
# 2. 环境初始化 (无需修改)
# =============================================================================
echo "=========================================="
echo "[$(date)] Task: $TASK_NAME"
echo "=========================================="
echo "[INFO] Job ID: $SLURM_JOB_ID"
echo "[INFO] Node:   $(hostname)"
echo "[INFO] GPU:    ${CUDA_VISIBLE_DEVICES:-N/A}"
echo "[INFO] Config: $CONFIG_FILE"

# 激活 Conda
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh || \
source $HOME/anaconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV" || { echo "[FATAL] Failed to activate $CONDA_ENV"; exit 1; }

# 关键修复: MKL 兼容性 (解决 iJIT_NotifyEvent 和 GLIBC 问题)
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

# 设置工作目录和 PYTHONPATH
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

# 创建日志和结果目录 (遵循 Rules: results/<idea>, logs/<idea>)
LOG_DIR="logs/${IDEA_NAME}"
RES_DIR="results/${IDEA_NAME}"
mkdir -p "$LOG_DIR" "$RES_DIR"

# 检查 Mamba 环境 (仅作提示)
python -c "
try:
    import mamba_ssm
    print('[INFO] Mamba backend: CUDA (mamba_ssm) ✓')
except ImportError:
    print('[INFO] Mamba backend: Fallback/None ⚠')
"

# =============================================================================
# 3. 启动训练
# =============================================================================
echo ""
echo "[$(date)] Starting training..."

# 使用 srun 启动，并重定向日志到规范目录
# 注意: SLURM 的 #SBATCH -o 只能接受静态路径。这里我们用 srun 的重定向功能覆盖它，
# 或者接受日志在 logs/ 下，之后手动移动。
# 为了保持简单，这里直接运行。日志位置由提交时的 --output 参数决定更好，
# 但为了自动化，建议在 submit.sh 中控制。
# 这里我们打印提示，让用户知道去哪找结果。

echo "[INFO] Results will be saved to: $RES_DIR"

srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo ""
echo "[$(date)] Finished (exit: $EXIT_CODE)"
exit $EXIT_CODE
