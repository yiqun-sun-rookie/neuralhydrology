# Idea 发表潜力评估（2026-02-23）

目标期刊：WRR / Journal of Hydrology 及以上。评估基于当前进展 + 2025-2026 文献调研。

---

## 结论总表

| ID | Idea | 评级 | 建议 |
|:---|:-----|:-----|:-----|
| 07 | HydroAgent | ⭐⭐⭐⭐⭐ | **最优先。** 可出 1-3 篇论文 |
| 41 | MTS-Mamba Global Transfer | ⭐⭐⭐⭐ | **核心论文。** 跨时间尺度 Mamba 迁移 |
| 03 | Mamba CAMELSH (小时) | ⭐⭐⭐ | 降格为 ID 41 的 baseline/对照实验 |
| 06 | Haihe River | ⭐⭐⭐ | 降格为 ID 41 的 data-scarce 迁移 case study |
| 01 | Caravan Global | ⭐⭐ | 继续做，纯基础设施（预训练权重），不单独发论文 |
| 02 | Mamba CAMELS-US (日) | ⭐ | 归档，工作量被 ID 41 吸收 |
| 05 | Full 531 Basins Benchmark | ⭐ | 归档，已无新颖性 |
| 04 | Nam Ou Kuwei | — | 已完成，不够 WRR/JH 级别，可投区域期刊或作为学位章节 |
| 99 | Global Hourly Model | — | 合并到 ID 41 |

---

## 详细评估

### ID 07 HydroAgent — LLM Agent 自动发现水文模型结构 ⭐⭐⭐⭐⭐

**新颖性：极高。** 文献中仅有 HydroLLM benchmark 和 WaterGPT 概念文章，尚无人做 LLM Agent + 概念模型结构自动搜索的闭环系统。

**完成度：** Diagnostics (Module A) 和 Environment (Module B) 已完成并通过集成验证。仅差 Agent 推理循环 (Module C)。

**论文拆分：**
- Paper 1: Diagnostic Framework（诊断体系，素材就绪）
- Paper 2: Automated Modeling Environment（自动化建模环境，素材就绪）
- Paper 3: Agentic Discovery（旗舰论文，待 Agent 开发完成）

**风险：** LLM Agent 的可复现性和稳定性；需要在足够多流域上验证泛化。

### ID 41 MTS-Mamba Global Transfer — 多时间尺度 Mamba 全球迁移 ⭐⭐⭐⭐

**新颖性：高。** 现有 Mamba 水文文献集中在单一时间尺度（Demiray & Demir 2025、RiverMamba 2025、LightMamba 2024）。跨时间尺度 Mamba（Daily → Hourly 状态传递）+ 全球预训练迁移尚无人做。

**完成度：** 早期阶段。依赖链长：ID 01 全球预训练 → mtsmamba.py 骨架 → 跨频率验证 → 迁移实验。

**故事：** 证明 MTS-Mamba + Caravan 全球日预训练在小时级洪水预报上优于 MTS-LSTM，尤其洪峰捕捉和跨区域泛化（US → GB/AUS）。WRR 级别。

**风险：** 依赖链过长；MTS-Mamba 架构设计本身有技术不确定性。

### ID 03 Mamba CAMELSH (小时) ⭐⭐⭐

**新颖性：已被抢占。** "首个大规模小时级 Mamba 验证"已被 Demiray & Demir (2025, 125 Iowa 流域) 和 RiverMamba (2025, 全球) 覆盖。单纯 Mamba vs LSTM 小时级 benchmark 不够新。

**建议：** 降格为 ID 41 论文的对照实验——提供小时级 LSTM baseline 和 Mamba fine-tuning target。

### ID 06 Haihe River ⭐⭐⭐

**新颖性：** 数据管线本身不成论文。但"全球预训练 → 中国数据稀缺流域迁移"是好故事。

**建议：** 作为 ID 41 论文的 case study 之一（data-scarce transfer），不单独投稿。目前仍在 data_prep 阶段，距投稿最远。

### ID 01 Caravan Global ⭐⭐

全球 LSTM 预训练已被 Kratzert et al. (2019, 2023) 充分研究。不构成独立论文，但是 ID 41 和 ID 06 的必要基础设施。继续推进但仅作为预训练 checkpoint 供下游消费。

### ID 02 Mamba CAMELS-US (日) ⭐

Mamba 在 CAMELS-US 日尺度 benchmark 已被多篇文献覆盖。进度也很初期（smoke test 阶段）。无独立发表价值，工作量可被 ID 41 吸收。建议归档。

### ID 05 Full 531 Basins Benchmark ⭐

多架构 benchmark（LSTM/GRU/Transformer）在 CAMELS-US 上的对比已被充分研究。结果（LSTM NSE=0.725）未超出已知范围。无新颖性，建议归档。

### ID 04 Nam Ou Kuwei —

已完成（1h NSE=0.975）。单流域 AR-LSTM 预报不具备 WRR/JH 级别普适性。可投区域性期刊或作为学位论文章节。

### ID 99 Global Hourly Model —

概念草案，与 ID 41 高度重叠。建议合并到 ID 41。

---

## 建议论文路线图

```
优先级 1（最高新颖性，精力 70%）
  ID 07 HydroAgent
    → Paper 1: 诊断框架
    → Paper 2: 自动建模环境
    → Paper 3: 旗舰——LLM Agent 模型结构发现

优先级 2（明确差异化，精力 30%）
  ID 41 MTS-Mamba
    ├─ 依赖 ID 01（全球预训练权重）
    ├─ 吸收 ID 02（CAMELS-US 对比）
    ├─ 吸收 ID 03（小时级 baseline）
    ├─ 吸收 ID 06（海河迁移 case study）
    └─ 合并 ID 99

归档：ID 02, 05
保留：ID 04（学位章节或区域期刊）
```

---

## 关键文献参考

- Demiray & Demir (2025): Mamba 小时级流量预报, 125 Iowa 流域 — SSRN preprint
- RiverMamba (2025): 全球尺度 Mamba 流量与洪水预报 — arXiv 2505.22535
- LightMamba (2024): 轻量 Mamba 日径流预测 — Hydrology Research
- Mamba Reservoir (2025): Mamba 水库调度, 441 CONUS 大坝 — Journal of Hydrology
- Jahangir et al. (2025): 多时间尺度分层深度学习水文预报 — WRR
- ms-Mamba (2025): 多尺度 Mamba 时间序列预测 — arXiv 2504.07654
- HydroLLM (2025): 水文 LLM 知识评估 benchmark — Environmental Data Science
