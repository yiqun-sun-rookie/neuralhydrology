# NeuralHydrology 安装和运行指南

## 项目简介

NeuralHydrology 是一个用于水文建模的深度学习库，支持多种神经网络模型进行径流预测。官方训练入口为 `neuralhydrology/nh_run.py`（可通过 `python -m neuralhydrology.nh_run` 或安装后的 `nh-run` CLI 调用）。

## 系统要求

### 硬件要求
- **CPU**: 推荐多核处理器（训练时间较长）
- **GPU**: 可选，NVIDIA GPU + CUDA支持（推荐，可显著加速训练）
- **内存**: 至少8GB RAM，推荐16GB以上
- **存储**: 至少10GB可用空间

### 软件要求
- **Python**: 3.8 或更高版本
- **操作系统**: Windows 10/11, macOS 10.15+, 或 Linux
- **CUDA**: 如果使用GPU，需要CUDA 11.8或兼容版本

## 安装步骤

### 方法一：使用Conda（推荐）

1. **安装Anaconda或Miniconda**
   - 下载并安装 [Anaconda](https://www.anaconda.com/download) 或 [Miniconda](https://docs.conda.io/en/latest/miniconda.html)

2. **创建虚拟环境**
   ```bash
   # 创建新环境
   conda create -n neuralhydrology python=3.10
   
   # 激活环境
   conda activate neuralhydrology
   ```

3. **安装依赖包（依赖套件）**

   推荐直接使用套件入口：
   ```bash
   # GPU（推荐）
   pip install -r requirements-gpu.txt

   # 或 CPU
   pip install -r requirements-cpu.txt
   ```

### 方法二：使用pip

1. **创建虚拟环境**
   ```bash
   # 创建虚拟环境
   python -m venv neuralhydrology_env
   
   # 激活环境
   # Windows:
   neuralhydrology_env\Scripts\activate
   # macOS/Linux:
   source neuralhydrology_env/bin/activate
   ```

2. **安装依赖包（依赖套件）**

   推荐直接使用套件入口：
   ```bash
   # GPU（推荐）
   pip install -r requirements-gpu.txt

   # 或 CPU
   pip install -r requirements-cpu.txt
   ```

## 验证安装

运行以下Python代码验证安装是否成功：

```python
import torch
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

print(f"PyTorch版本: {torch.__version__}")
print(f"CUDA可用: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"GPU数量: {torch.cuda.device_count()}")
    print(f"当前GPU: {torch.cuda.get_device_name(0)}")

print("所有依赖包安装成功！")
```

## 运行训练

### 基本用法

```bash
# 使用默认配置运行训练
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu 0

# 指定配置文件
python -m neuralhydrology.nh_run train --config-file src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml --gpu 0

# 指定 GPU（如果有多个 GPU）
python -m neuralhydrology.nh_run train --config-file src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml --gpu 1

# 使用 CPU 训练
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu -1

# 断点续训（需要指定 run_dir）
python -m neuralhydrology.nh_run continue_training --run-dir runs/your_run_directory --gpu 0
```

> 说明：旧版 `simple_train.py` 已移除，若需要清理失败的运行，请手动删除对应 `runs/<run_name>` 目录。

### 配置文件说明

项目包含多个预配置的训练配置文件：

- `src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml`: 完整训练配置（531个基准流域）
- `src/caravan_global/configs/`: Caravan 相关配置
- `src/mamba_camels_us/configs/`: Mamba CAMELS-US 配置
- `src/mamba_camelsh/configs/`: Mamba CAMELSH 配置

### 训练输出

训练结果将保存在 `runs/` 目录下，每个训练运行都有独立的文件夹，包含：
- 模型权重文件 (`model_epoch_*.pt`)
- 训练日志 (`output.log`)
- TensorBoard日志文件
- 评估结果和图表

## 常见问题

### 1. CUDA相关错误
```
RuntimeError: CUDA out of memory
```
**解决方案**: 减少batch_size或使用CPU训练

### 2. 依赖包冲突
```
ImportError: cannot import name 'xxx'
```
**解决方案**: 重新创建虚拟环境，按顺序安装依赖

### 3. 数据路径错误
```
FileNotFoundError: [Errno 2] No such file or directory
```
**解决方案**: 检查配置文件中的数据路径是否正确

### 4. 内存不足
```
MemoryError
```
**解决方案**: 减少batch_size、seq_length或使用更少的流域

## 性能优化建议

1. **使用GPU**: 如果有NVIDIA GPU，强烈推荐使用GPU版本
2. **调整batch_size**: 根据GPU内存调整batch_size
3. **减少流域数量**: 对于快速测试，可以使用较少的流域
4. **调整序列长度**: 减少seq_length可以节省内存

## 获取帮助

如果遇到问题，请检查：
1. Python版本是否符合要求
2. 所有依赖包是否正确安装
3. 配置文件路径是否正确
4. 数据文件是否存在

## 许可证

本项目基于BSD许可证开源。详见LICENSE文件。



