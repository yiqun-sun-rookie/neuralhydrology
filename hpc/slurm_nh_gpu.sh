#!/bin/bash
#===============================================================================
# NeuralHydrology GPU 训练作业 (参考 kalmannet 项目配置)
# 用于河海大学 HPC 平台
#===============================================================================
#SBATCH -J nh-caravan              # 作业名称
#SBATCH -p hgpu2p                  # GPU分区 (hgpu2p=2卡优先队列，推荐日常使用)
#SBATCH -N 1                       # 节点数
#SBATCH -n 1                       # 任务数
#SBATCH --cpus-per-task=16         # CPU核心数 (对应 num_workers)
#SBATCH --gres=gpu:1               # 申请1块GPU
#SBATCH --mem=64G                  # 内存 (Caravan 数据集较大，需要足够内存)
#SBATCH -t 72:00:00                # 时间限制72小时
#SBATCH --signal=TERM@300          # 超时前300秒发送SIGTERM (用于优雅保存)
#SBATCH -o logs/nh-%j.out          # 标准输出
#SBATCH -e logs/nh-%j.err          # 标准错误
#SBATCH --exclude=ngu201           # 排除不稳定节点

#===============================================================================
# 配置区域 (根据需要修改)
#===============================================================================
CONDA_ENV="${CONDA_ENV:-neuralhydrology}"
WORKDIR="${WORKDIR:-/data1/home/${USER}/neuralhydrology}"
CONFIG_FILE="${CONFIG_FILE:-src/caravan_global/configs/caravan_daily_basemodel.yml}"

# 日志控制 (从 kalmannet 借鉴)
LOG_LEVEL="${LOG_LEVEL:-minimal}"  # ultra_quiet, minimal, normal, verbose

#===============================================================================
# Conda 环境激活 (robust 方式，适配多种 HPC 环境)
#===============================================================================
_activate_conda() {
  if command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
  else
    for croot in "$HOME/miniconda3" "$HOME/anaconda3" "/opt/conda" "/usr/local/conda"; do
      if [ -f "$croot/etc/profile.d/conda.sh" ]; then
        source "$croot/etc/profile.d/conda.sh"
        break
      fi
    done
  fi
  
  if ! command -v conda >/dev/null 2>&1; then
    echo "[FATAL] conda 未找到，请检查环境配置" >&2
    exit 1
  fi
  
  conda activate "$CONDA_ENV" || { 
    echo "[FATAL] 激活环境失败: $CONDA_ENV"
    echo "[INFO] 可用环境列表:"
    conda env list
    exit 1
  }
}

#===============================================================================
# 信号处理 (优雅退出，保存检查点)
#===============================================================================
_TERM_FLAG="${WORKDIR}/.emergency_save_${SLURM_JOB_ID}.flag"
trap 'echo "[$(date)] 收到 SIGTERM -> 标记紧急保存"; echo "1" > "$_TERM_FLAG"' TERM

#===============================================================================
# 主执行流程
#===============================================================================
echo "========================================"
echo "[$(date)] NeuralHydrology HPC 训练开始"
echo "========================================"
echo "[INFO] 作业ID: ${SLURM_JOB_ID}"
echo "[INFO] 节点: $(hostname)"
echo "[INFO] 工作目录: ${WORKDIR}"
echo "[INFO] 配置文件: ${CONFIG_FILE}"
echo "[INFO] Conda环境: ${CONDA_ENV}"

# 确保日志目录存在
mkdir -p "${WORKDIR}/logs"

# 切换到工作目录
cd "${WORKDIR}" || { echo "[FATAL] 无法进入工作目录: ${WORKDIR}"; exit 1; }

# 激活 Conda
_activate_conda

# GPU 诊断
echo ""
echo "[INFO] GPU 诊断信息:"
export CUDA_DEVICE_ORDER=PCI_BUS_ID
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv
python -c "import torch; print(f'[INFO] PyTorch: {torch.__version__}, CUDA: {torch.cuda.is_available()}, 设备数: {torch.cuda.device_count()}')"

# 运行训练
echo ""
echo "[$(date)] 开始训练..."
echo "========================================"

srun --ntasks=1 --cpus-per-task=${SLURM_CPUS_PER_TASK} --gpus=1 \
  python -u -m neuralhydrology.nh_run train \
    --config-file "${CONFIG_FILE}"

EXIT_CODE=$?

echo "========================================"
echo "[$(date)] 训练结束，退出码: ${EXIT_CODE}"
echo "========================================"

# 清理临时文件
rm -f "$_TERM_FLAG"

exit ${EXIT_CODE}
