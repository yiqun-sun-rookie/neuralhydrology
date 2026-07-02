# Plan: Idea-05 Adversarial Rerun on the ID18 Kratzert-grade LSTM victim

> **v4（定稿）**（2026-06-18，3 次独立审核迭代后定稿；iter1 23 条 + iter2 15 条 + iter3 6 major 全部落实，0 误报）。实现阶段以本稿为准。
> 目标对照：用 ID18 重做 Idea-05 对抗结果，先修正管线**评估指标错误**与**威胁模型不可实现性**，落实文献审核（random-sign + Yang apples-to-apples + 删 over-claim）。

---

## 0. 现状 + 关键尺寸（已亲验，含 iter3 纠正）

- **新 victim = ID18 s100**：cudalstm+27static、maurer、reverse split test 1989-10-01..1999-09-30、h256、seq270、**predict_last_n=1**。**test MEDIAN NSE 0.7332**（per-basin −0.29..0.94，s100 近最佳，s600 0.7343，集成 0.7589）。
- **尺寸（iter3 纠正，载荷性）**：测试期 = **3652 个预测日 = 3652 stride-1 窗口**（warmup 取自 test 前 269 天）。**coherent 优化变量 `delta_cal[1, T_cal, F]`，T_cal = 3652 + seq_length−1 = 3921 连续日**（含 test 前 269 warmup 日，**可扰**，因其喂前 269 个窗口的历史）。指标在 **T_metric = 3652** 个 last-step 上算。重建：`window_i = continuous[i:i+270]`，`last-step(window_i)=continuous day i+269 = test day i`；NSE over 3652 点。（旧 §0 的"~3383"是错的：3383=3652−270+1 仅当错误地只窗口化 test 天而无 warmup。）
- **maurer 温度退化（官方固有）**：**Tmax(C)≡Tmin(C)** 字节相同（scaler center 10.4036/scale 10.7329 全等）；victim **4 有效动态通道**（PRCP=0/Tmin=1/Tmax=2/SRAD=3/Vp=4）。**所有攻击须 tie 索引 (1,2)**（见 F9），否则 worst-case 含不物理 Tmax≠Tmin。
- **管线既有评估指标错误（已证）**：runner 对全 270 步窗口算 NSE + n_samples=1；0.7332 是 last-step 拼接（`tester.py:535`）。**旧 17.5×/"0.74→X" 同建于此坏指标** → F2 纠正会动旧 headline（分解 指标F2/baseline F3/victim 三因）。
- clean 与 adv 的 reported NSE 都走 cuDNN no_grad（attack 返 detached）；非 cuDNN 仅攻击内部梯度环 → delta_nse 无路径混用。

## 1. Victim 决策

- **Primary headline = 单 seed s100**（白盒需单一可微模型；近最佳，不称弱；对标 Yang 单 LSTM）。每数附"单 seed"caveat。
- **集成鲁棒性 = 必做闸门，须 detached-residual 线性化（iter3 必修）**：NSE(集成均值) 对 δ **非线性**，**不能**对每模型各自 NSE 求梯度再求和（那是攻击各模型自身残差 → 攻击偏弱 → 高估鲁棒，恰是回答 Yang 的载荷量）。正确：(a) no_grad 前向 8 模型得均值 p̄、**detached** 残差 `r=y_obs−p̄`、detached `ss_tot`；(b) 逐模型 backward 代理 `L_i ∝ −(1/(8·ss_tot))·Σ_t r_t·f_{i,t}`（r、ss_tot detached），累积进共享 delta；复用 F2 窗口分块。**单元测试**：累积梯度 == autograd 穿 `torch.stack(preds).mean(0)`（2 模型玩具,|diff|<1e-6）。固定小分层 basin 子集，预算 ≈8× 单模型 APGD。**威胁模型披露**：白盒-穿均值=最强,transfer/黑盒更弱 → 闸门回答 Yang 的是 **worst-case 白盒鲁棒性**,非字面可部署。

