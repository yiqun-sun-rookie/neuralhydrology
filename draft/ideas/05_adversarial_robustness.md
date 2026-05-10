# Idea 05: 攻击方法的选择如何影响深度学习水文模型的鲁棒性评估

> **合并说明（2026-04-17）**: 原 ID 05 `full_531_basins`（531 流域多架构 benchmark，已归档无独立论文价值）已并入本 idea。其作为 CudaLSTM 基线预训练基础设施，代码迁到 `src/adversarial/baseline_531/`，模型 checkpoint 迁到 `results/05_adversarial_robustness/full_training_nse_2025_1025_1821_ep50/`（对抗实验的受害者模型）。

## 2026-05-10 深度同步（覆盖 2026-04-23 旧记录）

- **阶段**: 收尾阶段（写作已基本完成，无新实验计划）
- **正稿路线已敲定**: 2026-04-27 commit `3a8b7e0`（"Phase: switch adversarial paper to 531 benchmark"）确定唯一正稿走 **531 basins / 14 static / h=128 / Kratzert 标准时间分割** 路线，由 `draft/papers/05_adversarial_latex/main.tex` 承载。`05_adversarial_robustness_wrr.md` 在该 commit 中从 414 行收缩到 158 行作为存档，不再是平行候选。Pivot 之后 4 个 commit（`6b1e501` → `0e12b8f` → `8c476a2` → `90e7783`）全部只在 LaTeX 正稿上做 prose 级修润，再无人改 `.md` 草稿。配套计划文档：`docs/plans/2026-04-25-adversarial-531-rerun.md`。
- **正稿事实**（来自 `main.tex` abstract + Table `tab:attack`）：
  - **标题**（已定）：*Attack-Method Choice Changes Robustness Conclusions for a Standard LSTM Rainfall-Runoff Model*
  - **期刊**：Water Resources Research（已定）
  - **Victim**：单一 LSTM h=128，14 static + 5 daymet 动态特征，Kratzert 2018 标准时间分割（Train 1990-10-01 ~ 1995-09-30、Val 1995-10-01 ~ 2000-09-30、Test 2000-10-01 ~ 2005-09-30），epoch 20 checkpoint
  - **数据规模**：17,523 个实验记录、531 个 basin ID，其中 514 个 finite-NSE basin 用于 headline 统计（17 个流域因评估期 streamflow 方差近零导致 NSE 退化为非有限值）
  - **关键数字 @ ε=0.1**：
    - Auto-PGD median ΔNSE = **−0.408** [Q25, Q75 = −0.731, −0.225]
    - FGSM median ΔNSE = −0.358
    - Gaussian median ΔNSE = −0.023
    - **APGD / Gaussian = 17.5×**（@ ε=0.2 扩大到 21.6×）
    - 167 / 514 (**32.5%**) finite-NSE basins 跌破 NSE = 0
    - Statistical 约束下 median ΔNSE = **−0.19**（QC 不可检测的扰动仍显著有害）
- **故事重定位**：旧的"Auto-PGD 比 FGSM 揭示 1.5× 脆弱性"已被弱化（在 531/with-static 配置下 APGD/FGSM @ ε=0.1 仅 ≈1.14×，差距随 ε 增大而扩大）。新主信息是"**梯度类攻击 vs 随机噪声 = 17.5×**"——dominant gap 在 gradient-based 与 random 之间，而不在 iterative 与 single-step 之间。`Statistical` 约束与 `Causal Trigger` 分析均超出 Yang et al. (2026) 设置，构成与其工作的互补维度（他们变模型固定 attack，本文固定模型变 attack）。
- **剩余工作**：内部审阅 → cover letter → 投稿。

> ⚠ 本文件下文"全量结果 (520 basins)"、"核心发现"、"论文结构"、"目标期刊" 等章节是 pivot 前的探索版本（APGD/Gauss = 21.4×、APGD/FGSM = 1.5×、暂拟标题等），与当前正稿不一致，仅作历史保留。**LaTeX 正稿（`draft/papers/05_adversarial_latex/main.tex`）为唯一权威来源。**

---

## Baseline Infrastructure (合并自原 full_531_basins)

- **基线模型**: CudaLSTM hidden=128, ep50, **Median NSE=0.725** (531 basins, CAMELS-US, daymet)
- **训练路径**: `results/05_adversarial_robustness/full_training_nse_2025_1025_1821_ep50/model_epoch050.pt`
- **代码**: `src/adversarial/baseline_531/` (原 `src/full_531_basins/`) — 包含训练配置、数据审计、备份管理脚本
- **对比 baseline 表** (原 full_531_basins 归档结论，供参考):
  | Model | Val NSE | Test NSE |
  |---|---|---|
  | **CUDA-LSTM** | 0.735 | **0.725** |
  | GRU | 0.743 | 0.681 |
  | Transformer | 0.691 | — |
  | Multihead | 0.708 | 0.679 |

