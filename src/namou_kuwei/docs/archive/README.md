# Nam Ou 库尾站深度学习预报项目

> **迁移日期**: 2025-11-28  
> **来源项目**: `laos_forecast/_archive/experiments/namou_kuwei_dl/`  
> **主项目**: `neuralhydrology`

---

## 1. 项目概述

### 1.1 预报目标

| 项目 | 值 |
|------|-----|
| **预报对象** | 老挝南乌江（Nam Ou）七级电站库尾站 |
| **预报变量** | 逐小时流量 (m³/s) |
| **预报时效** | 1h ~ 48h（多提前量） |
| **精度目标** | NSE > 0.6（基准），NSE > 0.8（目标） |

### 1.2 流域基本信息

| 项目 | 值 |
|------|-----|
| 流域面积 | 1796.46 km² |
| 时间范围 | 2020-01-01 ~ 2024-12-31（5年） |
| 时间步长 | 1 小时 |
| 上游雨量站 | 孟乌、班腾、阿卡、库尾（本地） |
| 下游雨量站 | 班当、半坡寨、小栗树、新寨 |

---

## 2. 配置文件结构

所有配置文件位于 `configs/namou_kuwei/`：

```
configs/namou_kuwei/
├── hierarchy/              # 特征层级实验（9个配置）
│   ├── S1_Rain.yml         # 仅雨量（基准）
│   ├── S2_Rain_AR.yml      # 雨量 + 历史流量
│   ├── S3_Rain_Static.yml  # 雨量 + 静态属性
│   ├── S4_Rain_AR_Static.yml       # ★ 雨量 + AR + 静态（最佳）
│   ├── S4_Seq2Seq.yml      # S4 的 Seq2Seq 版本
│   ├── S5_Rain_AR_Downstream.yml   # 雨量 + AR + 下游水位
│   ├── S6_Rain_AR_Downstream_Static.yml  # 全要素融合
│   ├── S6_Seq2Seq.yml      # S6 的 Seq2Seq 版本
│   └── F4_Upstream_AR_Static.yml   # 仅上游雨量站
├── leadtime/               # 多提前量实验（4个配置）
│   ├── S4_LT6h.yml         # 6小时提前量
│   ├── S4_LT12h.yml        # 12小时提前量
│   ├── S4_LT24h.yml        # 24小时提前量
│   └── S4_LT48h.yml        # 48小时提前量
└── model_leadtime/         # 模型×提前量对比（20个配置）
    ├── S4_LSTM_LT*.yml     # LSTM 系列（1h/6h/12h/24h/48h）
    ├── S4_GRU_LT*.yml      # GRU 系列
    ├── S4_EALSTM_LT*.yml   # EALSTM 系列
    └── S4_Transformer_LT*.yml  # Transformer 系列
```

---

## 3. 实验设计

### 3.1 特征层级实验（信息阶梯）

设计目的：量化不同信息源对预报精度的贡献

| 编号 | 名称 | 输入特征 | 验证 NSE | 测试 NSE |
|------|------|----------|----------|----------|
| S1 | Rain | 仅雨量 | 0.37 | ~0.00 |
| S2 | Rain_AR | 雨量 + 历史流量/水位 | **0.874** | 0.49 |
| S3 | Rain_Static | 雨量 + 静态属性 | 0.37 | 0.004 |
| **S4** | **Rain_AR_Static** | 雨量 + AR + 静态 | **0.996** | **0.53** |
| S5 | Rain_AR_Downstream | 雨量 + AR + 下游水位 | - | - |
| S6 | Rain_AR_Downstream_Static | 全要素融合 | - | - |

**关键发现**：
1. 自回归特征（历史流量）至关重要，S2/S4 显著优于 S1/S3
2. 静态属性在单流域场景下贡献有限
3. 12h 滞后相关性最优，48h 累积降雨相关性最高（r ≈ 0.32）

### 3.2 多提前量实验

基于 S4 配置，测试不同预报时效：

| 提前量 | 配置文件 | predict_last_n |
|--------|----------|----------------|
| 1h | S4_Rain_AR_Static.yml | 1 |
| 6h | S4_LT6h.yml | 6 |
| 12h | S4_LT12h.yml | 12 |
| 24h | S4_LT24h.yml | 24 |
| 48h | S4_LT48h.yml | 48 |

### 3.3 模型架构对比

在 S4 配置基础上，对比 4 种模型架构 × 5 种提前量 = 20 组实验：

| 模型 | 特点 |
|------|------|
| LSTM | 标准 LSTM，基准模型 |
| GRU | 简化门控，训练更快 |
| EALSTM | Entity-Aware LSTM，专为水文设计 |
| Transformer | 注意力机制，捕捉长程依赖 |

---

## 4. 数据说明

### 4.1 数据位置

