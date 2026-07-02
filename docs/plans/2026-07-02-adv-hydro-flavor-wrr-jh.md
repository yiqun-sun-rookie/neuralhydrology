# ID05 对抗论文水文深化 → WRR/JH 计划（2026-07-02）

供 /goal 迭代使用。**"claim 边界"和"正确性修正"是硬护栏；其余（包括探索方向池）全部自由探索，可增删。**

## 目标

在已验证的雪脊柱（L0–L3，已入 main.tex、已过独立审查、未 commit）基础上，把
`draft/papers/05_adversarial_latex/main.tex` 的水文内容推进到 WRR / Journal of Hydrology 可投状态。
最终交付：稿件全稿一致（标题/摘要/PLS/正文/SI 两条脊柱对齐）、全部数字可溯源、独立审稿无 blocker，
并给出 WRR vs JH 各自的投稿差距结论。

## 已核验的证据现状（2026-07-02，7 个独立 agent：4 核验 + 3 评审，全部通过）

- **雪 = 全稿唯一完整机制链**（更脆 0.507 vs 0.319 且拟合更好 → 攻击切气温通道 0.11→0.27 → 削峰 −18% vs −7%、9/107 峰时移全雪区 → 幅度真实 0.45×）。数字全部逐位复算通过。
- **干旱端只有"梯度"没有"机制"**，且两个结构问题补跑也修不了：
  1. **归因不可分**：aridity/p_mean/runoff_ratio/q_mean 互相关 |ρ|0.60–0.94；控制 q_mean 后
     D~aridity 偏相关 +0.180→−0.127，amp~aridity +0.227→−0.017，q_mean 自身 −0.277/−0.271。
     "气候干旱"与"小河低均流 NSE 脆弱"（dry 流量 CV=6.2 vs humid 1.9）统计上分不开。
  2. **低流量机制指标全失效**：D_lowflow 有 NSE 加权循环（干旱区低流日仅占 NSE 方差 0.35%，
     机制天花板 ~0.004；且 D_lowflow 混淆攻击窗口与误差位置，如 06352000 D_lowflow=0.288≫天花板）；
     double_frac_low 的 0.01 mm/d 下限在 5/7 干旱流域 100% 触底，去掉后结论翻转
     （dry 0.197 vs humid 0.057, p=0.024）——间歇河里没有可信指标。
- **评审 3/3 一致**：框架 = 雪唯一机制范例 + 干旱降级为"湿-干/流量量级梯度"一段。
  **不要再尝试立第二机制轴**，除非新设计同时绕开上述两个结构问题。
- 可用的干旱端结果（V1 CONFIRMED）：偏相关（控 frac_snow+nse_clean, n=531）aridity +0.180 /
  p_mean −0.259 / runoff_ratio −0.251 / q_mean −0.277；amp(=D_APGD/D_rs100)~aridity +0.227 (p=1.2e-7)，
  内部稳健（1e-3 clip 从未触发，min D_rs100=0.0040；分母与 aridity 无关 +0.001；剔 D_rs100≤0.01 仍 +0.212）。
  **⚠ Round1 追加复核：amp 组中位反向（dry 9.9 < humid 15.0 < snow 16.7），主张不稳定，已撤下正文（见第 8 条）。**
- 通道归因（V2）：离散"干旱切换"无证据（precip_share dry 0.464 ≈ humid 0.459, p=0.80），
  但 precip_share~aridity 连续梯度在非雪流域内部成立且更强（+0.361, p=2e-3, n=71；雪区内 +0.50）。

## 正确性修正（与框架无关，必须做）

1. main.tex 称 107 子集为 "every fifth benchmark basin"——**2026-07-02 Round1 复核：指控被证伪，降级为表述精确化**。
   107 = `src/adversarial/data/531_basins.txt`（run list 顺序，非按 ID 排序）的 [::5]，集合逐流域吻合
   （V4 拿按 ID 排序后的 CSV 做 [::5] 才得 36/107）。稿件措辞只需明确"按 benchmark 清单顺序取每 5 个"；
   可加分布代表性注（KS 全 p>0.6，regime 计数 7/64/36 vs 期望 8.7/67.7/30.6）。
2. 若新增"损失技能比例"（D/cleanNSE）类表述：必须写明剔除 3 个 clean NSE≤0 干旱流域
   （07299670/08194200/09484600）后 dry 0.734 > snow 0.654；不剔除则雪区最大（0.654 vs 0.532）。最安全=不写。
3. 若 Part C 过程线数字入稿：加一行稳健性注——干旱区 clean 预测为负值天数中位 8.6%（最大 33.8%，
   08190500）；预测截断为 0 后各组中位变化 ≤6.1%、无符号翻转；dry 中位受离群流域影响
   （06352000 bias_rel +1.42），判断依赖偏相关而非中位数。
4. SI 注 p 值 df 约定（偏相关 n−2 vs n−2−k，如 2.9e-4 vs 3.3e-4，结论不变）。

## 梯度段 claim 边界（硬）

5. 措辞一律 **wet-dry / flow-magnitude gradient**，禁 "drought vulnerability/mechanism" 因果标签；
   必须披露 q_mean 敏感性（上面的翻转数字），解释为不可辨识（q_mean 可为中介）而非否证。
6. 机制 null 一律 "no evidence of" + 功效警告（干旱非雪 n=7，最小可检 Cohen's d≈1.11）；
   明写雪-干不对称部分是功效不对称。低流量机制写 **inconclusive**（理由见上），禁写"干旱无低流量机制"。
