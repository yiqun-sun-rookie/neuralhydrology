# NeuralHydrology GPU训练指南

## 概述

本项目提供了多个GPU训练脚本，帮助您快速启动和运行NeuralHydrology的GPU训练。

## 环境要求

### 硬件要求
- NVIDIA GPU (支持CUDA)
- 建议8GB+ GPU内存
- 足够的系统内存

### 软件要求
- Python 3.8+
- CUDA 11.8 或 12.1
- cuDNN
- GPU版本的PyTorch

## 安装GPU版本的PyTorch

### 方法1: 使用pip (推荐)
```bash
# 卸载CPU版本
pip uninstall torch torchvision torchaudio

# 安装CUDA 11.8版本
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# 或安装CUDA 12.1版本
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
```

### 方法2: 使用conda
```bash
conda install pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia
```

### 方法3: 使用项目环境文件
```bash
conda env create -f environments/environment_cuda11_8.yml
conda activate neuralhydrology
```

## 验证GPU安装

运行以下命令验证GPU环境：

```bash
python -c "import torch; print('PyTorch版本:', torch.__version__); print('CUDA可用:', torch.cuda.is_available()); print('GPU数量:', torch.cuda.device_count())"
```

期望输出：
- CUDA可用: True
- GPU数量: > 0

## GPU训练脚本

### 1. 快速GPU训练 (推荐新手)

**文件**: `quick_gpu_train.py`

交互式脚本，自动引导您选择配置和GPU。

```bash
python quick_gpu_train.py
```

**特点**:
- 交互式界面
- 自动检测GPU
- 预设配置选择
- 简单易用

### 2. 完整GPU训练脚本

**文件**: `gpu_training.py`

功能完整的GPU训练脚本，支持所有高级选项。

```bash
# 基本用法
python gpu_training.py --config examples/01-Introduction/1_basin_gpu.yml

# 指定GPU和参数
python gpu_training.py --config examples/01-Introduction/1_basin_gpu.yml --gpu 0 --batch-size 1024

# 列出可用配置
python gpu_training.py --list-configs

# 检查GPU环境
python gpu_training.py --check-env
```

**参数说明**:
- `--config, -c`: 配置文件路径
- `--gpu, -g`: GPU设备ID (默认: 0)
- `--batch-size, -b`: 批次大小 (默认: 512)
- `--hidden-size`: 隐藏层大小 (默认: 64)
- `--no-monitor`: 禁用GPU监控
- `--list-configs`: 列出可用配置文件
- `--check-env`: 仅检查GPU环境

### 3. Windows批处理启动器

**文件**: `start_gpu_training.bat`

Windows用户的一键启动脚本。

```cmd
start_gpu_training.bat
```

### 4. PowerShell启动器

**文件**: `start_gpu_training.ps1`

PowerShell用户的一键启动脚本。

```powershell
.\start_gpu_training.ps1
```

## 可用的GPU配置文件

### 单流域测试
- `examples/01-Introduction/1_basin_gpu.yml`
- 适合快速测试GPU环境
- 训练时间: 几分钟

### 多流域测试
- `examples/01-Introduction/3_basins_proper_split.yml`
- 适合验证GPU性能
- 训练时间: 10-30分钟

### 完整训练
- `examples/01-Introduction/full_training_gpu.yml`
- 使用所有674个流域
- 训练时间: 数小时

## GPU优化参数

### 推荐的GPU设置

```yaml
# 设备设置
device: cuda:0

# 模型设置
model: cudalstm  # 使用CUDA优化的LSTM
hidden_size: 128  # GPU上可以使用更大的隐藏层

# 训练设置
batch_size: 1024  # GPU上可以使用更大的批次
num_workers: 8    # 增加数据加载工作进程

# 验证设置
validate_every: 3  # GPU训练更快，可以更频繁验证
```

### 性能优化建议

1. **批次大小**: GPU上可以使用256-2048的批次大小
2. **隐藏层大小**: GPU上可以使用64-256的隐藏层
3. **数据加载**: 增加num_workers到4-8
4. **模型选择**: 使用cudalstm而不是普通lstm
5. **混合精度**: 考虑使用AMP加速训练

## 监控GPU使用

### 实时监控
```bash
# 查看GPU状态
nvidia-smi

# 实时监控GPU使用
nvidia-smi -l 1
```

### TensorBoard监控
```bash
# 启动TensorBoard
tensorboard --logdir runs/

# 在浏览器中打开 http://localhost:6006
```

## 故障排除

### 常见问题

1. **CUDA不可用**
   - 检查NVIDIA驱动是否最新
   - 确认安装了正确的CUDA版本
   - 验证PyTorch版本与CUDA版本兼容

2. **内存不足 (CUDA out of memory)**
   - 减小batch_size (例如: 512 → 256)
   - 减小hidden_size (例如: 128 → 64)
   - 使用梯度累积

3. **训练速度慢**
   - 检查是否真的在使用GPU (查看nvidia-smi)
   - 增加num_workers
   - 使用更大的batch_size
   - 确保使用cudalstm模型

4. **数据加载慢**
   - 增加num_workers
   - 使用SSD存储数据
   - 预加载数据到内存

### 性能基准

在RTX 3080 (10GB)上的参考性能：

| 配置 | 批次大小 | 隐藏层 | 训练速度 | 内存使用 |
|------|----------|--------|----------|----------|
| 单流域 | 512 | 64 | ~2分钟/epoch | ~2GB |
| 多流域 | 1024 | 128 | ~5分钟/epoch | ~4GB |
| 完整训练 | 1024 | 128 | ~30分钟/epoch | ~6GB |

## 示例用法

### 快速开始
```bash
# 1. 检查GPU环境
python gpu_training.py --check-env

# 2. 运行快速测试
python quick_gpu_train.py

# 3. 选择配置1 (单流域测试)
```

### 生产训练
```bash
# 1. 使用完整GPU训练脚本
python gpu_training.py --config examples/01-Introduction/full_training_gpu.yml --gpu 0 --batch-size 1024

# 2. 监控训练进度
tensorboard --logdir runs/
```

### 多GPU训练
```bash
# 使用GPU 1
python gpu_training.py --config examples/01-Introduction/full_training_gpu.yml --gpu 1

# 使用GPU 2
python gpu_training.py --config examples/01-Introduction/full_training_gpu.yml --gpu 2
```

## 结果查看

训练完成后，结果保存在 `runs/` 目录下：

```
runs/
└── experiment_name_YYYYMMDD_HHMMSS/
    ├── output.log          # 训练日志
    ├── config.yml          # 使用的配置
    ├── train_data/         # 模型权重
    │   ├── model_epoch_*.pth
    │   └── model.pth
    └── tensorboard/        # TensorBoard日志
        └── events.out.tfevents.*
```

## 支持

如果遇到问题，请：

1. 检查GPU环境是否正确安装
2. 查看训练日志 `runs/*/output.log`
3. 确认配置文件路径正确
4. 验证数据文件存在

## 更新日志

- v1.0: 初始版本，支持基本GPU训练
- v1.1: 添加交互式快速训练脚本
- v1.2: 添加Windows批处理和PowerShell启动器
- v1.3: 优化GPU参数和性能监控
