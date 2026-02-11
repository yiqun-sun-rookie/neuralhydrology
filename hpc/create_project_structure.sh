#!/bin/bash
#===============================================================================
# NeuralHydrology 项目目录结构创建脚本 (HPC 版)
# 用法: ./create_project_structure.sh [项目根目录]
# 示例: ./create_project_structure.sh /data1/home/user/neuralhydrology
#===============================================================================

set -e

PROJECT_ROOT="${1:-$(pwd)}"

echo "========================================"
echo "创建 NeuralHydrology 项目目录结构"
echo "========================================"
echo "项目根目录: ${PROJECT_ROOT}"
echo ""

# 创建主目录
mkdir -p "${PROJECT_ROOT}"
cd "${PROJECT_ROOT}"

# 创建核心目录结构
echo "[INFO] 创建目录结构..."

# 配置目录
mkdir -p configs/archive
mkdir -p configs/camels_us
mkdir -p configs/caravan
mkdir -p configs/full_training

# 数据目录 (Caravan 将在这里下载)
mkdir -p data/Caravan

# 文档目录
mkdir -p docs

# 环境配置
mkdir -p environments

# 示例和实验
mkdir -p examples
mkdir -p experiments/templates

# HPC 脚本
mkdir -p hpc

# 日志目录
mkdir -p logs

# 核心代码 (需要从本地上传)
mkdir -p neuralhydrology/datasetzoo
mkdir -p neuralhydrology/datautils
mkdir -p neuralhydrology/evaluation
mkdir -p neuralhydrology/modelzoo
mkdir -p neuralhydrology/training
mkdir -p neuralhydrology/utils

# 管道和项目
mkdir -p pipelines
mkdir -p projects

# 运行结果目录
mkdir -p runs

# 脚本和工具
mkdir -p scripts
mkdir -p tools

# SLURM 作业目录
mkdir -p slurm_jobs

# 测试目录
mkdir -p test

echo ""
echo "✓ 目录结构创建完成!"
echo ""
echo "目录树:"
find . -type d -maxdepth 2 | head -30
echo ""
echo "========================================"
echo "下一步操作:"
echo "========================================"
echo ""
echo "1. 上传代码文件:"
echo "   scp -r neuralhydrology/*.py user@hpc:${PROJECT_ROOT}/neuralhydrology/"
echo "   scp -r configs/* user@hpc:${PROJECT_ROOT}/configs/"
echo "   scp -r hpc/* user@hpc:${PROJECT_ROOT}/hpc/"
echo ""
echo "2. 下载 Caravan 数据集:"
echo "   cd ${PROJECT_ROOT}/hpc"
echo "   ./download_caravan.sh ${PROJECT_ROOT}/data"
echo ""
echo "3. 创建 Conda 环境:"
echo "   cd ${PROJECT_ROOT}/hpc"
echo "   ./setup_hpc.sh"
echo ""
