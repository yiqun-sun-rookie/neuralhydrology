# Nam Ou Kuwei 实验快速参考

> 最后更新: 2025-12-04

## 最佳配置推荐

### 1小时预报 (NSE=0.975)
```bash
python -m neuralhydrology.nh_run train --config-file src/namou_kuwei/configs/no_leak/03_with_ar/rain_ar_LT1h.yml
```

### 24小时预报 (NSE=0.735)
```bash
python -m neuralhydrology.nh_run train --config-file src/namou_kuwei/configs/no_leak/05_leadtime/rain_ar_LT24h.yml
```

### 一次预测24小时 Seq-to-Seq (NSE=0.730)
```bash
python -m neuralhydrology.nh_run train --config-file src/namou_kuwei/configs/no_leak/06_seq2seq/seq2seq_ar24lag_24h.yml
```

---

## 测试集结果速查表

| 实验 | 预报时效 | NSE | KGE | 配置文件 |
|------|----------|-----|-----|----------|
| 仅降雨 | 1h | -0.25 | -0.31 | `01_baseline/rain_only_LT1h.yml` |
| **降雨+AR** | **1h** | **0.975** | **0.885** | `03_with_ar/rain_ar_LT1h.yml` ⭐ |
| 降雨+AR | 6h | 0.763 | 0.575 | `05_leadtime/rain_ar_LT6h.yml` |
| 降雨+AR | 12h | 0.822 | 0.666 | `05_leadtime/rain_ar_LT12h.yml` |
| 降雨+AR | 24h | 0.735 | 0.546 | `05_leadtime/rain_ar_LT24h.yml` |
| Seq2Seq | 24h | 0.730 | 0.550 | `06_seq2seq/seq2seq_ar24lag_24h.yml` |

---

## 关键参数说明

### 预报时效控制 (无泄露)

| 预报时效 | lagged_features | autoregressive_inputs |
|----------|-----------------|----------------------|
| 1小时 | `qobs: [1]` | `qobs_shift1` |
| 6小时 | `qobs: [6]` | `qobs_shift6` |
| 12小时 | `qobs: [12]` | `qobs_shift12` |
| 24小时 | `qobs: [24]` | `qobs_shift24` |

### Seq-to-One vs Seq-to-Seq

| 参数 | Seq-to-One | Seq-to-Seq |
|------|------------|------------|
| `predict_last_n` | 1 | 24 |
| `seq_length` | 168 | 192 |
| 模型数量 | 每个时效一个 | 单一模型 |

---

## 评估命令

```bash
# 评估已训练模型
python -m neuralhydrology.nh_run evaluate --run-dir results/namou_kuwei/L3_Rain_AR_LT1h_2025_1201_1632_ep60

# 结果位置
results/namou_kuwei/<实验名>/test/model_epoch060/test_metrics.csv
```

---

## 核心发现

1. **AR是关键**: 无AR时NSE=-0.25，有AR时NSE=0.97
2. **静态属性无效**: 单站点场景下静态属性几乎无贡献
3. **时效vs精度**: 1h→24h，NSE从0.975降至0.735
4. **Seq2Seq可行**: 单模型预测多时刻，性能与独立模型相当

---

> 详细报告见: `EXPERIMENT_RESULTS_v2.md`