7. 不得写"aridity 梯度由雪端驱动"（已被非雪内部检验证伪）。
8. **amp 主张已撤下（2026-07-02 Round1）**：组中位数与条件相关方向相反（dry 9.9 < humid 15.0 <
   snow 16.7；+0.227 仅在控雪+skill 下出现，加 q_mean 塌到 −0.02）——"梯度审计优势在干旱区最大"
   随条件化翻转，不稳定，**正文不写**；至多 SI 一注说明其不稳定性。§4.3 原句"hierarchy nearly
   independent of catchment type"已软化为"holds at roughly an order of magnitude or more in every
   catchment class"（amp 中位 9.9–16.7 支持）。
9. 位置硬约束：§3.2 末一段 + §3.3 一句 + Discussion 一从句 + SI panel；
   **不进标题/摘要/Keypoints**；"extractability" 只能作 Discussion 一句展望。

## 收尾项

10. 先 commit 现有雪脊柱改动（含新脚本/artifact），本轮增补在其上，保证修改链可追溯。
11. PLS 更新：补雪脊柱 1–2 句（现为纯攻击方法版）。
12. 标题重构：反映"攻击方法选择 + 水文脆弱性结构"双脊柱，出 3–4 候选供用户选。
13. SI 补水文：梯度 panel + 上述稳健性注；SI 与正文数字交叉核对。
14. 终检：编译通过；每个新数字溯源到 `results/05_adversarial_robustness/id18_s100/` 的 artifact
    或 `src/adversarial/scripts/` 的脚本；用 wrr-paper-review（或等效独立审稿子代理）按 WRR 标准
    过一遍，无 blocker；输出 WRR vs JH 投稿差距结论。

## 探索方向池（非必做，自由增删）

- amp 逐流域地图/图版，把"哪里最需要梯度审计"可视化并挂回主轴。
- 雪机制补强（如攻击伤害的季节分布：融雪期 vs 非融雪期）。
- 保矩 QC 规避结果的水文分层（哪类流域最容易被躲过质检）。
- 面向业务的含义表（预报机构：哪些流域该做对抗压力测试）。

## 资源与坑

- artifact：`results/05_adversarial_robustness/id18_s100/`（hydro_vulnerability_summary.csv 531 行 /
  exp_l1l2_summary_eps0.1.json + l1l2_records 107 npz / l1_attribution_summary.csv /
  l2_signatures_summary.csv / drought_mechanism_summary.csv）；分析脚本 `src/adversarial/scripts/`
  （新增 analyze_drought_mechanism.py）。
- victim：`results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30`（test 中位 NSE 0.733）。
- GPU0 与其它任务共享（112–170 s/流域）；43 个干旱非雪流域补跑 ~2h，**仅当**某改进明确需要
  有功效的 null 才做，且先在轮报告里声明。
- 后台跑用裸 `python -u` + 后台工具，别 `nohup … &` 嵌套（会被杀）；runner 按已存 npz 自动续跑。
- L∞ 攻击每通道饱和 ±ε → 通道归因必须用留一法，不能用扰动能量。
- 期刊背景：WRR 全文原样评估 ~10–25%（创新性硬伤），水文脊柱是补短板动作；JH 接受度更高；
  此前 HESS 曾评为主选——最终由用户按差距结论拍。

## 进度记录

- **Round 1（2026-07-02）**：①雪脊柱 baseline 已 commit（`45aa837`，16 文件，含 107 子集措辞精确化）。
  ②"every fifth"指控复核后证伪（107=531_basins.txt 文件顺序 [::5] 逐流域吻合），降级为措辞精确化并已改。
  ③amp 主张复核后撤下（组中位反向，见第 8 条）。④梯度内容落地：§3.2 末新段（湿-干伤害梯度+
  不可辨识披露）、§3.3 末新段（无通道切换+连续梯度+n=7 功效+低流量 inconclusive）、§4.3 软化
  hierarchy 句+一句无机制解读声明；全部数字溯源 analyze_drought_mechanism.py（新增 Section D:
  互相关矩阵/q_mean 翻转/非雪内部 +0.361）。⑤编译 exit 0，21 页。⑥独立审查+复核：见下轮报告。
  待办→Round 2：SI panel+稳健性注、PLS、标题候选、独立审稿终检。
- **Round 2（2026-07-02）**：PLS 补雪脊柱句（`5259ede`）；SI 新增 Text S4 + Table S4（湿-干梯度全部偏相关/q_mean 翻转/p_mean 衰减/非雪 null）；复现表补 hydro-attribution 脚本。主 21pp、SI 4pp exit 0。
- **Round 3（2026-07-02）= 收敛闸门**：独立 `wrr-paper-review` agent（新 context 读 PDF + 实跑 analyze_drought_mechanism.py）返回。**无科学 blocker**；数字溯源评 A（headline + SI S4 全部逐条复现）。
  - 已做（路线无关，`9f4e419`）：M5 织入已存在却未引的文献（Intro: Beven2006/Kavetski2006/Renard2010/Clark2008/McMillan2012；Discussion: Klotz2022/Frame2022/Lees2021）；软化 over-claim（"reflects"→"consistent with"、"distributed across accumulation season compound"→"spread over many timesteps can compound"、结论"exposing"→"pointing to"）；m1 "equal"→"comparable sampling budget"。exit 0。
  - **待用户拍（全部用户门控，故 loop 停）**：①期刊路线 JH（1–2 周小修可投）vs WRR（3–6 周：reframe+M2 全雪区机制+M3 多 seed）②B1 repo Zenodo DOI（占位符 line 358，需用户建 archive）③B2 致谢文本（line 361 占位）④标题 reframe（WRR 必需/JH 可选，候选已在报告给出）。
  - 未做（用户门控/需 GPU）：M1 reframe、M2（全 152 雪区重跑温度归因/峰值/timing，~GPU）、M3（2–3 seed 复核）、M4 季节能量归因图（WRR 加分）。
