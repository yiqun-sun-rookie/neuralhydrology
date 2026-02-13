#!/usr/bin/env python3
"""NeuralHydrology 训练监控脚本

此脚本用于实时监控NeuralHydrology训练进度，包括：
1. 训练日志解析和显示
2. 系统资源监控
3. GPU使用情况监控
4. 训练进度可视化
5. 自动检测训练完成或异常

使用方式：
    # 监控最新训练
    python scripts/monitor_training.py
    
    # 监控指定训练运行
    python scripts/monitor_training.py --run-dir runs/full_training_2025_1024_1631
    
    # 启用详细监控
    python scripts/monitor_training.py --verbose
    
    # 生成训练报告
    python scripts/monitor_training.py --report

参数：
    --run-dir <path>      指定要监控的训练运行目录
    --verbose             启用详细输出
    --report              生成训练报告
    --interval <seconds>  监控间隔（默认30秒）
    --log-file <path>     指定日志文件路径
"""

import sys
import os
import time
import re
import json
import psutil
import threading
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict, deque

# 设置控制台编码解决中文乱码问题
if sys.platform.startswith('win'):
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.detach())

class TrainingMonitor:
    def __init__(self, run_dir=None, verbose=False, interval=30):
        self.run_dir = Path(run_dir) if run_dir else self._find_latest_run()
        self.verbose = verbose
        self.interval = interval
        self.monitoring = False
        
        # 训练状态
        self.current_epoch = 0
        self.total_epochs = 0
        self.best_validation_nse = -999
        self.training_losses = deque(maxlen=100)
        self.validation_losses = deque(maxlen=100)
        
        # 系统资源历史
        self.cpu_history = deque(maxlen=100)
        self.memory_history = deque(maxlen=100)
        self.gpu_history = deque(maxlen=100)
        
        # 日志文件
        self.log_file = self.run_dir / "output.log" if self.run_dir else None
        
    def _find_latest_run(self):
        """查找最新的训练运行目录"""
        runs_dir = Path("runs")
        if not runs_dir.exists():
            return None
        
        latest_run = None
        latest_time = 0
        
        for run_dir in runs_dir.iterdir():
            if run_dir.is_dir():
                # 检查是否有日志文件
                log_file = run_dir / "output.log"
                if log_file.exists():
                    mtime = log_file.stat().st_mtime
                    if mtime > latest_time:
                        latest_time = mtime
                        latest_run = run_dir
        
        return latest_run
    
    def get_system_resources(self):
        """获取系统资源使用情况"""
        # CPU使用率
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # 内存使用情况
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        memory_used_gb = memory.used / 1024**3
        memory_total_gb = memory.total / 1024**3
        
        # GPU使用情况
        gpu_info = {}
        try:
            import torch
            if torch.cuda.is_available():
                for i in range(torch.cuda.device_count()):
                    gpu_memory = torch.cuda.memory_allocated(i) / 1024**3
                    gpu_memory_max = torch.cuda.max_memory_allocated(i) / 1024**3
                    gpu_memory_total = torch.cuda.get_device_properties(i).total_memory / 1024**3
                    gpu_info[f'gpu_{i}'] = {
                        'memory_used': gpu_memory,
                        'memory_max': gpu_memory_max,
                        'memory_total': gpu_memory_total,
                        'utilization': (gpu_memory / gpu_memory_total) * 100
                    }
        except ImportError:
            pass
        
        return {
            'cpu_percent': cpu_percent,
            'memory_percent': memory_percent,
            'memory_used_gb': memory_used_gb,
            'memory_total_gb': memory_total_gb,
            'gpu_info': gpu_info
        }
    
    def parse_log_line(self, line):
        """解析日志行，提取训练信息"""
        # 解析epoch信息
        epoch_match = re.search(r'Epoch (\d+)/(\d+)', line)
        if epoch_match:
            self.current_epoch = int(epoch_match.group(1))
            self.total_epochs = int(epoch_match.group(2))
        
        # 解析训练损失
        train_loss_match = re.search(r'Train Loss: ([\d.]+)', line)
        if train_loss_match:
            loss = float(train_loss_match.group(1))
            self.training_losses.append(loss)
        
        # 解析验证损失
        val_loss_match = re.search(r'Val Loss: ([\d.]+)', line)
        if val_loss_match:
            loss = float(val_loss_match.group(1))
            self.validation_losses.append(loss)
        
        # 解析验证NSE
        nse_match = re.search(r'Validation NSE: ([\d.]+)', line)
        if nse_match:
            nse = float(nse_match.group(1))
            if nse > self.best_validation_nse:
                self.best_validation_nse = nse
        
        # 解析其他指标
        metrics = {}
        metric_patterns = {
            'KGE': r'KGE: ([\d.]+)',
            'Alpha-NSE': r'Alpha-NSE: ([\d.]+)',
            'Beta-NSE': r'Beta-NSE: ([\d.]+)'
        }
        
        for metric, pattern in metric_patterns.items():
            match = re.search(pattern, line)
            if match:
                metrics[metric] = float(match.group(1))
        
        return {
            'epoch': self.current_epoch,
            'total_epochs': self.total_epochs,
            'train_loss': self.training_losses[-1] if self.training_losses else None,
            'val_loss': self.validation_losses[-1] if self.validation_losses else None,
            'best_nse': self.best_validation_nse,
            'metrics': metrics
        }
    
    def read_log_tail(self, lines=50):
        """读取日志文件的最后几行"""
        if not self.log_file or not self.log_file.exists():
            return []
        
        try:
            with open(self.log_file, 'r', encoding='utf-8') as f:
                all_lines = f.readlines()
                return all_lines[-lines:] if len(all_lines) > lines else all_lines
        except Exception as e:
            if self.verbose:
                print(f"[WARNING] 读取日志文件失败: {e}")
            return []
    
    def display_status(self, resources, training_info):
        """显示当前状态"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        # 清屏（可选）
        if self.verbose:
            os.system('cls' if os.name == 'nt' else 'clear')
        
        print("=" * 80)
        print(f"NeuralHydrology 训练监控 - {timestamp}")
        print("=" * 80)
        
        # 训练信息
        if self.run_dir:
            print(f"运行目录: {self.run_dir.name}")
        
        if training_info['epoch'] > 0:
            progress = (training_info['epoch'] / training_info['total_epochs']) * 100
            print(f"训练进度: Epoch {training_info['epoch']}/{training_info['total_epochs']} ({progress:.1f}%)")
            
            if training_info['train_loss']:
                print(f"训练损失: {training_info['train_loss']:.6f}")
            if training_info['val_loss']:
                print(f"验证损失: {training_info['val_loss']:.6f}")
            if training_info['best_nse'] > -999:
                print(f"最佳NSE: {training_info['best_nse']:.6f}")
            
            # 显示其他指标
            for metric, value in training_info['metrics'].items():
                print(f"{metric}: {value:.6f}")
        
        print("-" * 80)
        
        # 系统资源
        print(f"CPU使用率: {resources['cpu_percent']:.1f}%")
        print(f"内存使用: {resources['memory_used_gb']:.1f}/{resources['memory_total_gb']:.1f} GB ({resources['memory_percent']:.1f}%)")
        
        # GPU信息
        if resources['gpu_info']:
            for gpu_id, gpu_data in resources['gpu_info'].items():
                print(f"{gpu_id.upper()}: {gpu_data['memory_used']:.1f}/{gpu_data['memory_total']:.1f} GB ({gpu_data['utilization']:.1f}%)")
        
        print("-" * 80)
        
        # 训练历史
        if self.training_losses:
            recent_losses = list(self.training_losses)[-5:]
            print(f"最近训练损失: {[f'{loss:.6f}' for loss in recent_losses]}")
        
        if self.validation_losses:
            recent_val_losses = list(self.validation_losses)[-5:]
            print(f"最近验证损失: {[f'{loss:.6f}' for loss in recent_val_losses]}")
        
        print("=" * 80)
    
    def check_training_status(self):
        """检查训练状态"""
        if not self.log_file or not self.log_file.exists():
            return "no_log"
        
        # 检查日志文件最后修改时间
        last_modified = datetime.fromtimestamp(self.log_file.stat().st_mtime)
        time_since_modified = datetime.now() - last_modified
        
        # 如果超过5分钟没有更新，可能训练已停止
        if time_since_modified > timedelta(minutes=5):
            return "stopped"
        
        # 检查是否有训练完成的标志
        try:
            with open(self.log_file, 'r', encoding='utf-8') as f:
                content = f.read()
                if "Training completed" in content or "训练完成" in content:
                    return "completed"
                elif "Error" in content or "Exception" in content:
                    return "error"
        except:
            pass
        
        return "running"
    
    def generate_report(self):
        """生成训练报告"""
        if not self.run_dir:
            print("[ERROR] 没有找到训练运行目录")
            return
        
        report_file = self.run_dir / "training_report.txt"
        
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write("NeuralHydrology 训练报告\n")
            f.write("=" * 50 + "\n")
            f.write(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"运行目录: {self.run_dir.name}\n\n")
            
            # 训练统计
            f.write("训练统计:\n")
            f.write(f"  当前Epoch: {self.current_epoch}\n")
            f.write(f"  总Epoch数: {self.total_epochs}\n")
            f.write(f"  最佳验证NSE: {self.best_validation_nse:.6f}\n")
            
            if self.training_losses:
                f.write(f"  最终训练损失: {self.training_losses[-1]:.6f}\n")
            if self.validation_losses:
                f.write(f"  最终验证损失: {self.validation_losses[-1]:.6f}\n")
            
            # 系统资源统计
            if self.cpu_history:
                avg_cpu = sum(self.cpu_history) / len(self.cpu_history)
                max_cpu = max(self.cpu_history)
                f.write(f"\n系统资源统计:\n")
                f.write(f"  平均CPU使用率: {avg_cpu:.1f}%\n")
                f.write(f"  最大CPU使用率: {max_cpu:.1f}%\n")
            
            if self.memory_history:
                avg_memory = sum(self.memory_history) / len(self.memory_history)
                max_memory = max(self.memory_history)
                f.write(f"  平均内存使用率: {avg_memory:.1f}%\n")
                f.write(f"  最大内存使用率: {max_memory:.1f}%\n")
        
        print(f"[INFO] 训练报告已生成: {report_file}")
    
    def monitor(self):
        """开始监控"""
        if not self.run_dir:
            print("[ERROR] 没有找到训练运行目录")
            return
        
        print(f"[INFO] 开始监控训练: {self.run_dir.name}")
        print(f"[INFO] 监控间隔: {self.interval}秒")
        print("[INFO] 按 Ctrl+C 停止监控")
        
        self.monitoring = True
        
        try:
            while self.monitoring:
                # 获取系统资源
                resources = self.get_system_resources()
                
                # 记录资源历史
                self.cpu_history.append(resources['cpu_percent'])
                self.memory_history.append(resources['memory_percent'])
                
                # 读取最新日志
                log_lines = self.read_log_tail(20)
                training_info = {'epoch': 0, 'total_epochs': 0, 'train_loss': None, 'val_loss': None, 'best_nse': -999, 'metrics': {}}
                
                # 解析最新日志行
                for line in log_lines:
                    info = self.parse_log_line(line)
                    if info['epoch'] > 0:
                        training_info.update(info)
                
                # 显示状态
                self.display_status(resources, training_info)
                
                # 检查训练状态
                status = self.check_training_status()
                if status == "completed":
                    print("\n[INFO] 训练已完成！")
                    break
                elif status == "stopped":
                    print("\n[WARNING] 训练可能已停止（超过5分钟无日志更新）")
                elif status == "error":
                    print("\n[ERROR] 训练过程中出现错误")
                
                # 等待下次监控
                time.sleep(self.interval)
                
        except KeyboardInterrupt:
            print("\n[INFO] 监控已停止")
        finally:
            self.monitoring = False

def main():
    import argparse
    parser = argparse.ArgumentParser(description="NeuralHydrology 训练监控脚本")
    parser.add_argument("--run-dir", help="指定要监控的训练运行目录")
    parser.add_argument("--verbose", action="store_true", help="启用详细输出")
    parser.add_argument("--report", action="store_true", help="生成训练报告")
    parser.add_argument("--interval", type=int, default=30, help="监控间隔（秒）")
    parser.add_argument("--log-file", help="指定日志文件路径")
    args = parser.parse_args()
    
    monitor = TrainingMonitor(
        run_dir=args.run_dir,
        verbose=args.verbose,
        interval=args.interval
    )
    
    if args.report:
        monitor.generate_report()
    else:
        monitor.monitor()

if __name__ == "__main__":
    main()