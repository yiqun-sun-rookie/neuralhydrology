# G3 阶段一：完整 IMM+HBV 理想实验准入门 设计冻结 — 2026-07-23

状态：**冻结于任何生成/运行之前**。本阶段回答一个可独立检验的准入问题：

> 完整交互式多模型（带状态交互 + 权重递归，`interaction_mode="full"`）+ 15 状态 HBV，在**理想合成实验**（真值全已知、真候选必在候选集内、间距最宽 + 预算最长 + 噪声最低）下，能否**稳定认出真值**？

依据用户 2026-07-23 设定的 G3 目标与三条理想实验条件（已知真值 / 真候选在集内 / 条件最优）。这是**准入门**，不是加分项：

- **过** → IMM+HBV 管线证成，ID23"认不出"边界（G1/G2）站得住，进入阶段二（IMM vs 无交互似然 vs 静态混合 vs oracle 的价值对照）。
- **不过** → 停下诊断"为什么连理想实验都过不了"（管线 bug 或方法不成立），**不报任何识别边界为有效**。诊断本身即交付。

## 1. 为什么用理想条件当门（方法论）

现有完整 IMM+HBV 冻结运行 `three_stage_parameter_switch_v02` 只在**必败的紧条件**（L=15、基线间距 m=1、标准噪声）下跑过，三阶段识别全 False（真候选中位概率 0.32–0.39 ≈ 均匀 0.33）。这只证明"紧条件下认不出"，不能排除"管线本身坏了"。理想实验把任务降到**最易、最干净、无借口**：真值已知（有答案 key）、真模型摆在候选集内（设定正确的最易情形）、条件最优。连它都过不了，就只能是管线/方法问题。

## 2. 理想条件（相对已冻结 v02，只改三个旋钮 + 判据）

复用 `three_stage_parameter_switch_v02` 的一切，仅改动使实验从"紧"变"理想"的三项，以隔离条件效应：

| 旋钮 | v02（紧） | 本阶段（理想） | 依据 |
|---|---|---|---|
| 候选间距 | m=1（基线） | **m=8**（最宽，已界内校验） | g2_spacing_inputs_v01/parameter_vectors_m80.csv |
| 每阶段预算 | L=15 | **L=180** | G2 已证 L=180 似然可分区 |
| 观测噪声 std | 0.946 mm/day（相对 ~14%） | **0.17798 mm/day**（= 2.6% × 均值流量 6.845） | 锚定 MATLAB 有利档相对噪声 2.6% |

不变项（与 v02 逐字相同）：scenario=parameter_switch、process_2 固定、warmup 45、`factor_transition_stay_probability=0.98`、`initial_covariance_fraction=0.001`、lead_days [1,3,7]、8 区块、bootstrap replicates 20000、integrity_gates。`reference_total_days = 45 + 3×180 + 7 = 592`。

**解释边界（预登记）**：间距 m 同时放大真值轨迹与候选差异（沿用 G2 声明）；低噪声同时降低生成噪声与滤波器假定噪声（well-specified，理想情形）；这是"最优条件"的定义，不是数据操纵——判据在看结果前冻结。

## 3. 准入判据（一次冻结，看结果前生效）

运行器 `three_stage_switching_validation` 对 parameter_switch 的每阶段判定：
`identification_passed = (primary_candidate_argmax_accuracy ≥ factor_argmax_accuracy_minimum) 且 (median_primary_true_candidate_probability ≥ median_true_candidate_probability_minimum)`

理想门把两阈值**调严**（远高于 v02 的 0.667 / 0.2，编码"清晰认出"）：

- `factor_argmax_accuracy_minimum = 0.9`（argmax 落真候选 ≥90% 评分日）
- `candidate_argmax_accuracy_minimum = 0.9`（联合口径同调，parameter_switch 实际只用 factor）
- `median_true_candidate_probability_minimum = 0.5`（真候选中位概率 ≥0.5，3 候选中占多数权重；均匀=0.33）

**门判定（预冻结语义）**：
- **PASS** = 三阶段 `identification_passed` 全 True（summary 的 `identification_passed_all_three_stages=True`）→ 管线证成，开门。
- **FAIL** = 任一阶段未达 → 停。进入管线诊断（低噪声/宽间距下逐阶段概率轨迹、滤波器数值健康、权重递归行为），**不报任何边界为有效**。禁止调判据或换种子救。
- 每阶段适应期排除首 5 日（沿用 v02）。

## 4. 种子（全新段 33x，避开已用 990001–998012 / 3001001–3002012 / 3110001–3250018 / 676701 / 575757）

- forcing 3301001–3301008；process 3302001–3302008；observation 3303001–3303008；bootstrap 3305757
- 发散冒烟（废弃，不作证据）：forcing 3309901；process 3319901；observation 3329901

## 5. 实现（复用优先，近零新代码）

- 运行器 `run_three_stage_switching_validation.py` **零修改复用**（`interaction_mode="full"` 已内建；识别判定 config 驱动）。
- 新增仅一件数据生成：`scripts/make_g3_ideal_inputs.py` → 密封 `g3_ideal_inputs_v01/`（低噪声 CSV + manifest + 校验和）；低噪声值 = 0.026 × 6.845259423847285 逐位可复算。
- 门判定直接读运行器自产 `summary.json` 的 `identification_passed_all_three_stages`，无需新判定代码。
- 资源：运行器自带资源预检；L=180×8 区块×完整 IMM+预报，按资源试点 11.4 s/区块@L=15 线性外推 ~137 s/区块 → ~18 min，单配置，让运行器预检把关内存。

## 6. 两层独立审查（阶段末）

- 第一层（方法）：理想条件是否只改三旋钮、判据是否看结果前冻结且严于 v02、运行器是否零改动、种子是否全新段。
- 第二层（复算）：从密封 evidence.npz 的完整 IMM 概率数组独立复算三阶段 argmax 准确率与真候选中位概率，与运行器 identification_passed 逐阶段对照。

## 7. 明确不做

- 不动任何冻结证据与运行器逻辑；不移植 HBV 进 MATLAB；不做过程噪声/联合场景、噪声轴扫描（本阶段单点理想条件）；不做真实流域/论文写作。阶段二（价值对照 + oracle 构造）待本门 PASS 后另行冻结。
