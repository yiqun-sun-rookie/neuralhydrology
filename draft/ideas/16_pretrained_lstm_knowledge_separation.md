# Idea 16: Pretrained LSTM Knowledge Separation

**状态**: design
**创建日期**: ~2026-02
**最后更新**: 2026-04-19

---

## 核心问题

大样本预训练水文 LSTM 中，**可迁移知识**与**领域特定知识**是否表现出部分可分的结构？通过对单一预训练模型施加不同的 finetune 组合（head / embedding / lstm / full），在低/高分布偏移目标流域下验证知识层级化假设。

## 源模型

基于 CAMELS-US（531 basins, Kratzert 2019 split）的 CudaLSTM 预训练权重。直接复用 ID 05（adversarial_robustness）的 baseline 531 训练结果：`results/05_adversarial_robustness/full_training_nse_2025_1025_1821_ep50/`。

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/pretrained_lstm_knowledge_separation/` | split 构建、matrix runner、结果汇总、表征漂移分析 |
| Results | `results/16_pretrained_lstm_knowledge_separation/` | manifest / summary_table / drift_metrics |
| Source model | `results/05_adversarial_robustness/` | 复用 ID 05 的 531 basin 检查点 |
| Tests | `test/test_pretrained_lstm_knowledge_separation_*.py` | 5 个测试文件 |

## Adaptation 组合

| Group | `finetune_modules` |
|---|---|
| head-only | `[head]` |
| embedding-only | `[embedding_net]` |
| lstm-only | `[lstm]` |
| full FT | `[embedding_net, lstm, head]` |

## Shift Conditions

按标准化属性空间（aridity / frac_snow / elevation / soil depth …）的 Mahalanobis 距离划分：
- **low shift** — 离源分布中心近
- **high shift** — 离源分布中心远

---

## 假设

1. 低偏移下 head-only 即可恢复大部分目标增益（可迁移知识已在底层）
2. 高偏移下需要更深层适配（领域特定信息在深层模块）
3. 适配越深 → 源知识遗忘越严重

---

## 进度记录

- 代码骨架完成：configs / split 构建 / matrix runner / 表征漂移分析 / 5 个测试
- 详见 `src/pretrained_lstm_knowledge_separation/README.md`
- 2026-04-19: 注册 ID 16，状态 design；首轮 matrix 实验待 ID 05 h256 baseline 稳定后启动
