#!/bin/bash
#===============================================================================
# NeuralHydrology HPC 环境初始化脚本
# 运行一次即可，用于在 HPC 上创建 Conda 环境并下载数据
#===============================================================================

set -e

echo "========================================"
echo "NeuralHydrology HPC 环境初始化"
echo "========================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(dirname "$SCRIPT_DIR")"
CONDA_ENV="neuralhydrology"

#===============================================================================
# Step 1: 创建 Conda 环境
#===============================================================================
echo ""
echo "[Step 1/4] 创建 Conda 环境..."

if conda env list | grep -q "^${CONDA_ENV} "; then
    echo "[INFO] 环境 ${CONDA_ENV} 已存在，跳过创建"
else
    echo "[INFO] 创建环境 ${CONDA_ENV}..."
    conda env create -f "${SCRIPT_DIR}/environment_hpc.yml"
fi

#===============================================================================
# Step 2: 创建目录结构
#===============================================================================
echo ""
echo "[Step 2/4] 创建目录结构..."

mkdir -p "${WORKDIR}/logs"
mkdir -p "${WORKDIR}/runs"
mkdir -p "${WORKDIR}/data"

echo "[INFO] 目录结构:"
echo "  ${WORKDIR}/logs   - SLURM 日志"
echo "  ${WORKDIR}/runs   - 训练输出"
echo "  ${WORKDIR}/data   - 数据集"

#===============================================================================
# Step 3: 下载 Caravan 数据集 (可选)
#===============================================================================
echo ""
echo "[Step 3/4] 数据集准备..."

CARAVAN_DIR="${WORKDIR}/data/Caravan"

if [ -d "$CARAVAN_DIR" ] && [ "$(ls -A $CARAVAN_DIR 2>/dev/null)" ]; then
    echo "[INFO] Caravan 数据集已存在: ${CARAVAN_DIR}"
    echo "[INFO] 文件数量: $(find $CARAVAN_DIR -type f | wc -l)"
else
    echo "[INFO] Caravan 数据集不存在"
    echo ""
    echo "请选择数据获取方式:"
    echo "  1. 手动上传: 将本地 data/Caravan 目录上传到 ${CARAVAN_DIR}"
    echo "  2. 从 Zenodo 下载 (推荐，HPC 下行速度快):"
    echo ""
    echo "     cd ${WORKDIR}/data"
    echo "     wget https://zenodo.org/record/7944025/files/Caravan.zip"
    echo "     unzip Caravan.zip"
    echo ""
fi

#===============================================================================
# Step 4: 验证安装
#===============================================================================
echo ""
echo "[Step 4/4] 验证安装..."

eval "$(conda shell.bash hook)"
conda activate ${CONDA_ENV}

echo "[INFO] 安装 NeuralHydrology (Editable mode)..."
pip install -e "${WORKDIR}"

echo "[INFO] Python 版本: $(python --version)"
echo "[INFO] PyTorch 版本: $(python -c 'import torch; print(torch.__version__)')"
echo "[INFO] CUDA 可用: $(python -c 'import torch; print(torch.cuda.is_available())')"
echo "[INFO] NeuralHydrology: $(python -c 'import neuralhydrology; print(neuralhydrology.__version__)' 2>/dev/null || echo '需要安装')"

#===============================================================================
# 完成
#===============================================================================
echo ""
echo "========================================"
echo "初始化完成!"
echo "========================================"
echo ""
echo "下一步:"
echo "  1. 确保数据集已准备好: ${CARAVAN_DIR}"
echo "  2. 提交训练作业:"
echo "     cd ${SCRIPT_DIR}"
echo "     ./submit_nh.sh"
echo ""
