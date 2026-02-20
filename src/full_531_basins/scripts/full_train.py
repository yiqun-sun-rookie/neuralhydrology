#!/usr/bin/env python3
"""NeuralHydrology 完整数据集训练启动器

此脚本专门用于完整数据集（674个流域）的训练。

功能：
1. 检查 neuralhydrology_gpu conda 环境是否存在
2. 读取 YAML 配置文件（默认 src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml）
3. 检查 GPU 可用性和内存
4. 在指定 conda 环境中启动训练
5. 支持断点续训功能
6. 训练进度监控和资源使用统计
7. 自动备份重要配置和日志

使用方式：
    # 新训练（完整数据集）
    python src/full_531_basins/scripts/full_train.py --config src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml --gpu 0
    
    # 断点续训（自动选择最新运行）
    python src/full_531_basins/scripts/full_train.py --resume
    
    # 从指定运行目录恢复训练
    python src/full_531_basins/scripts/full_train.py --resume --run-dir runs/full_training_2025_1024_1631_ep3
    
    # 从指定epoch恢复训练
    python src/full_531_basins/scripts/full_train.py --resume --run-dir runs/full_training_2025_1024_1631_ep3 --epoch 2
    
    # 监控模式（显示详细进度）
    python src/full_531_basins/scripts/full_train.py --monitor --config src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml

参数：
    --config <path.yml>   指定配置文件（可选，默认使用 full_training.yml）
    --gpu <id|-1>         指定 GPU ID，-1 表示使用 CPU
    --resume              继续训练（断点续训）
    --run-dir <path>      指定要继续的训练运行目录
    --epoch <num>         指定从哪个epoch开始继续训练
    --clean               清理不完整的运行目录
    --monitor             启用详细监控模式
    --backup              训练前备份重要文件

环境要求：
    - 必须安装 Anaconda 或 Miniconda
    - 必须存在 neuralhydrology_gpu conda 环境
    - 如果环境不存在，请运行：conda env create -f environments/environment_cuda11_8.yml
    - 建议至少 8GB GPU 内存用于完整数据集训练

建议：将不同实验的 YAML 复制改名，用 Git 追踪配置变更。
"""

import sys
import subprocess
import os
import time
import threading
from pathlib import Path
from datetime import datetime

# 尝试导入psutil，如果失败则使用替代方案
try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False
    print("[WARNING] psutil库未安装，部分系统监控功能将不可用")
    print("[INFO] 如需完整功能，请运行: conda install psutil")

# 设置控制台编码解决中文乱码问题
if sys.platform.startswith('win'):
    try:
        import codecs
        sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
        sys.stderr = codecs.getwriter('utf-8')(sys.stderr.detach())
    except:
        # 如果设置编码失败，继续运行
        pass

# 设置环境变量解决OpenMP冲突
os.environ['KMP_DUPLICATE_LIB_OK'] = 'TRUE'
os.environ['OMP_NUM_THREADS'] = '1'

DEFAULT_CONFIG = "src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml"

# 强制使用的 Conda 环境与 GPU 设置
CONDA_ENV_NAME = "neuralhydrology_gpu"
USE_CONDA_RUN = True  # 强制使用 conda 环境，如果不存在则报错

# 监控相关变量
monitoring_active = False
training_process = None


# =============================================================================
# 系统检查函数
# =============================================================================

def check_conda_env():
    """检查指定的 conda 环境是否存在"""
    try:
        result = subprocess.run(
            ["conda", "env", "list"], 
            capture_output=True, 
            text=True, 
            check=True
        )
        env_list = result.stdout
        if CONDA_ENV_NAME in env_list:
            print(f"[OK] 找到 conda 环境: {CONDA_ENV_NAME}")
            return True
        else:
            print(f"[ERROR] 未找到 conda 环境: {CONDA_ENV_NAME}")
            print(f"[INFO] 请先创建环境: conda env create -f environments/environment_cuda11_8.yml")
            return False
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("[ERROR] conda 命令不可用，请确保已安装 Anaconda 或 Miniconda")
        return False

