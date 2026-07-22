# ID09 三方独立核查 · 报告②（ML / 方法学视角，盲于水文）

**核查日期**: 2026-07-22 ｜ **裁决**: 组合层面空白、部件全已做(partial-novel)，置信度 ~72%
**⚠️ 取证**: WebFetch 全程 403（连维基百科也 403，通道级全域拦截）。无 [V]，全部 [S] 摘要/[U] 先验。

---

## 1. 裁决
四元组合（独立训练的循环 regime 专家 + 运行时硬切换 + 跨**不对齐**隐状态空间的显式移交算子 + 无需重新 warmup）作为一个具名方法**未被发表，置信度 72%**。扣分因为每个部件都成熟、可拼装，方法学审稿人几乎必然打"trivial composition of switching-MoE + model-stitching"。
**护城河（结构性区分）**：几乎所有 switching 模型（rSLDS/SNLDS/RED-SDS/DS3M/Markovian RNN）用**单一共享连续潜态 + 联合训练**，regime 只切换动力学/转移权重，**从不在两个独立训练、隐空间不对齐的模型间移交状态**（它们只有一个状态空间）。

## 2. 最近邻工作表（节选）
| Citation | 独立训练 | 切换 | 状态 | 跨不对齐空间 | 差异 |
|---|---|---|---|---|---|
| rSLDS (Linderman 2017) | 否(联合) | 软 | 共享单一潜态 | 否 | 单潜空间，regime 换线性动力学 |
| SNLDS/RED-SDS (2020/21) | 否 | 软 | 共享 | 否 | 深度化+停留时长；仍单潜态 |
| Markovian RNN (Ilhan TNNLS 2021) | 否 | 软(HMM权重混合) | 共享单一cell态 | 否 | 每 regime 控制**同一** cell 转移权重 |
| MoE-Mamba/Routing Mamba (24-26) | 否 | 硬(token路由) | 递归态在共享主干连续 | 否 | 参数MoE，主干态贯穿，联合训练 |
| Model Stitching (Bansal 2021) | **是** | 无 | 对齐**前馈层**表征 | **是**(仿射) | 离线缝成一个网络，非时序、无递归态、无切换 |
| Linear Representation Transferability (2506.00653) | **是** | 无 | 隐态间线性映射 | **是** | LLM 静态隐态对齐，非循环时序移交 |
| Git Re-Basin (ICLR 2023) | **是** | 无 | 置换对齐后合并 | **是**(置换) | 离线融合成一个模型，非运行时移交 |

**没有一行同时命中：独立训练 + 硬切换 + 递归状态移交 + 跨不对齐空间。** 命中"独立+跨不对齐对齐"的（stitching/LRT/Re-Basin）都**非循环、无运行时切换**；命中"切换+循环态"的都**联合训练+共享单态**。此正交分裂即 novelty。

## 3. 最强驳回 + 存活 novelty
**最强驳回**："这不过是 switching-MoE 与 model-stitching 的平凡组合。"
**存活**：
1. **对象错配使拼接非平凡**——stitching 对齐的是静态前馈激活、融成一个不再切换的网络；命题要对齐的是**循环、时序演化**的隐状态，两个专家**永远分离**、序列中反复硬切换，需回答 stitching 从不面对的"边界时刻递归动力学相位/记忆连续性"。
2. **"无重新 warmup"是可证伪功能主张**，switching-SSM 从不提出（只有一个状态、无 warmup 丢失问题）——独立于组合叙事的可实验贡献点。
3. **硬切换 + 独立训练的空集交点**：硬切换循环模型都联合训练共享主干；独立训练对齐的都无运行时切换。命题占两族空集交。

## 4. ML 视角特有发现（水文视角会漏）
1. **Model Stitching 系**（Lenc & Vedaldi 2015；Bansal NeurIPS 2021；Functional Latent Alignment 2025）——"用学得映射对齐两独立训练网络的不对齐表征"的正典先例，是命题移交算子的最近方法学祖先。**必须引用区分。**
2. **Linear Representation Transferability Hypothesis**（arXiv 2506.00653, 2025）——直训"源隐态→目标隐态"线性映射，比 stitching 更贴近命题。
3. **Git Re-Basin / Wasserstein barycenter fusion**——证明独立训练网络（含 LSTM cell）可经置换/最优传输对齐；同时是"离线融合≠运行时移交"的反例锚点。
4. **Markovian RNN/rSLDS 的"单一共享状态"本质**——最易被误判为"已做"，实则结构上不可能做状态移交（没有多个状态空间），正交陷阱。
5. **Dynamic TMoE**（arXiv 2605.20678）——"漂移触发 + GRU 路由器隐状态归档"，通用时序里最接近命题 (iii) 的雏形，水文侧必漏。

## 5. 引文核实层级（全部 [S]/[U]，WebFetch 403）
rSLDS AISTATS 2017 (1610.08466) [S]；SNLDS NeurIPS 2020 [S]；RED-SDS NeurIPS 2021 (2110.13878) [S]；DS3M IJF 2026 (2106.02329) [S]；Markovian RNN TNNLS 2021 (2006.10119) [S]；Namikawa & Tani 2008 (0706.1317) [S]；MOSAIC Wolpert & Kawato [U]；MoE-Mamba (2401.04081) [S]；Routing Mamba (OpenReview lqywifxoo1) [S]；BlackMamba (2402.01771) [S]；Bansal et al. NeurIPS 2021 (2106.07682) [S]；Functional Latent Alignment (2505.20142) [S]；Linear Representation Transferability (2506.00653) [S]；Git Re-Basin ICLR 2023 [U] / Wasserstein fusion (2210.06671) [S]；Hierarchically Gated Experts (2412.17188) [S]；Lenc & Vedaldi CVPR 2015 [U]。

## 6. 结论
组合空白但窄。建议贡献严格锚定"**跨不对齐循环隐空间的运行时时序状态移交算子 + 无 warmup 可证伪性**"，而非"多专家 regime 切换"这个饱和框架。72% 已计入取证不确定性；建议将来用授权通道复核 2505.20142 / 2506.00653 / 2106.02329 正文。
