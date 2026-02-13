#!/bin/bash
# =============================================================================
# NeuralHydrology HPC 快速部署脚本
# 一键部署和启动HPC训练
# =============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# 配置参数
# =============================================================================

PROJECT_DIR="/data/neuralhydrology"
CONDA_ENV_NAME="neuralhydrology_gpu"
USER_EMAIL="your_email@hhu.edu.cn"  # 需要用户修改

# 默认参数
MODE="help"
QUICK_TEST=false
FULL_TRAINING=false
SETUP_ENV=false
MONITOR=false

# =============================================================================
# 帮助信息
# =============================================================================

show_help() {
    cat << EOF
NeuralHydrology HPC 快速部署脚本

用法: $0 [选项]

选项:
    setup           设置HPC环境
    test            运行快速测试
    train           提交完整训练作业
    monitor         监控训练状态
    status          查看作业状态
    cancel          取消所有作业
    help            显示此帮助信息

示例:
    $0 setup         # 设置HPC环境
    $0 test          # 运行快速测试
    $0 train         # 提交完整训练
    $0 monitor       # 监控训练状态
    $0 status        # 查看作业状态

环境变量:
    PROJECT_DIR     项目目录 (默认: $PROJECT_DIR)
    USER_EMAIL      用户邮箱 (需要修改脚本中的默认值)

注意事项:
    1. 首次使用请先运行 'setup' 设置环境
    2. 建议先运行 'test' 验证环境配置
    3. 确认测试通过后再运行 'train' 提交完整训练
    4. 使用 'monitor' 监控训练进度

EOF
}

# =============================================================================
# 环境检查
# =============================================================================

check_environment() {
    print_info "检查HPC环境..."
    
    # 检查必要的命令
    local missing_commands=()
    
    if ! command -v sbatch &> /dev/null; then
        missing_commands+=("sbatch")
    fi
    
    if ! command -v squeue &> /dev/null; then
        missing_commands+=("squeue")
    fi
    
    if ! command -v conda &> /dev/null; then
        missing_commands+=("conda")
    fi
    
    if ! command -v nvidia-smi &> /dev/null; then
        missing_commands+=("nvidia-smi")
    fi
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        print_error "缺少必要的命令: ${missing_commands[*]}"
        print_error "请确保HPC环境已正确配置"
        exit 1
    fi
    
    print_success "HPC环境检查通过"
}

# =============================================================================
# 设置环境
# =============================================================================

setup_environment() {
    print_info "开始设置HPC环境..."
    
    # 检查项目目录
    if [ ! -d "$PROJECT_DIR" ]; then
        print_error "项目目录不存在: $PROJECT_DIR"
        print_error "请确保项目文件已正确上传"
        exit 1
    fi
    
    # 运行环境设置脚本
    if [ -f "$PROJECT_DIR/scripts/setup_hpc_environment.sh" ]; then
        print_info "运行环境设置脚本..."
        bash "$PROJECT_DIR/scripts/setup_hpc_environment.sh"
    else
        print_error "环境设置脚本不存在: $PROJECT_DIR/scripts/setup_hpc_environment.sh"
        exit 1
    fi
    
    print_success "HPC环境设置完成"
}

# =============================================================================
# 快速测试
# =============================================================================

run_quick_test() {
    print_info "提交快速测试作业..."
    
    # 检查配置文件
    local config_file="$PROJECT_DIR/configs/hpc/hpc_quick_test.yml"
    if [ ! -f "$config_file" ]; then
        print_error "快速测试配置文件不存在: $config_file"
        exit 1
    fi
    
    # 检查SLURM脚本
    local slurm_script="$PROJECT_DIR/slurm_jobs/hpc_quick_test.slurm"
    if [ ! -f "$slurm_script" ]; then
        print_error "快速测试SLURM脚本不存在: $slurm_script"
        exit 1
    fi
    
    # 提交作业
    print_info "提交快速测试作业..."
    local job_id=$(sbatch "$slurm_script" | awk '{print $4}')
    
    if [ -n "$job_id" ]; then
        print_success "快速测试作业已提交，作业ID: $job_id"
        print_info "查看作业状态: squeue -u \$USER"
        print_info "查看作业输出: tail -f $PROJECT_DIR/logs/neuralhydrology_test_${job_id}.out"
    else
        print_error "提交快速测试作业失败"
        exit 1
    fi
}

# =============================================================================
# 完整训练
# =============================================================================