def check_pytorch_gpu():
    """检查PyTorch和GPU支持，包括内存信息"""
    try:
        import torch
        print(f"[OK] PyTorch版本: {torch.__version__}")
        
        if torch.cuda.is_available():
            gpu_count = torch.cuda.device_count()
            print(f"[OK] CUDA可用: {gpu_count} 个GPU设备")
            
            # 显示每个GPU的详细信息
            for i in range(gpu_count):
                gpu_name = torch.cuda.get_device_name(i)
                gpu_memory = torch.cuda.get_device_properties(i).total_memory / 1024**3
                print(f"  GPU {i}: {gpu_name} ({gpu_memory:.1f} GB)")
            
            return True, gpu_count
        else:
            print("[ERROR] CUDA不可用")
            return False, 0
    except ImportError:
        print("[ERROR] PyTorch未安装")
        return False, 0

def check_system_resources():
    """检查系统资源"""
    if PSUTIL_AVAILABLE:
        # CPU信息
        cpu_count = psutil.cpu_count()
        cpu_percent = psutil.cpu_percent(interval=1)
        print(f"[INFO] CPU: {cpu_count} 核心，当前使用率: {cpu_percent:.1f}%")
        
        # 内存信息
        memory = psutil.virtual_memory()
        memory_gb = memory.total / 1024**3
        memory_used_gb = memory.used / 1024**3
        memory_percent = memory.percent
        print(f"[INFO] 内存: {memory_gb:.1f} GB 总计，{memory_used_gb:.1f} GB 已用 ({memory_percent:.1f}%)")
        
        # 磁盘空间
        disk = psutil.disk_usage('.')
        disk_free_gb = disk.free / 1024**3
        print(f"[INFO] 磁盘可用空间: {disk_free_gb:.1f} GB")
        
        return {
            'cpu_count': cpu_count,
            'memory_gb': memory_gb,
            'disk_free_gb': disk_free_gb
        }
    else:
        print("[INFO] 系统资源检查跳过（psutil未安装）")
        return {
            'cpu_count': 'unknown',
            'memory_gb': 'unknown',
            'disk_free_gb': 'unknown'
        }

def check_data_availability():
    """检查数据文件是否可用"""
    data_dir = Path("data/CAMELS_US")
    if not data_dir.exists():
        print(f"[ERROR] 数据目录不存在: {data_dir}")
        return False
    
    # 检查CAMELS-US数据集的必要目录结构
    required_dirs = [
        "basin_mean_forcing",
        "usgs_streamflow",
        "camels_attributes_v2.0"
    ]
    
    missing_dirs = []
    for dir_name in required_dirs:
        dir_path = data_dir / dir_name
        if not dir_path.exists():
            missing_dirs.append(dir_name)
    
    if missing_dirs:
        print(f"[ERROR] 缺少必要的数据目录: {missing_dirs}")
        return False
    
    # 检查forcing数据
    forcing_dir = data_dir / "basin_mean_forcing"
    daymet_dir = forcing_dir / "daymet"
    if not daymet_dir.exists():
        print(f"[ERROR] 缺少daymet forcing数据目录: {daymet_dir}")
        return False
    
    # 检查是否有流域数据文件
    daymet_files = list(daymet_dir.glob("**/*.txt"))
    if len(daymet_files) == 0:
        print(f"[ERROR] 在 {daymet_dir} 中没有找到流域数据文件")
        return False
    
    # 检查streamflow数据
    streamflow_dir = data_dir / "usgs_streamflow"
    streamflow_files = list(streamflow_dir.glob("**/*.txt"))
    if len(streamflow_files) == 0:
        print(f"[ERROR] 在 {streamflow_dir} 中没有找到streamflow数据文件")
        return False
    
    # 检查属性文件
    attributes_dir = data_dir / "camels_attributes_v2.0"
    attribute_files = list(attributes_dir.glob("*.txt"))
    if len(attribute_files) == 0:
        print(f"[ERROR] 在 {attributes_dir} 中没有找到属性文件")
        return False
    
    print(f"[OK] 数据目录检查通过: {data_dir}")
    print(f"[INFO] 找到 {len(daymet_files)} 个forcing文件")
    print(f"[INFO] 找到 {len(streamflow_files)} 个streamflow文件")
    print(f"[INFO] 找到 {len(attribute_files)} 个属性文件")
    return True


