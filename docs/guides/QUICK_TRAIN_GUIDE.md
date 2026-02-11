# NeuralHydrology 快速训练指南

## 概述

`quick_gpu_train.py` 现在支持直接在脚本中修改关键训练参数，无需手动编辑配置文件。

## 🎯 关键参数配置

### 在脚本中直接修改参数

打开 `quick_gpu_train.py`，找到第17-92行的配置区域：

```python
# =============================================================================
# 关键训练参数配置 - 可直接修改这些参数
# =============================================================================

# 训练配置
TRAINING_CONFIG = {
    # 基础训练参数
    'epochs': 50,                    # 训练轮数 (可修改: 10, 20, 50, 100, 200)
    'batch_size': 256,               # 批次大小 (可修改: 128, 256, 512, 1024)
    'learning_rate': 0.003,          # 初始学习率 (可修改: 0.001, 0.003, 0.005, 0.01)
    
    # 模型配置
    'hidden_size': 128,              # 隐藏层大小 (可修改: 64, 128, 256, 512)
    'output_dropout': 0.3,           # Dropout率 (可修改: 0.1, 0.2, 0.3, 0.4, 0.5)
    'seq_length': 365,               # 序列长度 (可修改: 180, 365, 730)
    
    # 设备配置
    'use_gpu': True,                 # 是否使用GPU (True=GPU, False=CPU)
    'gpu_id': 0,                     # GPU ID (可修改: 0, 1, 2, ...)
    
    # 优化器配置
    'optimizer': 'Adam',             # 优化器 (可修改: 'Adam', 'AdamW', 'SGD')
    'clip_gradient_norm': 1.0,       # 梯度裁剪 (可修改: 0.5, 1.0, 2.0)
    
    # 学习率调度
    'lr_schedule': {                 # 学习率调度 (可修改epoch和对应的学习率)
        0: 0.003,                    # 第0个epoch的学习率
        10: 0.002,                   # 第10个epoch的学习率
        25: 0.001,                   # 第25个epoch的学习率
        40: 0.0005,                  # 第40个epoch的学习率
    },
    
    # 验证和保存配置
    'validate_every': 2,             # 每N个epoch验证一次 (可修改: 1, 2, 5, 10)
    'save_weights_every': 5,         # 每N个epoch保存一次 (可修改: 1, 5, 10, 20)
    
    # 评估指标
    'metrics': ['NSE', 'KGE', 'Alpha-NSE'],  # 评估指标 (可添加: 'Beta-NSE', 'R²')
    
    # 数据配置
    'num_workers': 8,                # 数据加载线程数 (可修改: 4, 8, 16)
    'log_interval': 5,               # 日志输出间隔 (可修改: 1, 5, 10)
}
```

## 🚀 使用方法

### 方法1: 使用自定义配置 (推荐)

```bash
# 使用脚本中的自定义配置参数
python quick_gpu_train.py --custom --auto

# 使用预设配置
python quick_gpu_train.py --custom --preset quick_test --auto
python quick_gpu_train.py --custom --preset balanced --auto
python quick_gpu_train.py --custom --preset high_performance --auto
python quick_gpu_train.py --custom --preset cpu_optimized --auto
```

### 方法2: 使用传统配置文件

```bash
# 使用预定义的配置文件
python quick_gpu_train.py --config 1 --auto  # 基础配置
python quick_gpu_train.py --config 2 --auto  # 改进配置
python quick_gpu_train.py --config 3 --auto  # 高级配置
```

### 方法3: 续跑训练

```bash
# 续跑最新的中断训练
python quick_gpu_train.py --resume
```

## 📋 预设配置说明

| 预设名称 | Epochs | Batch Size | Hidden Size | 学习率 | 描述 |
|----------|--------|------------|-------------|--------|------|
| `quick_test` | 10 | 512 | 64 | 0.005 | 快速测试配置 |
| `balanced` | 50 | 256 | 128 | 0.003 | 平衡配置 |
| `high_performance` | 100 | 128 | 256 | 0.001 | 高性能配置 |
| `cpu_optimized` | 20 | 64 | 64 | 0.005 | CPU优化配置 |

## ⚙️ 参数修改示例

### 增加训练轮数
```python
'epochs': 100,  # 从50改为100
```

### 使用CPU训练
```python
'use_gpu': False,  # 从True改为False
```

### 增加模型容量
```python
'hidden_size': 256,  # 从128改为256
```

### 修改学习率调度
```python
'lr_schedule': {
    0: 0.001,    # 更保守的初始学习率
    20: 0.0008,
    40: 0.0005,
    60: 0.0003,
    80: 0.0001,
},
```

### 添加更多评估指标
```python
'metrics': ['NSE', 'KGE', 'Alpha-NSE', 'Beta-NSE', 'R²'],
```

## 🎯 训练结果对比

### 之前的训练 (10 epochs)
- 最终NSE: 0.51287
- 训练时间: ~7分钟
- 模型容量: 64

### 改进的训练 (50 epochs)
- 最终NSE: 0.95621
- 训练时间: ~21分钟
- 模型容量: 128

### 快速测试 (10 epochs, 预设)
- 最终NSE: 0.61797
- 训练时间: ~5分钟
- 模型容量: 64

## 💡 优化建议

### 1. 根据硬件调整参数
- **GPU内存充足**: 增加 `batch_size` 和 `hidden_size`
- **GPU内存不足**: 减少 `batch_size`，使用 `cpu_optimized` 预设
- **CPU训练**: 设置 `use_gpu: False`，使用较小的模型

### 2. 根据训练目标调整
- **快速测试**: 使用 `quick_test` 预设
- **最佳性能**: 使用 `high_performance` 预设
- **平衡训练**: 使用 `balanced` 预设

### 3. 监控训练进度
- 使用 `validate_every: 1` 更频繁地验证
- 使用 `save_weights_every: 1` 更频繁地保存
- 查看TensorBoard: `tensorboard --logdir runs/`

## 🔧 故障排除

### 问题1: GPU内存不足
```python
'batch_size': 128,  # 减小批次大小
'hidden_size': 64,  # 减小模型容量
```

### 问题2: 训练太慢
```python
'epochs': 20,       # 减少训练轮数
'validate_every': 5, # 减少验证频率
'save_weights_every': 10, # 减少保存频率
```

### 问题3: 收敛太慢
```python
'learning_rate': 0.005,  # 增加学习率
'lr_schedule': {0: 0.005, 5: 0.003, 10: 0.001},  # 调整学习率调度
```

## 📊 性能监控

训练完成后，可以查看：
- **日志文件**: `runs/*/output.log`
- **TensorBoard**: `tensorboard --logdir runs/`
- **模型文件**: `runs/*/model_epoch*.pt`
- **配置文件**: `runs/*/config.yml`

现在您可以轻松地修改训练参数，无需手动编辑配置文件！
