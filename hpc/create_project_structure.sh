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

# 研究索引与文档
mkdir -p draft/ideas
mkdir -p docs

# 统一项目目录
mkdir -p src/templates
mkdir -p results
mkdir -p logs

# 数据目录
mkdir -p data/Caravan

# 环境与示例
mkdir -p environments
mkdir -p examples

# HPC 脚本
mkdir -p hpc

# 核心代码 (需要从本地上传)
mkdir -p neuralhydrology/datasetzoo
mkdir -p neuralhydrology/datautils
mkdir -p neuralhydrology/evaluation
mkdir -p neuralhydrology/modelzoo
mkdir -p neuralhydrology/training
mkdir -p neuralhydrology/utils

# 运行结果目录
mkdir -p runs

# 脚本和工具
mkdir -p scripts
mkdir -p tools

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
echo "   scp -r src/* user@hpc:${PROJECT_ROOT}/src/"
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
