# NeuralHydrology 依赖包清单

## 核心依赖包

### 深度学习框架
- **torch** (>=2.0.0): PyTorch深度学习框架
- **torchvision** (>=0.15.0): 计算机视觉工具包
- **torchaudio** (>=0.12.0): 音频处理工具包

### 科学计算
- **numpy** (>=1.21.0): 数值计算基础库
- **pandas** (>=1.3.0): 数据分析和处理
- **scipy** (>=1.7.0): 科学计算库
- **xarray** (>=0.20.0): 多维数组处理

### 数据处理
- **h5py** (>=3.6.0): HDF5文件格式支持
- **netcdf4** (>=1.6.0): NetCDF文件格式支持
- **ruamel.yaml** (>=0.17.0): YAML配置文件解析

### 可视化
- **matplotlib** (>=3.5.0): 绘图库
- **tensorboard** (>=2.8.0): 训练过程可视化

### 工具库
- **tqdm** (>=4.64.0): 进度条显示
- **numba** (>=0.56.0): 高性能数值计算

## 可选依赖包

### 开发工具
- **jupyter** (>=1.0.0): Jupyter notebook支持
- **pytest** (>=6.0.0): 单元测试框架
- **sphinx** (>=3.2.1): 文档生成工具

### 可视化增强
- **bokeh** (>=2.4.0): 交互式可视化

### 特殊功能
- **mamba-ssm**: Mamba模型支持（可选）

## 安装命令

### GPU版本（推荐）
```bash
# 安装PyTorch GPU版本
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# 安装其他依赖
pip install numpy>=1.21.0 pandas>=1.3.0 scipy>=1.7.0 xarray>=0.20.0
pip install matplotlib>=3.5.0 h5py>=3.6.0 netcdf4>=1.6.0
pip install ruamel.yaml>=0.17.0 tqdm>=4.64.0 tensorboard>=2.8.0
pip install numba>=0.56.0
```

### CPU版本
```bash
# 安装PyTorch CPU版本
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# 安装其他依赖（同上）
pip install numpy>=1.21.0 pandas>=1.3.0 scipy>=1.7.0 xarray>=0.20.0
pip install matplotlib>=3.5.0 h5py>=3.6.0 netcdf4>=1.6.0
pip install ruamel.yaml>=0.17.0 tqdm>=4.64.0 tensorboard>=2.8.0
pip install numba>=0.56.0
```

### 使用requirements文件
```bash
# GPU版本
pip install -r requirements-gpu.txt

# CPU版本
pip install -r requirements-cpu.txt

# 通用版本
pip install -r requirements.txt
```

## 版本兼容性

### Python版本
- **推荐**: Python 3.10
- **支持**: Python 3.8 - 3.11

### CUDA版本（GPU用户）
- **推荐**: CUDA 11.8
- **支持**: CUDA 11.7 - 12.1

### 操作系统
- **Windows**: 10/11 (64位)
- **macOS**: 10.15+ (Intel/Apple Silicon)
- **Linux**: Ubuntu 18.04+, CentOS 7+, 其他主流发行版

## 依赖包大小估算

| 包名 | 大小 | 说明 |
|------|------|------|
| torch | ~2GB | PyTorch核心库 |
| torchvision | ~200MB | 视觉工具包 |
| torchaudio | ~100MB | 音频工具包 |
| numpy | ~50MB | 数值计算 |
| pandas | ~100MB | 数据处理 |
| matplotlib | ~100MB | 绘图库 |
| 其他 | ~200MB | 其余依赖包 |
| **总计** | **~2.7GB** | 完整安装 |

## 最小安装

如果只需要基本功能，可以只安装核心依赖：

```bash
pip install torch numpy pandas matplotlib ruamel.yaml tqdm
```

## 故障排除

### 常见安装问题

1. **PyTorch安装失败**
   - 检查Python版本
   - 确认网络连接
   - 使用国内镜像源

2. **CUDA版本不匹配**
   - 检查NVIDIA驱动版本
   - 安装对应CUDA版本的PyTorch

3. **依赖冲突**
   - 使用虚拟环境
   - 按顺序安装依赖包

### 验证安装

```python
# 检查关键依赖
import torch
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

print("所有依赖包安装成功！")
print(f"PyTorch版本: {torch.__version__}")
print(f"CUDA可用: {torch.cuda.is_available()}")
```