---



## 一句话概括

单步攻击 (FGSM) 会低估 LSTM 水文模型的脆弱性——迭代攻击 (Auto-PGD) 揭示的最坏情况性能退化是 FGSM 的 1.5 倍、随机噪声的 21 倍。攻击方法的选择对鲁棒性结论有决定性影响。

---

## 研究动机

### 背景
深度学习（LSTM）水文模型在 CAMELS 等 benchmark 上表现优异（NSE > 0.7），正在向业务预报系统部署推进。在此背景下，模型对输入不确定性的敏感度——即鲁棒性——成为一个重要的实际问题。

现实中气象输入天然存在不确定性：
- 雨量计：5-15% 系统偏差
- 温度传感器：±0.5°C 漂移
- 格点产品（Daymet/ERA5）：空间插值带来更大误差

### 已有工作
Yang et al. (2026, arXiv:2602.05237) 率先将对抗鲁棒性分析引入水文建模，在 1,347 个德国流域上比较了 LSTM 与 HBV 对 FGSM 扰动的敏感度。他们发现 LSTM 通常比 HBV 更鲁棒（ΔKGE: -0.105 vs -0.164 @ ε=0.2），灾难性失效罕见，支持 LSTM 在业务中的部署。

### 我们的问题
Yang et al. 的工作开创性地建立了对抗鲁棒性分析在水文领域的方法论框架。然而，他们仅使用了 FGSM（快速梯度符号法），这是一种单步攻击，计算高效但未必能找到最坏情况下的扰动。在计算机视觉领域，已有大量工作表明单步攻击会高估模型鲁棒性，迭代攻击（如 PGD）能揭示更大的脆弱性。

**核心问题：攻击方法的选择在多大程度上影响水文模型鲁棒性的评估结论？**

---

## 方法

### 目标模型
- CudaLSTM (neuralhydrology 框架), hidden_size=128, 50 epochs
- CAMELS-US 520 流域, daymet 气象驱动
- 5 个动态输入特征：降水、辐射、最高温、最低温、水汽压

### 扰动方法矩阵

我们设计了包含不同复杂度的扰动方法，从随机基线到迭代优化：

| 方法 | 类型 | 原理 | 计算成本 |
|------|------|------|---------|
| Gaussian Noise | 随机基线 | 各向同性随机扰动 | 极低 |
| Mult. Bias | 随机基线 | 乘性随机偏差 | 极低 |
| Temp. Corr. Noise | 随机基线 | 时间相关随机噪声 | 极低 |
| **FGSM** | 单步对抗 | 单步梯度方向扰动 | 低 |
| **Auto-PGD** | 迭代对抗 | 多步梯度优化，自适应步长 | 中 |
| **C&W** | 最小扰动 | 寻找使 NSE 降至阈值以下的最小扰动 | 高 |
| **Causal Trigger** | 时序定向 | 仅扰动洪峰前 N 天 | 中 |

### 约束层级

| 层级 | 约束内容 | 现实对应 |
|------|---------|---------|
| Lp | 仅限制扰动幅度 ≤ ε | 基本约束 |
| Physical | 降水 ≥ 0、温度在合理范围 | 物理常识 |
| Statistical | 扰动后各特征均值和标准差不变 | 统计质控不可检测 |

### ε 与真实观测误差的对应

| ε | 降水 (mm/day) | 温度 (°C) | 对应现实来源 |
|---|--------------|-----------|-------------|
| 0.01 | ±0.08 | ±0.11 | 高精度站点 |
| 0.05 | ±0.4 | ±0.6 | 典型站点观测误差 |
| **0.1** | **±0.8** | **±1.1** | **格点产品典型误差** |
| 0.2 | ±1.5 | ±2.2 | 遥感/再分析产品 |

---

## 全量结果 (520 basins, **pivot 前的探索版 — 已被 531/with-static 正稿替代**)

### 实验 1：攻击方法对比 (Table 1)

约束=Lp, 目标=untargeted, median ΔNSE [Q25, Q75]

