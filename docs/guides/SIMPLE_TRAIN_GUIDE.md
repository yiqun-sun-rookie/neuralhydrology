# NeuralHydrology 简单训练指南

## 概述

`simple_train.py` 是一个基于 YAML 配置的训练启动器，强制使用 `neuralhydrology_gpu` conda 环境，确保训练环境的一致性。

## 📁 文件说明

### 1. `simple_train.py` - YAML 配置训练启动器
- 强制使用 `neuralhydrology_gpu` conda 环境
- 基于 YAML 配置文件进行训练
- 自动检查环境和 GPU 可用性
- 支持命令行参数指定配置文件和 GPU

### 2. `full_data_train.py` - 全部数据训练脚本
- 专门用于674个流域的完整训练
- 优化的参数配置
- 适合大规模训练

### 3. `train_config.py` + `train_with_config.py` - 分离式配置
- `train_config.py`: 配置文件，只包含参数
- `train_with_config.py`: 训练脚本，读取配置文件
- 适合团队协作和版本控制

## 🚀 使用方法

### 环境要求

在运行训练之前，请确保：

1. **安装 Anaconda 或 Miniconda**
2. **创建 neuralhydrology_gpu 环境**：
   ```bash
   conda env create -f environments/environment_cuda11_8.yml
   ```

### 方法1: 使用默认配置

直接运行脚本，使用默认的 `full_training.yml` 配置：

```bash
python simple_train.py
```

### 方法2: 指定配置文件

使用自定义的 YAML 配置文件：

```bash
python simple_train.py --config examples/01-Introduction/full_training.yml
```

### 方法3: 指定 GPU

指定使用的 GPU ID（-1 表示使用 CPU）：

```bash
# 使用 GPU 0
python simple_train.py --gpu 0

# 使用 GPU 1
python simple_train.py --gpu 1

# 使用 CPU
python simple_train.py --gpu -1
```

### 方法4: 组合参数

同时指定配置文件和 GPU：

```bash
python simple_train.py --config examples/01-Introduction/full_training.yml --gpu 0
```

## ⚙️ YAML 配置说明

### 修改训练配置

要修改训练参数，请编辑对应的 YAML 配置文件（如 `examples/01-Introduction/full_training.yml`）：

```yaml
# 基础设置
experiment_name: full_training_nse
dataset: camels_us
data_dir: F:\github\pycharm\projects\neuralhydrology\data\CAMELS_US

# 模型配置
model: cudalstm
hidden_size: 128
output_dropout: 0.3

# 训练配置
epochs: 10
batch_size: 256
optimizer: AdamW
loss: NSE

# 时间分割 - 避免数据泄露
train_start_date: 01/10/1980
train_end_date: 30/09/1999
validation_start_date: 01/10/2000
validation_end_date: 30/09/2007
test_start_date: 01/10/2008
test_end_date: 30/09/2014

# 学习率调度
learning_rate:
  0: 0.003
  10: 0.002
  25: 0.001
  40: 0.0005
```

### 常用参数修改

#### 增加训练轮数
```yaml
epochs: 100  # 从 10 改为 100
```

#### 调整批次大小
```yaml
batch_size: 128  # 从 256 改为 128
```

#### 修改模型大小
```yaml
hidden_size: 256  # 从 128 改为 256
```

#### 调整学习率
```yaml
learning_rate:
  0: 0.001    # 更保守的初始学习率
  20: 0.0008
  40: 0.0005
  60: 0.0003
  80: 0.0001
```

#### 修改时间分割
```yaml
# 确保训练、验证、测试时间段不重叠
train_start_date: 01/10/1980
train_end_date: 30/09/1999
validation_start_date: 01/10/2000
validation_end_date: 30/09/2007
test_start_date: 01/10/2008
test_end_date: 30/09/2014
```

**⚠️ 重要提醒**：
- 训练、验证、测试时间段必须**不重叠**
- 时间顺序应该是：训练 → 验证 → 测试
- 这样可以避免数据泄露，确保模型泛化能力

### 方法2: 使用全部数据训练脚本

1. **修改配置** - 打开 `full_data_train.py`，修改参数：

```python
# 基础训练参数
EPOCHS = 100                   # 训练轮数 (推荐100+)
BATCH_SIZE = 128               # 批次大小 (推荐128)
LEARNING_RATE = 0.001          # 学习率 (推荐0.001)

# 模型配置
HIDDEN_SIZE = 256              # 隐藏层大小 (推荐256+)
OUTPUT_DROPOUT = 0.2           # Dropout率 (推荐0.2)
```

2. **运行训练**：
```bash
python full_data_train.py
```

### 方法3: 使用分离式配置

1. **修改配置** - 打开 `train_config.py`，修改参数：

```python
# 基础训练参数
EPOCHS = 50                    # 训练轮数
BATCH_SIZE = 256               # 批次大小
LEARNING_RATE = 0.003          # 学习率

# 模型配置
HIDDEN_SIZE = 128              # 隐藏层大小
OUTPUT_DROPOUT = 0.3           # Dropout率

# 设备配置
USE_GPU = True                 # 是否使用GPU
GPU_ID = 0                     # GPU ID
```

2. **运行训练**：
```bash
python train_with_config.py
```

## ⚙️ 配置参数说明

### 基础训练参数
- `EPOCHS`: 训练轮数 (10, 20, 50, 100, 200)
- `BATCH_SIZE`: 批次大小 (128, 256, 512, 1024)
- `LEARNING_RATE`: 初始学习率 (0.001, 0.003, 0.005, 0.01)

