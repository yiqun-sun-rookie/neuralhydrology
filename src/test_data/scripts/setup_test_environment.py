#!/usr/bin/env python3
"""
测试环境设置脚本

此脚本帮助用户快速设置测试环境，包括：
1. 创建测试数据集
2. 验证依赖包安装
3. 运行快速测试

使用方法:
    python src/test_data/scripts/setup_test_environment.py
"""

import os
import sys
import subprocess
from pathlib import Path

def check_dependencies():
    """检查依赖包是否安装"""
    print("检查依赖包安装状态...")
    
    required_packages = [
        'torch', 'numpy', 'pandas', 'matplotlib', 
        'scipy', 'xarray', 'ruamel.yaml', 'tqdm', 'tensorboard'
    ]
    
    missing_packages = []
    
    for package in required_packages:
        try:
            __import__(package)
            print(f"  [OK] {package}")
        except ImportError:
            print(f"  [MISSING] {package} (未安装)")
            missing_packages.append(package)
    
    if missing_packages:
        print(f"\n缺少以下依赖包: {', '.join(missing_packages)}")
        print("请运行以下命令安装:")
        print("pip install -r requirements.txt")
        return False
    else:
        print("\n所有依赖包已安装!")
        return True

def check_pytorch():
    """检查PyTorch和GPU支持"""
    print("\n检查PyTorch安装...")
    
    try:
        import torch
        print(f"  PyTorch版本: {torch.__version__}")
        
        if torch.cuda.is_available():
            gpu_count = torch.cuda.device_count()
            print(f"  CUDA可用: 是 ({gpu_count} 个GPU)")
            print(f"  当前GPU: {torch.cuda.get_device_name(0)}")
            return True, gpu_count
        else:
            print("  CUDA可用: 否 (将使用CPU)")
            return False, 0
    except ImportError:
        print("  PyTorch未安装!")
        return False, 0

def create_test_data():
    """创建测试数据集"""
    print("\n创建测试数据集...")
    
    # 检查是否已存在
    test_data_dir = Path("data/test_data")
    if test_data_dir.exists():
        print("  测试数据集已存在，跳过创建")
        return True
    
    # 运行创建脚本
    try:
        create_script = Path(__file__).with_name("create_test_data.py")
        result = subprocess.run([
            sys.executable, str(create_script)
        ], capture_output=True, text=True, encoding='utf-8')
        
        if result.returncode == 0:
            print("  测试数据集创建成功!")
            return True
        else:
            print(f"  创建失败: {result.stderr}")
            return False
    except Exception as e:
        print(f"  创建失败: {e}")
        return False

def run_quick_test():
    """运行快速测试"""
    print("\n运行快速测试...")
    
    config_file = "src/test_data/configs/quick_test.yml"
    if not Path(config_file).exists():
        print(f"  配置文件不存在: {config_file}")
        return False
    
    print(f"  使用配置文件: {config_file}")
    print("  开始训练（预计2-3分钟）...")
    
    try:
        # 运行训练
        cmd = [
            sys.executable, "-m", "neuralhydrology.nh_run",
            "train",
            "--config-file", config_file,
            "--gpu", "-1"  # 使用CPU，避免GPU问题
        ]
        
        print(f"  执行命令: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
        
        if result.returncode == 0:
            print("  [OK] 快速测试成功!")
            print("  训练日志:")
            print(result.stdout[-500:])  # 显示最后500个字符
            return True
        else:
            print("  [FAILED] 快速测试失败!")
            print("  错误信息:")
            print(result.stderr[-500:])  # 显示最后500个字符
            return False
            
    except Exception as e:
        print(f"  测试失败: {e}")
        return False

def main():
    """主函数"""
    print("NeuralHydrology 测试环境设置")
    print("=" * 50)
    
    # 检查依赖包
    if not check_dependencies():
        print("\n请先安装依赖包，然后重新运行此脚本")
        return False
    
    # 检查PyTorch
    gpu_available, gpu_count = check_pytorch()
    
    # 创建测试数据
    if not create_test_data():
        print("\n无法创建测试数据集，请检查数据源")
        return False
    
    # 运行快速测试
    if not run_quick_test():
        print("\n快速测试失败，请检查配置和依赖")
        return False
    
    print("\n" + "=" * 50)
    print("测试环境设置完成!")
    print("\n下一步:")
    print("1. 查看训练结果: runs/quick_test_*/")
    print("2. 运行完整测试: python -m neuralhydrology.nh_run train --config-file src/test_data/configs/test_config.yml --gpu -1")
    print("3. 使用TensorBoard: tensorboard --logdir runs/")
    
    return True

if __name__ == "__main__":
    success = main()
    if not success:
        sys.exit(1)
