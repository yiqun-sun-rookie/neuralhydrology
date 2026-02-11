#!/bin/bash
#===============================================================================
# Caravan 数据集下载脚本 (HPC 版)
# 用法: ./download_caravan.sh [目标目录]
# 示例: ./download_caravan.sh /data1/home/user/neuralhydrology/data
#===============================================================================

set -e

# 配置
TARGET_DIR="${1:-$(pwd)/data}"
CARAVAN_DIR="${TARGET_DIR}/Caravan"
ZENODO_URL="https://zenodo.org/record/7944025/files/Caravan.zip"
EXPECTED_MD5="bd9d6e9dd1d0da0731b53678f551f8f9"

echo "========================================"
echo "Caravan 数据集下载脚本"
echo "========================================"
echo "目标目录: ${TARGET_DIR}"
echo "Zenodo URL: ${ZENODO_URL}"
echo ""

#===============================================================================
# Step 1: 创建目录结构
#===============================================================================
echo "[Step 1/4] 创建目录结构..."
mkdir -p "${TARGET_DIR}"
cd "${TARGET_DIR}"

echo "  ✓ 目录已创建: ${TARGET_DIR}"

#===============================================================================
# Step 2: 下载数据集
#===============================================================================
echo ""
echo "[Step 2/4] 下载 Caravan.zip (~12.5GB)..."

if [ -f "Caravan.zip" ]; then
    echo "  [INFO] Caravan.zip 已存在，跳过下载"
else
    echo "  [INFO] 开始下载..."
    wget --progress=bar:force:noscroll -O Caravan.zip "${ZENODO_URL}"
    echo "  ✓ 下载完成"
fi

#===============================================================================
# Step 3: 验证 MD5 校验和
#===============================================================================
echo ""
echo "[Step 3/4] 验证 MD5 校验和..."

ACTUAL_MD5=$(md5sum Caravan.zip | awk '{print $1}')

if [ "${ACTUAL_MD5}" = "${EXPECTED_MD5}" ]; then
    echo "  ✓ MD5 校验通过!"
    echo "    期望: ${EXPECTED_MD5}"
    echo "    实际: ${ACTUAL_MD5}"
else
    echo "  ✗ MD5 校验失败!"
    echo "    期望: ${EXPECTED_MD5}"
    echo "    实际: ${ACTUAL_MD5}"
    echo ""
    echo "  文件可能损坏，请删除后重新下载:"
    echo "    rm Caravan.zip"
    echo "    ./download_caravan.sh"
    exit 1
fi

#===============================================================================
# Step 4: 解压数据集
#===============================================================================
echo ""
echo "[Step 4/4] 解压数据集..."

if [ -d "Caravan" ] && [ "$(ls -A Caravan 2>/dev/null)" ]; then
    echo "  [INFO] Caravan 目录已存在且非空，跳过解压"
else
    echo "  [INFO] 解压中 (可能需要几分钟)..."
    unzip -q Caravan.zip
    echo "  ✓ 解压完成"
fi

#===============================================================================
# 验证结果
#===============================================================================
echo ""
echo "========================================"
echo "下载完成!"
echo "========================================"
echo ""
echo "数据集位置: ${CARAVAN_DIR}"
echo "文件统计:"
find "${CARAVAN_DIR}" -type f | wc -l | xargs -I {} echo "  文件数: {}"
du -sh "${CARAVAN_DIR}" | awk '{print "  总大小: " $1}'
echo ""
echo "目录结构:"
ls -la "${CARAVAN_DIR}" | head -10
echo ""
echo "下一步: 修改配置文件中的 data_dir 指向此目录"
echo "  data_dir: ${TARGET_DIR}/Caravan"
echo ""

# 可选：删除 zip 文件节省空间
read -p "是否删除 Caravan.zip 以节省空间? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f Caravan.zip
    echo "  ✓ Caravan.zip 已删除"
fi
