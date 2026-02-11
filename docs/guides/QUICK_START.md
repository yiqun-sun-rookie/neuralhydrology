# NeuralHydrology 快速开始指南

## 5分钟快速上手

### 1. 环境准备

```bash
# 创建并激活虚拟环境
conda create -n neuralhydrology python=3.10
conda activate neuralhydrology

# 安装依赖（选择GPU或CPU版本）
# GPU版本：
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
pip install -r requirements-gpu.txt

# CPU版本：
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements-cpu.txt
```

### 2. 验证安装

```python
import torch
print(f"PyTorch: {torch.__version__}")
print(f"CUDA可用: {torch.cuda.is_available()}")
```

### 3. 运行训练

```bash
# 超快速验证（推荐首次使用）
python -m neuralhydrology.nh_run train --config-file configs/test_data/quick_test.yml --gpu 0

# 标准测试
python -m neuralhydrology.nh_run train --config-file configs/test_data/test_config.yml --gpu 0

# 快速演示（小数据集）
python -m neuralhydrology.nh_run train --config-file configs/quick_demo.yml --gpu 0

# 单流域训练
python -m neuralhydrology.nh_run train --config-file configs/single_basin/1_basin.yml --gpu 0

# 完整训练（需要更多时间和资源）
python -m neuralhydrology.nh_run train --config-file configs/full_training/full_training.yml --gpu 0
```

### 4. 查看结果

训练完成后，结果保存在 `runs/` 目录下：
- 打开 `runs/最新运行目录/output.log` 查看训练日志
- 使用TensorBoard查看训练曲线：
  ```bash
  tensorboard --logdir runs/
  ```

## 常用命令

```bash
# 使用 GPU 0 训练
python -m neuralhydrology.nh_run train --config-file configs/test_data/quick_test.yml --gpu 0

# 使用 CPU 训练
python -m neuralhydrology.nh_run train --config-file configs/test_data/quick_test.yml --gpu -1

# 指定自定义配置
python -m neuralhydrology.nh_run train --config-file 你的配置文件.yml --gpu 0
```

> 说明：`nh-run` 不再提供自动清理功能，如需移除不完整的运行，请手动删除对应的 `runs/<run_name>` 目录。

## 配置文件选择

| 配置文件 | 用途 | 训练时间 | 资源需求 | 数据大小 |
|---------|------|----------|----------|----------|
| `configs/test_data/quick_test.yml` | 超快速验证 | 2-3分钟 | 极低 | ~50MB |
| `configs/test_data/test_config.yml` | 标准测试 | 5-10分钟 | 低 | ~50MB |
| `quick_demo.yml` | 快速演示 | 5-10分钟 | 低 | ~500MB |
| `1_basin.yml` | 单流域训练 | 10-30分钟 | 低 | ~500MB |
| `3_basins.yml` | 多流域训练 | 30-60分钟 | 中等 | ~1GB |
| `full_training.yml` | 完整训练 | 数小时 | 高 | ~10GB |

## 故障排除

**问题**: `conda: command not found`
**解决**: 安装 [Anaconda](https://www.anaconda.com/download) 或 [Miniconda](https://docs.conda.io/en/latest/miniconda.html)

**问题**: `CUDA out of memory`
**解决**: 使用 `--gpu -1` 切换到CPU训练

**问题**: `FileNotFoundError`
**解决**: 检查数据路径，确保 `data/CAMELS_US/` 目录存在

## 下一步

- 查看 [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md) 获取详细安装说明
- 阅读配置文件了解参数设置
- 查看 `runs/` 目录下的训练结果
- 使用TensorBoard可视化训练过程
