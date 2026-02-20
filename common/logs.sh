#!/usr/bin/env bash
# =============================================================================
# HPC 日志管理脚本
#
# 用法:
#   ./common/logs.sh                     # 列出所有任务日志概览
#   ./common/logs.sh list                # 同上
#   ./common/logs.sh <task>              # 列出指定任务的日志
#   ./common/logs.sh <task> <job_id>     # 查看指定作业的日志
#   ./common/logs.sh tail <task>         # 实时查看最新日志
#   ./common/logs.sh clean <task>        # 清理指定任务的旧日志
#   ./common/logs.sh clean all           # 清理所有旧日志
#
# 示例:
#   ./common/logs.sh mamba_quick
#   ./common/logs.sh mamba_quick 12345
#   ./common/logs.sh tail caravan
#   ./common/logs.sh clean mamba_quick
# =============================================================================

set -eo pipefail

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 项目根目录
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_BASE="$PROJECT_ROOT/logs"

# 参数
ACTION="${1:-list}"
TASK="${2:-}"
JOB_ID="${3:-}"

# 列出所有任务日志概览
list_all() {
    echo -e "${BLUE}=========================================="
    echo "HPC 日志概览"
    echo -e "==========================================${NC}"
    echo -e "日志根目录: ${GREEN}$LOG_BASE${NC}"
    echo ""

    if [ ! -d "$LOG_BASE" ]; then
        echo -e "${YELLOW}[INFO] 日志目录不存在${NC}"
        return
    fi

    for task_dir in "$LOG_BASE"/*/; do
        if [ -d "$task_dir" ]; then
            task_name=$(basename "$task_dir")
            log_count=$(find "$task_dir" -name "*.out" 2>/dev/null | wc -l)
            if [ "$log_count" -gt 0 ]; then
                latest=$(ls -t "$task_dir"/*.out 2>/dev/null | head -1)
                latest_time=$(stat -c %y "$latest" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$latest" 2>/dev/null)
                echo -e "${CYAN}$task_name${NC}"
                echo -e "  日志数: $log_count"
                echo -e "  最新:   $(basename "$latest") ($latest_time)"
            else
                echo -e "${CYAN}$task_name${NC} (空)"
            fi
        fi
    done
    echo ""
    echo -e "${YELLOW}用法: ./common/logs.sh <task_name> [job_id]${NC}"
}

# 列出指定任务的日志
list_task() {
    local task="$1"
    local task_dir="$LOG_BASE/$task"

    if [ ! -d "$task_dir" ]; then
        echo -e "${RED}[ERROR] 任务日志目录不存在: $task_dir${NC}"
        return 1
    fi

    echo -e "${BLUE}=========================================="
    echo "任务: $task"
    echo -e "==========================================${NC}"

    # 列出所有日志（按时间倒序）
    echo -e "${GREEN}最近的作业日志:${NC}"
    for out_file in $(ls -t "$task_dir"/*.out 2>/dev/null | head -10); do
        job_id=$(basename "$out_file" .out)
        err_file="$task_dir/${job_id}.err"
        
        # 获取文件大小和时间
        out_size=$(du -h "$out_file" 2>/dev/null | cut -f1)
        mod_time=$(stat -c %y "$out_file" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$out_file" 2>/dev/null)
        
        # 检查是否有错误
        err_size=0
        if [ -f "$err_file" ]; then
            err_size=$(wc -c < "$err_file")
        fi
        
        if [ "$err_size" -gt 100 ]; then
            status="${RED}✗${NC}"
        else
            status="${GREEN}✓${NC}"
        fi
        
        printf "  %s %s  (%s, %s)\n" "$status" "$job_id" "$out_size" "$mod_time"
    done
    
    echo ""
    echo -e "${YELLOW}查看日志: ./common/logs.sh $task <job_id>${NC}"
    echo -e "${YELLOW}实时日志: ./common/logs.sh tail $task${NC}"
}

# 查看指定作业的日志
view_job() {
    local task="$1"
    local job_id="$2"
    local out_file="$LOG_BASE/$task/${job_id}.out"
    local err_file="$LOG_BASE/$task/${job_id}.err"

    if [ ! -f "$out_file" ]; then
        echo -e "${RED}[ERROR] 日志文件不存在: $out_file${NC}"
        return 1
    fi

    echo -e "${BLUE}=========================================="
    echo "Job: $job_id ($task)"
    echo -e "==========================================${NC}"
    
    # 显示标准输出
    echo -e "${GREEN}=== STDOUT ===${NC}"
    cat "$out_file"
    
    # 如果有错误输出
    if [ -f "$err_file" ] && [ -s "$err_file" ]; then
        echo ""
        echo -e "${RED}=== STDERR ===${NC}"
        cat "$err_file"
    fi
}

# 实时查看最新日志
tail_logs() {
    local task="$1"
    local task_dir="$LOG_BASE/$task"

    if [ ! -d "$task_dir" ]; then
        echo -e "${RED}[ERROR] 任务日志目录不存在: $task_dir${NC}"
        return 1
    fi

    # 找到最新的日志文件
    latest=$(ls -t "$task_dir"/*.out 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
        echo -e "${YELLOW}[INFO] 没有找到日志文件${NC}"
        return 1
    fi

    echo -e "${GREEN}[INFO] 实时查看: $latest${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    echo ""
    tail -f "$latest"
}

# 清理旧日志
clean_logs() {
    local task="$1"
    local keep_count=5  # 保留最近 5 个

    if [ "$task" = "all" ]; then
        echo -e "${YELLOW}清理所有任务的旧日志...${NC}"
        for task_dir in "$LOG_BASE"/*/; do
            if [ -d "$task_dir" ]; then
                task_name=$(basename "$task_dir")
                _clean_task "$task_name" "$keep_count"
            fi
        done
    else
        _clean_task "$task" "$keep_count"
    fi
}

