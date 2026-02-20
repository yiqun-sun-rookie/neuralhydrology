# Nam Ou 库尾站 - 配置文件参考

> 本文档详细说明各配置文件的用途和参数设置

---

## 1. 配置文件清单

### 1.1 hierarchy/ - 特征层级实验（9个）

| 配置文件 | 动态特征 | 静态属性 | predict_last_n |
|----------|----------|----------|----------------|
| S1_Rain.yml | 仅雨量 (8站) | ❌ | 1 |
| S2_Rain_AR.yml | 雨量 + qobs | ❌ | 1 |
| S3_Rain_Static.yml | 仅雨量 | ✅ | 1 |
| **S4_Rain_AR_Static.yml** | 雨量 + qobs | ✅ | 1 |
| S4_Seq2Seq.yml | 雨量 + qobs | ✅ | 24 |
| S5_Rain_AR_Downstream.yml | 雨量 + qobs + stage_baqian | ❌ | 1 |
| S6_Rain_AR_Downstream_Static.yml | 雨量 + qobs + stage_baqian | ✅ | 1 |
| S6_Seq2Seq.yml | 雨量 + qobs + stage_baqian | ✅ | 24 |
| F4_Upstream_AR_Static.yml | 仅上游4站 + qobs | ✅ | 1 |

### 1.2 leadtime/ - 多提前量实验（4个）

基于 S4 配置，仅修改 `predict_last_n`：

| 配置文件 | predict_last_n | 预报时效 |
|----------|----------------|----------|
| S4_LT6h.yml | 6 | 6小时 |
| S4_LT12h.yml | 12 | 12小时 |
| S4_LT24h.yml | 24 | 24小时 |
| S4_LT48h.yml | 48 | 48小时 |

### 1.3 model_leadtime/ - 模型×提前量对比（20个）

4种模型 × 5种提前量：

| 模型 | 配置前缀 | 提前量选项 |
|------|----------|------------|
| LSTM | S4_LSTM_LT* | 1h, 6h, 12h, 24h, 48h |
| GRU | S4_GRU_LT* | 1h, 6h, 12h, 24h, 48h |
| EALSTM | S4_EALSTM_LT* | 1h, 6h, 12h, 24h, 48h |
| Transformer | S4_Transformer_LT* | 1h, 6h, 12h, 24h, 48h |

---

## 2. 通用配置说明

### 2.1 数据路径

```yaml
data_dir: F:/github/pycharm/projects/neuralhydrology/data/namou_kuwei/hourly
train_basin_file: F:/github/pycharm/projects/neuralhydrology/data/namou_kuwei/hourly/train_basins.txt
validation_basin_file: F:/github/pycharm/projects/neuralhydrology/data/namou_kuwei/hourly/validation_basins.txt
test_basin_file: F:/github/pycharm/projects/neuralhydrology/data/namou_kuwei/hourly/test_basins.txt
```

### 2.2 时间划分

```yaml
train_start_date: "01/01/2020"
train_end_date: "31/12/2022"
validation_start_date: "01/01/2023"
validation_end_date: "31/12/2023"
test_start_date: "01/01/2023"
test_end_date: "31/12/2023"
```

### 2.3 模型配置

```yaml
model: cudalstm         # 模型架构
head: regression        # 输出头
hidden_size: 64         # 隐藏层大小
initial_forget_bias: 3  # 遗忘门偏置
```

### 2.4 训练配置

```yaml
optimizer: Adam
loss: NSE
learning_rate:
  0: 0.001    # 初始学习率
  30: 0.0005  # 30 epoch 后
  60: 0.0001  # 60 epoch 后
batch_size: 256
epochs: 60
clip_gradient_norm: 1.0
validate_every: 5
save_weights_every: 5
seed: 2025
device: cpu
```

### 2.5 序列配置

```yaml
seq_length: 168      # 历史窗口（7天 = 168小时）
predict_last_n: 1    # 预测提前量（1=1小时）
```

---

## 3. 特征说明

### 3.1 动态特征

**雨量站（8个）**：
```yaml
dynamic_inputs:
  - p_aka       # 阿卡站
  - p_bandang   # 班当站
  - p_banpozai  # 半坡寨站
  - p_banteng   # 班腾站
  - p_kuwei     # 库尾站本地
  - p_mengwu    # 孟乌站
  - p_xiaolishu # 小栗树站
  - p_xinzai    # 新寨站
```

**自回归特征**：
```yaml
  - qobs        # 历史流量
  - stage_kuwei # 历史水位（部分配置）
```

**下游信息**：
```yaml
  - stage_baqian  # 坝前水位（S5/S6使用）
```

### 3.2 静态属性

```yaml
static_attributes:
  - area        # 流域面积 (km²)
  - elev_mean   # 平均高程 (m)
  - slope_mean  # 平均坡度 (°)
```

### 3.3 目标变量

```yaml
target_variables:
  - qobs        # 观测流量 (m³/s)
```

### 3.4 评估指标

```yaml
metrics:
  - NSE         # 纳什效率系数
  - KGE         # 克林-古普塔效率
  - RMSE        # 均方根误差
  - Peak-MAPE   # 峰值平均绝对百分比误差
```

---

## 4. 模型架构说明

### 4.1 LSTM (cudalstm)

标准 LSTM，NeuralHydrology 默认模型：
```yaml
model: cudalstm
hidden_size: 64
```

### 4.2 GRU

简化门控结构，训练更快：
```yaml
model: gru
hidden_size: 64
```

### 4.3 EALSTM

Entity-Aware LSTM，专为水文设计：
```yaml
model: ealstm
hidden_size: 64
```

### 4.4 Transformer

基于注意力机制：
```yaml
model: transformer
hidden_size: 64
num_layers: 2
num_heads: 4
```

---

## 5. 配置修改指南

### 5.1 修改提前量

```yaml
# 从 1h 改为 12h
predict_last_n: 12
```

### 5.2 修改模型架构

```yaml
# 从 LSTM 改为 GRU
model: gru
```

### 5.3 修改训练参数

```yaml
# 增加训练轮数
epochs: 100

# 增加隐藏层大小
hidden_size: 128

# 修改学习率调度
learning_rate:
  0: 0.0005
  50: 0.0001
```

### 5.4 使用 GPU

```yaml
# 从 CPU 改为 GPU
device: cuda:0
```

---

## 6. 注意事项

### 6.1 路径问题

配置文件中使用绝对路径，如需在其他机器运行，需修改：
- `run_dir`
- `data_dir`
- `*_basin_file`

### 6.2 设备兼容

当前默认 `device: cpu`，GPU 训练需：
1. 安装 CUDA 版 PyTorch
2. 修改 `device: cuda:0`

### 6.3 下游数据

S5/S6 实验使用 `data/namou_kuwei/hourly_downstream/` 数据集，包含坝前水位。

---

> 更新日期: 2025-11-28


