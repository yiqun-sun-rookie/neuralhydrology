# Nam Ou 库尾站项目迁移总结

> **迁移日期**: 2025-11-28  
> **来源**: `laos_forecast/_archive/experiments/namou_kuwei_dl/`  
> **目标**: `neuralhydrology/src/namou_kuwei/configs/archive_legacy/` + `neuralhydrology/docs/namou_kuwei/`

---

## 1. 迁移概述

本次迁移将老挝南乌江（Nam Ou）七级电站库尾站的深度学习预报实验从 `laos_forecast` 项目完整迁移到 `neuralhydrology` 项目。

### 1.1 迁移背景

原项目 `laos_forecast` 已重构为纯数据处理项目，深度学习相关的配置、实验和文档需要迁移到专门的 DL 项目 `neuralhydrology`。

### 1.2 迁移范围

| 类型 | 数量 | 来源 | 目标 |
|------|------|------|------|
| 配置文件 | 33个 | `laos_forecast/_archive/experiments/` | `neuralhydrology/src/namou_kuwei/configs/archive_legacy/` |
| 文档 | 3个 | 整理自 `laos_forecast/_archive/docs/` | `neuralhydrology/docs/namou_kuwei/` |
| 数据 | 已存在 | - | `neuralhydrology/data/namou_kuwei/hourly/` |
| 训练结果 | 已存在 | - | `neuralhydrology/runs/namou_kuwei/` |

---

## 2. 迁移内容明细

### 2.1 配置文件（33个）

#### hierarchy/ - 特征层级实验（9个）

| 文件名 | 说明 | 状态 |
|--------|------|------|
| S1_Rain.yml | 仅雨量基准 | ✅ 已迁移 |
| S2_Rain_AR.yml | 雨量 + 自回归 | ✅ 已迁移 |
| S3_Rain_Static.yml | 雨量 + 静态属性 | ✅ 已迁移 |
| **S4_Rain_AR_Static.yml** | **最佳配置** | ✅ 已迁移 |
| S4_Seq2Seq.yml | S4 Seq2Seq 版本 | ✅ 已迁移 |
| S5_Rain_AR_Downstream.yml | 雨量 + AR + 下游 | ✅ 已迁移 |
| S6_Rain_AR_Downstream_Static.yml | 全要素融合 | ✅ 已迁移 |
| S6_Seq2Seq.yml | S6 Seq2Seq 版本 | ✅ 已迁移 |
| F4_Upstream_AR_Static.yml | 仅上游雨量站 | ✅ 已迁移 |

#### leadtime/ - 多提前量实验（4个）

| 文件名 | 预报时效 | 状态 |
|--------|----------|------|
| S4_LT6h.yml | 6小时 | ✅ 已迁移 |
| S4_LT12h.yml | 12小时 | ✅ 已迁移 |
| S4_LT24h.yml | 24小时 | ✅ 已迁移 |
| S4_LT48h.yml | 48小时 | ✅ 已迁移 |

#### model_leadtime/ - 模型×提前量对比（20个）

| 模型 | 文件数 | 提前量 | 状态 |
|------|--------|--------|------|
| LSTM | 5个 | 1h/6h/12h/24h/48h | ✅ 已迁移 |
| GRU | 5个 | 1h/6h/12h/24h/48h | ✅ 已迁移 |
| EALSTM | 5个 | 1h/6h/12h/24h/48h | ✅ 已迁移 |
| Transformer | 5个 | 1h/6h/12h/24h/48h | ✅ 已迁移 |

### 2.2 文档（3个）

| 文件名 | 说明 | 状态 |
|--------|------|------|
| README.md | 项目主文档 | ✅ 新建 |
| ANALYSIS_LOG.md | 实验分析日志 | ✅ 整理自 laos_forecast |
| CONFIG_REFERENCE.md | 配置文件参考 | ✅ 新建 |
| MIGRATION_SUMMARY.md | 迁移总结（本文档） | ✅ 新建 |

### 2.3 数据（已存在，无需迁移）

```
data/namou_kuwei/hourly/
├── basins.txt
├── train_basins.txt
├── validation_basins.txt
├── test_basins.txt
├── attributes/attributes.csv
├── time_series/namou_kuwei.csv
├── time_series/namou_kuwei.nc
└── manifest.json

data/namou_kuwei/hourly_downstream/
└── (类似结构，包含下游数据)
```

### 2.4 训练结果（已存在，无需迁移）

```
runs/namou_kuwei/
├── S1_Rain_2025_1124_*/
├── S2_Rain_AR_2025_1124_*/
├── S3_Rain_Static_2025_1124_*/
├── S4_Rain_AR_Static_2025_1124_*/
├── S4_LT*_2025_1126_*/
├── S4_LSTM_LT*_2025_1126_*/
├── S5_Rain_AR_Downstream_*/
├── S6_Rain_AR_Downstream_Static_*/
└── ...
```

---

## 3. 目录结构