_clean_task() {
    local task="$1"
    local keep="$2"
    local task_dir="$LOG_BASE/$task"

    if [ ! -d "$task_dir" ]; then
        return
    fi

    local total=$(find "$task_dir" -name "*.out" | wc -l)
    if [ "$total" -le "$keep" ]; then
        echo -e "  $task: 无需清理 ($total 个日志)"
        return
    fi

    local to_delete=$((total - keep))
    echo -e "  $task: 删除 $to_delete 个旧日志 (保留最近 $keep 个)"
    
    # 删除最旧的日志
    ls -t "$task_dir"/*.out 2>/dev/null | tail -n "$to_delete" | while read f; do
        job_id=$(basename "$f" .out)
        rm -f "$task_dir/${job_id}.out" "$task_dir/${job_id}.err"
    done
}

# 主逻辑
case "$ACTION" in
    list)
        list_all
        ;;
    tail)
        if [ -z "$TASK" ]; then
            echo -e "${RED}[ERROR] 请指定任务名称: ./common/logs.sh tail <task>${NC}"
            exit 1
        fi
        tail_logs "$TASK"
        ;;
    clean)
        if [ -z "$TASK" ]; then
            echo -e "${RED}[ERROR] 请指定任务名称或 'all': ./common/logs.sh clean <task|all>${NC}"
            exit 1
        fi
        clean_logs "$TASK"
        ;;
    *)
        # 如果第一个参数是任务名称
        if [ -d "$LOG_BASE/$ACTION" ]; then
            if [ -n "$TASK" ]; then
                view_job "$ACTION" "$TASK"
            else
                list_task "$ACTION"
            fi
        else
            echo -e "${RED}[ERROR] 未知命令或任务: $ACTION${NC}"
            echo ""
            echo "用法:"
            echo "  ./common/logs.sh                   # 列出所有任务"
            echo "  ./common/logs.sh <task>            # 列出任务日志"
            echo "  ./common/logs.sh <task> <job_id>   # 查看作业日志"
            echo "  ./common/logs.sh tail <task>       # 实时日志"
            echo "  ./common/logs.sh clean <task|all>  # 清理旧日志"
            exit 1
        fi
        ;;
esac
