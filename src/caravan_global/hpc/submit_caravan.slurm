#!/usr/bin/env bash
# =============================================================================
# Caravan 全球日模型训练作业 (Rules 规范版)
# 位置: src/caravan_global/hpc/submit_caravan.slurm
# 用法: sbatch src/caravan_global/hpc/submit_caravan.slurm
# =============================================================================
#SBATCH -J nh_caravan_01
#SBATCH -p hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH -t 72:00:00
#SBATCH --exclude=ngu001,ngu201,ngu202  # 避开问题节点 (CUDA初始化失败)
#SBATCH -o logs/01_caravan_global/%j.out
#SBATCH -e logs/01_caravan_global/%j.err

set -eo pipefail

# =============================================================================
# 配置变量
# =============================================================================
CONDA_ENV="${CONDA_ENV:-nh_final}"
CONFIG_FILE="src/caravan_global/configs/caravan_hpc.yml"
TASK_NAME="01 Caravan Global Daily Model"

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

# 修复 PyTorch/MKL 兼容性问题 (iJIT_NotifyEvent) - 对 Caravan 也是必须的
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

# 工作目录
cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH

# =============================================================================
# 预检查 - 确保目录和文件存在
# =============================================================================
echo ""
echo "[$(date)] Pre-flight checks..."

# 创建必要的目录
mkdir -p logs/01_caravan_global results/01_caravan_global

# 检查磁盘空间 (至少需要 10GB)
AVAIL_GB=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
echo "[INFO] Available disk space: ${AVAIL_GB}GB"
if [ "$AVAIL_GB" -lt 10 ]; then
    echo "[WARN] Low disk space! Consider cleaning up old results."
fi

# 使用任务内隔离的 basin 列表（不依赖 data/Caravan 临时分析文件）
VALID_BASINS="src/caravan_global/data/valid_basins.txt"
if [ ! -f "$VALID_BASINS" ]; then
    echo "[FATAL] Missing isolated basin file: $VALID_BASINS"
    echo "[FATAL] Sync src/caravan_global/data/valid_basins.txt before submission."
    exit 1
fi

# 验证 basin 文件（要求纯列表，一行一个 basin id）
BASIN_COUNT=$(wc -l < "$VALID_BASINS")
echo "[INFO] Valid basins: $BASIN_COUNT"
if [ "$BASIN_COUNT" -lt 100 ]; then
    echo "[FATAL] Too few basins ($BASIN_COUNT), something is wrong!"
    exit 1
fi

# 环境检查
echo "[INFO] Python: $(python --version 2>&1)"
echo "[INFO] PyTorch CUDA: $(python -c 'import torch; print(torch.cuda.is_available())')"

# 检查 GPU 内存
python -c "import torch; print(f'[INFO] GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f}GB')" 2>/dev/null || echo "[WARN] Could not check GPU memory"

# =============================================================================
# 训练
# =============================================================================
echo ""
echo "[$(date)] Starting training..."
echo "[INFO] Training with $BASIN_COUNT basins, 30 epochs"
echo "[INFO] Estimated time: 40-50 hours"
echo ""

# 使用 unbuffered output 确保日志实时写入
srun python -u -m neuralhydrology.nh_run train --config-file "$CONFIG_FILE"

EXIT_CODE=$?
echo ""
echo "[$(date)] Finished (exit: $EXIT_CODE)"

# 训练完成后的简单统计
if [ $EXIT_CODE -eq 0 ]; then
    echo "[SUCCESS] Training completed successfully!"
    # 列出生成的模型文件
    find results/01_caravan_global -name "*.pt" -newer "$0" 2>/dev/null | head -5
fi

exit $EXIT_CODE
