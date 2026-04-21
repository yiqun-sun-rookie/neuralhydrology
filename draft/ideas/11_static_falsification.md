# Idea 11: Static Attribute Falsification

## One-liner

EALSTM 真的利用了静态流域属性的物理信息吗？通过属性置换实验证伪。

## Status: design_complete

## Spec

`docs/superpowers/specs/2026-03-29-static-falsification-design.md`

## Key References

- Kratzert et al. 2019 HESS — EALSTM 架构，static→input gate
- Kratzert et al. 2019 WRR — CudaLSTM + static for PUB
- Nearing et al. 2024 Nature — 全球 LSTM，用了 HydroATLAS static 但无消融
- Lees et al. 2022 HESS — shuffle hidden states（不是 input attributes）
- Bayati 2026 WRR — LSTM 功能现实性质疑

## Core Idea

4 组实验 (E1-E4) × 5-fold PUB CV，EALSTM on CAMELS-US 531:
- E1: 正确 static（baseline）
- E2: 训练正确、测试 shuffle（零成本，复用 E1）
- E3: 训练+测试都 shuffle
- E4: 常数 static（全零）

如果 E1 ≈ E2 → static 的物理含义未被利用 → 强证伪
