#!/bin/bash
#===============================================================================
# NeuralHydrology 快速提交脚本
# 用法: ./submit_nh.sh [config_file] [partition] [time]
# 示例: ./submit_nh.sh src/caravan_global/configs/caravan_daily_basemodel.yml hgpu2p 48:00:00
#===============================================================================

set -e

# 默认值
CONFIG_FILE="${1:-src/caravan_global/configs/caravan_daily_basemodel.yml}"
PARTITION="${2:-hgpu2p}"
WALLTIME="${3:-72:00:00}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "NeuralHydrology HPC 作业提交"
echo "========================================"
echo "配置文件: ${CONFIG_FILE}"
echo "分区: ${PARTITION}"
echo "时间限制: ${WALLTIME}"
echo "工作目录: ${WORKDIR}"
echo ""

# 检查配置文件是否存在
if [ ! -f "${WORKDIR}/${CONFIG_FILE}" ]; then
    echo "[ERROR] 配置文件不存在: ${WORKDIR}/${CONFIG_FILE}"
    exit 1
fi

# 确保日志目录存在
mkdir -p "${WORKDIR}/logs"

# 提交作业
JOB_ID=$(sbatch \
    --partition="${PARTITION}" \
    --time="${WALLTIME}" \
    --export=ALL,WORKDIR="${WORKDIR}",CONFIG_FILE="${CONFIG_FILE}" \
    "${SCRIPT_DIR}/slurm_nh_gpu.sh" | awk '{print $4}')

echo ""
echo "[SUCCESS] 作业已提交!"
echo "作业ID: ${JOB_ID}"
echo ""
echo "监控命令:"
echo "  squeue -j ${JOB_ID}                    # 查看作业状态"
echo "  tail -f logs/nh-${JOB_ID}.out          # 查看输出日志"
echo "  scancel ${JOB_ID}                      # 取消作业"
echo ""
