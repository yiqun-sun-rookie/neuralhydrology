#!/usr/bin/env python3
"""
创建轻量级测试数据集脚本

此脚本从完整的CAMELS_US数据集中选择少量流域，创建一个小规模的测试数据集，
用于快速验证neuralhydrology库的安装和运行。

使用方法:
    python scripts/create_test_data.py

输出:
    - data/test_data/ 目录，包含3个流域的完整数据
    - configs/test_data/ 目录，包含测试配置文件
"""

import os
import shutil
import pandas as pd
from pathlib import Path
import random

def create_test_data():
    """创建测试数据集"""
    
    # 设置随机种子确保可重现性
    random.seed(42)
    
    # 定义路径
    source_data_dir = Path("data/CAMELS_US")
    test_data_dir = Path("data/test_data")
    config_dir = Path("configs/test_data")
    
    # 选择3个代表性流域（不同地区，不同特征）
    # 注意：需要确保这些流域在数据集中存在
    test_basins = [
        "01022500",  # 东北部流域
        "01030500",  # 东北部流域（备选）
        "01031500"   # 东北部流域（备选）
    ]
    
    print(f"创建测试数据集，包含流域: {', '.join(test_basins)}")
    
    # 创建目录结构
    test_data_dir.mkdir(exist_ok=True)
    config_dir.mkdir(exist_ok=True)
    
    # 复制流域属性文件
    print("复制流域属性文件...")
    attr_files = [
        "camels_clim.txt",
        "camels_geol.txt", 
        "camels_hydro.txt",
        "camels_name.txt",
        "camels_soil.txt",
        "camels_topo.txt",
        "camels_vege.txt"
    ]
    
    for attr_file in attr_files:
        src = source_data_dir / attr_file
        dst = test_data_dir / attr_file
        if src.exists():
            shutil.copy2(src, dst)
            print(f"  复制: {attr_file}")
    
    # 复制camels_attributes_v2.0目录
    src_attr_dir = source_data_dir / "camels_attributes_v2.0"
    dst_attr_dir = test_data_dir / "camels_attributes_v2.0"
    if src_attr_dir.exists():
        if dst_attr_dir.exists():
            shutil.rmtree(dst_attr_dir)
        shutil.copytree(src_attr_dir, dst_attr_dir)
        print("  复制: camels_attributes_v2.0/")
    
    # 创建usgs_streamflow目录并复制选定的流域数据
    print("复制径流数据...")
    streamflow_dir = test_data_dir / "usgs_streamflow"
    streamflow_dir.mkdir(exist_ok=True)
    
    for basin in test_basins:
        # 确定流域所在的子目录（前两位数字）
        subdir = basin[:2]
        src_file = source_data_dir / "usgs_streamflow" / subdir / f"{basin}_streamflow_qc.txt"
        dst_file = streamflow_dir / f"{basin}_streamflow_qc.txt"
        
        if src_file.exists():
            shutil.copy2(src_file, dst_file)
            print(f"  复制径流数据: {basin}")
        else:
            print(f"  警告: 未找到径流数据 {basin}")
    
    # 创建basin_mean_forcing目录并复制气象数据
    print("复制气象数据...")
    forcing_dir = test_data_dir / "basin_mean_forcing"
    forcing_dir.mkdir(exist_ok=True)
    
    # 只复制daymet数据（最常用的）
    daymet_dir = forcing_dir / "daymet"
    daymet_dir.mkdir(exist_ok=True)
    
    for basin in test_basins:
        # 确定流域所在的子目录
        subdir = basin[:2]
        src_file = source_data_dir / "basin_mean_forcing" / "daymet" / subdir / f"{basin}_lump_cida_forcing_leap.txt"
        dst_file = daymet_dir / f"{basin}_lump_cida_forcing_leap.txt"
        
        if src_file.exists():
            shutil.copy2(src_file, dst_file)
            print(f"  复制气象数据: {basin}")
        else:
            print(f"  警告: 未找到气象数据 {basin}")
    
    # 创建流域列表文件
    print("创建流域列表文件...")
    
    # 训练集（2个流域）
    train_basins = test_basins[:2]
    with open(config_dir / "test_train_basins.txt", "w") as f:
        for basin in train_basins:
            f.write(f"{basin}\n")
    
    # 验证集（1个流域）
    val_basins = test_basins[2:3]
    with open(config_dir / "test_val_basins.txt", "w") as f:
        for basin in val_basins:
            f.write(f"{basin}\n")
    
    # 测试集（所有3个流域）
    with open(config_dir / "test_test_basins.txt", "w") as f:
        for basin in test_basins:
            f.write(f"{basin}\n")
    
    print(f"  创建: test_train_basins.txt ({len(train_basins)} 个流域)")
    print(f"  创建: test_val_basins.txt ({len(val_basins)} 个流域)")
    print(f"  创建: test_test_basins.txt ({len(test_basins)} 个流域)")
    
    # 创建测试配置文件
    print("创建测试配置文件...")
    create_test_config(config_dir, test_data_dir, test_basins)
    
    # 创建数据说明文件
    create_data_readme(test_data_dir, test_basins)
    
    print(f"\n[SUCCESS] 测试数据集创建完成!")
    print(f"[INFO] 数据目录: {test_data_dir}")
    print(f"[INFO] 配置目录: {config_dir}")
    print(f"[INFO] 包含流域: {', '.join(test_basins)}")
    print(f"[INFO] 估计大小: ~50MB (相比完整数据集 ~10GB)")

