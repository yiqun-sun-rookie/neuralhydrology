# 测试数据集使用指�?

## 概述

为了帮助用户快速验证neuralhydrology库的安装和运行，我们提供了轻量级的测试数据集。这些数据集大大减少了下载和存储需求，同时保持了完整的功能验证�?

## 测试数据集特�?

### 数据规模对比

| 数据集类�?| 流域数量 | 数据大小 | 训练时间 | 用�?|
|-----------|----------|----------|----------|------|
| **测试数据�?* | 3个流�?| ~50MB | 2-10分钟 | 快速验�?|
| 演示数据�?| 4个流�?| ~500MB | 5-15分钟 | 功能演示 |
| 完整数据�?| 531个流�?| ~10GB | 数小�?| 正式训练 |

### 包含的流�?

测试数据集包�?个代表性流域：
- **01022500**: 东北部流�?
- **01030500**: 东北部流域（备选）
- **01031500**: 东北部流域（备选）

## 快速开�?

### 1. 自动设置（推荐）

```bash
# 运行自动设置脚本
python src/test_data/scripts/setup_test_environment.py
```

此脚本将�?
- 检查依赖包安装
- 创建测试数据�?
- 运行快速验证测�?

### 2. 手动设置

```bash
# 1. 创建测试数据�?
python src/test_data/scripts/create_test_data.py

# 2. 运行超快速测试（2-3分钟�?
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu 0

# 3. 运行标准测试�?-10分钟�?
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/test_config.yml --gpu 0
```

## 配置文件说明

### quick_test.yml - 超快速验�?
- **训练时间**: 2-3分钟
- **模型参数**: 最小化（hidden_size=16, epochs=3�?
- **序列长度**: 10�?
- **用�?*: 验证安装和基本功�?

### test_config.yml - 标准测试
- **训练时间**: 5-10分钟
- **模型参数**: 简化（hidden_size=32, epochs=10�?
- **序列长度**: 30�?
- **用�?*: 验证完整训练流程

## 数据内容

### 径流数据
- 3个流域的日径流观测数�?
- 时间范围: 2000-2005�?
- 数据格式: 标准CAMELS格式

### 气象数据
- daymet气象强迫数据
- 包含: 降水、太阳辐射、最�?最低温度、水汽压
- 时间范围: 2000-2005�?

### 流域属�?
- 气候特�?
- 地质特征
- 水文特征
- 土壤特征
- 地形特征
- 植被特征

## 预期结果

### 训练输出
```
训练完成后，在runs/目录下会生成�?
├── quick_test_YYYYMMDD_HHMMSS/
�?  ├── model_epoch_1.pt
�?  ├── model_epoch_2.pt
�?  ├── model_epoch_3.pt
�?  ├── output.log
�?  └── tensorboard/
└── test_run_YYYYMMDD_HHMMSS/
    ├── model_epoch_*.pt
    ├── output.log
    └── tensorboard/
```

### 性能指标
- **NSE (Nash-Sutcliffe效率)**: 通常�?.3-0.7之间
- **MSE (均方误差)**: 取决于流域特�?
- **注意**: 测试数据集性能不代表完整数据集表现

## 故障排除

### 常见问题

1. **数据文件不存�?*
   ```
   FileNotFoundError: [Errno 2] No such file or directory
   ```
   **解决**: 运行 `python src/test_data/scripts/create_test_data.py` 创建测试数据

2. **内存不足**
   ```
   RuntimeError: CUDA out of memory
   ```
   **解决**: 使用 `--gpu -1` 切换到CPU训练

3. **依赖包缺�?*
   ```
   ImportError: No module named 'xxx'
   ```
   **解决**: 安装依赖�?`pip install -r requirements.txt`（或 GPU 环境�?`requirements.txt`�?
### 验证安装

```python
# 检查关键依�?
import torch
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

print("所有依赖包安装成功�?)
print(f"PyTorch版本: {torch.__version__}")
print(f"CUDA可用: {torch.cuda.is_available()}")
```

## 下一�?

### 测试成功�?
1. **查看训练结果**: `runs/quick_test_*/output.log`
2. **使用TensorBoard**: `tensorboard --logdir runs/`
3. **尝试更大数据�?*: 使用 `src/test_data/configs/test_config.yml`
4. **正式训练**: 使用完整数据集和 `src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml`

### 性能优化
- 使用GPU加速训�?
- 调整batch_size和seq_length
- 增加训练轮数
- 使用更多流域数据

## 注意事项

1. **数据完整�?*: 测试数据集仅用于验证功能，不代表完整性能
2. **模型性能**: 小数据集上的结果不能推广到完整数据集
3. **时间范围**: 测试数据时间范围较短，实际应用需要更长的时间序列
4. **流域选择**: 测试流域可能不具有代表性，完整训练需要更多样化的流域

## 技术支�?

如果遇到问题�?
1. 检查依赖包安装
2. 验证数据文件完整�?
3. 查看训练日志文件
4. 参考故障排除指�?
5. 联系技术支�?



