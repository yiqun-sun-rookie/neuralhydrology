# 训练总结报告：531流域 + 静态属性

**实验名称**: `full_531_temporal_with_static`  
**训练日期**: 2025-11-27 ~ 2025-11-28  
**运行时间**: 约 10.8 小时  

---

## 1. 数据泄露检查 ✅ 无泄露

### 1.1 时间划分（Temporal Split）

| 数据集 | 时间范围 | 长度 |
|--------|----------|------|
| **训练集** | 1990-10-01 ~ 1995-09-30 | 5 年 |
| **验证集** | 1995-10-01 ~ 2000-09-30 | 5 年 |
| **测试集** | 2000-10-01 ~ 2005-09-30 | 5 年 |

**结论**: ✅ **无时间重叠**，训练/验证/测试时间段完全分离。

### 1.2 流域划分

- **训练流域**: 531 个
- **验证流域**: 531 个（与训练集相同）
- **测试流域**: 531 个（与训练集相同）

**说明**: 这是 **Temporal Split**（时间划分）策略，所有流域都用于训练和评估，但时间段不同。这是标准的做法，**不构成数据泄露**。

### 1.3 归一化

- **动态输入**: 全局 Z-score（在训练集上计算 mean/std）
- **静态属性**: 全局 Z-score（在训练集上计算 mean/std）
- **目标变量**: 全局 Z-score

**结论**: ✅ 归一化统计量仅在训练集上计算，验证/测试时使用训练集的统计量。

---

## 2. 数据配置

### 2.1 数据集

- **数据集**: CAMELS US
- **流域数量**: 531 个（Kratzert et al., 2019 基准流域）
- **数据来源**: `src/full_531_basins/data/531_basin_list.txt`

### 2.2 动态输入（5 个变量）

| 变量名 | 描述 | 单位 | 来源 |
|--------|------|------|------|
| `prcp(mm/day)` | 日降水量 | mm/day | Daymet |
| `srad(W/m2)` | 短波辐射 | W/m² | Daymet |
| `tmax(C)` | 日最高温度 | °C | Daymet |
| `tmin(C)` | 日最低温度 | °C | Daymet |
| `vp(Pa)` | 水汽压 | Pa | Daymet |

### 2.3 静态属性（14 个变量）

| 类别 | 变量名 | 描述 | 单位 |
|------|--------|------|------|
| **地形** | `elev_mean` | 平均高程 | m |
| | `slope_mean` | 平均坡度 | m/km |
| | `area_gages2` | 流域面积 | km² |
| **土壤** | `soil_depth_pelletier` | 土壤深度 | m |
| | `soil_porosity` | 土壤孔隙度 | - |
| | `sand_frac` | 砂土比例 | % |
| | `clay_frac` | 黏土比例 | % |
| **植被** | `frac_forest` | 森林覆盖率 | - |
| | `lai_max` | 最大叶面积指数 | - |
| | `gvf_max` | 最大绿色植被覆盖 | - |
| **气候** | `p_mean` | 平均降水 | mm/day |
| | `aridity` | 干旱指数 (PET/P) | - |
| | `frac_snow` | 降雪比例 | - |
| | `high_prec_freq` | 高降水频率 | days/year |

### 2.4 目标变量

| 变量名 | 描述 | 单位 |
|--------|------|------|
| `QObs(mm/d)` | 观测径流 | mm/day |

---

## 3. 模型结构

### 3.1 整体架构

```
输入层 (InputLayer)
    ├── 动态输入: [batch, seq_len, 5] → 直接传递（无嵌入）
    ├── 静态属性: [batch, 14] → 直接传递（无嵌入）
    └── 拼接: 静态属性在每个时间步重复并与动态输入拼接
         → [seq_len, batch, 5 + 14 = 19]

LSTM 层
    ├── 输入维度: 19
    ├── 隐藏层维度: 128
    ├── 层数: 1
    └── 输出: [batch, seq_len, 128]

Dropout 层
    └── dropout rate: 0.0（无 dropout）

回归头 (Regression Head)
    ├── 输入: 128
    ├── 输出: 1（QObs）
    └── 激活函数: linear
```

### 3.2 静态属性如何融入模型

```python
# InputLayer.forward() 中的关键逻辑：
if statics_out is not None:
    # 将静态属性在时间维度上重复
    statics_out = statics_out.unsqueeze(0).repeat(seq_len, 1, 1)
    # 与动态输入拼接
    ret_val = torch.cat([dynamics_out, statics_out], dim=-1)
```

**解释**: 静态属性（14维）在每个时间步都与动态输入（5维）拼接，形成19维的输入向量。这样 LSTM 在处理每个时间步时都能"看到"流域的静态特征。

### 3.3 模型参数

| 参数 | 值 |
|------|-----|
| 隐藏层大小 | 128 |
| 初始遗忘门偏置 | 3 |
| 输出 Dropout | 0.0 |
| 输出激活函数 | linear |
| 序列长度 | 365 天 |
| 预测最后 N 步 | 1 |

---

## 4. 训练配置

### 4.1 优化器

| 参数 | 值 |
|------|-----|
| 优化器 | AdamW |
| 批次大小 | 256 |
| 梯度裁剪 | 1.0 |

