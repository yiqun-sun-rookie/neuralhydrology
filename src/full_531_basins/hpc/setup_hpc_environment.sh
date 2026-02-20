#!/bin/bash
# =============================================================================
# NeuralHydrology HPC 环境设置脚本
# 用于在河海大学HPC平台上配置训练环境
# =============================================================================

set -e  # 遇到错误立即退出

echo "=========================================="
echo "NeuralHydrology HPC 环境设置"
echo "开始时间: $(date)"
echo "=========================================="

# =============================================================================
# 配置参数
# =============================================================================

# 项目配置
PROJECT_NAME="neuralhydrology"
PROJECT_DIR="/data/neuralhydrology"
CONDA_ENV_NAME="neuralhydrology_gpu"
PYTHON_VERSION="3.10"

# 数据配置
DATA_DIR="/data/neuralhydrology/CAMELS_US"
CONFIGS_DIR="/data/neuralhydrology/configs"
RUNS_DIR="/data/neuralhydrology/runs"
LOGS_DIR="/data/neuralhydrology/logs"

# 用户配置（需要根据实际情况修改）
USER_EMAIL="your_email@hhu.edu.cn"  # 替换为您的邮箱

echo "配置参数:"
echo "项目目录: $PROJECT_DIR"
echo "Conda环境: $CONDA_ENV_NAME"
echo "Python版本: $PYTHON_VERSION"
echo "数据目录: $DATA_DIR"

# =============================================================================
# 环境检查
# =============================================================================

echo "=========================================="
echo "检查HPC环境..."
echo "=========================================="

# 检查必要的模块
echo "检查可用模块..."
module avail python
module avail cuda
module avail gcc

# 加载基础模块
echo "加载基础模块..."
module load python/3.10
module load cuda/11.8
module load gcc/9.3.0

# 检查conda
echo "检查conda..."
if ! command -v conda &> /dev/null; then
    echo "错误: conda未安装或不在PATH中"
    echo "请先安装Miniconda或Anaconda"
    exit 1
fi

echo "Conda版本: $(conda --version)"

# 检查CUDA
echo "检查CUDA..."
if ! command -v nvcc &> /dev/null; then
    echo "警告: nvcc未找到，但CUDA模块已加载"
fi

if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi未找到"
else
    echo "GPU信息:"
    nvidia-smi
fi

# =============================================================================
# 目录创建
# =============================================================================

echo "=========================================="
echo "创建项目目录结构..."
echo "=========================================="

# 创建主项目目录
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# 创建子目录
mkdir -p $DATA_DIR
mkdir -p $CONFIGS_DIR
mkdir -p $RUNS_DIR
mkdir -p $LOGS_DIR
mkdir -p $PROJECT_DIR/checkpoints
mkdir -p $PROJECT_DIR/backups
mkdir -p $PROJECT_DIR/slurm_jobs

echo "目录结构已创建:"
tree -L 2 $PROJECT_DIR || ls -la $PROJECT_DIR

# =============================================================================
# Conda环境设置
# =============================================================================

echo "=========================================="
echo "设置Conda环境..."
echo "=========================================="

# 检查环境是否已存在
if conda env list | grep -q $CONDA_ENV_NAME; then
    echo "Conda环境 $CONDA_ENV_NAME 已存在"
    echo "是否要重新创建? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "删除现有环境..."
        conda env remove -n $CONDA_ENV_NAME -y
    else
        echo "使用现有环境"
        conda activate $CONDA_ENV_NAME
    fi
fi

# 创建新环境（如果不存在）
if ! conda env list | grep -q $CONDA_ENV_NAME; then
    echo "创建新的Conda环境..."
    conda create -n $CONDA_ENV_NAME python=$PYTHON_VERSION -y
    
    # 激活环境
    conda activate $CONDA_ENV_NAME
    
    # 安装基础包
    echo "安装基础包..."
    conda install -c conda-forge -y \
        numpy pandas scipy matplotlib \
        h5py netcdf4 xarray \
        tqdm ruamel.yaml \
        jupyter ipython
    
    # 安装PyTorch (CUDA 11.8版本)
    echo "安装PyTorch (CUDA 11.8)..."
    conda install pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia -y
    
    # 安装其他依赖
    echo "安装其他依赖..."
    pip install tensorboard numba
    
    echo "Conda环境创建完成"
