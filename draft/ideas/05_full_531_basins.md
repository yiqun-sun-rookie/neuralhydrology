# 05 - Full 531 Basins Multi-Architecture Benchmark

**状态**: active
**创建日期**: 2025-11-01
**最后更新**: 2026-02-18

---

## 研究目标

基于 CAMELS-US 数据集 (531 流域)，建立大样本水文深度学习模型的性能基准 (Benchmark)，对比 LSTM、GRU、Transformer、EA-LSTM、AR-LSTM、Multihead 等架构的表现。

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/full_531_basins/` | 配置、脚本、basin lists |
| Results | `results/05_full_531_basins/` | 训练输出、图表、报告 |
| Logs | `logs/05_full_531_basins/` | 训练日志 |
| Docs | `draft/ideas/05_full_531_basins.md` | 本文档 |
| Index | `draft/RESEARCH_INDEX.md` | 主索引 |

注: Mamba 在 CAMELS-US 日尺度的验证属于 ID 02 (mamba_camels_us)，不在本项目范围。

---

## 实验进度

| 实验ID | 模型 | 状态 | Best Val NSE | Test NSE | 备注 |
|---|---|---|---|---|---|
| reproduce_531_nse074 | **CUDA-LSTM** | completed | 0.735 | **0.725** | 基线确立 |
| full_531_gru_ep30 | GRU | completed | 0.743 (Ep44) | **0.681** | 略逊于 LSTM |
| full_531_transformer | Transformer | completed | 0.691 | - | 收敛较慢 |
| full_531_ealstm | EA-LSTM | interrupted | 0.732 | - | CPU 训练太慢 |
| full_531_arlstm | AR-LSTM | interrupted | 0.830* | - | *疑 AR 泄露 |
| full_531_mtslstm | MTS-LSTM | not_applicable | - | - | 需多频率数据 |
| full_531_multihead | Multihead | completed | 0.708 (Ep26) | **0.679** | 已修复配置 |

**LSTM 基线详情**: Median NSE=0.725, Good(>=0.7)=56.5%, Poor(<0.5)=14.9%

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| Plot (baseline) | `src/full_531_basins/scripts/plot_531_baseline.py` | 基线结果可视化 |
| Plot (spatial) | `src/full_531_basins/scripts/plot_531_spatial.py` | 空间分布可视化 |
| Data Audit | `src/full_531_basins/scripts/data_availability.py` | 流域可用性审计（缺测/零方差） |
| Backup Manager | `src/full_531_basins/scripts/manage_backups.py` | 结果备份清理与管理 |
| Problematic Basins | `src/full_531_basins/data/problematic_basins.txt` | 问题流域列表 |
| Figures | `results/05_full_531_basins/figures/` | 所有实验图表 |
| Reports | `results/05_full_531_basins/reports/` | 训练状态报告 |
| Models | `results/05_full_531_basins/models/` | 预训练模型 |
| Backups | `results/05_full_531_basins/backups/` | 历史配置与流域划分备份 |

---

## Results Index

| Run ID | Date | Output Path | Notes |
| :--- | :--- | :--- | :--- |
| reproduce_531_nse074 | 2025-11 | `results/05_full_531_basins/` | LSTM 基线 |
| full_531_gru_ep30 | 2025-12 | `results/05_full_531_basins/` | GRU 对比 |
| full_531_multihead | 2025-12-21 | `results/05_full_531_basins/` | Multihead 对比 |
| camels_us_674_basins_2025_1025 | 2025-10-25 | `results/05_full_531_basins/models/` | 预训练模型 |
| legacy_backups_2025 | 2025-10 | `results/05_full_531_basins/backups/` | 已从历史根目录备份桶迁移（旧根目录已删除） |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2025-11-01 | 项目启动 | LSTM 基线训练 |
| 2025-11-15 | LSTM 基线完成 | NSE=0.725, 基线确立 |
| 2025-12-01 | GRU 完成 | NSE=0.681, 略逊于 LSTM |
| 2025-12-10 | Transformer 完成 | NSE=0.691, 收敛较慢 |
| 2025-12-16 | 配置修复 | MTS-LSTM 不适用; Multihead 缺配置已修复 |
| 2025-12-21 | Multihead 完成 | NSE=0.679, 测试完成 |
| 2026-02-10 | 目录迁移 | 整理到 src/full_531_basins/ |
| 2026-02-18 | 脚本入口统一 | 旧 `src/full_531_basins/tools/` 下脚本已迁移到 `src/full_531_basins/scripts/`，统一执行入口 |

---

## 下一步

1. 重新评估 AR-LSTM，确认 AR 泄露问题
2. EA-LSTM 迁移到 HPC (GPU) 训练
3. 尝试 Attention-LSTM, Transformer 改进版
4. 整理最终对比报告
