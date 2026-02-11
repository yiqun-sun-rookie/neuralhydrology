#!/bin/bash
#SBATCH --job-name=neuralhydrology_test
#SBATCH --output=logs/neuralhydrology_test_%j.out
#SBATCH --error=logs/neuralhydrology_test_%j.err
#SBATCH --time=00:30:00              # 30分钟快速测试
#SBATCH --partition=gpu              # GPU分区
#SBATCH --gres=gpu:1                 # 申请1个GPU
#SBATCH --mem=16G                    # 16GB内存
#SBATCH --cpus-per-task=4            # 4个CPU核心
#SBATCH --nodes=1                    # 单节点
#SBATCH --ntasks-per-node=1          # 每节点1个任务
#SBATCH --mail-type=END,FAIL         # 邮件通知类型
#SBATCH --mail-user=your_email@hhu.edu.cn  # 替换为您的邮箱

# =============================================================================
# NeuralHydrology HPC 快速测试 SLURM 作业脚本
# 用于验证HPC环境配置和快速功能测试
# =============================================================================

echo "=========================================="
echo "NeuralHydrology HPC 快速测试作业"
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
mkdir -p /data/neuralhydrology/runs/quick_test
mkdir -p /data/neuralhydrology/logs/quick_test

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

# 验证CUDA环境
echo "验证CUDA环境..."
nvidia-smi

# 验证PyTorch GPU支持
echo "验证PyTorch GPU支持..."
python -c "import torch; print(f'PyTorch版本: {torch.__version__}'); print(f'CUDA可用: {torch.cuda.is_available()}'); print(f'GPU数量: {torch.cuda.device_count()}')"

# =============================================================================
# 环境变量设置
# =============================================================================

# 设置CUDA环境变量
export CUDA_VISIBLE_DEVICES=0
export CUDA_DEVICE_ORDER=PCI_BUS_ID

# 设置OpenMP环境变量
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4

# 设置PyTorch环境变量
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256

# 显示环境变量
echo "环境变量设置:"
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo "OMP_NUM_THREADS: $OMP_NUM_THREADS"

# =============================================================================
# 项目设置
# =============================================================================

# 进入项目目录
PROJECT_DIR="/data/neuralhydrology"
cd $PROJECT_DIR

echo "当前工作目录: $(pwd)"

# 检查配置文件
CONFIG_FILE="configs/hpc/hpc_quick_test.yml"
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

echo "数据目录存在，开始快速测试..."

# =============================================================================
# 快速测试执行
# =============================================================================

echo "=========================================="
echo "开始快速测试..."
echo "开始时间: $(date)"
echo "=========================================="

# 记录系统资源使用情况
echo "测试前系统状态:"
free -h
nvidia-smi

# 执行快速测试
python simple_train.py \
    --config $CONFIG_FILE \
    --gpu 0

# 记录测试退出状态
TEST_EXIT_CODE=$?
echo "测试退出状态: $TEST_EXIT_CODE"

# =============================================================================
# 测试后处理
# =============================================================================

echo "=========================================="
echo "快速测试完成..."
echo "结束时间: $(date)"
echo "=========================================="

# 记录测试后系统状态
echo "测试后系统状态:"
free -h
nvidia-smi

# 检查测试结果
echo "检查测试结果..."
if [ -d "runs" ]; then
    echo "测试运行目录:"
    ls -la runs/
    
    # 查找最新的运行目录
    LATEST_RUN=$(ls -t runs/ | head -1)
    if [ -n "$LATEST_RUN" ]; then
        echo "最新运行目录: $LATEST_RUN"
        echo "运行目录内容:"
        ls -la runs/$LATEST_RUN/
    fi
else
    echo "警告: 未找到测试运行目录"
fi

# 生成测试报告
echo "生成测试报告..."
REPORT_FILE="logs/quick_test_report_${SLURM_JOB_ID}.txt"
cat > $REPORT_FILE << EOF
NeuralHydrology HPC 快速测试报告
===============================
作业ID: $SLURM_JOB_ID
开始时间: $(date -d @$SLURM_JOB_START_TIME 2>/dev/null || echo "未知")
结束时间: $(date)
运行时间: $(( $(date +%s) - $SLURM_JOB_START_TIME )) 秒
节点: $SLURMD_NODENAME
GPU: $CUDA_VISIBLE_DEVICES
配置文件: $CONFIG_FILE
测试退出状态: $TEST_EXIT_CODE

系统资源:
- 内存: 16GB
- CPU核心: 4
- GPU: 1个

测试结果:
- 最新运行目录: $LATEST_RUN

EOF

echo "测试报告已保存到: $REPORT_FILE"

# =============================================================================
# 清理和退出
# =============================================================================

# 最终状态检查
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "✅ 快速测试成功完成"
    echo "HPC环境配置正确，可以提交完整训练作业"
    exit 0
else
    echo "❌ 快速测试失败，退出状态: $TEST_EXIT_CODE"
    echo "请检查HPC环境配置和依赖包安装"
    exit $TEST_EXIT_CODE
fi