run_full_training() {
    print_info "提交完整训练作业..."
    
    # 检查配置文件
    local config_file="$PROJECT_DIR/configs/hpc/hpc_full_training.yml"
    if [ ! -f "$config_file" ]; then
        print_error "完整训练配置文件不存在: $config_file"
        exit 1
    fi
    
    # 检查SLURM脚本
    local slurm_script="$PROJECT_DIR/slurm_jobs/hpc_full_training.slurm"
    if [ ! -f "$slurm_script" ]; then
        print_error "完整训练SLURM脚本不存在: $slurm_script"
        exit 1
    fi
    
    # 确认提交
    print_warning "即将提交完整训练作业，预计运行72小时"
    print_warning "请确认您有足够的计算资源配额"
    read -p "是否继续? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "已取消提交"
        exit 0
    fi
    
    # 提交作业
    print_info "提交完整训练作业..."
    local job_id=$(sbatch "$slurm_script" | awk '{print $4}')
    
    if [ -n "$job_id" ]; then
        print_success "完整训练作业已提交，作业ID: $job_id"
        print_info "查看作业状态: squeue -u \$USER"
        print_info "查看作业输出: tail -f $PROJECT_DIR/logs/neuralhydrology_full_${job_id}.out"
        print_info "监控训练进度: $0 monitor"
    else
        print_error "提交完整训练作业失败"
        exit 1
    fi
}

# =============================================================================
# 监控训练
# =============================================================================

monitor_training() {
    print_info "启动训练监控..."
    
    # 检查监控脚本
    local monitor_script="$PROJECT_DIR/scripts/monitor_training.py"
    if [ ! -f "$monitor_script" ]; then
        print_error "监控脚本不存在: $monitor_script"
        exit 1
    fi
    
    # 运行监控
    print_info "运行训练监控 (按Ctrl+C停止)..."
    python "$monitor_script" --project-dir "$PROJECT_DIR" --interval 60
}

# =============================================================================
# 查看状态
# =============================================================================

show_status() {
    print_info "查看作业状态..."
    
    # 显示SLURM作业
    echo "当前作业:"
    squeue -u "$USER" --format="%.10i %.20j %.8T %.10M %.6D %R"
    
    echo ""
    print_info "查看详细状态:"
    echo "  查看所有作业: squeue -u \$USER"
    echo "  查看作业详情: scontrol show job <job_id>"
    echo "  查看作业输出: tail -f $PROJECT_DIR/logs/*.out"
    
    # 显示GPU状态
    if command -v nvidia-smi &> /dev/null; then
        echo ""
        print_info "GPU状态:"
        nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv
    fi
}

# =============================================================================
# 取消作业
# =============================================================================

cancel_jobs() {
    print_info "取消所有作业..."
    
    # 获取当前用户的作业
    local jobs=$(squeue -u "$USER" --format="%.10i" --noheader)
    
    if [ -z "$jobs" ]; then
        print_info "没有运行中的作业"
        return 0
    fi
    
    # 确认取消
    print_warning "将取消以下作业:"
    squeue -u "$USER"
    read -p "确认取消所有作业? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "已取消操作"
        return 0
    fi
    
    # 取消作业
    for job_id in $jobs; do
        print_info "取消作业: $job_id"
        scancel "$job_id"
    done
    
    print_success "所有作业已取消"
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            setup)
                MODE="setup"
                shift
                ;;
            test)
                MODE="test"
                shift
                ;;
            train)
                MODE="train"
                shift
                ;;
            monitor)
                MODE="monitor"
                shift
                ;;
            status)
                MODE="status"
                shift
                ;;
            cancel)
                MODE="cancel"
                shift
                ;;
            help|--help|-h)
                MODE="help"
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 显示标题
    echo "=========================================="
    echo "NeuralHydrology HPC 快速部署脚本"
    echo "=========================================="
    
    # 检查邮箱配置
    if [ "$USER_EMAIL" = "your_email@hhu.edu.cn" ]; then
        print_warning "请修改脚本中的USER_EMAIL变量为您的实际邮箱"
    fi
    
    # 执行相应操作
    case $MODE in
        setup)
            check_environment
            setup_environment
            ;;
        test)
            check_environment
            run_quick_test
            ;;
        train)
            check_environment
            run_full_training
            ;;
        monitor)
            monitor_training
            ;;
        status)
            show_status
            ;;
        cancel)
            cancel_jobs
            ;;
        help)
            show_help
            ;;
        *)
            print_error "未知模式: $MODE"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