def create_test_config(config_dir, test_data_dir, test_basins):
    """创建测试配置文件"""
    
    config_content = f"""# 轻量级测试配置
# 用于快速验证neuralhydrology库的安装和运行
# 包含3个流域，训练时间约5-10分钟

# 基本设置
experiment_name: test_run
dataset: camels_us
data_dir: {test_data_dir.absolute()}

# 模型配置（简化参数以加快训练）
model: cudalstm
head: regression
hidden_size: 32  # 较小的隐藏层
initial_forget_bias: 3
output_dropout: 0.2
output_activation: linear

# 训练配置（快速训练）
epochs: 10  # 较少的训练轮数
batch_size: 64  # 较小的批次大小
optimizer: Adam
loss: MSE

# 学习率
learning_rate: 0.001

# 数据配置
train_basin_file: {config_dir.absolute()}/test_train_basins.txt
validation_basin_file: {config_dir.absolute()}/test_val_basins.txt
test_basin_file: {config_dir.absolute()}/test_test_basins.txt

# 时间范围（较短的时间段）
train_start_date: 01/10/2000
train_end_date: 30/09/2005
validation_start_date: 01/10/2000
validation_end_date: 30/09/2005
test_start_date: 01/10/2000
test_end_date: 30/09/2005

# 输入特征（只使用daymet数据）
forcings:
  - daymet

dynamic_inputs:
  - prcp(mm/day)
  - srad(W/m2)
  - tmax(C)
  - tmin(C)
  - vp(Pa)

# 目标变量
target_variables:
  - QObs(mm/d)

# 数据预处理
clip_targets_to_zero:
  - QObs(mm/d)

# 训练参数（优化用于快速测试）
seq_length: 30  # 较短的序列长度
predict_last_n: 1
num_workers: 0  # Windows兼容性
validate_every: 2
validate_n_random_basins: 1

# 正则化
clip_gradient_norm: 1.0

# 日志和保存
log_interval: 1
log_tensorboard: true
log_n_figures: 1
save_weights_every: 5

# 评估指标
metrics:
  - NSE
  - MSE

# 随机种子
seed: 42

# 测试流域信息
# 训练集: {test_basins[:2]}
# 验证集: {test_basins[2:3]}
# 测试集: {test_basins}
"""
    
    with open(config_dir / "test_config.yml", "w", encoding="utf-8") as f:
        f.write(config_content)
    
    print(f"  创建: test_config.yml")

def create_data_readme(test_data_dir, test_basins):
    """创建数据说明文件"""
    
    readme_content = f"""# 测试数据集说明

## 概述
这是一个轻量级的测试数据集，用于快速验证neuralhydrology库的安装和运行。
数据集大小约50MB，相比完整数据集（~10GB）大幅减少。

## 包含的流域
- {test_basins[0]}: 东北部流域
- {test_basins[1]}: 中部流域  
- {test_basins[2]}: 南部流域

## 数据内容
- **径流数据**: 3个流域的日径流观测数据
- **气象数据**: daymet气象强迫数据（降水、太阳辐射、温度等）
- **流域属性**: 气候、地质、水文、土壤、地形、植被等属性

## 使用方法
```bash
# 运行测试训练
python simple_train.py --config configs/test_data/test_config.yml

# 使用CPU训练（如果GPU不可用）
python simple_train.py --config configs/test_data/test_config.yml --gpu -1
```

## 预期结果
- 训练时间: 5-10分钟（GPU）或 15-30分钟（CPU）
- 模型文件: runs/test_run_*/model_epoch_*.pt
- 训练日志: runs/test_run_*/output.log
- TensorBoard: runs/test_run_*/tensorboard/

## 注意事项
- 这是一个简化的测试数据集，仅用于验证安装和基本功能
- 模型性能不代表在完整数据集上的表现
- 如需完整训练，请使用完整数据集和相应配置
"""
    
    with open(test_data_dir / "README.md", "w", encoding="utf-8") as f:
        f.write(readme_content)
    
    print(f"  创建: README.md")

if __name__ == "__main__":
    create_test_data()
