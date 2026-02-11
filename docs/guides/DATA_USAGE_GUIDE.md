# 📊 CAMELS 数据使用指南 (跨项目复用)

**创建日期**: 2025-12-21  
**数据检查日期**: 2025-12-21  
**适用项目**: NeuralHydrology 及衍生项目  
**维护者**: 水文深度学习团队

---

## 目录
1. [CAMELS-US 日尺度 (531 Basins)](#1-camels-us-日尺度-531-basins---成功基线)
2. [CAMELS-H 小时尺度](#2-camels-h-小时尺度-camelsh)
3. [Caravan 全球数据集](#3-caravan-全球数据集)
4. [Nam Ou Kuwei 自定义数据集](#4-nam-ou-kuwei-自定义数据集)
5. [跨项目复用建议](#5-跨项目复用建议)
6. [变量映射表](#6-变量映射表)

---

## 1. CAMELS-US 日尺度 (531 Basins) - 成功基线

### 1.1 基本信息

| 项目 | 配置值 |
|------|--------|
| **数据集类型** | `camels_us` |
| **数据路径** | `data/camels_us/full` |
| **驱动产品** | `daymet` |
| **流域数量** | 531 |
| **时间分辨率** | 日尺度 (Daily) |
| **数据来源** | [CAMELS](https://ral.ucar.edu/solutions/products/camels) |

### 1.2 动态输入特征 (5 个)

```yaml
dynamic_inputs:
  - prcp(mm/day)      # 日降水量
  - srad(W/m2)        # 太阳短波辐射
  - tmax(C)           # 日最高温度
  - tmin(C)           # 日最低温度
  - vp(Pa)            # 水汽压
```

**说明**：这是 Daymet 驱动数据的标准变量集，已在多个研究中验证有效。

### 1.3 静态属性 (14 个)

```yaml
static_attributes:
  # 地形特征 (3个)
  - elev_mean           # 平均高程 (m)
  - slope_mean          # 平均坡度 (m/km)
  - area_gages2         # 流域面积 (km²)
  
  # 土壤特征 (4个)
  - soil_depth_pelletier # 土壤深度 (m)
  - soil_porosity       # 土壤孔隙率 (-)
  - sand_frac           # 砂粒比例 (%)
  - clay_frac           # 黏土比例 (%)
  
  # 植被特征 (3个)
  - frac_forest         # 森林覆盖率 (%)
  - lai_max             # 最大叶面积指数 (-)
  - gvf_max             # 最大绿色植被覆盖度 (-)
  
  # 气候特征 (4个)
  - p_mean              # 年均降水 (mm/day)
  - aridity             # 干旱指数 PET/P (-)
  - frac_snow           # 降雪比例 (%)
  - high_prec_freq      # 高降水事件频率 (days/year)
```

**来源文件**: `data/camels_us/camels_attributes_v2.0/` 下的各属性文件

### 1.4 目标变量

```yaml
target_variables:
  - QObs(mm/d)          # 观测径流深 (mm/day)

clip_targets_to_zero:
  - QObs(mm/d)          # 将负值裁剪为0
```

### 1.5 时间划分 (标准方案)

| 阶段 | 开始日期 | 结束日期 | 时长 | 说明 |
|------|----------|----------|------|------|
| **训练** | 1990-10-01 | 1995-09-30 | 5 年 | 水文年起止 |
| **验证** | 1995-10-01 | 2000-09-30 | 5 年 | 超参数调优 |
| **测试** | 2000-10-01 | 2005-09-30 | 5 年 | 最终评估 |

**注意**: 日期格式为 `DD/MM/YYYY`（NeuralHydrology 默认格式）

### 1.6 模型超参数 (推荐配置)

```yaml
# 模型架构
model: cudalstm         # 或 gru
hidden_size: 128
head: regression
output_activation: linear
output_dropout: 0.0
initial_forget_bias: 3  # LSTM 专用

# 序列设置
seq_length: 365         # 1年历史数据
predict_last_n: 1       # 预测最后1步

# 训练设置
batch_size: 256
epochs: 30
optimizer: AdamW
loss: NSE
clip_gradient_norm: 1.0

# 学习率调度
learning_rate:
  0: 0.003              # 初始学习率
  10: 0.001             # Epoch 10 降低
  20: 0.0005            # Epoch 20 降低

# 验证设置
validate_every: 2
validate_n_random_basins: 50

# 日志设置
num_workers: 0          # Windows 建议设为 0
log_interval: 10
save_weights_every: 5
```

### 1.7 性能基准

| 模型 | Best Val NSE | Test Median NSE | Test Mean NSE | NSE≥0.7 | NSE<0.5 |
|------|--------------|-----------------|---------------|---------|---------|
| **CUDA-LSTM** | 0.735 | **0.725** | 0.650 | **56.5%** | 14.9% |
| GRU | 0.743 | 0.681 | 0.570 | 45.0% | 22.4% |
| Multihead | 0.708 | 0.679 | 0.548 | 42.0% | 19.8% |
| Transformer | 0.691 | - | - | - | - |

**结论**: CUDA-LSTM 是日尺度流量模拟的最稳健选择。

---

## 2. CAMELS-H 小时尺度 (Camelsh)

### 2.1 基本信息

| 项目 | 配置值 |
|------|--------|
| **数据集类型** | `generic` |
| **数据路径** | `data/camelsh` |
| **流域数量** | 455 (可用) |
| **时间分辨率** | 小时级 (Hourly) |

### 2.2 动态输入特征 (9 个)

```yaml
dynamic_inputs:
  - Rainf               # 降水率 (kg/m²/s)
  - Tair                # 气温 (K)
  - SWdown              # 向下短波辐射 (W/m²)
  - LWdown              # 向下长波辐射 (W/m²)
  - Qair                # 比湿 (kg/kg)
  - PSurf               # 地表气压 (Pa)
  - Wind_E              # 东向风速 (m/s)
  - Wind_N              # 北向风速 (m/s)
  - PotEvap             # 潜在蒸发 (kg/m²/s)
```

### 2.3 静态属性 (13 个)

```yaml
static_attributes:
  - elev_mean           # 平均高程
  - slope_mean          # 平均坡度
  - area                # 流域面积
  - clay_frac           # 黏土比例
  - sand_frac           # 砂粒比例
  - soil_porosity       # 土壤孔隙率
  - permeability        # 渗透率
  - frac_forest         # 森林覆盖率
  - p_mean              # 年均降水
  - pet_mean            # 年均潜在蒸发
  - aridity             # 干旱指数
  - frac_snow           # 降雪比例
  - high_prec_freq      # 高降水频率
```

### 2.4 目标变量

```yaml
target_variables:
  - Streamflow          # 流量 (m³/s 或标准化值)
```

### 2.5 时间划分

| 阶段 | 开始日期 | 结束日期 |
|------|----------|----------|
| **训练** | 2010-01-01 | 2014-12-31 |
| **验证** | 2015-01-01 | 2017-12-31 |
| **测试** | 2018-01-01 | 2020-12-31 |

### 2.6 推荐超参数

```yaml
seq_length: 168         # 7天 (168小时)
# 或 336 (14天) 用于更长记忆
hidden_size: 128
batch_size: 256
```

---

## 3. Caravan 全球数据集

### 3.1 数据可用性

| 子数据集 | 地区 | 流域数 | 属性 | 时间序列 | 状态 |
|----------|------|--------|------|----------|------|
| **camels** | 美国 | 531 | ✅ | ✅ | 可用 (Benchmark Basins) |
| **camelsaus** | 澳大利亚 | 561 | ✅ | ✅ | 可用 |
| **camelsbr** | 巴西 | 870 | ✅ | ✅ | 可用 |
| **camelscl** | 智利 | 505 | ✅ | ✅ | 可用 |
| **camelsgb** | 英国 | 671 | ✅ | ✅ | 可用 |
| **hysets** | 加拿大/北美 | 4225 | ✅ | ✅ | 可用 |
| **lamah** | 中欧 | 859 | ✅ | ✅ | 可用 |

> **总计**: 8,362 个流域 (更新于 2025-12-21)

**数据路径**: `data/Caravan/`

### 3.2 动态变量 (Caravan 标准)

```yaml
dynamic_inputs:
  # 降水与温度 (核心)
  - total_precipitation_sum           # 降水总量 (mm)
  - temperature_2m_mean               # 平均气温 (K)
  - temperature_2m_max                # 最高气温 (K)
  - temperature_2m_min                # 最低气温 (K)
  
  # 蒸发与辐射
  - potential_evaporation_sum_ERA5_LAND  # 潜在蒸发 (mm)
  - surface_net_solar_radiation_mean     # 净太阳辐射 (J/m²)
  
  # 其他气象
  - surface_pressure_mean                # 平均气压 (Pa)
  - snow_depth_water_equivalent_mean     # 雪水当量 (m)
  - dewpoint_temperature_2m_mean         # 露点温度 (K)
  
  # 土壤水分 (可选)
  - volumetric_soil_water_layer_1_mean   # 表层土壤水分

target_variables:
  - streamflow                           # 流量
```

### 3.3 静态属性 (Caravan 标准)

```yaml
static_attributes:
  # 气候属性 (attributes_caravan_*.csv)
  - aridity_ERA5_LAND          # 干旱指数
  - frac_snow                  # 降雪比例
  - high_prec_freq             # 高降水频率
  - low_prec_freq              # 低降水频率
  - p_mean                     # 年均降水
  - pet_mean_ERA5_LAND         # 年均潜在蒸发
  - moisture_index_ERA5_LAND   # 湿润指数
  - seasonality_ERA5_LAND      # 季节性指数
  
  # HydroATLAS 属性 (attributes_hydroatlas_*.csv)
  # ... 更多地形、土壤属性
```

### 3.4 配置示例

```yaml
experiment_name: caravan_global_daily

dataset: caravan
data_dir: data/Caravan

dynamic_inputs:
  - total_precipitation_sum
  - temperature_2m_mean
  - temperature_2m_max
  - temperature_2m_min
  - potential_evaporation_sum_ERA5_LAND
  - surface_net_solar_radiation_mean

static_attributes:
  - aridity_ERA5_LAND
  - frac_snow
  - p_mean
  - pet_mean_ERA5_LAND

target_variables:
  - streamflow
```

---

## 4. Nam Ou Kuwei 自定义数据集

### 4.1 基本信息

| 项目 | 配置值 |
|------|--------|
| **数据集类型** | `generic` |
| **数据路径** | `data/namou_kuwei_hourly` |
| **流域数量** | 1 (单站点预报) |
| **时间分辨率** | 小时级 |

### 4.2 动态输入 (含自回归)

```yaml
dynamic_inputs:
  # 多站雨量
  - p_aka
  - p_bandang
  - p_banpozai
  - p_banteng
  - p_kuwei
  - p_mengwu
  - p_xiaolishu
  - p_xinzai
  
  # 观测数据 (可用于自回归)
  - qobs                # 观测流量
  - stage_kuwei         # 水位

# 自回归配置 (AR-LSTM)
autoregressive_inputs:
  - qobs_shift1         # 1小时滞后流量 (用于 1h 预报)
  - qobs_shift24        # 24小时滞后流量 (用于 24h 预报)

lagged_features:
  qobs: [1]             # 或 [24] 取决于预报时效
```

### 4.3 静态属性

```yaml
static_attributes:
  - area                # 流域面积
  - elev_mean           # 平均高程
  - slope_mean          # 平均坡度
```

### 4.4 最佳结果

| 预报时效 | 模型 | 配置 | Test NSE | Test KGE |
|----------|------|------|----------|----------|
| **1小时** | AR-LSTM | L3_Rain_AR_LT1h | **0.975** | 0.885 |
| **24小时** | AR-LSTM | L5_Rain_AR_LT24h | **0.735** | - |
| **24小时** | Seq2Seq | L6_Seq2Seq_AR24lag | 0.730 | - |

### 4.5 关键超参数

```yaml
model: arlstm           # 或 cudalstm
hidden_size: 64
seq_length: 168         # 7天
epochs: 60
seed: 2025
```

---

## 5. 跨项目复用建议

### 5.1 日尺度基准任务

直接复用 **CAMELS-US 531** 配置：
- 动态输入: 5 个 Daymet 变量
- 静态属性: 14 个标准属性
- 模型: CUDA-LSTM, hidden_size=128, seq_length=365

### 5.2 小时尺度任务

使用 **CAMELS-H** 或 **generic** 数据集：
- seq_length 调整为 168-336 (7-14 天)
- 增加气象变量 (辐射、风速、湿度等)

### 5.3 全球/多区域扩展

使用 **Caravan** 数据集：
- 变量名与 CAMELS-US 不同，需映射 (见下表)
- 可组合多个子数据集训练全球模型

### 5.4 实时预报任务

使用 **AR-LSTM** 模型 + 自回归输入：
- 添加 `autoregressive_inputs` 配置
- 预报提前量决定 lagged_features 的 shift 值

---

## 6. 变量映射表

### 动态变量映射

| 含义 | CAMELS-US (Daymet) | Caravan | CAMELS-H |
|------|-------------------|---------|----------|
| 降水 | `prcp(mm/day)` | `total_precipitation_sum` | `Rainf` |
| 最高温 | `tmax(C)` | `temperature_2m_max` | - |
| 最低温 | `tmin(C)` | `temperature_2m_min` | - |
| 平均温 | - | `temperature_2m_mean` | `Tair` |
| 太阳辐射 | `srad(W/m2)` | `surface_net_solar_radiation_mean` | `SWdown` |
| 水汽压 | `vp(Pa)` | - | - |
| 潜在蒸发 | - | `potential_evaporation_sum_ERA5_LAND` | `PotEvap` |
| 流量目标 | `QObs(mm/d)` | `streamflow` | `Streamflow` |

### 静态属性映射

| 含义 | CAMELS-US | Caravan | CAMELS-H |
|------|-----------|---------|----------|
| 流域面积 | `area_gages2` | (HydroATLAS) | `area` |
| 平均高程 | `elev_mean` | (HydroATLAS) | `elev_mean` |
| 平均坡度 | `slope_mean` | (HydroATLAS) | `slope_mean` |
| 干旱指数 | `aridity` | `aridity_ERA5_LAND` | `aridity` |
| 年均降水 | `p_mean` | `p_mean` | `p_mean` |
| 降雪比例 | `frac_snow` | `frac_snow` | `frac_snow` |
| 森林覆盖 | `frac_forest` | (HydroATLAS) | `frac_forest` |

---

## 附录: 完整配置模板

### A. CAMELS-US 日尺度模板

```yaml
# configs/templates/camels_us_daily_template.yml
experiment_name: my_experiment

# 数据配置
dataset: camels_us
data_dir: data/camels_us/full
forcings:
  - daymet

# 流域文件
train_basin_file: examples/06-Finetuning/531_basin_list.txt
validation_basin_file: examples/06-Finetuning/531_basin_list.txt
test_basin_file: examples/06-Finetuning/531_basin_list.txt

# 时间划分
train_start_date: "01/10/1990"
train_end_date: "30/09/1995"
validation_start_date: "01/10/1995"
validation_end_date: "30/09/2000"
test_start_date: "01/10/2000"
test_end_date: "30/09/2005"

# 输入输出
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
clip_targets_to_zero:
  - QObs(mm/d)

# 模型配置
model: cudalstm
hidden_size: 128
head: regression
output_activation: linear
output_dropout: 0.0

# 序列配置
seq_length: 365
predict_last_n: 1

# 训练配置
epochs: 30
batch_size: 256
optimizer: AdamW
loss: NSE
clip_gradient_norm: 1.0
learning_rate:
  0: 0.003
  10: 0.001
  20: 0.0005

# 验证与日志
validate_every: 2
validate_n_random_basins: 50
num_workers: 0
log_interval: 10
save_weights_every: 5
metrics:
  - NSE
```

---

[返回项目总览](PROJECTS_OVERVIEW.md)

