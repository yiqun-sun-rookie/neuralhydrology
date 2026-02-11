# Simple Train 使用说明

## 快速开始

### 1. 环境准备

确保已安装 `neuralhydrology_gpu` conda 环境：

```bash
# 如果环境不存在，创建它
conda env create -f environments/environment_cuda11_8.yml
```

### 2. 运行训练

#### 使用默认配置
```bash
python simple_train.py
```

#### 指定 GPU
```bash
# 使用 GPU 0
python simple_train.py --gpu 0

# 使用 CPU
python simple_train.py --gpu -1
```

#### 指定配置文件
```bash
python simple_train.py --config examples/01-Introduction/full_training.yml
```

## 脚本特性

- ✅ **强制使用 conda 环境**: 确保环境一致性
- ✅ **自动环境检查**: 启动前验证环境是否存在
- ✅ **GPU 检测**: 自动检测 GPU 可用性
- ✅ **错误处理**: 清晰的错误信息和解决建议
- ✅ **YAML 配置**: 使用 YAML 文件管理训练参数

## 常见问题

### Q: 提示 "未找到 conda 环境"
**A**: 运行 `conda env create -f environments/environment_cuda11_8.yml` 创建环境

### Q: 提示 "conda 命令不可用"
**A**: 安装 Anaconda 或 Miniconda，并确保 conda 在系统 PATH 中

### Q: 想修改训练参数怎么办？
**A**: 编辑对应的 YAML 配置文件（如 `examples/01-Introduction/full_training.yml`）

## 训练结果

训练完成后，查看结果：
- **日志**: `runs/*/output.log`
- **TensorBoard**: `tensorboard --logdir runs/`
- **模型**: `runs/*/model_epoch*.pt`

## 更多信息

详细说明请参考 `SIMPLE_TRAIN_GUIDE.md`