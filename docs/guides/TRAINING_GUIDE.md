# NeuralHydrology 训练指南

## 环境配置状态

### Conda 环境信息
- **环境名称**: `neuralhydrology_gpu`
- **Python 路径**: `C:\Users\yiqun\anaconda3\envs\neuralhydrology_gpu\python.exe`
- **状态**: ✅ 已配置完成

### 已安装的核心依赖
- **PyTorch**: 2.3.1 (CUDA 11.8 支持)
- **CUDA**: 11.8 (可用)
- **NumPy**: 2.3.3
- **Pandas**: 2.3.3
- **Matplotlib**: 3.10.6
- **SciPy**: 1.16.2
- **TensorBoard**: 2.20.0
- **tqdm**: 4.67.1
- **xarray**: 2025.9.1
- **Numba**: 0.62.1
- **ruamel.yaml**: 0.18.15

### 环境验证
```bash
# 验证 PyTorch 和 CUDA
C:\Users\yiqun\anaconda3\envs\neuralhydrology_gpu\python.exe -c "import torch; print('PyTorch version:', torch.__version__); print('CUDA available:', torch.cuda.is_available())"

# 验证所有依赖
C:\Users\yiqun\anaconda3\envs\neuralhydrology_gpu\python.exe -c "import numpy, pandas, matplotlib, scipy, torch; print('All core dependencies installed successfully')"
```

## 快速启动训练

### 1. 激活环境
```bash
conda activate neuralhydrology_gpu
```

### 2. 使用正确的 Python 路径
```bash
# 直接使用环境中的 Python
C:\Users\yiqun\anaconda3\envs\neuralhydrology_gpu\python.exe neuralhydrology/nh_run.py train --config-file examples\01-Introduction\full_training.yml --gpu 0
```

### 3. 常用训练命令
```bash
# GPU 训练
C:\Users\yiqun\anaconda3\envs\neuralhydrology_gpu\python.exe neuralhydrology/nh_run.py train --config-file examples\01-Introduction\full_training.yml --gpu 0

# CPU 训练
C:\Users\yiqun\anaconda3\envs\neuralhydrology_gpu\python.exe neuralhydrology/nh_run.py train --config-file examples\01-Introduction\full_training.yml --gpu -1
```

## 环境问题解决

### 问题1: ModuleNotFoundError: No module named 'numpy'
**解决方案**: 已在 neuralhydrology_gpu 环境中安装所有必需依赖

### 问题1.1: ModuleNotFoundError: No module named 'ruamel'
**解决方案**: 已安装 ruamel.yaml 0.18.15

### 问题2: 环境激活问题
**解决方案**: 直接使用完整 Python 路径，避免环境激活问题

### 问题3: CUDA 不可用
**解决方案**: PyTorch 2.3.1 已正确配置 CUDA 11.8 支持

## 配置文件位置
- 示例配置: `examples\01-Introduction\full_training.yml`
- 自定义配置: 可参考示例配置文件创建

## 训练输出
- 模型保存位置: `runs/` 目录
- 日志文件: 各运行目录下的 `output.log`
- TensorBoard 日志: 各运行目录下的 `tensorboard/`

## 注意事项
1. 确保使用 `neuralhydrology_gpu` 环境中的 Python
2. GPU 训练需要 CUDA 支持的显卡
3. 训练前检查数据路径是否正确
4. 监控 GPU 内存使用情况

---
*最后更新: 2025年1月 - 环境配置完成*
