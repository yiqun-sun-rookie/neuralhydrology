#!/usr/bin/env bash
# =============================================================================
# 智能作业提交脚本 - 自动管理日志目录
# 
# 用法:
#   ./hpc/submit.sh <task_name> [slurm_script] [extra_sbatch_args]
#
# 示例:
#   ./hpc/submit.sh mamba_camels_us                    # 全量 Mamba 训练
#   ./hpc/submit.sh mamba_quick                        # Mamba 快速验证
#   ./hpc/submit.sh caravan                            # Caravan 训练
#   ./hpc/submit.sh lstm_benchmark hpc/custom.slurm    # 自定义脚本
#
# 日志结构:
#   logs/
#   ├── mamba_camels_us/
#   │   ├── 12345.out
#   │   └── 12345.err
#   ├── mamba_quick/
#   │   └── ...
#   └── caravan/
#       └── ...
# =============================================================================

set -eo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 任务名称到 SLURM 脚本的映射
declare -A TASK_SCRIPTS=(
    ["mamba_camels_us"]="src/mamba_camels_us/hpc/submit_mamba_camels_us.slurm"
    ["mamba_quick"]="src/mamba_camels_us/hpc/submit_mamba_quick.slurm"
    ["caravan"]="hpc/submit_caravan.slurm"
    ["caravan_global"]="src/caravan_global/hpc/slurm_caravan_global.sh"
)

# 任务名称到描述的映射
declare -A TASK_DESCRIPTIONS=(
    ["mamba_camels_us"]="Mamba CAMELS-US 531 basins (Full)"
    ["mamba_quick"]="Mamba CAMELS-US 100 basins (Quick)"
    ["caravan"]="Caravan Global Daily Model"
    ["caravan_global"]="Caravan Global (Extended)"
)

# 获取项目根目录
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 解析参数
TASK_NAME="${1:-}"
SLURM_SCRIPT="${2:-}"
EXTRA_ARGS="${@:3}"

# 帮助信息
show_help() {
    echo -e "${BLUE}=========================================="
    echo "NeuralHydrology HPC 作业提交脚本"
    echo -e "==========================================${NC}"
    echo ""
    echo "用法: ./hpc/submit.sh <task_name> [slurm_script] [extra_args]"
    echo ""
    echo -e "${GREEN}可用任务:${NC}"
    for task in "${!TASK_SCRIPTS[@]}"; do
        printf "  %-20s - %s\n" "$task" "${TASK_DESCRIPTIONS[$task]}"
    done
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  ./hpc/submit.sh mamba_quick              # 快速验证"
    echo "  ./hpc/submit.sh mamba_camels_us          # 全量训练"
    echo "  ./hpc/submit.sh caravan                  # Caravan 训练"
    echo "  ./hpc/submit.sh my_exp hpc/custom.slurm  # 自定义脚本"
    echo ""
    echo -e "${BLUE}查看作业状态:${NC}"
    echo "  squeue -u \$USER"
    echo ""
    echo -e "${BLUE}查看日志:${NC}"
    echo "  tail -f logs/<task_name>/<job_id>.out"
    echo ""
}

# 检查参数
if [ -z "$TASK_NAME" ]; then
    show_help
    exit 0
fi

# 确定 SLURM 脚本
if [ -z "$SLURM_SCRIPT" ]; then
    # 使用预定义映射
    if [ -n "${TASK_SCRIPTS[$TASK_NAME]}" ]; then
        SLURM_SCRIPT="${TASK_SCRIPTS[$TASK_NAME]}"
    else
        echo -e "${RED}[ERROR] 未知任务: $TASK_NAME${NC}"
        echo "请指定 SLURM 脚本: ./hpc/submit.sh $TASK_NAME <slurm_script>"
        exit 1
    fi
fi

# 检查脚本文件是否存在
if [ ! -f "$SLURM_SCRIPT" ]; then
    echo -e "${RED}[ERROR] SLURM 脚本不存在: $SLURM_SCRIPT${NC}"
    exit 1
fi

# 创建日志目录
LOG_DIR="logs/${TASK_NAME}"
mkdir -p "$LOG_DIR"

# 显示提交信息
echo -e "${BLUE}=========================================="
echo "提交 HPC 作业"
echo -e "==========================================${NC}"
echo -e "任务名称:   ${GREEN}$TASK_NAME${NC}"
echo -e "SLURM 脚本: ${GREEN}$SLURM_SCRIPT${NC}"
echo -e "日志目录:   ${GREEN}$LOG_DIR/${NC}"
echo -e "项目根目录: ${GREEN}$PROJECT_ROOT${NC}"
if [ -n "$EXTRA_ARGS" ]; then
    echo -e "额外参数:   ${YELLOW}$EXTRA_ARGS${NC}"
fi
echo ""

# 提交作业，覆盖日志路径
JOB_OUTPUT=$(sbatch \
    --output="${LOG_DIR}/%j.out" \
    --error="${LOG_DIR}/%j.err" \
    --job-name="nh_${TASK_NAME}" \
    $EXTRA_ARGS \
    "$SLURM_SCRIPT" 2>&1)

# 解析 Job ID
if [[ "$JOB_OUTPUT" =~ Submitted\ batch\ job\ ([0-9]+) ]]; then
    JOB_ID="${BASH_REMATCH[1]}"
    echo -e "${GREEN}[SUCCESS] 作业已提交!${NC}"
    echo -e "  Job ID:    ${GREEN}$JOB_ID${NC}"
    echo -e "  输出日志:  ${GREEN}${LOG_DIR}/${JOB_ID}.out${NC}"
    echo -e "  错误日志:  ${GREEN}${LOG_DIR}/${JOB_ID}.err${NC}"
    echo ""
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  查看队列:    squeue -u \$USER"
    echo "  实时日志:    tail -f ${LOG_DIR}/${JOB_ID}.out"
    echo "  取消作业:    scancel $JOB_ID"
    echo ""
else
    echo -e "${RED}[ERROR] 作业提交失败:${NC}"
    echo "$JOB_OUTPUT"
    exit 1
fi
