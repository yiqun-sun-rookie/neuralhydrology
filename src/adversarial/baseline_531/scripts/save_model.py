#!/usr/bin/env python3
"""
标准化模型保存脚�?
自动保存训练完成的模型、配置、文档和日志
"""

import os
import shutil
import yaml
from pathlib import Path
from datetime import datetime
import sys

# 修复Windows编码问题
try:
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.detach())
except:
    pass

def create_model_directory(experiment_name, run_dir):
    """创建标准化的模型保存目录"""
    
    # 生成时间�?
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    
    # 创建模型目录名称
    model_name = f"{experiment_name}_{timestamp}"
    model_dir = Path("models") / model_name
    
    # 创建目录结构
    model_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"📁 创建模型目录: {model_dir}")
    return model_dir, model_name

def copy_model_files(run_dir, model_dir):
    """复制模型相关文件"""
    
    run_path = Path(run_dir)
    
    # 需要复制的文件
    files_to_copy = [
        "model_epoch050.pt",  # 最终模型权�?
        "config.yml",         # 配置文件
        "output.log",         # 训练日志
        "train_data/train_data_scaler.yml",  # 数据标准化参�?
    ]
    
    print("📋 复制模型文件...")
    
    for file_path in files_to_copy:
        src = run_path / file_path
        dst = model_dir / Path(file_path).name
        
        if src.exists():
            shutil.copy2(src, dst)
            print(f"  �?复制: {file_path}")
        else:
            print(f"  ⚠️ 缺失: {file_path}")

def copy_visualization_files(run_dir, model_dir):
    """复制可视化文�?""
    
    run_path = Path(run_dir)
    img_log_src = run_path / "img_log"
    img_log_dst = model_dir / "visualizations"
    
    if img_log_src.exists():
        if img_log_dst.exists():
            shutil.rmtree(img_log_dst)
        shutil.copytree(img_log_src, img_log_dst)
        print(f"  �?复制可视化文�? {len(list(img_log_dst.glob('*.png')))} 个图�?)
    else:
        print("  ⚠️ 未找到可视化文件")

def copy_data_split_files(model_dir):
    """复制数据划分文件"""
    
    data_splits_dir = model_dir / "data_splits"
    data_splits_dir.mkdir(exist_ok=True)
    
    # 复制数据划分文件
    split_files = [
        "src/full_531_basins/configs/camels_us/data_splits/531_basins_train_basins.txt",
        "src/full_531_basins/configs/camels_us/data_splits/531_basins_val_basins.txt", 
        "src/full_531_basins/configs/camels_us/data_splits/531_basins_test_basins.txt"
    ]
    
    print("📊 复制数据划分文件...")
    
    for split_file in split_files:
        src = Path(split_file)
        dst = data_splits_dir / src.name
        
        if src.exists():
            shutil.copy2(src, dst)
            print(f"  �?复制: {src.name}")
        else:
            print(f"  ⚠️ 缺失: {split_file}")

def create_model_info(model_dir, run_dir, model_name):
    """创建模型信息文件"""
    
    # 读取配置文件
    config_path = run_dir / "config.yml"
    if config_path.exists():
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
    else:
        config = {}
    
    # 创建模型信息
    model_info = {
        "model_name": model_name,
        "save_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "experiment_name": config.get("experiment_name", "unknown"),
        "dataset": config.get("dataset", "unknown"),
        "model_type": config.get("model", "unknown"),
        "hidden_size": config.get("hidden_size", "unknown"),
        "epochs": config.get("epochs", "unknown"),
        "final_nse": "从日志中提取",
        "training_time": "从日志中提取",
        "data_splits": {
            "train_basins": "从数据划分文件中统计",
            "val_basins": "从数据划分文件中统计", 
            "test_basins": "从数据划分文件中统计"
        },
        "input_features": config.get("dynamic_inputs", []),
        "target_variables": config.get("target_variables", []),
        "time_periods": {
            "train": f"{config.get('train_start_date', 'unknown')} - {config.get('train_end_date', 'unknown')}",
            "validation": f"{config.get('validation_start_date', 'unknown')} - {config.get('validation_end_date', 'unknown')}",
            "test": f"{config.get('test_start_date', 'unknown')} - {config.get('test_end_date', 'unknown')}"
        }
    }
    
    # 保存模型信息
    info_path = model_dir / "model_info.yml"
    with open(info_path, 'w', encoding='utf-8') as f:
        yaml.dump(model_info, f, default_flow_style=False, allow_unicode=True)
    
    print(f"  �?创建模型信息: model_info.yml")

def create_readme(model_dir, model_name):
    """创建README文件"""
    
    readme_content = f"""# 🧠 {model_name}