# =============================================================================
# 监控功能
# =============================================================================

def monitor_resources():
    """监控系统资源使用情况"""
    global monitoring_active, training_process
    
    while monitoring_active:
        try:
            if PSUTIL_AVAILABLE:
                # CPU和内存使用率
                cpu_percent = psutil.cpu_percent(interval=1)
                memory = psutil.virtual_memory()
                memory_percent = memory.percent
                
                # 训练进程信息
                process_info = ""
                if training_process and training_process.poll() is None:
                    try:
                        process = psutil.Process(training_process.pid)
                        process_memory = process.memory_info().rss / 1024**3
                        process_cpu = process.cpu_percent()
                        process_info = f"训练进程: {process_memory:.1f}GB内存, {process_cpu:.1f}%CPU"
                    except:
                        pass
                
                system_info = f"CPU: {cpu_percent:.1f}% | 内存: {memory_percent:.1f}% | {process_info}"
            else:
                system_info = "系统监控不可用（psutil未安装）"
            
            # GPU使用情况（如果可用）
            gpu_info = ""
            try:
                import torch
                if torch.cuda.is_available():
                    for i in range(torch.cuda.device_count()):
                        gpu_memory = torch.cuda.memory_allocated(i) / 1024**3
                        gpu_memory_max = torch.cuda.max_memory_allocated(i) / 1024**3
                        gpu_info += f"GPU{i}: {gpu_memory:.1f}/{gpu_memory_max:.1f}GB "
            except:
                pass
            
            timestamp = datetime.now().strftime("%H:%M:%S")
            print(f"[{timestamp}] {system_info} | {gpu_info}")
            
            time.sleep(30)  # 每30秒监控一次
            
        except Exception as e:
            print(f"[WARNING] 监控出错: {e}")
            time.sleep(60)

def start_monitoring():
    """启动资源监控"""
    global monitoring_active
    monitoring_active = True
    monitor_thread = threading.Thread(target=monitor_resources, daemon=True)
    monitor_thread.start()
    print("[INFO] 资源监控已启动")

def stop_monitoring():
    """停止资源监控"""
    global monitoring_active
    monitoring_active = False
    print("[INFO] 资源监控已停止")


# =============================================================================
# 文件管理功能
# =============================================================================

def backup_important_files():
    """备份重要文件"""
    backup_dir = Path("backups")
    backup_dir.mkdir(exist_ok=True)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_subdir = backup_dir / f"backup_{timestamp}"
    backup_subdir.mkdir(exist_ok=True)
    
    # 备份配置文件
    config_files = [
        "src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml",
        "src/full_531_basins/configs/camels_us/data_splits/531_basins_train_basins.txt",
        "src/full_531_basins/configs/camels_us/data_splits/531_basins_val_basins.txt",
        "src/full_531_basins/configs/camels_us/data_splits/531_basins_test_basins.txt"
    ]
    
    for config_file in config_files:
        src = Path(config_file)
        if src.exists():
            dst = backup_subdir / src.name
            import shutil
            shutil.copy2(src, dst)
            print(f"[BACKUP] 已备份: {config_file}")
    
    print(f"[INFO] 备份完成: {backup_subdir}")
    return backup_subdir

