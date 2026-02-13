#!/usr/bin/env python3
"""NeuralHydrology 训练恢复和错误处理脚本

此脚本提供训练过程中的错误检测、恢复和诊断功能：
1. 自动检测训练异常
2. 智能恢复训练
3. 错误诊断和修复建议
4. 训练状态验证
5. 数据完整性检查

使用方式：
    # 检查所有训练运行状态
    python scripts/training_recovery.py --check-all
    
    # 诊断特定训练运行
    python scripts/training_recovery.py --diagnose --run-dir runs/full_training_2025_1024_1631
    
    # 自动恢复失败的训练
    python scripts/training_recovery.py --auto-recover
    
    # 验证数据完整性
    python scripts/training_recovery.py --verify-data

参数：
    --check-all          检查所有训练运行状态
    --diagnose           诊断训练问题
    --run-dir <path>     指定训练运行目录
    --auto-recover       自动恢复失败的训练
    --verify-data        验证数据完整性
    --fix-issues         尝试修复发现的问题
    --verbose            启用详细输出
"""

import sys
import os
import json
import re
import shutil
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict

# 设置控制台编码解决中文乱码问题
if sys.platform.startswith('win'):
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.detach())

class TrainingRecovery:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.runs_dir = Path("runs")
        self.data_dir = Path("data/CAMELS_US")
        
    def log(self, message, level="INFO"):
        """记录日志"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        if level == "ERROR":
            print(f"[{timestamp}] [ERROR] {message}")
        elif level == "WARNING":
            print(f"[{timestamp}] [WARNING] {message}")
        elif level == "SUCCESS":
            print(f"[{timestamp}] [SUCCESS] {message}")
        else:
            print(f"[{timestamp}] [INFO] {message}")
    
    def check_training_run(self, run_dir):
        """检查单个训练运行的状态"""
        run_dir = Path(run_dir)
        if not run_dir.exists():
            return {"status": "not_found", "issues": ["运行目录不存在"]}
        
        issues = []
        status = "unknown"
        
        # 检查必要文件
        required_files = ["config.yml", "output.log"]
        for file_name in required_files:
            file_path = run_dir / file_name
            if not file_path.exists():
                issues.append(f"缺少必要文件: {file_name}")
        
        # 检查日志文件
        log_file = run_dir / "output.log"
        if log_file.exists():
            log_status = self._analyze_log_file(log_file)
            status = log_status["status"]
            issues.extend(log_status["issues"])
        else:
            issues.append("缺少日志文件")
            status = "no_log"
        
        # 检查模型文件
        model_files = list(run_dir.glob("model_epoch*.pt"))
        if not model_files:
            issues.append("没有找到模型文件")
            if status == "unknown":
                status = "no_models"
        else:
            # 检查模型文件完整性
            for model_file in model_files:
                if model_file.stat().st_size == 0:
                    issues.append(f"模型文件为空: {model_file.name}")
        
        # 检查配置文件
        config_file = run_dir / "config.yml"
        if config_file.exists():
            config_issues = self._check_config_file(config_file)
            issues.extend(config_issues)
        
        # 检查磁盘空间
        disk_usage = shutil.disk_usage(run_dir)
        free_gb = disk_usage.free / (1024**3)
        if free_gb < 1.0:
            issues.append(f"磁盘空间不足: {free_gb:.1f} GB")
        
        return {
            "status": status,
            "issues": issues,
            "model_count": len(model_files),
            "disk_free_gb": free_gb
        }
    
    def _analyze_log_file(self, log_file):
        """分析日志文件"""
        issues = []
        status = "running"
        
        try:
            with open(log_file, 'r', encoding='utf-8') as f:
                content = f.read()
                lines = content.split('\n')
                
                # 检查最后几行
                last_lines = lines[-10:] if len(lines) > 10 else lines
                
                # 检查错误信息
                error_patterns = [
                    r"Error:",
                    r"Exception:",
                    r"Traceback",
                    r"CUDA out of memory",
                    r"RuntimeError",
                    r"FileNotFoundError",
                    r"PermissionError"
                ]
                
                for line in last_lines:
                    for pattern in error_patterns:
                        if re.search(pattern, line, re.IGNORECASE):
                            issues.append(f"发现错误: {line.strip()}")
                            status = "error"
                
                # 检查训练完成标志
                if "Training completed" in content or "训练完成" in content:
                    status = "completed"
                elif "Training stopped" in content or "训练停止" in content:
                    status = "stopped"
                
                # 检查最后修改时间
                last_modified = datetime.fromtimestamp(log_file.stat().st_mtime)
                time_since_modified = datetime.now() - last_modified
                
                if time_since_modified > timedelta(minutes=10) and status == "running":
                    status = "stalled"
                    issues.append(f"日志超过10分钟未更新: {time_since_modified}")
                
        except Exception as e:
            issues.append(f"读取日志文件失败: {e}")
            status = "log_error"
        
        return {"status": status, "issues": issues}
    
    def _check_config_file(self, config_file):
        """检查配置文件"""
        issues = []
        
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                content = f.read()
                
                # 检查关键配置项
                required_configs = [
                    "experiment_name",
                    "dataset",
                    "model",
                    "epochs",
                    "batch_size"
                ]
                
                for config in required_configs:
                    if config not in content:
                        issues.append(f"配置文件缺少: {config}")
                
                # 检查数据路径
                if "data_dir:" in content:
                    data_dir_match = re.search(r"data_dir:\s*(.+)", content)
                    if data_dir_match:
                        data_dir = data_dir_match.group(1).strip()
                        if not Path(data_dir).exists():
                            issues.append(f"数据目录不存在: {data_dir}")
                
        except Exception as e:
            issues.append(f"读取配置文件失败: {e}")
        
        return issues
    
    def check_all_runs(self):
        """检查所有训练运行"""
        if not self.runs_dir.exists():
            self.log("runs目录不存在", "WARNING")
            return {}
        
        runs_status = {}
        
        for run_dir in self.runs_dir.iterdir():
            if run_dir.is_dir():
                self.log(f"检查运行: {run_dir.name}")
                status = self.check_training_run(run_dir)
                runs_status[run_dir.name] = status
                
                if self.verbose:
                    self.log(f"  状态: {status['status']}")
                    self.log(f"  模型文件数: {status['model_count']}")
                    if status['issues']:
                        for issue in status['issues']:
                            self.log(f"  问题: {issue}", "WARNING")
        
        return runs_status
    
    def diagnose_run(self, run_dir):
        """诊断特定训练运行"""
        self.log(f"诊断训练运行: {run_dir}")
        
        status = self.check_training_run(run_dir)
        
        print("\n" + "="*60)
        print(f"训练运行诊断报告: {Path(run_dir).name}")
        print("="*60)
        
        print(f"状态: {status['status']}")
        print(f"模型文件数: {status['model_count']}")
        print(f"可用磁盘空间: {status['disk_free_gb']:.1f} GB")
        
        if status['issues']:
            print("\n发现的问题:")
            for i, issue in enumerate(status['issues'], 1):
                print(f"  {i}. {issue}")
        else:
            print("\n未发现明显问题")
        
        # 提供修复建议
        suggestions = self._get_fix_suggestions(status)
        if suggestions:
            print("\n修复建议:")
            for i, suggestion in enumerate(suggestions, 1):
                print(f"  {i}. {suggestion}")
        
        return status
    
    def _get_fix_suggestions(self, status):
        """获取修复建议"""
        suggestions = []
        
        if status['status'] == 'error':
            suggestions.append("检查日志文件中的具体错误信息")
            suggestions.append("尝试从最新检查点恢复训练")
        
        if status['status'] == 'stalled':
            suggestions.append("检查系统资源使用情况")
            suggestions.append("尝试重启训练")
        
        if status['status'] == 'no_models':
            suggestions.append("重新开始训练")
        
        if status['disk_free_gb'] < 1.0:
            suggestions.append("清理磁盘空间或移动训练到其他位置")
        
        if any("CUDA out of memory" in issue for issue in status['issues']):
            suggestions.append("减小batch_size或使用CPU训练")
        
        if any("数据目录不存在" in issue for issue in status['issues']):
            suggestions.append("检查数据路径配置")
        
        return suggestions
    
    def auto_recover(self):
        """自动恢复失败的训练"""
        self.log("开始自动恢复检查...")
        
        runs_status = self.check_all_runs()
        recovered_count = 0
        
        for run_name, status in runs_status.items():
            if status['status'] in ['error', 'stalled'] and status['model_count'] > 0:
                self.log(f"尝试恢复: {run_name}")
                
                run_dir = self.runs_dir / run_name
                if self._attempt_recovery(run_dir):
                    recovered_count += 1
                    self.log(f"成功恢复: {run_name}", "SUCCESS")
                else:
                    self.log(f"恢复失败: {run_name}", "ERROR")
        
        self.log(f"自动恢复完成，成功恢复 {recovered_count} 个训练")
        return recovered_count
    
    def _attempt_recovery(self, run_dir):
        """尝试恢复单个训练"""
        try:
            # 检查最新模型文件
            model_files = list(run_dir.glob("model_epoch*.pt"))
            if not model_files:
                return False
            
            # 找到最新的epoch
            latest_epoch = 0
            for model_file in model_files:
                epoch_match = re.search(r'model_epoch(\d+)\.pt', model_file.name)
                if epoch_match:
                    epoch = int(epoch_match.group(1))
                    latest_epoch = max(latest_epoch, epoch)
            
            if latest_epoch == 0:
                return False
            
            # 尝试恢复训练
            cmd = [
                "python", "scripts/full_train.py",
                "--resume",
                "--run-dir", str(run_dir),
                "--gpu", "0"
            ]
            
            self.log(f"执行恢复命令: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                return True
            else:
                self.log(f"恢复命令失败: {result.stderr}", "ERROR")
                return False
                
        except Exception as e:
            self.log(f"恢复过程中出错: {e}", "ERROR")
            return False
    
    def verify_data_integrity(self):
        """验证数据完整性"""
        self.log("验证数据完整性...")
        
        if not self.data_dir.exists():
            self.log("数据目录不存在", "ERROR")
            return False
        
        issues = []
        
        # 检查必要的数据目录
        required_dirs = [
            "basin_mean_forcing",
            "usgs_streamflow",
            "camels_attributes_v2.0"
        ]
        
        for dir_name in required_dirs:
            dir_path = self.data_dir / dir_name
            if not dir_path.exists():
                issues.append(f"缺少数据目录: {dir_name}")
        
        # 检查forcing数据
        forcing_dir = self.data_dir / "basin_mean_forcing"
        daymet_dir = forcing_dir / "daymet"
        if daymet_dir.exists():
            daymet_files = list(daymet_dir.glob("**/*.txt"))
            if len(daymet_files) == 0:
                issues.append("daymet forcing数据目录为空")
        else:
            issues.append("缺少daymet forcing数据目录")
        
        # 检查streamflow数据
        streamflow_dir = self.data_dir / "usgs_streamflow"
        if streamflow_dir.exists():
            streamflow_files = list(streamflow_dir.glob("**/*.txt"))
            if len(streamflow_files) == 0:
                issues.append("streamflow数据目录为空")
        else:
            issues.append("缺少streamflow数据目录")
        
        # 检查流域数据目录
        basin_dirs = [d for d in self.data_dir.iterdir() if d.is_dir() and d.name.isdigit()]
        if len(basin_dirs) == 0:
            issues.append("没有找到流域数据目录")
        else:
            self.log(f"找到 {len(basin_dirs)} 个流域数据目录")
            
            # 检查前几个流域的数据完整性
            sample_basins = basin_dirs[:5]
            for basin_dir in sample_basins:
                basin_issues = self._check_basin_data(basin_dir)
                issues.extend(basin_issues)
        
        if issues:
            self.log("数据完整性检查发现问题:", "WARNING")
            for issue in issues:
                self.log(f"  - {issue}", "WARNING")
            return False
        else:
            self.log("数据完整性检查通过", "SUCCESS")
            return True
    
    def _check_basin_data(self, basin_dir):
        """检查单个流域的数据"""
        issues = []
        
        # 检查必要文件
        required_files = ["forcing_daymet.txt", "streamflow_qc.txt"]
        for file_name in required_files:
            file_path = basin_dir / file_name
            if not file_path.exists():
                issues.append(f"流域 {basin_dir.name} 缺少文件: {file_name}")
            elif file_path.stat().st_size == 0:
                issues.append(f"流域 {basin_dir.name} 文件为空: {file_name}")
        
        return issues
    
    def fix_issues(self, run_dir=None):
        """尝试修复发现的问题"""
        if run_dir:
            # 修复特定运行
            status = self.check_training_run(run_dir)
            return self._fix_run_issues(run_dir, status)
        else:
            # 修复所有运行
            runs_status = self.check_all_runs()
            fixed_count = 0
            
            for run_name, status in runs_status.items():
                run_dir = self.runs_dir / run_name
                if self._fix_run_issues(run_dir, status):
                    fixed_count += 1
            
            self.log(f"修复完成，成功修复 {fixed_count} 个问题")
            return fixed_count
    
    def _fix_run_issues(self, run_dir, status):
        """修复单个运行的问题"""
        fixed = False
        
        for issue in status['issues']:
            if "磁盘空间不足" in issue:
                # 清理临时文件
                self._clean_temp_files(run_dir)
                fixed = True
            
            elif "模型文件为空" in issue:
                # 删除空的模型文件
                self._remove_empty_model_files(run_dir)
                fixed = True
            
            elif "日志文件" in issue and "失败" in issue:
                # 重新创建日志文件
                self._recreate_log_file(run_dir)
                fixed = True
        
        return fixed
    
    def _clean_temp_files(self, run_dir):
        """清理临时文件"""
        temp_patterns = ["*.tmp", "*.temp", "*.log.tmp"]
        for pattern in temp_patterns:
            for temp_file in run_dir.glob(pattern):
                try:
                    temp_file.unlink()
                    self.log(f"删除临时文件: {temp_file.name}")
                except:
                    pass
    
    def _remove_empty_model_files(self, run_dir):
        """删除空的模型文件"""
        for model_file in run_dir.glob("model_epoch*.pt"):
            if model_file.stat().st_size == 0:
                try:
                    model_file.unlink()
                    self.log(f"删除空模型文件: {model_file.name}")
                except:
                    pass
    
    def _recreate_log_file(self, run_dir):
        """重新创建日志文件"""
        log_file = run_dir / "output.log"
        try:
            if log_file.exists():
                log_file.unlink()
            log_file.touch()
            self.log(f"重新创建日志文件: {log_file.name}")
        except:
            pass

def main():
    import argparse
    parser = argparse.ArgumentParser(description="NeuralHydrology 训练恢复和错误处理脚本")
    parser.add_argument("--check-all", action="store_true", help="检查所有训练运行状态")
    parser.add_argument("--diagnose", action="store_true", help="诊断训练问题")
    parser.add_argument("--run-dir", help="指定训练运行目录")
    parser.add_argument("--auto-recover", action="store_true", help="自动恢复失败的训练")
    parser.add_argument("--verify-data", action="store_true", help="验证数据完整性")
    parser.add_argument("--fix-issues", action="store_true", help="尝试修复发现的问题")
    parser.add_argument("--verbose", action="store_true", help="启用详细输出")
    args = parser.parse_args()
    
    recovery = TrainingRecovery(verbose=args.verbose)
    
    if args.check_all:
        runs_status = recovery.check_all_runs()
        print(f"\n检查完成，共检查 {len(runs_status)} 个训练运行")
        
        # 统计状态
        status_counts = defaultdict(int)
        for status in runs_status.values():
            status_counts[status['status']] += 1
        
        print("\n状态统计:")
        for status, count in status_counts.items():
            print(f"  {status}: {count}")
    
    elif args.diagnose:
        if not args.run_dir:
            print("[ERROR] 诊断模式需要指定 --run-dir")
            return
        recovery.diagnose_run(args.run_dir)
    
    elif args.auto_recover:
        recovered_count = recovery.auto_recover()
        print(f"\n自动恢复完成，成功恢复 {recovered_count} 个训练")
    
    elif args.verify_data:
        success = recovery.verify_data_integrity()
        if success:
            print("\n数据完整性验证通过")
        else:
            print("\n数据完整性验证失败")
    
    elif args.fix_issues:
        if args.run_dir:
            fixed = recovery.fix_issues(args.run_dir)
            print(f"\n修复完成: {fixed}")
        else:
            fixed_count = recovery.fix_issues()
            print(f"\n修复完成，成功修复 {fixed_count} 个问题")
    
    else:
        # 默认执行全面检查
        print("执行全面检查...")
        runs_status = recovery.check_all_runs()
        recovery.verify_data_integrity()
        
        # 显示问题汇总
        total_issues = 0
        for status in runs_status.values():
            total_issues += len(status['issues'])
        
        print(f"\n检查完成:")
        print(f"  训练运行数: {len(runs_status)}")
        print(f"  发现问题数: {total_issues}")

if __name__ == "__main__":
    main()