| 方法 | ε=0.01 | ε=0.05 | ε=0.1 | ε=0.2 |
|------|--------|--------|-------|-------|
| Auto-PGD | -0.045 [-0.084, -0.024] | -0.270 [-0.542, -0.143] | **-0.587** [-1.481, -0.303] | -1.282 [-5.077, -0.631] |
| FGSM | -0.043 [-0.082, -0.024] | -0.216 [-0.429, -0.120] | -0.394 [-0.858, -0.223] | -0.639 [-1.828, -0.385] |
| Gaussian | -0.003 [-0.005, -0.001] | -0.013 [-0.026, -0.007] | -0.027 [-0.053, -0.014] | -0.057 [-0.109, -0.030] |
| Mult. Bias | -0.002 [-0.003, -0.001] | -0.008 [-0.018, -0.004] | -0.018 [-0.037, -0.009] | -0.038 [-0.079, -0.018] |
| Temp. Corr. | -0.002 [-0.004, -0.001] | -0.011 [-0.020, -0.005] | -0.022 [-0.041, -0.011] | -0.046 [-0.081, -0.024] |

**关键比值 (ε=0.1):**
- APGD / Gaussian = **21.4x**（迭代对抗 vs 随机）
- APGD / FGSM = **1.5x**（迭代 vs 单步）
- FGSM / Gaussian = **14.6x**（单步对抗 vs 随机）

### 实验 2：约束消融 (Table 2)

attack=auto_pgd, target=untargeted, median ΔNSE (mean ΔNSE)

| 约束 | N | ε=0.05 | ε=0.1 | ε=0.2 |
|------|---|--------|-------|-------|
| Lp | 520 | -0.270 (-0.924) | -0.587 (-2.549) | -1.282 (-7.853) |
| Physical | 490 | -0.251 (-0.870) | -0.552 (-2.393) | -1.563 (-8.295) |
| Statistical | 490 | -0.148 (-0.451) | **-0.347** (-1.127) | -0.747 (-3.059) |

统计约束将中位损失从 -0.587 降低到 -0.347（减少 41%），但仍然显著。

### 实验 3：定向攻击 (Table 3)

APGD, ε=0.1, constraint=lp, median ΔNSE [Q25, Q75]

| 目标 | ΔNSE | ΔKGE |
|------|------|------|
| Untargeted | -0.587 [-1.481, -0.303] | -0.556 [-1.274, -0.176] |
| Flood | -0.501 [-1.129, -0.250] | -0.553 [-1.259, -0.214] |
| Low-flow | -0.019 [-0.100, 0.016] | -0.018 [-0.203, 0.080] |

### 实验 4：Causal Trigger 窗口效应 (Fig 3)

causal_trigger, ε=0.1, median ΔNSE

| 洪峰前窗口 | Median ΔNSE |
|-----------|-------------|
| 1 天 | -0.013 |
| 3 天 | -0.034 |
| 7 天 | -0.070 |
| 14 天 | -0.122 |

### 实验 5：流域脆弱性分布 (Fig 2)

APGD, ε=0.1, constraint=lp, N=520 basins:
- Median ΔNSE = **-0.59**
- 10th percentile = -4.61
- **169 个流域 (32.5%) ΔNSE < -1**

---

## 核心发现

### Finding 1: 攻击方法的选择显著影响鲁棒性结论

FGSM 在所有 ε 下均低估模型脆弱性。在 ε=0.1 时，Auto-PGD 揭示的性能退化是 FGSM 的 1.5 倍（median ΔNSE: -0.587 vs -0.394）。这一差距随 ε 增大而扩大（ε=0.2 时为 2.0 倍）。

这意味着基于 FGSM 的鲁棒性评估虽然有价值，但可能给出过于乐观的结论。对于关键部署场景（如洪水预警），需要更强的压力测试。

### Finding 2: 对抗扰动与随机噪声的差距远大于预期

在相同扰动预算下，Auto-PGD 造成的性能退化是 Gaussian 噪声的 21 倍。这表明传统的随机噪声敏感性分析远不足以揭示模型最坏情况。

Yang et al. 观察到 FGSM 和随机扰动的响应模式相似（approximately linear）。我们发现，这一结论在单步攻击下成立，但迭代攻击可以找到显著更差的方向。

### Finding 3: 统计上不可检测的扰动仍然有效

即使在统计约束下（扰动后各特征的均值和标准差保持不变），Auto-PGD 仍使 median ΔNSE 下降 0.347。这意味着常规的统计质控手段（检查输入数据的统计特性）无法发现此类有害的输入误差模式。

### Finding 4: 洪峰前的输入误差影响不成比例

