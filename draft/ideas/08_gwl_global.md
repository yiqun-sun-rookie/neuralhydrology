# Idea 08: GWL Global — 全球地下水位预测模型

## 状态: dev (Phase 0)

## 核心问题

能否构建一个可泛化的全球地下水位 (GWL) 深度学习预测模型，基于气象驱动（降雨、蒸发）预测地下水位变化，同时区分自然过程与人为影响？

## 创新点

1. **双尺度架构**: 长周期 Encoder（捕捉地下水数月~数年的记忆）+ 短周期 LSTM
2. **MoE 人为影响识别**: Mixture of Experts 模块，用 gating 权重无监督地区分自然/人为驱动
3. **全球泛化**: 从高质量荷兰数据出发，迁移学习推广到多气候区

## 数据

- **Phase 0 (荷兰)**: BRO 地下水位 + KNMI 气象 (P, ET)
- **Phase 4 (全球)**: GGMN + ERA5 + USGS/BoM/CGWB

## 技术路线

| Phase | 内容 | 依赖 |
|-------|------|------|
| P0 | 荷兰数据获取+清洗 | 无 |
| P1 | Pastas baseline + persistence/MLP baseline | P0 |
| P2 | 双尺度 LSTM vs 单尺度 LSTM (不同 lookback) | P0, P1 |
| P3 | MoE 人为影响识别 (先做残差分析验证假设) | P2 |
| P4 | 多区域推广 (US, AU, IN, DE) | P3 |
| P5 | 论文 (目标: WRR 或 HESS) | P3+ |

## 评估指标

NSE, KGE, RMSE, R², 季节相位误差, 极端低水位命中率

## 关键参考文献

- HESS 2024: global entity-aware DL for GWL prediction
- WRR 2023: doi 10.1029/2023WR035139 (4-country comparison)
- JH 2024: multi-site DL, 1800+ wells, 5 continents
- Pastas: system identification baseline

## 代码

- `src/gwl_global/` — 数据获取、模型、评估
- `results/08_gwl_global/` — 实验结果
- `logs/08_gwl_global/` — 运行日志

## 实施计划

详见 `docs/superpowers/plans/2026-03-19-gwl-global-phase0.md`