### 模型配置
- `HIDDEN_SIZE`: 隐藏层大小 (64, 128, 256, 512)
- `OUTPUT_DROPOUT`: Dropout率 (0.1, 0.2, 0.3, 0.4, 0.5)
- `SEQ_LENGTH`: 序列长度 (180, 365, 730)

### 设备配置
- `USE_GPU`: 是否使用GPU (True=GPU, False=CPU)
- `GPU_ID`: GPU ID (0, 1, 2, ...)

### 优化器配置
- `OPTIMIZER`: 优化器 ('Adam', 'AdamW', 'SGD')
- `CLIP_GRADIENT_NORM`: 梯度裁剪 (0.5, 1.0, 2.0)

### 学习率调度
```python
LR_SCHEDULE = {
    0: 0.003,                  # 第0个epoch的学习率
    10: 0.002,                 # 第10个epoch的学习率
    25: 0.001,                 # 第25个epoch的学习率
    40: 0.0005,                # 第40个epoch的学习率
}
```

## 🎯 预设配置

### 快速测试配置
```python
EPOCHS = 10
BATCH_SIZE = 512
HIDDEN_SIZE = 64
LEARNING_RATE = 0.005
EXPERIMENT_NAME = "quick_test"
```

### 高性能配置
```python
EPOCHS = 100
BATCH_SIZE = 128
HIDDEN_SIZE = 256
LEARNING_RATE = 0.001
EXPERIMENT_NAME = "high_performance"
```

### CPU训练配置
```python
USE_GPU = False
EPOCHS = 20
BATCH_SIZE = 64
HIDDEN_SIZE = 64
LEARNING_RATE = 0.005
EXPERIMENT_NAME = "cpu_training"
```

## 📊 使用示例

### 示例1: 快速测试
1. 打开 `simple_train.py`
2. 修改参数：
```python
EPOCHS = 10
BATCH_SIZE = 512
HIDDEN_SIZE = 64
LEARNING_RATE = 0.005
EXPERIMENT_NAME = "quick_test"
```
3. 运行：`python simple_train.py`

### 示例2: 高性能训练
1. 打开 `train_config.py`
2. 修改参数：
```python
EPOCHS = 100
BATCH_SIZE = 128
HIDDEN_SIZE = 256
LEARNING_RATE = 0.001
EXPERIMENT_NAME = "high_performance"
```
3. 运行：`python train_with_config.py`

### 示例3: CPU训练
1. 打开 `simple_train.py`
2. 修改参数：
```python
USE_GPU = False
EPOCHS = 20
BATCH_SIZE = 64
HIDDEN_SIZE = 64
LEARNING_RATE = 0.005
EXPERIMENT_NAME = "cpu_training"
```
3. 运行：`python simple_train.py`

## 🔧 常见修改

### 增加训练轮数
```python
EPOCHS = 100  # 从50改为100
```

### 使用CPU训练
```python
USE_GPU = False  # 从True改为False
```

### 增加模型容量
```python
HIDDEN_SIZE = 256  # 从128改为256
```

### 调整学习率调度
```python
LR_SCHEDULE = {
    0: 0.001,    # 更保守的初始学习率
    20: 0.0008,
    40: 0.0005,
    60: 0.0003,
    80: 0.0001,
}
```

## 📈 训练结果

训练完成后，可以查看：
- **日志文件**: `runs/*/output.log`
- **TensorBoard**: `tensorboard --logdir runs/`
- **模型文件**: `runs/*/model_epoch*.pt`
- **配置文件**: `runs/*/config.yml`

## 🔧 错误处理和故障排除

### 常见错误

#### 1. Conda 环境不存在
```
[ERROR] 未找到 conda 环境: neuralhydrology_gpu
[INFO] 请先创建环境: conda env create -f environments/environment_cuda11_8.yml
```

**解决方案**：
```bash
conda env create -f environments/environment_cuda11_8.yml
```

#### 2. Conda 命令不可用
```
[ERROR] conda 命令不可用，请确保已安装 Anaconda 或 Miniconda
```

**解决方案**：
- 安装 [Anaconda](https://www.anaconda.com/download) 或 [Miniconda](https://docs.conda.io/en/latest/miniconda.html)
- 确保 conda 在系统 PATH 中

#### 3. 配置文件不存在
```
[ERROR] 找不到配置文件: examples/01-Introduction/full_training.yml
```

**解决方案**：
- 检查文件路径是否正确
- 使用 `--config` 参数指定正确的配置文件路径

#### 4. GPU 不可用
```
[WARNING] 未检测到可用 GPU，改用 CPU (--gpu -1)
```

**解决方案**：
- 检查 CUDA 驱动是否正确安装
- 使用 `--gpu -1` 强制使用 CPU 训练

### 环境检查

运行以下命令检查环境状态：

```bash
# 检查 conda 环境
conda env list

# 检查 PyTorch 和 CUDA
conda run -n neuralhydrology_gpu python -c "import torch; print('PyTorch:', torch.__version__); print('CUDA:', torch.cuda.is_available())"
```

## 💡 优势

1. **环境一致性**: 强制使用指定的 conda 环境，避免依赖冲突
2. **自动检查**: 自动验证环境和 GPU 可用性
3. **配置分离**: 使用 YAML 文件管理配置，便于版本控制
4. **错误提示**: 清晰的错误信息和解决建议
5. **灵活使用**: 支持命令行参数和默认配置

现在您可以安全地运行训练，脚本会自动处理环境检查！
