# G3 阶段二：交互机制价值对照 结论闭合 — 2026-07-23

设计冻结：`docs/plans/2026-07-23-g3-phase2-interaction-value-comparison-design.md`
配置：`src/hbv_multilead_joint_uncertainty/configs/g3_phase2_interaction_value_param_switch_v01.json`（sha256 `6b0c4ab18eb4eaa04a0d79ca5f7c0893317717d4238d05ff0adc4321cfcde981`）
封存证据：`results/23_hbv_multilead_joint_uncertainty/g3_phase2_interaction_value_param_switch_v01/`

## 1. 完整性（integrity_status = passed）

- **交叉核对逐位一致**：复现的 parameter_only `full` 臂预报、无噪真值预报、含噪观测与已封 G3 门证据（`evidence.npz` sha `77f84d79…`，parameter_only 在门证据的 method 索引 2）**byte-identical**。→ 阶段二复用的是**与门逐位相同的真值**，门轮判定未被触碰（线未动）。
- 受保护产物执行前后哈希不变（门证据 + 全部冻结输入 + 设计/闭合文档 + 两配置）。

## 2. 结果（看结果前冻结的判据；机器输出）

**预报 RMSE（越低越好）：**

| lead | full | none | static | oracle |
|---|---|---|---|---|
| 1 天 | **1.529** | 1.651 | 1.760 | 1.654 |
| 3 天 | 3.082 | **2.735** | 2.859 | 2.742 |
| 7 天 | 7.201 | 6.624 | 7.011 | **6.565** |

**识别（真候选后验中位概率，越高越好）：** full [0.998, 0.998, 1.000]；none [0.963, 0.948, 0.959]。

**假设判定：** **H1 成立**（逐阶段 full median 真概率 ≥ none）；**H2 不成立**（full≤none≤static 的 RMSE 序不成立）；**H3 不成立**（full 未比 static 更接近 oracle：|full−oracle|=0.125/0.340/0.637 vs |static−oracle|=0.106/0.116/0.447）。

**配对 block-bootstrap（20000 次，种子 3306757）：** full−none 均值 [−0.39, +2.02, +7.99]，CI 下界 [−1.27, **+0.66**, **+4.03**]——lead 3/7 整段 >0，即 **full 在 3/7 天预报显著劣于 none**。none−static 各 lead CI 跨 0（不显著）。

## 3. 判读（负结果，忠于数组）

- **交互加识别**（H1 成立）：完整 IMM 的权重/似然递归把后验更集中在真值上（0.998 vs 0.96）。绝对差不大（两者均 >0.94），但方向一致。
- **交互不加预报、长 lead 净负**：full 仅在 1 天最好（甚至微超 oracle，短期跨近似候选的集成平滑效应）；**3/7 天变四臂最差**，比"无交互似然"(none) 显著更差。机制假说（非定论）：完整 IMM 每个预报日做**状态混合**，把错误候选的状态动力学掺入，多天累积退化——这是冻结 IMM 的定义行为（`full` 臂 TDD 锚定与冻结运行器逐位相等，非 bug）。
- **oracle ≈ none**：即便**精确知道真模型**，预报 RMSE 也几乎不比简单无交互似然滤波强（各 lead 差 ≤0.06）。→ 理想条件下预报技巧几乎被简单似然滤波吃满，留给识别/交互机制去捞的预报头寸很小。

**一句话**：交互机制的价值是分裂的——**识别值（H1），预报不值、长 lead 倒扣（H2/H3 不成立）**。

## 4. 两层独立审查（均过）

- **复算层**（独立子上下文，numpy 从 evidence.npz 从零重算，不信 summary）：平方误差、四臂×三 lead RMSE、两对配对 bootstrap（mean/CI）、full/none 识别中位、H1/H2/H3、oracle_ratio、交叉核对——**全部 maxdiff 0.00e+00 逐位一致**，无一不符。脚本 `scratchpad/verify.py`。
- **方法层**：配置仅复用门轮输入源（param/process/obs 三 sha 与门同）+ bootstrap 3306757 + adaptation 5 + hypotheses；交叉核对逐位证真值同源；四臂 TDD 锚定（`full`==冻结运行器逐位、`static`/`oracle` 逐位符定义）；识别主判据=后验概率质量（argmax 不进判定，落实门轮判据教训）。

## 5. 边界（scope，不外推）

理想条件**单点**（间距 m=8、L=180、噪声 2.6%）。状态混合在候选**分得最开**时最伤预报；紧条件下（候选相似）权衡可能不同。结论只覆盖"理想条件下交互对识别与多 lead 预报的价值"，不外推其它间距/预算/噪声/场景/真实流域。

## 结论

阶段二价值对照完成，两层审查逐位通过、完整性干净（真值与门逐位同源、门轮未动）：**交互机制加识别、不加预报**——完整 IMM 把真候选后验从 0.96 提到 0.998（H1 成立），但其状态混合在 3/7 天预报上**显著劣于**无交互似然（H2/H3 不成立），且 oracle 几乎不比 none 强（预报技巧被简单似然滤波吃满）。这是干净的负结果，直接回答"交互值不值"：识别值、预报不值（长 lead 倒扣）。与 G3 门（理想条件可识别）、G2（紧条件认不出）合成 ID23 的完整叙事：能识别时，识别本身对多 lead 预报的增益也很有限。