def clean_incomplete_runs():
    """清理不完整的训练运行目录"""
    runs_dir = Path("runs")
    if not runs_dir.exists():
        return
    
    print("[INFO] 检查不完整的训练运行...")
    cleaned_count = 0
    
    for run_dir in runs_dir.iterdir():
        if run_dir.is_dir():
            # 检查是否有模型文件
            model_files = list(run_dir.glob("model_epoch*.pt"))
            if not model_files:
                # 没有模型文件，可能是不完整的运行
                try:
                    import shutil
                    shutil.rmtree(run_dir)
                    print(f"[CLEAN] 删除不完整的运行目录: {run_dir.name}")
                    cleaned_count += 1
                except Exception as e:
                    print(f"[WARNING] 无法删除目录 {run_dir.name}: {e}")
    
    if cleaned_count > 0:
        print(f"[INFO] 清理了 {cleaned_count} 个不完整的运行目录")
    else:
        print("[INFO] 没有发现不完整的运行目录")

def list_available_runs():
    """列出可用的训练运行"""
    runs_dir = Path("runs")
    if not runs_dir.exists():
        print("[INFO] 没有找到训练运行目录")
        return []
    
    runs = []
    for run_dir in runs_dir.iterdir():
        if run_dir.is_dir():
            # 检查是否有模型文件
            model_files = list(run_dir.glob("model_epoch*.pt"))
            if model_files:
                # 获取最新的epoch
                epochs = []
                for f in model_files:
                    # 解析文件名，如 model_epoch010.pt -> 10
                    epoch_str = f.stem.replace('model_epoch', '')
                    try:
                        epochs.append(int(epoch_str))
                    except ValueError:
                        continue
                
                if epochs:
                    latest_epoch = max(epochs)
                    runs.append({
                        'path': run_dir,
                        'name': run_dir.name,
                        'latest_epoch': latest_epoch,
                        'model_count': len(model_files)
                    })
    
    # 按修改时间排序（最新的在前）
    runs.sort(key=lambda x: x['path'].stat().st_mtime, reverse=True)
    return runs

def select_run_to_resume(runs):
    """选择要恢复的训练运行"""
    if not runs:
        print("[ERROR] 没有找到可恢复的训练运行")
        return None
    
    print("\n[INFO] 可用的训练运行:")
    for i, run in enumerate(runs):
        print(f"  {i+1}. {run['name']} (最新epoch: {run['latest_epoch']}, 模型文件: {run['model_count']})")
    
    while True:
        try:
            choice = input(f"\n请选择要恢复的训练运行 (1-{len(runs)}, 或按Enter选择最新的): ").strip()
            if not choice:
                return runs[0]['path']
            
            choice_idx = int(choice) - 1
            if 0 <= choice_idx < len(runs):
                return runs[choice_idx]['path']
            else:
                print(f"[ERROR] 请输入1到{len(runs)}之间的数字")
        except ValueError:
            print("[ERROR] 请输入有效的数字")
        except KeyboardInterrupt:
            print("\n[INFO] 操作已取消")
            return None


# =============================================================================
# 训练函数
# =============================================================================

def resume_training(run_dir, gpu_flag, epoch=None, monitor=False):
    """恢复训练"""
    global training_process
    
    run_dir = Path(run_dir)
    if not run_dir.exists():
        print(f"[ERROR] 运行目录不存在: {run_dir}")
        return False
    
    # 检查配置文件
    config_file = run_dir / "config.yml"
    if not config_file.exists():
        print(f"[ERROR] 配置文件不存在: {config_file}")
        return False
    
    # 构建继续训练命令
    base_cmd = [
        "neuralhydrology/nh_run.py",
        "continue_training",
        "--run-dir", str(run_dir),
        "--gpu", gpu_flag
    ]
    
    if epoch is not None:
        base_cmd.extend(["--epoch", str(epoch)])
    
    # 强制使用 conda 环境运行训练
    cmd = [
        "conda", "run", "-n", CONDA_ENV_NAME, "python",
        *base_cmd
    ]
    
    print(f"[INFO] 从 {run_dir.name} 恢复训练...")
    if epoch is not None:
        print(f"[INFO] 从 epoch {epoch} 开始")
    else:
        print("[INFO] 从最新检查点开始")
    
    print("Resume training: " + " ".join(cmd))
    
    # 启动监控
    if monitor:
        start_monitoring()
    
    try:
        training_process = subprocess.Popen(cmd)
        training_process.wait()
        
        if monitor:
            stop_monitoring()
        
        if training_process.returncode == 0:
            print("Training resumed and completed, check runs/*/output.log")
            return True
        else:
            print(f"[ERROR] 恢复训练失败，退出码: {training_process.returncode}")
            return False
    except FileNotFoundError:
        print(f"[ERROR] conda 命令不可用，请确保已安装 Anaconda 或 Miniconda")
        return False
    except KeyboardInterrupt:
        print("\n[INFO] 训练被用户中断")
        if training_process:
            training_process.terminate()
        if monitor:
            stop_monitoring()
        return False

