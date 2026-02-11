# NeuralHydrology GPU 设置指南

## 当前状态
检测到您当前安装的是CPU版本的PyTorch，需要安装GPU版本才能使用CUDA加速。

## 安装GPU版本的PyTorch

### 方法1: 使用pip安装 (推荐)

```bash
# 卸载当前CPU版本
pip uninstall torch torchvision torchaudio

# 安装CUDA 11.8版本 (适用于大多数GPU)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# 或者安装CUDA 12.1版本 (较新的GPU)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
```

### 方法2: 使用conda安装

```bash
# 卸载当前版本
conda uninstall pytorch torchvision torchaudio

# 安装CUDA版本
conda install pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia
```

### 方法3: 使用项目环境文件

项目提供了GPU环境配置文件：

```bash
# 使用CUDA 11.8环境
conda env create -f environments/environment_cuda11_8.yml
conda activate neuralhydrology_cuda11_8
```

## 验证GPU安装

安装完成后，运行以下命令验证：

```bash
python -c "import torch; print('PyTorch版本:', torch.__version__); print('CUDA可用:', torch.cuda.is_available()); print('GPU数量:', torch.cuda.device_count()); print('GPU名称:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'N/A')"
```

期望输出应该显示：
- CUDA可用: True
- GPU数量: > 0
- GPU名称: 您的GPU型号

## 运行GPU训练

安装GPU版本后，您可以使用以下脚本：

### 使用批处理脚本 (Windows)
```bash
# 运行GPU训练
run_training_gpu.bat

# 或者使用PowerShell
.\run_training_gpu.ps1
```

### 使用Python脚本
```bash
# 自动检测GPU
python run_training.py --config examples/01-Introduction/1_basin_gpu.yml

# 强制使用GPU
python run_training.py --config examples/01-Introduction/1_basin_gpu.yml --device cuda

# 指定特定GPU
python run_training.py --config examples/01-Introduction/1_basin_gpu.yml --gpu 0
```

## 配置文件说明

### GPU优化配置
- `1_basin_gpu.yml`: 单流域GPU训练配置
- `full_training_gpu.yml`: 全数据集GPU训练配置

### 主要GPU优化参数
- `device: cuda:0`: 使用第一个GPU
- `batch_size: 512`: 增大批次大小 (GPU内存允许)
- `hidden_size: 64`: 增大隐藏层大小
- `num_workers: 8`: 增加数据加载工作进程
- `model: cudalstm`: 使用CUDA优化的LSTM模型

## 性能优化建议

1. **批次大小**: GPU上可以使用更大的批次大小 (256-1024)
2. **隐藏层大小**: GPU上可以使用更大的隐藏层 (64-256)
3. **数据加载**: 增加num_workers以充分利用GPU
4. **模型选择**: 使用cudalstm而不是普通lstm
5. **混合精度**: 考虑使用AMP (Automatic Mixed Precision) 加速训练

## 故障排除

### 常见问题

1. **CUDA不可用**
   - 检查NVIDIA驱动是否最新
   - 确认安装了正确的CUDA版本
   - 验证PyTorch版本与CUDA版本兼容

2. **内存不足**
   - 减小batch_size
   - 减小hidden_size
   - 使用梯度累积

3. **训练速度慢**
   - 检查是否真的在使用GPU (查看nvidia-smi)
   - 增加num_workers
   - 使用更大的batch_size

### 检查GPU使用情况
```bash
# 查看GPU状态
nvidia-smi

# 实时监控GPU使用
nvidia-smi -l 1
```

## 环境要求

- NVIDIA GPU (支持CUDA)
- CUDA 11.8 或 12.1
- cuDNN (通常随CUDA一起安装)
- 足够的GPU内存 (建议8GB+)