### 4.2 学习率调度

| Epoch | 学习率 |
|-------|--------|
| 0-9 | 0.003 |
| 10-19 | 0.001 |
| 20-29 | 0.0005 |

### 4.3 损失函数

**NSE Loss (Nash-Sutcliffe Efficiency)**

```
NSE = 1 - Σ(obs - pred)² / Σ(obs - mean(obs))²
```

训练时使用的是 **per-basin weighted NSE**，每个流域的权重与其目标变量的标准差成反比，以平衡不同流域的贡献。

---

## 5. 训练结果

### 5.1 验证集性能

| Epoch | Validation Loss | Median NSE | 备注 |
|-------|-----------------|------------|------|
| 2 | 0.02186 | 0.644 | 起步 |
| 4 | 0.01974 | **0.727** | 快速提升 |
| 6 | 0.02030 | 0.693 | |
| 8 | 0.01859 | 0.710 | |
| 10 | 0.01933 | 0.744 | 学习率降低 |
| 12 | 0.01868 | 0.724 | |
| 14 | 0.01903 | 0.697 | |
| 16 | 0.01706 | 0.719 | |
| 18 | 0.02250 | 0.708 | |
| 20 | 0.01965 | 0.729 | 学习率再次降低 |
| **22** | **0.01650** | **0.747** | 🏆 **最佳** |
| 24 | 0.02003 | 0.700 | |
| 26 | 0.02038 | 0.639 | 开始过拟合 |
| 28 | 0.02111 | 0.689 | |
| 30 | 0.02226 | 0.674 | 结束 |

### 5.2 与无静态属性的对比

| 配置 | 最佳 Median NSE | 最佳 Epoch | 相对提升 |
|------|-----------------|------------|----------|
| **带静态属性** | **0.747** | 22 | **+21.5%** |
| 无静态属性 (baseline) | 0.615 | 8 | - |

### 5.3 训练 Loss 变化

| Epoch | Training Loss |
|-------|---------------|
| 1 | 0.02990 |
| 5 | 0.01787 |
| 10 | 0.01264 |
| 15 | 0.01055 |
| 20 | 0.00858 |
| 25 | 0.00765 |
| 30 | 0.00722 |

---

## 6. 保存的模型

| 文件 | Epoch | 验证 NSE |
|------|-------|----------|
| `model_epoch005.pt` | 5 | - |
| `model_epoch010.pt` | 10 | 0.744 |
| `model_epoch015.pt` | 15 | - |
| `model_epoch020.pt` | 20 | 0.729 |
| `model_epoch025.pt` | 25 | - |
| `model_epoch030.pt` | 30 | 0.674 |

**推荐使用**: `model_epoch010.pt` 或重新训练到 epoch 22 并保存。

---

## 7. 结论与建议

### 7.1 关键发现

1. **静态属性效果显著**: NSE 从 0.615 提升到 0.747，**提升 21.5%**
2. **收敛更快**: 有静态属性时 Epoch 2 就达到 0.644（无静态属性 Epoch 2 只有 0.497）
3. **后期过拟合**: Epoch 22 后验证 NSE 开始下降

### 7.2 建议

1. **Early Stopping**: 建议在 Epoch 22 左右停止训练
2. **模型选择**: 使用 Epoch 10 或 Epoch 22 的模型
3. **进一步优化**:
   - 尝试更多静态属性
   - 尝试静态属性嵌入网络
   - 尝试更大的隐藏层（256）

---

## 8. 配置文件

```yaml
# src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml

experiment_name: full_531_temporal_with_static
dataset: camels_us
model: cudalstm
hidden_size: 128
epochs: 30
batch_size: 256
optimizer: AdamW
loss: NSE

learning_rate:
  0: 0.003
  10: 0.001
  20: 0.0005

train_start_date: 01/10/1990
train_end_date: 30/09/1995
validation_start_date: 01/10/1995
validation_end_date: 30/09/2000
test_start_date: 01/10/2000
test_end_date: 30/09/2005

dynamic_inputs:
  - prcp(mm/day)
  - srad(W/m2)
  - tmax(C)
  - tmin(C)
  - vp(Pa)

static_attributes:
  - elev_mean
  - slope_mean
  - area_gages2
  - soil_depth_pelletier
  - soil_porosity
  - sand_frac
  - clay_frac
  - frac_forest
  - lai_max
  - gvf_max
  - p_mean
  - aridity
  - frac_snow
  - high_prec_freq

target_variables:
  - QObs(mm/d)

seq_length: 365
seed: 159193
```

---

## 9. 运行目录

```
runs/full_531_temporal_with_static_2025_1127_2057_ep30/
├── config.yml                    # 配置文件副本
├── output.log                    # 训练日志
├── events.out.tfevents.*         # TensorBoard 日志
├── model_epoch*.pt               # 模型权重
├── optimizer_state_epoch*.pt     # 优化器状态
├── train_data/                   # 训练数据缓存
│   ├── train_data_scaler.yml     # 归一化参数
│   └── ...
└── img_log/                      # 可视化图片
    └── QObsmmd_freq1D_epoch*.png
```

---

**报告生成时间**: 2025-11-28