def start_training(config_path, gpu_flag, monitor=False, backup=False):
    """开始新训练"""
    global training_process
    
    # 备份重要文件
    if backup:
        backup_important_files()
    
    # 构建训练命令
    base_cmd = [
        "neuralhydrology/nh_run.py",
        "train",
        "--config-file", str(config_path),
        "--gpu", gpu_flag
    ]

    # 强制使用 conda 环境运行训练
    cmd = [
        "conda", "run", "-n", CONDA_ENV_NAME, "python",
        *base_cmd
    ]

    print("Starting training: " + " ".join(cmd))
    
    # 启动监控
    if monitor:
        start_monitoring()
    
    try:
        training_process = subprocess.Popen(cmd)
        training_process.wait()
        
        if monitor:
            stop_monitoring()
        
        if training_process.returncode == 0:
            print("Training completed, check runs/*/output.log")
            return True
        else:
            print(f"[ERROR] 训练失败，退出码: {training_process.returncode}")
            return False
    except FileNotFoundError:
        print(f"[ERROR] conda 命令不可用，请确保已安装 Anaconda 或 Miniconda")
        return False
    except KeyboardInterrupt:
        print("\n[INFO] 训练被用户中断")
        if training_process:
            training_process.terminate()
        if monitor:
            stop_monitoring()
        return False


# =============================================================================
# 主函数
# =============================================================================

def show_interactive_menu():
    """显示交互式菜单"""
    print("\n" + "="*60)
    print("NeuralHydrology 完整数据集训练启动器")
    print("="*60)
    print("请选择操作:")
    print("1. 开始新训练（完整数据集）")
    print("2. 继续训练（断点续训）")
    print("3. 监控训练进度")
    print("4. 清理不完整的运行")
    print("5. 生成训练报告")
    print("6. 退出")
    print("="*60)
    
    while True:
        try:
            choice = input("\n请输入选择 (1-6): ").strip()
            if choice in ['1', '2', '3', '4', '5', '6']:
                return int(choice)
            else:
                print("[ERROR] 无效选择，请输入1-6之间的数字")
        except KeyboardInterrupt:
            print("\n[INFO] 操作已取消")
            return 6
        except Exception:
            print("[ERROR] 输入错误，请重新输入")

def get_user_inputs():
    """获取用户输入"""
    inputs = {}
    
    # GPU选择
    while True:
        try:
            gpu_input = input("请输入GPU ID (0-3, 或-1使用CPU, 默认0): ").strip()
            if not gpu_input:
                inputs['gpu'] = "0"
                break
            elif gpu_input in ['-1', '0', '1', '2', '3']:
                inputs['gpu'] = gpu_input
                break
            else:
                print("[ERROR] 无效GPU ID，请输入0-3或-1")
        except KeyboardInterrupt:
            print("\n[INFO] 操作已取消")
            return None
    
    # 监控模式选择
    monitor_input = input("是否启用监控模式? (y/N, 默认N): ").strip().lower()
    inputs['monitor'] = monitor_input in ['y', 'yes']
    
    # 备份选择
    backup_input = input("是否备份重要文件? (y/N, 默认Y): ").strip().lower()
    inputs['backup'] = backup_input not in ['n', 'no']
    
    return inputs

