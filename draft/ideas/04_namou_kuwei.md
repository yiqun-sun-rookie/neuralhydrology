# 04 - Nam Ou Kuwei Hourly Flow Forecasting

**状态**: completed
**创建日期**: 2025-10-01
**最后更新**: 2026-02-10

---

## 研究目标

针对 Nam Ou Kuwei 流域，开发高精度小时级流量预报模型，分别针对 1 小时和 24 小时预见期。重点验证自回归 (AR) 输入对短临预报的增益效果。

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/namou_kuwei/` | 配置、脚本、文档 |
| Results | `results/04_namou_kuwei/` | 训练输出、图表、总结 |
| Logs | `logs/04_namou_kuwei/` | 训练日志 |
| Docs | `draft/ideas/04_namou_kuwei.md` | 本文档 |
| Index | `draft/RESEARCH_INDEX.md` | 主索引 |

---

## 关键成果

| 预报类型 | 最佳模型ID | 架构 | Test NSE | Test KGE |
|---|---|---|---|---|
| 1小时预报 | L3_Rain_AR_LT1h | AR-LSTM | **0.975** | 0.885 |
| 24小时预报 | L5_Rain_AR_LT24h | AR-LSTM | **0.735** | - |
| 24小时预报 | L6_Seq2Seq | Seq2Seq | 0.730 | - |

**核心结论**: 引入自回归 (AR) 输入 (上一时刻观测流量) 显著提升短临预报精度。

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| Best 1h Config | `src/namou_kuwei/configs/no_leak/03_with_ar/rain_ar_LT1h.yml` | 1h 最佳: seq=168, hidden=64, qobs_shift1 |
| Best 24h Config | `src/namou_kuwei/configs/no_leak/05_leadtime/rain_ar_LT24h.yml` | 24h 最佳: qobs_shift24 |
| Seq2Seq Configs | `src/namou_kuwei/configs/no_leak/06_seq2seq/` | Seq2Seq 变体 |
| Baseline Configs | `src/namou_kuwei/configs/no_leak/01_baseline/` | 仅降雨输入 (L1) |
| Static Configs | `src/namou_kuwei/configs/no_leak/02_with_static/` | 降雨+静态属性 (L2) |
| Full Configs | `src/namou_kuwei/configs/no_leak/04_full/` | 所有输入 (L4) |
| Plot Script | `src/namou_kuwei/scripts/plot_namou_kuwei.py` | 结果可视化 |
| Summary | `results/04_namou_kuwei/namou_kuwei_summary.md` | 实验总结 |
| Performance Plot | `results/04_namou_kuwei/namou_kuwei_performance.png` | 性能对比图 |

---

## 实验设计

| 层级 | 名称 | 输入 | 目的 |
|------|------|------|------|
| L1 | Baseline | 仅降雨 | 最简基线 |
| L2 | +Static | 降雨+静态属性 | 静态属性增益 |
| L3 | +AR | 降雨+自回归 | **验证AR增益 (核心)** |
| L4 | Full | 所有输入 | 全输入上限 |
| L5 | Lead Time | AR+不同预见期 | 预见期影响 |
| L6 | Seq2Seq | Encoder-Decoder | 多步预报方案 |

- Train: 2020.1 - 2021.6
- Val: 2021.7 - 2021.12
- Test: 2022 全年
- Seed: 2025

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2025-10-01 | 项目启动 | 数据准备和初始配置 |
| 2025-11-15 | L1-L4 完成 | 基线到全输入的逐层实验 |
| 2025-12-01 | L5 预见期测试 | 1h-24h 不同预见期对比 |
| 2025-12-05 | L6 Seq2Seq | Encoder-Decoder 变体 |
| 2025-12-10 | Phase 1 完成 | 最佳 1h NSE=0.975, 24h NSE=0.735 |
| 2026-02-10 | 目录迁移 | 从 experiments/namou_kuwei/ 迁移到 src/namou_kuwei/ |

---

## 归档文档

详细实验设计、分析日志和配置参考文档归档于 `src/namou_kuwei/docs/archive/`。
