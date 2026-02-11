#!/bin/bash
#SBATCH --job-name=neuralhydrology_full
#SBATCH --output=logs/neuralhydrology_full_%j.out
#SBATCH --error=logs/neuralhydrology_full_%j.err
#SBATCH --time=72:00:00              # 72小时训练时间
#SBATCH --partition=gpu              # GPU分区
#SBATCH --gres=gpu:2                 # 申请2个GPU
#SBATCH --mem=64G                    # 64GB内存
#SBATCH --cpus-per-task=16           # 16个CPU核心
#SBATCH --nodes=1                    # 单节点
#SBATCH --ntasks-per-node=1          # 每节点1个任务
#SBATCH --mail-type=BEGIN,END,FAIL   # 邮件通知类型
#SBATCH --mail-user=your_email@hhu.edu.cn  # 替换为您的邮箱

# =============================================================================
# NeuralHydrology 完整流域训练 SLURM 作业脚本
# 针对河海大学HPC平台优化
# =============================================================================

echo "=========================================="
echo "NeuralHydrology HPC 完整训练作业"
echo "作业ID: $SLURM_JOB_ID"
echo "开始时间: $(date)"
echo "节点: $SLURMD_NODENAME"
echo "GPU设备: $CUDA_VISIBLE_DEVICES"
echo "=========================================="

# =============================================================================
# 环境设置
# =============================================================================

# 创建必要的目录
mkdir -p logs
mkdir -p /data/neuralhydrology/runs
mkdir -p /data/neuralhydrology/logs
mkdir -p /data/neuralhydrology/checkpoints

# 加载必要的模块
echo "加载HPC模块..."
module load python/3.10
module load cuda/11.8
module load gcc/9.3.0

# 显示模块信息
echo "已加载模块:"
module list

# 激活conda环境
echo "激活conda环境..."
source ~/miniconda3/etc/profile.d/conda.sh
conda activate neuralhydrology_gpu

# 验证环境
echo "验证Python环境..."
python --version
which python
which pip

# 验证CUDA环境
echo "验证CUDA环境..."
nvidia-smi
nvcc --version

# 验证PyTorch GPU支持
echo "验证PyTorch GPU支持..."
python -c "import torch; print(f'PyTorch版本: {torch.__version__}'); print(f'CUDA可用: {torch.cuda.is_available()}'); print(f'GPU数量: {torch.cuda.device_count()}')"

# =============================================================================
# 环境变量设置
# =============================================================================

# 设置CUDA环境变量
export CUDA_VISIBLE_DEVICES=0,1
export CUDA_DEVICE_ORDER=PCI_BUS_ID

# 设置OpenMP环境变量
export OMP_NUM_THREADS=16
export MKL_NUM_THREADS=16

# 设置PyTorch环境变量
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export TORCH_CUDNN_V8_API_ENABLED=1

# 设置数据加载环境变量
export TOKENIZERS_PARALLELISM=false

# 显示环境变量
echo "环境变量设置:"
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo "OMP_NUM_THREADS: $OMP_NUM_THREADS"
echo "PYTORCH_CUDA_ALLOC_CONF: $PYTORCH_CUDA_ALLOC_CONF"

# =============================================================================
# 项目设置
# =============================================================================

# 进入项目目录
PROJECT_DIR="/data/neuralhydrology"
cd $PROJECT_DIR

echo "当前工作目录: $(pwd)"
echo "项目文件列表:"
ls -la

# 检查配置文件
CONFIG_FILE="configs/hpc/hpc_full_training.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

echo "使用配置文件: $CONFIG_FILE"

# =============================================================================
# 数据检查
# =============================================================================

echo "检查数据目录..."
DATA_DIR="/data/neuralhydrology/CAMELS_US"
if [ ! -d "$DATA_DIR" ]; then
    echo "错误: 数据目录不存在: $DATA_DIR"
    exit 1
fi

echo "数据目录大小: $(du -sh $DATA_DIR)"
echo "数据文件数量: $(find $DATA_DIR -name "*.txt" | wc -l)"

# =============================================================================
# 训练执行
# =============================================================================

echo "=========================================="
echo "开始训练..."
echo "开始时间: $(date)"
echo "=========================================="

# 记录系统资源使用情况
echo "训练前系统状态:"
free -h
df -h /data
nvidia-smi

# 执行训练
python simple_train.py \
    --config $CONFIG_FILE \
    --gpu 0

# 记录训练退出状态
TRAIN_EXIT_CODE=$?
echo "训练退出状态: $TRAIN_EXIT_CODE"

# =============================================================================
# 训练后处理
# =============================================================================

echo "=========================================="
echo "训练完成..."
echo "结束时间: $(date)"
echo "=========================================="

# 记录训练后系统状态
echo "训练后系统状态:"
free -h
df -h /data
nvidia-smi

# 检查训练结果
echo "检查训练结果..."
if [ -d "runs" ]; then
    echo "训练运行目录:"
    ls -la runs/
    
    # 查找最新的运行目录
    LATEST_RUN=$(ls -t runs/ | head -1)
    if [ -n "$LATEST_RUN" ]; then
        echo "最新运行目录: $LATEST_RUN"
        echo "运行目录大小: $(du -sh runs/$LATEST_RUN)"
        echo "模型文件:"
        ls -la runs/$LATEST_RUN/model_*.pt 2>/dev/null || echo "未找到模型文件"
        echo "日志文件:"
        ls -la runs/$LATEST_RUN/*.log 2>/dev/null || echo "未找到日志文件"
    fi
else
    echo "警告: 未找到训练运行目录"
fi

# 备份重要结果
echo "备份训练结果..."
BACKUP_DIR="/data/neuralhydrology/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

if [ -d "runs" ]; then
    cp -r runs/ $BACKUP_DIR/
    echo "结果已备份到: $BACKUP_DIR"
fi

# 生成训练报告
echo "生成训练报告..."
REPORT_FILE="logs/training_report_${SLURM_JOB_ID}.txt"
cat > $REPORT_FILE << EOF
NeuralHydrology HPC 训练报告
============================
作业ID: $SLURM_JOB_ID
开始时间: $(date -d @$SLURM_JOB_START_TIME 2>/dev/null || echo "未知")
结束时间: $(date)
运行时间: $(( $(date +%s) - $SLURM_JOB_START_TIME )) 秒
节点: $SLURMD_NODENAME
GPU: $CUDA_VISIBLE_DEVICES
配置文件: $CONFIG_FILE
训练退出状态: $TRAIN_EXIT_CODE

系统资源:
- 内存: 64GB
- CPU核心: 16
- GPU: 2个

训练结果:
- 最新运行目录: $LATEST_RUN
- 备份目录: $BACKUP_DIR

EOF

echo "训练报告已保存到: $REPORT_FILE"

# =============================================================================
# 清理和退出
# =============================================================================

# 清理临时文件
echo "清理临时文件..."
find /tmp -name "*.tmp" -user $USER -delete 2>/dev/null || true

# 最终状态检查
if [ $TRAIN_EXIT_CODE -eq 0 ]; then
    echo "✅ 训练成功完成"
    exit 0
else
    echo "❌ 训练失败，退出状态: $TRAIN_EXIT_CODE"
    exit $TRAIN_EXIT_CODE
fi