```
data/namou_kuwei_hourly/
├── basins.txt                  # 流域列表
├── train_basins.txt            # 训练流域
├── validation_basins.txt       # 验证流域
├── test_basins.txt             # 测试流域
├── attributes/
│   └── attributes.csv          # 静态属性（面积、高程、坡度）
├── time_series/
│   ├── namou_kuwei.csv         # 主时间序列
│   └── namou_kuwei.nc          # NetCDF 格式
└── manifest.json               # 数据清单
```

### 4.2 动态特征

| 变量名 | 说明 | 单位 |
|--------|------|------|
| p_aka | 阿卡站降雨 | mm/h |
| p_bandang | 班当站降雨 | mm/h |
| p_banpozai | 半坡寨站降雨 | mm/h |
| p_banteng | 班腾站降雨 | mm/h |
| p_kuwei | 库尾站本地降雨 | mm/h |
| p_mengwu | 孟乌站降雨 | mm/h |
| p_xiaolishu | 小栗树站降雨 | mm/h |
| p_xinzai | 新寨站降雨 | mm/h |
| qobs | 观测流量（目标变量） | m³/s |
| stage_kuwei | 库尾站水位 | m |

### 4.3 静态属性

| 属性 | 说明 | 值 |
|------|------|-----|
| area | 流域面积 | 1796.46 km² |
| elev_mean | 平均高程 | ~1200 m |
| slope_mean | 平均坡度 | ~15° |

### 4.4 时间划分

| 时段 | 范围 | 用途 |
|------|------|------|
| 训练期 | 2020-01-01 ~ 2022-12-31 | 模型训练 |
| 验证期 | 2023-01-01 ~ 2023-12-31 | 超参数调优 |
| 测试期 | 2023-01-01 ~ 2023-12-31* | 最终评估 |

> *注：2024年数据存在录入错误，暂不使用

---

## 5. 训练结果

训练结果保存在 `runs/namou_kuwei/`：

```
runs/namou_kuwei/
├── S1_Rain_2025_1124_*/          # S1 实验
├── S2_Rain_AR_2025_1124_*/       # S2 实验（多次运行）
├── S3_Rain_Static_2025_1124_*/   # S3 实验
├── S4_Rain_AR_Static_2025_1124_*/# S4 实验 ★
├── S4_LT6h_2025_1126_*/          # 6h 提前量
├── S4_LT12h_2025_1126_*/         # 12h 提前量
├── S4_LT24h_2025_1127_*/         # 24h 提前量
├── S4_LT48h_2025_1127_*/         # 48h 提前量
├── S4_LSTM_LT*_2025_1126_*/      # LSTM 系列
├── S5_Rain_AR_Downstream_*/      # S5 实验
├── S6_Rain_AR_Downstream_Static_*/# S6 实验
└── ...
```

每个 run 目录包含：
- `config.yml` - 实际使用的配置
- `model_epoch*.pt` - 模型权重
- `output.log` - 训练日志
- `train_data/` - 训练数据缓存
- `validation/` / `test/` - 评估结果

---

## 6. 快速使用

### 6.1 训练新模型

```bash
cd F:\github\pycharm\projects\neuralhydrology

# 使用最佳配置 S4
python -m neuralhydrology.nh_run train \
    --config-file configs/namou_kuwei/hierarchy/S4_Rain_AR_Static.yml

# 多提前量实验
python -m neuralhydrology.nh_run train \
    --config-file configs/namou_kuwei/leadtime/S4_LT12h.yml
```

### 6.2 评估已有模型

```bash
# 评估验证期
python -m neuralhydrology.nh_run evaluate \
    --run-dir runs/namou_kuwei/S4_Rain_AR_Static_2025_1124_1835_ep60 \
    --period validation \
    --epoch 60

# 评估测试期
python -m neuralhydrology.nh_run evaluate \
    --run-dir runs/namou_kuwei/S4_Rain_AR_Static_2025_1124_1835_ep60 \
    --period test \
    --epoch 60
```

### 6.3 批量运行

```bash
# 批量运行 leadtime 实验
for config in configs/namou_kuwei/leadtime/*.yml; do
    python -m neuralhydrology.nh_run train --config-file $config
done
```

---

## 7. 技术说明

### 7.1 Perfect Rain 假设

当前配置属于"水文模拟验证"模式：
- **允许**：训练/预测时使用预报时段的观测降雨
- **禁止**：使用预报时段的观测流量/水位

这用于检验模型在已知降雨下的产汇流模拟能力。实际业务预报需替换为降雨预报产品。

### 7.2 模型配置说明

```yaml
# 通用配置
model: cudalstm
hidden_size: 64
seq_length: 168        # 7天历史窗口
predict_last_n: 1      # 预测提前量
batch_size: 256
epochs: 60

# 学习率调度
learning_rate:
  0: 0.001
  30: 0.0005
  60: 0.0001
```

