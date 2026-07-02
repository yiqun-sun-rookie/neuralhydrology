# Idea 05 — Yang2026 忠实账 + 差异化定位 + 决定性实验计划

> 生成 2026-06-17，经 **3 次独立审核 + reconcile** 修订（每个审核 agent 独立重 fetch arXiv:2602.05237 核 verbatim + 读 main.tex）。
> **审核结果**：C1–C16 **真实性全 PASS**（Yang 事实与 main.tex 数值逐字对得上）。**有效性**：C13=PARTIAL(三审一致)、C7=SPLIT(已修)、§1 prose=FAIL(已按 12 条改)、实验计划=有条件 GO(已加固)。本版已落实全部 12 条必改。
> 竞品 = Yang et al. 2026, *On the Adversarial Robustness of Hydrological Models*, arXiv:2602.05237（已发 *Hydrology Research* 2026；code github stsfk/hydrological_adversarial_robustness）。

> **⚠ 头号纠正（审核迫使，且推翻我前几轮的乐观）**：把"本文可纠正 Yang 的 gradient-vs-random"**降级**。原因：(1) Yang 的 DE911520 测的是 **ε-线性/预测敏感度斜率**，**不是 ΔNSE 伤害**——"梯度方向更伤害"与他"各方向斜率相当"**正交、互不矛盾**，不能说"纠正"他；(2) Yang 用的随机方向是 **matched-magnitude 符号向量** {−1,0,1}，他就发现"斜率相当"——这**预示实验 1 可能复现而非纠正 Yang**，现 17.5× 主要靠**弱 Gaussian baseline**，换 random-sign 后倍数可能塌到 1–2×。**现在能立的只有"方法学/样本量"纠正(514 vs n=1)**；"梯度方向特殊"这个**实质**结论**待实验 1**，且结果**真不确定**。

---

## §1 Related-Work / 反驳段（English, manuscript-ready）

### §1a —— 现在就可插入 main.tex（只含当前有证据支持的内容）

> The first dedicated adversarial-robustness analysis of rainfall-runoff models is that of \citeA{Yang2026},\footnote{Earlier adversarial work on sequential regressors (e.g.\ on generic or medical time-series forecasting, and on urban water-\emph{demand} LSTMs) exists, but \citeA{Yang2026} is, to our knowledge, the first to target catchment rainfall-runoff (streamflow) simulation specifically.} who applied the single-step Fast Gradient Sign Method (FGSM) to the meteorological forcings of an LSTM and an HBV model across 1{,}347 German catchments (CAMELS-DE). Their analysis is large-sample and carefully framed: FGSM systematically reduced KGE and increased MSE, yet the median LSTM degradation was modest (median KGE falling from 0.833 to 0.728, a change of $-0.105$, at $\varepsilon=0.2$), catastrophic failure was rare, and both the predicted hydrographs and the internal model states responded approximately linearly (at least locally) to the perturbation magnitude. On this basis \citeA{Yang2026} concluded that LSTMs are at least as robust as conceptual models---their median sensitivity slope was about a third smaller than HBV's (a $36\%$ reduction for the $\Delta$KGE slope and $31\%$ for the $\Delta$MSE slope)---and that this robustness, with their predictive skill, supports their consideration for operational deployment.
>
> Our study is complementary to that picture and extends it in three directions. First, where \citeA{Yang2026} characterise robustness with a single-step attack and summary slope statistics---noting only in passing, without reporting results, that a basic iterative method run on ``several catchments'' changed little relative to FGSM---we confirm and quantify that observation on the 531-basin CAMELS-US benchmark (iterative Auto-PGD exceeds FGSM by only $1.14\times$ at $\varepsilon=0.1$, widening to $1.41\times$ at $\varepsilon=0.2$), and we additionally report the lower tail of the per-basin degradation distribution (a median NSE degradation of $-0.41$ and roughly one-third of finite basins falling below NSE $=0$ under Auto-PGD at $\varepsilon=0.1$ on CAMELS-US) that median-and-slope summaries do not surface. Second, our stress test addresses regimes \citeA{Yang2026} did not probe: a minimum-perturbation (Carlini--Wagner) safety margin per basin, a moment-preserving constraint that tests the limits of distributional quality control, and a temporally localised pre-event attack aimed at the operational flood-forecasting window. None of these is a new attack mechanism---each adapts established machine-learning machinery (see \S\ref{sec:related-methods})---but together they give a hydrology-specific, worst-case-oriented characterisation that complements the average-case, large-sample picture of \citeA{Yang2026}. Third, we broaden the question of whether the gradient direction is special: \citeA{Yang2026} examined the \emph{linearity} of the response in directions other than the gradient sign, for a single catchment (DE911520, 100 ternary $\{-1,0,1\}$ directions), and found comparable per-direction slopes; we examine the \emph{damage} (NSE loss) caused by gradient-based versus gradient-free perturbations across 514 finite-NSE basins. These are distinct, mutually consistent quantities---comparable per-step sensitivity slopes do not imply comparable accumulated skill damage---so our result complements rather than contradicts theirs, and its principal value here is breadth (514 basins versus one) and a decision-relevant damage metric.