## 2. 预修代码（TDD；F2 核心重写）

**F1（physical 名 bug）** `physical.py` 两侧 casefold（`_PHYSICAL_BOUNDS_CF={k.casefold():v}`，查 `feat.casefold()`；裸 `.lower()` 只救 PRCP，键含大写单位）。验证：(a) 确定性单元测试构造越界→断言 clamp **必须过**；(b) Exp2 physical≈lp 在最小 ε 合法,不得误判失败。

**F2（核心重写：last-step 测试期 NSE + coherent 单序列 + 分块 per-chunk backward）**
- **优化变量** = `delta_cal[1, 3921, F]`（T_cal=3921 含 warmup,见 §0）；窗口仅前向重切 stride-1；**严禁** per-window 独立扰动后拼接。
- **指标 = last-step 拼接全测试期 NSE**（3652 点,复刻 RegressionTester）。
- **分块 per-chunk backward（必须,内存有界且精确）**：obs 不扰 → **预算一次** 全局 last-step `ȳ`、`ss_tot=Σ(y_obs−ȳ)²`（常量,无 grad）；对 512–1024 窗口分块,**逐块算 `ss_res_i`(对 delta_cal 有 grad)、`ss_res_i.backward()` 累积进 `delta_cal.grad`、释放该块图**;全部块后 `grad(NSE) = −(1/ss_tot)·delta_cal.grad`(NSE 对 ss_res 仿射 → 精确)。**禁**"带 grad 累积 ss_res 再单次 backward"(会保留全部块图,内存爆),**也禁**每 chunk 算 NSE 再平均。单元检验:分块梯度==单批 autograd 梯度(小 basin)。
- **攻击 loss 切 last-step**:对 stacked-windows `[N_windows,270,1]` 切 `y_hat[:,-1]` 拼接(非单窗口 B=1,那是 1 点退化)。
- **约束作用在序列**:所有约束作用在 `delta_cal[1,T_cal,F]`、windowing 之前(linf/physical 逐元素;statistical 对 dim=1 算矩 → **全测试期矩**,`statistical.py` 无需改)。**caveat**:statistical 行=全测试期矩 ≠ 旧每 270 窗口矩,与旧论文不直接可比。
- **可行性**:APGD = n_iter×n_chunks ≈ 50×8 ≈ **~400 非 cuDNN chunk-pass/basin/ε**。**先单 basin 端到端基准定算力**。

**F2b（算力 contingency,iter3 必加,适用 Exp1/2/3 的 APGD）** 单 basin 基准测出 秒/(basin,ε) 后,若 full-531×4ε APGD 超既定 wall-clock 预算,**确定性降级**(择一,由基准数定):仅 full-531 跑 headline ε=0.1;ε-曲线用 coarser grid 或**分层 ~100-basin 子集**(同 C&W/集成的子集手法);或减 n_iter。→ headline 从"有界但可能数天"变**计划内预算**。

**F3（random-sign + 全攻击走 coherent driver,iter3 必修）** 加 `RandomSign`:`eps·v, v∈{−1,+1}`,best-of-K。**注册** `attacks/__init__.py`+`ATTACK_REGISTRY`+`__all__`+config 键+集成测试。**K-sweep 机制**:注册 `random_sign_k1`/`random_sign_k100` 两键(或加 K sweep 到 `_prepare_attack_sweep`)。**关键(iter3)**:**Exp1 全部攻击(梯度 + 随机 best-of-K = Gaussian/mult_bias/temp_corr/random_sign)都走 coherent driver**——随机样本在 calendar 空间 `delta_cal[1,T_cal,F]` 采样、re-window、**用同一 coherent last-step NSE 做 best-of-K 选择**(非 per-window B=1 的 compute_loss),否则 random_sign(K=100) 作为 GATE 分母无效、Table1 混两套指标。随机 no_grad 前向可保 cuDNN(便宜)。

**F4** ε→物理表用 ID18 scaler 重算;温度按单通道计 ε 与归因。