Causal Trigger 实验表明，仅扰动洪峰前 14 天的气象输入就能造成 median ΔNSE = -0.122 的下降。对于洪水预警系统而言，这恰恰是数据质量最为关键的时段。

---

## 论文结构

### Title (暂定)

"Does the Choice of Attack Method Matter? Revisiting Adversarial Robustness of LSTM Rainfall-Runoff Models with Iterative Perturbations"

或更简洁：

"Beyond FGSM: How Iterative Adversarial Attacks Reveal Hidden Fragility in LSTM Hydrological Models"

### 故事线

```
1. Introduction
   LSTM 水文模型正在走向业务部署。Yang et al. (2026) 开创性地将对抗鲁棒性
   分析引入水文领域，用 FGSM 评估后得出 LSTM 相当鲁棒的结论。然而，在 CV
   领域已有充分证据表明单步攻击会低估脆弱性。
   → 我们的问题：攻击方法的选择在多大程度上影响鲁棒性结论？

2. Methods
   - 目标模型（CudaLSTM, CAMELS-US 520 basins）
   - 5 种扰动方法（3 随机 + FGSM + Auto-PGD）+ C&W + Causal Trigger
   - 3 层约束（Lp / Physical / Statistical）
   - ε 与真实观测误差的对应

3. Results
   3.1 攻击方法对比：APGD > FGSM > Random（Table 1 + Fig 1）
   3.2 流域脆弱性分布：1/3 流域灾难性退化（Fig 2）
   3.3 约束消融：统计不可检测的扰动仍有效（Table 2）
   3.4 定向攻击与 Causal Trigger（Table 3 + Fig 3）
   3.5 C&W 最小扰动分析（Fig 4）
   3.6 可检测性分析（Fig 5）

4. Discussion
   4.1 与 Yang et al. 的关系：互补而非矛盾
       - 他们用 FGSM 在 CAMELS-DE 上得出 LSTM 比 HBV 鲁棒——这个结论
         在 FGSM 框架下是成立的
       - 我们的贡献是表明：更强的攻击能揭示 FGSM 未发现的脆弱性
       - 两项工作共同说明：鲁棒性评估需要多层次的压力测试
   4.2 对实际部署的启示
       - 不是说 LSTM 不能部署，而是部署前需要充分的压力测试
       - 洪水预警等高风险场景应采用更严格的鲁棒性标准
   4.3 防御方向展望
       - 对抗训练、ensemble、输入不确定性量化
   4.4 局限性
       - 仅测试了单一模型架构（CudaLSTM）
       - 未包含概念模型对比（Yang et al. 已做）
       - CAMELS-US 单一数据集

5. Conclusions
```

---

## 与 Yang et al. (2026) 的定位关系

| 维度 | Yang et al. | 本文 | 互补性 |
|------|------------|------|--------|
| 数据集 | CAMELS-DE (1347) | CAMELS-US (520) | 跨区域验证 |
| 模型 | LSTM vs HBV | CudaLSTM | 他们已做模型对比 |
| 攻击 | FGSM only | FGSM + **APGD** + 3 random + C&W + Causal | 攻击深度 |
| 约束 | Physical only | Lp + Physical + **Statistical** | 约束完整性 |
| 时序分析 | 无 | **Causal Trigger** (1/3/7/14d) | 时序维度 |
| 核心贡献 | 建立方法论框架，LSTM vs HBV 对比 | 攻击方法选择的影响，更深层的脆弱性分析 | — |

我们不需要重复他们的 LSTM vs HBV 对比，而是在攻击方法维度上做更深入的探索。两篇论文互为补充：他们回答了"LSTM 和概念模型谁更鲁棒"，我们回答了"用什么方法做压力测试才够充分"。

---

## 目标期刊

**Water Resources Research** — 方法论深度 + 对部署安全的实际警示 + 与 Yang et al. 形成有价值的学术对话

---

## 当前状态

- [x] 代码框架：10 种攻击、3 层约束
- [x] HPC 全量实验（探索版）：520 basins × 16,563 records（已被正稿数据覆盖）
- [x] HPC 全量实验（正稿）：531 basins × 17,523 records（2026-04-27 pivot 后）
- [x] 分析出图：3 表 5 图（已修订为 publication quality）
- [x] 正式主线收束：2026-04-27 `3a8b7e0` 切到 `531/with-static`，`.md` 草稿不再维护
- [x] 论文撰写：LaTeX 正稿在 prose-级修润阶段（`main.tex/pdf` + `supporting_information.tex/pdf` 齐全，已编译）
- [ ] 内部审阅
- [ ] 投稿