### §1b —— **待实验 1 跑完才能插入**（现在 main.tex 无 random-sign baseline，写了即伪造结果）

> *[PENDING EXPERIMENT 1 — do NOT insert until the random-sign baseline is run.]* Whether gradient-based perturbations are substantially more damaging than gradient-free ones is sensitive to the gradient-free baseline. Our primary random baseline is i.i.d.\ Gaussian noise, an interior-$L_2$ probe that is weaker than the $L_\infty$-magnitude $\{-1,0,1\}$ sign-vector directions of \citeA{Yang2026}; the large Auto-PGD-to-Gaussian ratio we observe ($17.5\times$ at $\varepsilon=0.1$) therefore conflates direction with perturbation energy. To isolate the role of \emph{direction}, we add a matched-structure random-sign baseline and report both the FGSM-to-random-sign ratio (single-step, equal-budget) and the Auto-PGD-to-random-sign ratio (Section~\ref{sec:caveat}). *[Outcome A: if the gradient still dominates a matched random-sign baseline, the direction is genuinely special and this also extends \citeA{Yang2026}'s single-catchment linearity observation to a damage metric at scale. Outcome B: if the ratio collapses toward unity, the $17.5\times$ is largely a weak-Gaussian artefact and only the breadth correction (514 vs.\ 1) stands; we will rewrite the headline accordingly.]*

**§1 自带诚实边界（审核新增第 5 条已落实）**：
- (b1) 不自称 "first iterative/Auto-PGD"；"first" 只给 Yang，且加脚注界定为"rainfall-runoff 专属首篇"。
- (b2) 迭代轴 = "confirm and quantify"，非 refute。
- (b3) **gradient-vs-random 的强结论全部移入 §1b、标 PENDING**；§1a 只说"breadth + damage metric"，不预判 corrective。
- (b4) robust-vs-fragile = "report the lower tail that median summaries do not surface" + 显式标 "on CAMELS-US"，不说 "Yang 错/LSTM 不鲁棒"。
- (b5)〔新〕不把 Yang 的 linearity/slope 结果说成 "damage" 比较；明确两者正交、consistent。

---

## §2 差异化表（Yang 做了 vs 我们做）

| 维度 | Yang2026 | 本文 Idea 05 | 性质 |
|---|---|---|---|
| 攻击-单步 | FGSM（headline，带数） | FGSM | 重叠 |
| 攻击-迭代 | BIM，"several catchments"，**未报数**，≈FGSM | Auto-PGD 50it，全 531 流域带数（APGD/FGSM=1.14×→1.41×@0.2） | 我们**量化确认**他未报的观察（非纠正） |
| 攻击-最小扰动 | 无 | C&W 回归，per-basin min-L2-to-NSE<0 | hydrology 内独有（**方法借 Fre-CW**，非新机制） |
| 约束 | physical | magnitude/physical/**statistical(矩保持)** | hydrology 内独有（**概念借 Imgrund/TSA-STAT**） |
| 时序攻击 | 无 | **causal-trigger 洪峰前窗口** + flood/low-flow targeted | hydrology 内独有（**机制借 Chen&Zhu/Zhang**） |
| 方向是否特殊 | DE911520 **1 流域**，100 个三元方向，测 **ε-线性/斜率**（Fig13 报直方图斜率统计，**非"无数值"**） | 514 流域，测 **ΔNSE 伤害**；17.5× 是 **APGD/Gaussian(弱 baseline)** | **不同量(斜率 vs 伤害)**；本文优势=**样本量 514 vs 1**，非 like-for-like 幅度;实质比较待 Exp1 |
| 度量 | KGE/MSE，中位/斜率 | ΔNSE 分布 + %跌破0 + 尾部（CAMELS-US/NSE 口径） | 我们看 worst-case 尾 |
| 数据 | CAMELS-DE 1347 德国 | CAMELS-US 531 | 同任务异区域（跨数据集，非复现 Yang） |
| 结论 | LSTM 鲁棒 → 可部署 | worst-case 尾部更脆（**须 Exp2 apples-to-apples 才能 claim 纠正**） | 互补；实质纠正待证 |

> **§2/§1 用到的"借方法"四引文（Fre-CW / Imgrund / TSA-STAT / Chen&Zhu，及 Govindarajulu2023 / Homaei2025 / Anand&Pappas2026）目前 main.tex 与 references.bib 均无 → 用前必须补进 .bib，否则"no new mechanism"免责声明无依据。**（来源已在前两轮 workflow 联网 verified，见 memory `adversarial_paper_handoff.md`）

---

## §3 决定性实验计划（一页，已按审核加固）

> 目的：把"被 Yang 抢先"翻成"严格评估"，并**诚实地**检验 gradient-vs-random 实质结论。实验 1 结果**真不确定**——可能纠正 Yang，也可能复现 Yang（届时 17.5× 证实为 Gaussian artifact）。

### 实验 1（决定性）：把"方向是否特殊"打成铁案 —— **承认可能两种结局**
- **动机**：现 17.5× = APGD/Gaussian（弱、内部 L2）；Yang 用 matched-magnitude 符号向量就发现"斜率相当"。必须用**同结构**随机 baseline 才能分清"方向特殊"vs"Gaussian 太弱"。
- **做法（4 条加固）**：
  1. 新增 `random_sign`：ε·v, v∈{−1,+1}^(T×F)（**用 {−1,+1} 无零，或对 APGD 做 L2-match**，消除 ~1.2–1.4× 残余 L2 混淆；若用 Yang 的 {−1,0,1} 则显式标"故意保守 baseline"）。
  2. **主指标 foreground = FGSM / random_sign**（单步 vs 等预算最坏随机 = 纯"方向"对照；APGD/random_sign 留作"方向+优化"合并效应,不当主指标）。
  3. **搜索深度对称**：random_sign 报 **worst-of-K 敏感性,K 上到 ~100**（对齐 Yang 100 方向 / APGD 50 迭代），堵"随机空间搜得太浅"反驳。
  4. **度量对齐**：要么复现 Yang 的**逐日 slope/linearity** 指标在 gradient vs random_sign 上重算（直接对话他的 DE911520），要么在文中**明说本实验测的是 ΔNSE 伤害这一不同量**。
- **成功判据（双结局都诚实）**：报 APGD/Gaussian、FGSM/random_sign、APGD/random_sign 三比值。
  - **结局 A**：FGSM/random_sign 仍 ≫1（多 basin 成立）→ 方向确实特殊，且把 Yang 单流域 linearity 观察**扩到 514 流域的伤害量**。
  - **结局 B**：塌到 ~1–2× → 原 17.5× 主要是 Gaussian artifact，主信息退回"gradient>gradient-free 但有限"，**仅保留 514-vs-1 方法学纠正**，改写 headline。
- **成本**：复用现 APGD/FGSM，只新增 1 random 方法 ×4 ε ×531 ×worst-of-K，GPU 数小时。

### 实验 2（robust-vs-fragile 能否 claim 纠正 + 修 main.tex 现存 over-claim）
- **动机**：Yang 中位 KGE−0.105(温和) vs 本文 NSE−0.41+32.5%<0(严重),混了 **NSE-vs-KGE / neg-NSE-loss / worst-vs-median / ε(0.1 vs 0.2) / US-vs-DE** 五重混淆。**注：main.tex Discussion 4.1(line 299)已存在此 over-claim**（"catastrophic rare harder to defend … at the same budget" 却悄悄换成 US+NSE<0 对 Yang 的 DE+KGE-无阈值）——本实验同时修它。
- **做法**：(a) 同度量复算 **中位 ΔKGE**(本文 531, APGD@0.1/0.2)对 Yang 同口径；(b) 把 32.5%<0 按 **clean-NSE 分层**,查脆弱是否集中在低裕度流域(Yang 注"大跌来自低 unperturbed KGE");(c)(可选最强) 在 **CAMELS-DE** 复用一 LSTM 跑本文 APGD,消 dataset 混淆。
- **成功判据**：分歧归因清楚后,论文只 claim 证据支持的那部分;否则 Discussion 4.1 收窄为 "on CAMELS-US under NSE"。

### 实验 3（可选，最低优先）：gradient-masking sanity（回应 Anand&Pappas 2026）
- 跑 1 个非梯度/transfer 攻击,确认 APGD 非被 masking 限制(APGD 本身抗 masking,故最低优先);transfer ≤ APGD → 一句 limitation。

---

## §4 逐条 Claim 溯源表（审核后状态：真实性 / 有效性）

> 类型：F=事实；I=推断。来源 Y=Yang2026(3 审重 fetch verified)；M=main.tex；L=前两轮 workflow verified 文献。

| # | Claim | 真实 | 有效 | 备注（审核后） |
|---|---|---|---|---|
| C1 | Yang FGSM,1347 CAMELS-DE,LSTM vs HBV | PASS | PASS | abstract verbatim |
| C2 | LSTM 中位 KGE 0.833→0.728,Δ−0.105@0.2 | PASS | PASS | 0.833 为正文直引,非仅算术 |
| C3 | "catastrophic rare";仅 5/1347 LSTM、3/1347 HBV 变好;无阈值 | PASS | PASS | 5/3 是"变好"非"灾难",已正确标 |
| C4 | LSTM>HBV 斜率 −0.479 vs −0.753 | PASS | PASS | §1 衍生"36–40%"→**已改 ~36%/31%** |
| C5 | 近似(局部)ε-线性 | PASS | PASS | abstract verbatim |
| C6 | BIM 仅"several catchments"、未报、≈FGSM | PASS | PASS | 最强引,用于禁本文"first iterative" |
| C7 | random-vs-gradient 仅 DE911520,100 个 {−1,0,1} 方向 | PASS | **已修** | Fig13 caption 为证;**纠正:Yang 测 linearity/slope 且有直方图统计(非"无数值");§2 已改** |
| C8 | Yang 结论支持 LSTM 部署 | PASS | PASS | abstract verbatim |
| C9 | APGD/FGSM=1.14×@0.1(→1.41×@0.2) | PASS | PASS | 与 Yang BIM≈FGSM 一致(确认非矛盾) |
| C10 | APGD median ΔNSE−0.408;32.5%<NSE=0 | PASS | PASS | 167/514=0.3249 |
| C11 | 17.5×=APGD/**Gaussian**;Gaussian=i.i.d.N(0,ε²)clip | PASS | PASS | 诚实标弱 baseline |
| C12 | 17.5× baseline-依赖,须 random-sign 验 | PASS | PASS | L2 差~1.4×(对 Yang {−1,0,1} 更只~1.14×)不足解释 17.5×→定性真、幅度待验 |
| C13 | random-vs-gradient 轴本文可"纠正"Yang | PASS | **PARTIAL→已降级** | **仅方法学/样本量(514 vs 1)纠正现成立;实质"方向特殊"待 Exp1,且 Yang matched 探针预示可能复现;度量(slope vs ΔNSE)正交** |
| C14 | robust-vs-fragile 真分歧但多重混淆,须 apples-to-apples;反向风险=低-clean-NSE | PASS | PASS | **已补混淆:ε(0.1 vs 0.2)、slope-vs-ΔNSE、US-vs-DE** |
| C15 | C&W/statistical/causal 是 Yang 没碰的regime;方法非新(借 Fre-CW/Imgrund/TSA-STAT/Chen&Zhu) | PASS | PASS | §2 已改"hydrology 内独有(方法借…)";**须补引文进 .bib** |
| C16 | 删所有"first iterative/Auto-PGD on rainfall-runoff LSTM" | NA | PASS | Govindarajulu(通用/医疗)、Homaei(水需求)非 rainfall-runoff→Yang"首篇 rainfall-runoff 对抗"可立(已加脚注界定) |

---

## §5 审核留痕 & 残余风险（投稿前必清）

**3 次独立审核(workflow wf_a6cded38-178,3 agent 各自重 fetch arXiv + 读 main.tex + reconcile)结论**：
- 真实性 **C1–C16 全 PASS**(逐字)；有效性问题集中在 C13(三审一致 PARTIAL)、C7(audit3 对)、§1 prose(2:1 FAIL)——**本版已全部修**。

**残余风险(写进论文 limitation 或先做实验)**：
1. **实验 1 结局真不确定**：若 APGD/random-sign 塌到 ~1–2×,17.5× 即证实为弱-Gaussian artifact,**实质纠正 Yang 失败,只剩 514-vs-1 方法学纠正**。§1b 已标 PENDING,不预判。
2. 即便 Exp1 赢,也是 APGD/US/ΔNSE vs Yang n=1/DE/slope——**非字面复现**;跨数据集+度量差须 Exp2(c)+slope 复算才闭合。
3. **main.tex Discussion 4.1(line 299)现已存在 live over-claim**(US/NSE<0 冒充与 Yang DE/KGE 同口径)——非未来风险,是当前手稿就有,Yang 当审稿会抓。Exp2 修。
4. 借方法 7 引文(Fre-CW/Imgrund/TSA-STAT/Chen&Zhu/Govindarajulu/Homaei/Anand&Pappas)**当前 .bib 缺**,用前必补。
5. worst-of-10 随机搜索 vs APGD 50it/Yang 100 方向不对称——Exp1 已加 worst-of-K(K~100)堵此。