**F5** Exp6 KGE 物理空间:`y_phys=y_norm*3.6298+1.5118` 对 obs+pred 反标准化再 `compute_kge`(β 非仿射不变;NSE 仿射不变故 nse_clean 在归一化空间比较合法)。参考 KGE **从 test_results.p 物理 xr 现算**(run 只存 NSE)。

**F6** `peak_error` 反标准化到 mm/d,或移除。

**F7（C&W 子集化）** C&W 的 **LpConstraint 也用大预算建**(非只 tanh scale;`run_adversarial_eval.py:246` 用 loop ε 建约束会 re-clamp);**跳过 ε-sweep**;仅跑**分层 ~50–100 basin**,`binary_search_steps=3, n_iter=100`;solved 由 `nse_adv≤target_nse` 在 runner 导出,报 solved 比例 + best-effort min-L2。

**F8（data tripwire）** `data_dir: data/camels_us`(**绝不 full/**,坏小写表头);断言 531 非退化加载 + checksum 4 修复文件表头。

**F9（温度 tie,attack-agnostic,iter3 必修）** 在**所有攻击共用的 chokepoint(`constraint.project` 之后/返回前)** tie 温度索引 (1,2):**采一个温度扰动 copy 到两通道** `delta[...,1]=delta[...,2]=avg`(梯度攻击用 `½(g1+g2)`,随机攻击 copy 单一采样)。二者 center/scale 全等 → 归一化 tie=物理 tie。**Exp1 全攻击(含 random_sign/Gaussian)都 tie**,使 APGD 与 random_sign(K=100) 同处 4-DOF 物理子空间(消 gate 偏置)。Exp2 物理约束下 tied delta clamp 到两通道 bound 交集(或 methods 注明微小越界可忽略)。smoke 断言 Exp1 每攻击 `delta_Tmax==delta_Tmin`。headline 报 tied,untied 作 upper bound。

## 3. 隔离配置

`src/adversarial/configs/eval_id18_s100.yaml`:run_dir→ID18 s100、epoch30、cuda:0、`data.data_dir: data/camels_us`、`output_dir: results/05_adversarial_robustness/id18_s100`。约束级 `lp/physical/statistical`;攻击键用代码 registry 全名 + `random_sign_k1/random_sign_k100`。

## 4. 实验块

- **Smoke（≥3 basin,走 coherent 路径,分块）**:(a) **每 basin** 断言 `nse_clean == test_results.p[basin]['1D']['NSE']`(|diff|<1e-3,归一化空间比较,NSE 仿射不变)——非中位 0.7332;(b) ΔNSE 有限、physical clamp、KGE 物理对齐现算参考、Exp1 每攻击 `delta_Tmax==delta_Tmin`;(c) ordering 闸门 `Gaussian<FGSM≤APGD` 取 smoke 集**中位/加容差**,random_sign 排除。
- **Exp1（核心 GATE）**:{APGD, FGSM, Gaussian, **random_sign_k1 & random_sign_k100**, mult_bias, temp_corr} × ε{0.01,0.05,0.1,0.2},lp,untargeted,531 basin,coherent 指标,全攻击走 driver + tie 温度。(F2b contingency 适用)
- **Exp2**:约束消融 APGD×{lp,physical,statistical}×ε{0.05,0.1,0.2}(F1 后;statistical=全测试期矩 caveat;注:Exp2 APGD 4779 run > Exp1,F2b 同适用)。
- **Exp3**:targeted {untargeted,flood,lowflow} APGD ε=0.1。
- **Exp4（causal-trigger,iter3 定为 sparse-peak 重设计）**:事件 = **稀疏峰**(复用 `_find_peaks` min-distance-14);在共享 `delta_cal` 上建 **calendar-day pre-event mask**(峰前 pre_window∈{1,3,7,14} 日);**伤害测在峰 last-step 上**(其 last-step 为峰的窗口),**非全测试期 NSE**;caveat:`pre_window ≥ 峰间距`(=14)时 causal cleanliness 退化。**不用**"每窗 last-step=事件"措辞(会塌成全天)。作为**独立 threat model 单列**,不与 coherent Exp1 同轴报。
- **Exp5**:C&W(F7:~50–100 子集、专属预算)min-L2 + solved 比例。
- **Exp6（Yang 调和）**:物理 中位 ΔKGE(对 Yang −0.105);32.5%<0 按 clean-NSE 分层;集成鲁棒性闸门(§1)。

## 5. 闸门与判据

- **Smoke 过**:每 basin nse_clean==官方[1D][NSE]、ΔNSE 有限、physical/KGE/温度-tie 检查过 → 才跑 Exp1。
- **Exp1 GATE（专用 gate 函数,非 analyze_results 现成比值翻符号）**:
  - **新建 gate 函数**:per-basin `D(attack)=NSE_clean − NSE_adv ≥ 0`(正=伤害大;避 delta_nse 负号);finite-NSE 子集每 cell 重算(不假设 514)。
  - **主比较 = APGD vs random_sign(K=100)**(query 大致公平):主统计量 = 配对差 `D_APGD − D_random_sign(K=100)`,报 **中位+IQR + Wilcoxon 符号秩**;描述比值 `median D_APGD / median D_random_sign(K=100)`,near-zero 分母加容差。
  - **纯单步子检验** = FGSM vs random_sign(K=1)(1 vs 1 query),配对差描述性。
  - **判定**:主配对差显著>0 且 比值 **≥3 → 结局 A(方向特殊)**;比值 **≤2 或不显著 → 结局 B(17.5× 主要弱-baseline artifact,改写 headline)**;2–3 之间 report-and-discuss。**两结局如实写,不预设。**
- 每块:覆盖(C&W/集成子集除外)、finite-NSE 重算、provenance。

## 6. 公平性

- 同 531 basin、同 test 期、同 maurer 物理文件(F8 checksum)、同 scaler。
- 披露:maurer 4 有效动态通道(Tmax≡Tmin,官方固有,Kratzert 同款);**所有攻击 tie 温度**(F9) → worst-case 不含不物理 Tmax≠Tmin。
- 诚实 scope:CAMELS-US worst-case 基准,非 Yang(DE) 字面复现;旧 17.5× 亦在坏指标上(F2 纠正)。单 seed 每数附 caveat;集成闸门=worst-case 白盒。
- statistical 行=全测试期矩,与旧论文不直接可比;Exp4 causal 为独立 threat model 单列。limitation 承接 ID18 静态属性窗口重叠。

## 7. 迭代与审核结构

- **计划阶段(已完成 3 次审核迭代,本稿 v4 定稿)**:iter1→v2、iter2→v3、iter3→v4;每次审核每个发现独立验证(成立→修;不成立→排除)。
- **实验阶段**:先 TDD 实现 F1/F3/F5–F9 + F2 coherent driver(独立模块,跨块 per-chunk backward) → **单 basin 端到端基准**(验 nse_clean==官方[1D][NSE] + 定算力 + F2b contingency) → smoke(≥3 basin) → **Exp1 GATE**(结局 A/B) → Exp2-6;≤10 迭代;每次独立审核最好结果 code/结果/文档正确+逻辑+相互对应;发现独立验证→成立下次修。**每迭代回顾本计划,不跑偏。**
- **禁**:不碰旧结果树;不改 main.tex 直到新结果审完。

## 8. 实现风险清单(进实验前已知,smoke/单 basin 基准兜底)

1. F2 coherent driver = 独立模块(不复用 per-window body),含 re-window 前向 + 跨块 per-chunk backward + 全攻击(含随机 best-of-K)走此 driver + tie 温度 chokepoint。单 basin 基准是硬闸门。
2. Exp4 sparse-peak 重设计需独立 smoke(峰 last-step 伤害口径)。
3. 集成闸门 detached-residual 线性化需独立单元测试。
4. F2b 算力 contingency 由单 basin 基准数触发。