def main():
    import argparse
    parser = argparse.ArgumentParser(description="NeuralHydrology 完整数据集训练启动器")
    parser.add_argument("--config", default=DEFAULT_CONFIG, help="YAML 配置文件路径")
    parser.add_argument("--gpu", default="0", help="GPU id，-1 表示 CPU")
    parser.add_argument("--clean", action="store_true", help="清理不完整的运行目录")
    parser.add_argument("--resume", action="store_true", help="继续训练（断点续训）")
    parser.add_argument("--run-dir", help="指定要继续的训练运行目录")
    parser.add_argument("--epoch", type=int, help="指定从哪个epoch开始继续训练")
    parser.add_argument("--monitor", action="store_true", help="启用详细监控模式")
    parser.add_argument("--backup", action="store_true", help="训练前备份重要文件")
    parser.add_argument("--interactive", action="store_true", help="启用交互式菜单")
    args = parser.parse_args()
    
    # 如果没有提供任何参数，先进行数据检查，然后询问是否使用交互模式
    if len(sys.argv) == 1:
        # 直接进行数据检查
        print("=" * 60)
        print("NeuralHydrology 完整数据集训练启动器")
        print("=" * 60)
        
        # 系统检查
        print("\n[INFO] 执行系统检查...")
        
        # 检查 conda 环境
        if not check_conda_env():
            print(f"[ERROR] 必须使用 {CONDA_ENV_NAME} conda 环境才能运行训练")
            return False
        
        # 检查数据可用性
        if not check_data_availability():
            print("\n[ERROR] 数据检查失败，无法开始训练")
            return False
        
        print("\n[SUCCESS] 所有检查通过！数据准备就绪。")
        
        # 询问是否使用交互模式
        try:
            use_interactive = input("\n是否使用交互式菜单? (y/N): ").strip().lower()
            if use_interactive in ['y', 'yes']:
                args.interactive = True
            else:
                print("\n[INFO] 使用命令行模式")
                print("\n使用方法:")
                print("  python src/full_531_basins/scripts/full_train.py --config src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml --gpu 0")
                print("  python src/full_531_basins/scripts/full_train.py --resume  # 继续训练")
                print("  python src/full_531_basins/scripts/full_train.py --interactive  # 启用交互式菜单")
                return True
        except KeyboardInterrupt:
            print("\n[INFO] 操作已取消")
            return True

    # 如果启用了交互式菜单
    if args.interactive:
        while True:
            choice = show_interactive_menu()
            
            if choice == 1:  # 新训练
                print("\n[INFO] 开始新训练...")
                inputs = get_user_inputs()
                if inputs is None:
                    continue
                
                config_path = Path(args.config)
                if not config_path.exists():
                    print(f"[ERROR] 找不到配置文件: {config_path}")
                    print("[INFO] 请确保配置文件存在或使用正确的路径")
                    try:
                        retry = input("\n是否返回主菜单? (y/N): ").strip().lower()
                        if retry not in ['y', 'yes']:
                            continue
                    except KeyboardInterrupt:
                        print("\n[INFO] 操作已取消")
                        continue
                
                # 系统检查
                if not check_conda_env():
                    print(f"[ERROR] 必须使用 {CONDA_ENV_NAME} conda 环境才能运行训练")
                    print("[INFO] 请先激活正确的conda环境: conda activate neuralhydrology_gpu")
                    try:
                        retry = input("\n是否返回主菜单? (y/N): ").strip().lower()
                        if retry not in ['y', 'yes']:
                            continue
                    except KeyboardInterrupt:
                        print("\n[INFO] 操作已取消")
                        continue
                
                if not check_data_availability():
                    print("\n[ERROR] 数据文件检查失败，无法开始训练")
                    print("[INFO] 请确保CAMELS-US数据集已正确放置在 data/CAMELS_US 目录下")
                    try:
                        retry = input("\n是否重新检查数据? (y/N): ").strip().lower()
                        if retry not in ['y', 'yes']:
                            continue
                        else:
                            # 重新检查数据
                            if not check_data_availability():
                                print("[ERROR] 数据检查仍然失败，返回主菜单")
                                continue
                    except KeyboardInterrupt:
                        print("\n[INFO] 操作已取消")
                        continue
                
                # 处理GPU设置
                gpu_flag = inputs['gpu']
                if gpu_flag != "-1":
                    gpu_available, cnt = check_pytorch_gpu()
                    if not gpu_available:
                        print("[WARNING] 未检测到可用 GPU，改用 CPU (--gpu -1)")
                        gpu_flag = "-1"
                    else:
                        try:
                            if int(gpu_flag) >= cnt:
                                print(f"[WARNING] GPU {gpu_flag} 超出范围(共有{cnt}块)，使用 0")
                                gpu_flag = "0"
                        except ValueError:
                            print("[WARNING] 非法 GPU 参数，使用 0")
                            gpu_flag = "0"
                
                # 显示配置信息
                print(f"\n[INFO] 训练配置:")
                print(f"  配置文件: {config_path}")
                print(f"  GPU设备: {gpu_flag}")
                print(f"  监控模式: {'启用' if inputs['monitor'] else '禁用'}")
                print(f"  自动备份: {'启用' if inputs['backup'] else '禁用'}")
                
                # 确认开始训练
                try:
                    confirm = input("\n是否开始训练? (y/N): ").strip().lower()
                    if confirm in ['y', 'yes']:
                        success = start_training(config_path, gpu_flag, inputs['monitor'], inputs['backup'])
                        if success:
                            print("\n[SUCCESS] 训练完成！")
                        else:
                            print("\n[ERROR] 训练失败")
                    else:
                        print("[INFO] 训练已取消")
                except KeyboardInterrupt:
                    print("\n[INFO] 训练已取消")
                
            elif choice == 2:  # 继续训练
                print("\n[INFO] 继续训练...")
                inputs = get_user_inputs()
                if inputs is None:
                    continue
                
                # 系统检查
                if not check_conda_env():
                    print(f"[ERROR] 必须使用 {CONDA_ENV_NAME} conda 环境才能运行训练")
                    continue
                
                # 处理GPU设置
                gpu_flag = inputs['gpu']
                if gpu_flag != "-1":
                    gpu_available, cnt = check_pytorch_gpu()
                    if not gpu_available:
                        print("[WARNING] 未检测到可用 GPU，改用 CPU (--gpu -1)")
                        gpu_flag = "-1"
                    else:
                        try:
                            if int(gpu_flag) >= cnt:
                                print(f"[WARNING] GPU {gpu_flag} 超出范围(共有{cnt}块)，使用 0")
                                gpu_flag = "0"
                        except ValueError:
                            print("[WARNING] 非法 GPU 参数，使用 0")
                            gpu_flag = "0"
                
                # 列出可用的运行
                runs = list_available_runs()
                if not runs:
                    print("[ERROR] 没有找到可恢复的训练运行")
                    continue
                
                selected_run = select_run_to_resume(runs)
                if selected_run:
                    success = resume_training(selected_run, gpu_flag, None, inputs['monitor'])
                    if success:
                        print("\n[SUCCESS] 训练恢复完成！")
                    else:
                        print("\n[ERROR] 训练恢复失败")
                
            elif choice == 3:  # 监控训练
                print("\n[INFO] 启动训练监控...")
                try:
                    monitor_script = Path(__file__).with_name("monitor_training.py")
                    subprocess.run([sys.executable, str(monitor_script), "--verbose"], check=True)
                except subprocess.CalledProcessError:
                    print("[ERROR] 监控脚本执行失败")
                except FileNotFoundError:
                    print("[ERROR] 找不到监控脚本")
                
            elif choice == 4:  # 清理运行
                print("\n[INFO] 清理不完整的运行...")
                clean_incomplete_runs()
                
            elif choice == 5:  # 生成报告
                print("\n[INFO] 生成训练报告...")
                try:
                    monitor_script = Path(__file__).with_name("monitor_training.py")
                    subprocess.run([sys.executable, str(monitor_script), "--report"], check=True)
                except subprocess.CalledProcessError:
                    print("[ERROR] 报告生成失败")
                except FileNotFoundError:
                    print("[ERROR] 找不到监控脚本")
                
            elif choice == 6:  # 退出
                print("\n[INFO] 退出程序")
                return True
            
            # 操作完成后暂停
            if choice != 6:
                try:
                    continue_choice = input("\n按Enter键继续，或输入'q'退出程序: ").strip().lower()
                    if continue_choice == 'q':
                        print("\n[INFO] 退出程序")
                        return True
                except KeyboardInterrupt:
                    print("\n[INFO] 退出程序")
                    return True
        
        return True

    print("=" * 60)
    print("NeuralHydrology 完整数据集训练启动器")
    print("=" * 60)

    # 如果指定了清理选项，先清理不完整的运行
    if args.clean:
        clean_incomplete_runs()
        return True

    # 系统检查
    print("\n[INFO] 执行系统检查...")
    
    # 检查 conda 环境
    if not check_conda_env():
        print(f"[ERROR] 必须使用 {CONDA_ENV_NAME} conda 环境才能运行训练")
        return False
    
    # 检查系统资源
    resources = check_system_resources()
    
    # 检查数据可用性
    if not check_data_availability():
        return False
    
    # 如果指定了恢复训练选项
    if args.resume:
        # 处理GPU设置
        gpu_flag = args.gpu
        if gpu_flag != "-1":
            gpu_available, cnt = check_pytorch_gpu()
            if not gpu_available:
                print("[WARNING] 未检测到可用 GPU，改用 CPU (--gpu -1)")
                gpu_flag = "-1"
            else:
                try:
                    if int(gpu_flag) >= cnt:
                        print(f"[WARNING] GPU {gpu_flag} 超出范围(共有{cnt}块)，使用 0")
                        gpu_flag = "0"
                except ValueError:
                    print("[WARNING] 非法 GPU 参数，使用 0")
                    gpu_flag = "0"
        
        # 如果指定了运行目录，直接恢复
        if args.run_dir:
            return resume_training(args.run_dir, gpu_flag, args.epoch, args.monitor)
        
        # 否则列出可用的运行让用户选择
        runs = list_available_runs()
        if not runs:
            print("[ERROR] 没有找到可恢复的训练运行")
            return False
        
        selected_run = select_run_to_resume(runs)
        if selected_run:
            return resume_training(selected_run, gpu_flag, args.epoch, args.monitor)
        else:
            return False

    # 新训练
    config_path = Path(args.config)
    if not config_path.exists():
        print(f"[ERROR] 找不到配置文件: {config_path}")
        return False

    # 处理GPU设置
    gpu_flag = args.gpu
    if gpu_flag != "-1":
        gpu_available, cnt = check_pytorch_gpu()
        if not gpu_available:
            print("[WARNING] 未检测到可用 GPU，改用 CPU (--gpu -1)")
            gpu_flag = "-1"
        else:
            try:
                if int(gpu_flag) >= cnt:
                    print(f"[WARNING] GPU {gpu_flag} 超出范围(共有{cnt}块)，使用 0")
                    gpu_flag = "0"
            except ValueError:
                print("[WARNING] 非法 GPU 参数，使用 0")
                gpu_flag = "0"

    # 显示训练配置信息
    print(f"\n[INFO] 训练配置:")
    print(f"  配置文件: {config_path}")
    print(f"  GPU设备: {gpu_flag}")
    print(f"  监控模式: {'启用' if args.monitor else '禁用'}")
    print(f"  自动备份: {'启用' if args.backup else '禁用'}")
    
    # 确认开始训练
    if not args.monitor:  # 监控模式下自动开始
        try:
            confirm = input("\n是否开始训练? (y/N): ").strip().lower()
            if confirm not in ['y', 'yes']:
                print("[INFO] 训练已取消")
                return False
        except KeyboardInterrupt:
            print("\n[INFO] 训练已取消")
            return False

    return start_training(config_path, gpu_flag, args.monitor, args.backup)

if __name__ == "__main__":
    try:
        success = main()
        if not success:
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n[INFO] 程序被用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] 程序执行出错: {e}")
        sys.exit(1)