### 7.3 已知问题与修复

1. **S2 评估 NaN 问题**（已修复）
   - 症状：评估时 qobs_sim 大量 NaN
   - 原因：warmup 阶段错误清空了 AR 特征
   - 修复：调整 `basedataset.py` 中的 warmup 处理逻辑

2. **单流域静态属性归一化**（已修复）
   - 症状：静态属性方差为零导致报错
   - 修复：增加 `allow_constant` 逻辑

---

## 8. 相关项目

| 项目 | 路径 | 职责 |
|------|------|------|
| **neuralhydrology** | 当前项目 | DL 模型训练与实验 |
| **forecast_system_lite** | `../forecast_system_lite` | FSL 传统模型率定 |
| **laos_forecast** | `../laos_forecast` | 数据处理与导出 |

---

## 9. 与 CAMELS 日步长方案对比分析

> 更新日期：2025-11-28  
> 参考：`cursor_.md` 中 CAMELS 531 流域日步长训练经验

### 9.1 关键差异对比

| 配置项 | CAMELS 日步长 (531流域) | Kuwei 小时步长 (单流域) | 备注 |
|--------|------------------------|------------------------|------|
| 时间步长 | 日 | 小时 | ✓ 合理 |
| seq_length | 365 (1年) | 168 (7天) | ✓ 等效历史窗口 |
| 流域数量 | 531 | 1 | ⚠️ 单流域数据有限 |
| 静态属性 | 14 个 | 3 个 | ✓ 单流域下作用有限 |
| 自回归输入 | 无 | qobs | ✅ **关键优势** |
| hidden_size | 128 | 64 | ✓ 单流域可小些 |
| 归一化 | custom_normalization | 默认 Z-score | ⚠️ 可优化 |

### 9.2 静态属性核实

**结论：kuwei 无静态属性遗漏问题**

- CAMELS 日步长曾遗漏 `static_attributes` 配置（详见 `cursor_.md`）
- kuwei 已正确配置所有可用属性：`area`, `elev_mean`, `slope_mean`
- 单流域场景下，静态属性仅提供常数输入，对泛化帮助有限

### 9.3 方案合理性评估

**✅ 合理的设计**：
1. 自回归特征 (qobs) 是核心，验证 NSE=0.996
2. 8 个分布式雨量站输入，捕捉空间降雨分布
3. seq_length=168h（7天）适合小时尺度响应
4. 支持 1h~48h 多提前量预报

**⚠️ 待改进项**：
1. Perfect Rain 假设：需替换为降雨预报产品
2. 归一化未定制：建议对降雨/流量使用 `centering: none`
3. 测试期泛化：训练期(2020-2022)与测试期(2023)分布差异大

---

## 10. 改进计划

### 10.1 短期（可直接实施）

- [x] ~~添加 `custom_normalization` 配置~~ ✅ 完成 (2025-11-29)
- [x] ~~修复时间划分（验证期≠测试期）~~ ✅ 完成 (2025-11-30)
- [ ] 修复 p_mengwu 2023年数据
- [ ] 补充 2024 年修正后的数据
- [ ] 完成 EALSTM/Transformer 模型对比

> 详细实验结果见 `docs/namou_kuwei/EXPERIMENT_RESULTS.md`

### 10.2 中期（需要额外数据）

- [ ] 集成 ERA5-Land PET 替换气候态估算
- [ ] 接入降雨预报产品（如 ECMWF）
- [ ] 扩展历史数据（如 2018-2019）

### 10.3 归一化配置建议

```yaml
# 推荐添加到配置文件
custom_normalization:
  p_aka:
    centering: none  # 保持零点
    scaling: std
  p_bandang:
    centering: none
    scaling: std
  p_banpozai:
    centering: none
    scaling: std
  p_banteng:
    centering: none
    scaling: std
  p_kuwei:
    centering: none
    scaling: std
  p_mengwu:
    centering: none
    scaling: std
  p_xiaolishu:
    centering: none
    scaling: std
  p_xinzai:
    centering: none
    scaling: std
  qobs:
    centering: none
    scaling: std
```

---

## 11. 历史记录

本项目从 `laos_forecast/_archive/experiments/namou_kuwei_dl/` 迁移而来，包含：

- 配置文件（33个）
- 数据集（已在 `data/namou_kuwei_hourly/`）
- 训练结果（已在 `runs/namou_kuwei/`）

迁移日期：2025-11-28

---

> 更多详细信息请参阅：
> - `docs/namou_kuwei/ANALYSIS_LOG.md` - 实验分析日志
> - `cursor_.md` - CAMELS 日步长训练经验（含静态属性问题修复）