else
    # 激活现有环境
    conda activate $CONDA_ENV_NAME
fi

# 验证环境
echo "验证Conda环境..."
python --version
which python
which pip

# 验证PyTorch
echo "验证PyTorch安装..."
python -c "
import torch
print(f'PyTorch版本: {torch.__version__}')
print(f'CUDA可用: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'CUDA版本: {torch.version.cuda}')
    print(f'GPU数量: {torch.cuda.device_count()}')
    for i in range(torch.cuda.device_count()):
        print(f'GPU {i}: {torch.cuda.get_device_name(i)}')
"

# =============================================================================
# 项目文件部署
# =============================================================================

echo "=========================================="
echo "部署项目文件..."
echo "=========================================="

# 检查项目文件是否存在
if [ ! -f "neuralhydrology/__init__.py" ]; then
    echo "错误: NeuralHydrology项目文件未找到"
    echo "请确保项目文件已正确上传到 $PROJECT_DIR"
    exit 1
fi

# 安装项目
echo "安装NeuralHydrology项目..."
pip install -e .

# 验证安装
echo "验证项目安装..."
python -c "import neuralhydrology; print('NeuralHydrology导入成功')"

# =============================================================================
# 配置文件部署
# =============================================================================

echo "=========================================="
echo "部署配置文件..."
echo "=========================================="

# 从 src/<idea>/configs/ 收集并复制配置文件到HPC配置目录
if [ -d "src" ]; then
    copied_count=0
    while IFS= read -r cfg_dir; do
        idea_name=$(basename "$(dirname "$cfg_dir")")
        target_dir="$CONFIGS_DIR/$idea_name"
        mkdir -p "$target_dir"
        cp -r "$cfg_dir/"* "$target_dir/" 2>/dev/null || true
        echo "已复制 $idea_name 配置: $cfg_dir -> $target_dir"
        copied_count=$((copied_count + 1))
    done < <(find src -type d -name "configs")

    if [ "$copied_count" -eq 0 ]; then
        echo "警告: 未找到 src/<idea>/configs 目录"
    else
        echo "配置文件已复制到 $CONFIGS_DIR (共 $copied_count 个项目)"
    fi
else
    echo "警告: 未找到src目录"
fi

# 复制SLURM作业脚本
if [ -d "hpc" ]; then
    mkdir -p "$PROJECT_DIR/hpc"
    # 仅复制根目录共享脚本，跳过 archive 子目录
    find hpc -maxdepth 1 -type f -exec cp {} "$PROJECT_DIR/hpc/" \;
    echo "共享HPC脚本已复制到 $PROJECT_DIR/hpc"
else
    echo "警告: 未找到hpc目录"
fi

# 更新配置文件中的邮箱地址
echo "更新配置文件中的邮箱地址..."
find $PROJECT_DIR/hpc -name "*.slurm" -exec sed -i "s/your_email@hhu.edu.cn/$USER_EMAIL/g" {} \; 2>/dev/null || true

# =============================================================================
# 数据准备
# =============================================================================

echo "=========================================="
echo "检查数据准备..."
echo "=========================================="

# 检查数据目录
if [ -d "$DATA_DIR" ] && [ "$(ls -A $DATA_DIR)" ]; then
    echo "数据目录已存在且不为空"
    echo "数据目录大小: $(du -sh $DATA_DIR)"
    echo "数据文件数量: $(find $DATA_DIR -name "*.txt" | wc -l)"
else
    echo "警告: 数据目录为空或不存在"
    echo "请确保CAMELS_US数据已正确上传到 $DATA_DIR"
    echo "数据下载命令示例:"
    echo "  python src/full_531_basins/scripts/download_camels_us.py --data_dir $DATA_DIR"
fi

# =============================================================================
# 权限设置
# =============================================================================

echo "=========================================="
echo "设置文件权限..."
echo "=========================================="

# 设置项目目录权限
chmod -R 755 $PROJECT_DIR
chmod +x $PROJECT_DIR/hpc/*.slurm 2>/dev/null || true
chmod +x $PROJECT_DIR/src/full_531_basins/hpc/*.sh

echo "文件权限已设置"

# =============================================================================
# 环境测试
# =============================================================================

echo "=========================================="
echo "执行环境测试..."
echo "=========================================="

# 创建测试脚本
TEST_SCRIPT="$PROJECT_DIR/test_environment.py"
cat > $TEST_SCRIPT << 'EOF'
#!/usr/bin/env python3
"""HPC环境测试脚本"""

import sys
import os
import torch
import numpy as np
import pandas as pd

def test_environment():
    print("=" * 50)
    print("HPC环境测试")
    print("=" * 50)
    
    # Python环境
    print(f"Python版本: {sys.version}")
    print(f"Python路径: {sys.executable}")
    
    # PyTorch环境
    print(f"PyTorch版本: {torch.__version__}")
    print(f"CUDA可用: {torch.cuda.is_available()}")
    
    if torch.cuda.is_available():
        print(f"CUDA版本: {torch.version.cuda}")
        print(f"GPU数量: {torch.cuda.device_count()}")
        for i in range(torch.cuda.device_count()):
            print(f"GPU {i}: {torch.cuda.get_device_name(i)}")
            print(f"GPU {i} 内存: {torch.cuda.get_device_properties(i).total_memory / 1024**3:.1f} GB")
    
    # 其他包
    print(f"NumPy版本: {np.__version__}")
    print(f"Pandas版本: {pd.__version__}")
    
    # 内存测试
    print("\n内存测试:")
    try:
        # 创建大数组测试内存
        x = torch.randn(1000, 1000, device='cuda' if torch.cuda.is_available() else 'cpu')
        print("✅ 内存测试通过")
    except Exception as e:
        print(f"❌ 内存测试失败: {e}")
    
    # 导入测试
    print("\n导入测试:")
    try:
        import neuralhydrology
        print("✅ NeuralHydrology导入成功")
    except Exception as e:
        print(f"❌ NeuralHydrology导入失败: {e}")
    
    print("\n环境测试完成!")

if __name__ == "__main__":
    test_environment()
EOF

# 运行环境测试
echo "运行环境测试..."
python $TEST_SCRIPT

# 清理测试脚本
rm $TEST_SCRIPT

# =============================================================================
# 完成设置
# =============================================================================

echo "=========================================="
echo "HPC环境设置完成!"
echo "结束时间: $(date)"
echo "=========================================="

echo "设置摘要:"
echo "- 项目目录: $PROJECT_DIR"
echo "- Conda环境: $CONDA_ENV_NAME"
echo "- 数据目录: $DATA_DIR"
echo "- 配置文件: $CONFIGS_DIR"
echo "- 运行目录: $RUNS_DIR"
echo "- 日志目录: $LOGS_DIR"

echo ""
echo "下一步操作:"
echo "1. 检查数据是否已正确上传"
echo "2. 运行快速测试: sbatch $PROJECT_DIR/src/full_531_basins/hpc/hpc_quick_test.slurm"
echo "3. 如果测试通过，提交完整训练: sbatch $PROJECT_DIR/src/full_531_basins/hpc/hpc_full_training.slurm"
echo "4. 监控作业状态: squeue -u \$USER"

echo ""
echo "常用命令:"
echo "- 查看作业状态: squeue -u \$USER"
echo "- 查看作业输出: tail -f logs/neuralhydrology_*.out"
echo "- 取消作业: scancel <job_id>"
echo "- 激活环境: conda activate $CONDA_ENV_NAME"

echo ""
echo "✅ HPC环境设置完成!"