### 3.1 迁移后的 neuralhydrology 项目结构

```
neuralhydrology/
├── configs/
│   └── namou_kuwei/           # ★ 配置文件（已迁移）
│       ├── hierarchy/         # 9个特征层级配置
│       ├── leadtime/          # 4个多提前量配置
│       └── model_leadtime/    # 20个模型对比配置
├── data/
│   ├── namou_kuwei_hourly/    # 主数据集（已存在）
│   └── namou_kuwei_hourly_downstream/  # 下游数据集
├── docs/
│   └── namou_kuwei/           # ★ 文档目录（新建）
│       ├── README.md          # 项目主文档
│       ├── ANALYSIS_LOG.md    # 分析日志
│       ├── CONFIG_REFERENCE.md # 配置参考
│       └── MIGRATION_SUMMARY.md # 本文档
├── experiments/
│   └── namou_kuwei/           # 实验目录（已存在）
└── runs/
    └── namou_kuwei/           # 训练结果（已存在）
```

### 3.2 三项目分工

| 项目 | 路径 | 职责 |
|------|------|------|
| **neuralhydrology** | `F:\...\neuralhydrology` | DL 模型训练、配置管理、实验分析 |
| **forecast_system_lite** | `F:\...\forecast_system_lite` | FSL 传统模型率定与调试 |
| **laos_forecast** | `F:\...\laos_forecast` | 数据处理与导出（纯数据项目） |

---

## 4. 实验结果汇总

### 4.1 特征层级实验

| 实验 | 验证 NSE | 测试 NSE | 关键发现 |
|------|----------|----------|----------|
| S1_Rain | 0.37 | ~0.00 | 仅雨量不足 |
| S2_Rain_AR | 0.87 | 0.49 | 自回归至关重要 |
| S3_Rain_Static | 0.37 | 0.00 | 静态属性贡献有限 |
| **S4_Rain_AR_Static** | **0.996** | **0.53** | **最佳配置** |
| S5_Rain_AR_Downstream | - | - | 待评估 |
| S6_Rain_AR_Downstream_Static | - | - | 待评估 |

### 4.2 关键发现

1. **自回归特征至关重要**：历史流量是预测的核心特征
2. **最佳配置**：S4_Rain_AR_Static（雨量 + 自回归 + 静态）
3. **测试期 NSE**：最佳约 0.53，受单站数据和 Perfect Rain 限制
4. **12h 滞后相关**：降雨滞后 12h 与流量相关性最高

---

## 5. 后续工作入口

### 5.1 训练新模型

```bash
cd F:\github\pycharm\projects\neuralhydrology

# 使用最佳配置
python -m neuralhydrology.nh_run train \
    --config-file src/namou_kuwei/configs/archive_legacy/hierarchy/S4_Rain_AR_Static.yml
```

### 5.2 评估已有模型

```bash
python -m neuralhydrology.nh_run evaluate \
    --run-dir runs/namou_kuwei/S4_Rain_AR_Static_2025_1124_1835_ep60 \
    --period validation --epoch 60
```

### 5.3 文档参考

- **项目概览**: `docs/namou_kuwei/README.md`
- **分析日志**: `docs/namou_kuwei/ANALYSIS_LOG.md`
- **配置参考**: `docs/namou_kuwei/CONFIG_REFERENCE.md`

---

## 6. 注意事项

### 6.1 配置文件路径

配置文件中使用绝对路径，如需在其他机器运行需修改：
- `run_dir`
- `data_dir`
- `*_basin_file`

### 6.2 laos_forecast 归档

原始配置文件仍保留在 `laos_forecast/_archive/experiments/namou_kuwei_dl/`，作为历史备份。

### 6.3 数据更新

如需更新数据，请在 `laos_forecast` 项目中运行数据处理脚本，然后同步到 `neuralhydrology/data/`。

---

## 7. 迁移执行记录

| 时间 | 操作 | 状态 |
|------|------|------|
| 2025-11-28 | 分析 laos_forecast 中的 kuwei 相关内容 | ✅ |
| 2025-11-28 | 创建 docs/namou_kuwei/ 目录 | ✅ |
| 2025-11-28 | 迁移 hierarchy/ 配置（6个新增） | ✅ |
| 2025-11-28 | 迁移 leadtime/ 配置（4个） | ✅ |
| 2025-11-28 | 迁移 model_leadtime/ 配置（20个） | ✅ |
| 2025-11-28 | 创建 README.md 主文档 | ✅ |
| 2025-11-28 | 创建 ANALYSIS_LOG.md 分析日志 | ✅ |
| 2025-11-28 | 创建 CONFIG_REFERENCE.md 配置参考 | ✅ |
| 2025-11-28 | 创建 MIGRATION_SUMMARY.md 迁移总结 | ✅ |
| 2025-11-28 | 更新 forecast_system_lite 项目状态文档 | ✅ |

---

> **迁移完成** ✅  
> 更新日期: 2025-11-28