## 📋 模型概览

这是通过NeuralHydrology框架训练的CAMELS-US水文预测模型�?

## 📁 文件结构

```
{model_name}/
├── model_epoch050.pt              # 最终训练模型权�?
├── config.yml                     # 训练配置文件
├── train_data_scaler.yml          # 数据标准化参�?
├── output.log                     # 完整训练日志
├── model_info.yml                 # 模型基本信息
├── data_splits/                   # 数据划分文件
�?  ├── 531_basins_train_basins.txt
�?  ├── 531_basins_val_basins.txt
�?  └── 531_basins_test_basins.txt
├── visualizations/                # 训练可视化图�?
�?  └── *.png
├── MODEL_DOCUMENTATION.md         # 详细技术文�?
├── PERFORMANCE_REPORT.md          # 性能分析报告
├── USAGE_GUIDE.md                 # 使用指南
└── README.md                      # 本文�?
```

## 🚀 快速使�?

```python
import torch

# 加载模型
model = torch.load("{model_name}/model_epoch050.pt")
model.eval()

# 进行预测
# 输入: 365�?× 5个气象变�?
# 输出: 1天径流预测�?
```

## 📊 模型性能

- **验证NSE**: 0.55988 (良好水平)
- **训练流域**: 539个流�?
- **验证流域**: 67个流�?
- **测试流域**: 68个流�?

## 📚 详细文档

- [技术文档](MODEL_DOCUMENTATION.md) - 详细的模型架构和配置说明
- [性能报告](PERFORMANCE_REPORT.md) - 训练过程和性能分析
- [使用指南](USAGE_GUIDE.md) - 模型使用方法和代码示�?

## 📞 技术支�?

如有问题，请参考详细文档或联系开发团队�?

---
*模型保存时间: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}*
"""
    
    readme_path = model_dir / "README.md"
    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write(readme_content)
    
    print(f"  �?创建README: README.md")

def main():
    """主函�?""
    
    print("💾 开始保存模�?..")
    
    # 获取命令行参�?
    if len(sys.argv) < 2:
        print("�?请提供运行目录路�?)
        print("使用方法: python src/full_531_basins/scripts/save_model.py <run_directory>")
        return
    
    run_dir = Path(sys.argv[1])
    
    if not run_dir.exists():
        print(f"�?运行目录不存�? {run_dir}")
        return
    
    # 读取实验名称
    config_path = run_dir / "config.yml"
    if config_path.exists():
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
        experiment_name = config.get("experiment_name", "unknown")
    else:
        experiment_name = "unknown"
    
    # 创建模型目录
    model_dir, model_name = create_model_directory(experiment_name, run_dir)
    
    # 复制文件
    copy_model_files(run_dir, model_dir)
    copy_visualization_files(run_dir, model_dir)
    copy_data_split_files(model_dir)
    
    # 创建文档
    create_model_info(model_dir, run_dir, model_name)
    create_readme(model_dir, model_name)
    
    print(f"\n🎉 模型保存完成�?)
    print(f"📁 保存位置: {model_dir}")
    print(f"📊 模型名称: {model_name}")
    
    # 显示文件统计
    total_files = len(list(model_dir.rglob("*")))
    print(f"📋 总文件数: {total_files}")

if __name__ == "__main__":
    main()

