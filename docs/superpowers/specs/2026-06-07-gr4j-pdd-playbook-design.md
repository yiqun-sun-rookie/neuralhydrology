# GR4J(+PDD) Playbook — CAMELS-US 531 repro_v01 设计

**日期**: 2026-06-07
**Idea**: 10 三学派概念模型对比 (XAJ vs HBV vs **GR4J**)
**前置**: HBV-lite (0.5995/0.6180) 与 XAJ-PDD (0.6232 PT / 0.6372 Oudin) 已定稿。本设计把同一标定 playbook 迁到 GR4J。

## 1. 目标 (Goal)

用与 HBV-lite / XAJ-PDD **完全平等**的 repro_v01 条件，搭建 GR4J(+PDD) 标定训练，≤10 次迭代，
每次迭代独立审核 + 独立验证问题，每轮回顾目标不偏离，终点：

- **硬指标**: full-531 median eval NSE **≥ 0.55**。
- **理想**: 接近/超过现有方法 (SAC-SMA 0.607, HBV-lite single 0.6180, XAJ-PDD 0.6232)。
- 代码 bit-exact 可复现；审核全过；代码/结果/文档相互对应。

## 2. 平等条件 (byte-equal 复用，不得偏离)

| 维度 | 取值 | 来源 (复用，不重写) |
|---|---|---|
| 协议 | repro_v01 | `xaj_global_pilot.config.repro_split_periods()` |
| cal | 1999-10-01 .. 2008-09-30 (9 wy) | 同上 |
| eval | 1989-10-01 .. 1999-09-30 (10 wy) | 同上 |
| forcing | maurer | `config.REPRO_FORCING` |
| PET | oudin / priestley_taylor | `hydroagent.data_loading.load_camels_basin(pet_method=...)` |
| 数据加载 | `keep_obs_nan_days=True` | 同上 (forcing 连续，metric 仍 dropna) |
| 标定器 | CMA-ES 多重启 | `xaj_model._cmaes_multi_restart` (seed 42+restart*1000, init_mean 0.5, sigma 0.3, [0,1] norm, maxfevals=trials, warmup=min(365,len/4), loss 1-nse) |
| warmup init | 跑 eval 前一年得 eval init state | runner 内逻辑 (clone XAJ) |
| metric | `xaj_global_pilot.metrics.compute_metrics` | 全模型同一函数 |
| 子集预算 | 2000 trials × 2 restarts | 与 XAJ playbook 迭代一致 |
| 最终预算 | 5000 × 3 (与 HBV 同) | headline 公平 |
| 迭代子集 | `configs/xaj_playbook_iter_subset_40.txt` (39 basin) | 与 XAJ 同子集 → 可直接对比 |

**子集参照系 (同子集，来自 xaj_playbook_iteration_log)**: XAJ iter3 (Oudin+warmup) 0.6470, HBV ens 0.6401, **HBV-v1 single 0.5447**。GR4J 目标 ≥0.55 ≈ HBV-v1 single 水平。

## 3. 模型结构

### 3.1 GR4J (4 参, Perrin et al. 2003)
状态: production store `S`, routing store `R`, 两个单位线卷积队列 `UH1/UH2`。
- 净雨/净蒸发: `Pn=max(P-E,0)`, `En=max(E-P,0)`
- production store: `Ps`(tanh 充蓄) / `Es`(tanh 蒸发) 更新 `S`
- percolation: `Perc = S*(1-(1+(4S/9x1)^4)^(-1/4))`
- routing 输入: `Pr = Perc + (Pn-Ps)`; 90% → UH1, 10% → UH2
- UH1 (基 `x4`) / UH2 (基 `2*x4`): SH ordinate 卷积
- groundwater exchange: `F = x2*(R/x3)^3.5`
- routing store: `R=max(0,R+Q9+F)`; `Qr=R*(1-(1+(R/x3)^4)^(-1/4))`; `R-=Qr`
- direct: `Qd=max(0,Q1+F)`; `Q=Qr+Qd`

参数: x1 production cap (mm), x2 exchange (mm), x3 routing cap (mm), x4 UH time base (day)。

### 3.2 雪前端 (可插拔接口)
统一接口 `snow_step(state, temp, prec_mm, params) → (new_state, liquid_input_mm)`。
- **PDD (主线, Phase 1)**: 复用 `pdd_core.pdd_step`，**砍 ice** (`pdd_factor_ice`/`refreeze_ice` 在 CAMELS 恒无效)。
  雪 4 参: `pdd_factor_snow`, `refreeze_snow`, `temp_snow`, `temp_rain`。
- **CemaNeige (Phase 2, robustness)**: 同接口，2 参 (`Kf` degree-day, `Tt` 阈值 + cold-content)。仅在 reviewer 质疑或时间允许时做。

### 3.3 耦合
`snow_step` 输出 liquid_input (mm, rain+melt) → GR4J 的 `P` 输入。耦合面仅此一个接口 (与 PDD+XAJ 同构)。

**GR4J+PDD 参数量 = 4 (GR4J) + 4 (PDD-noice) = 8**，仍 < XAJ 20 / HBV 13 → 保住"参数最省"卖点。

### 3.4 状态向量
`[snow, ice(=0), last_temp, S, R, UH1_queue(NUH1_MAX), UH2_queue(NUH2_MAX)]`
UH 队列长度由 x4 决定，Numba 需固定大小 → 预分配 `NUH1_MAX/NUH2_MAX` (x4≤15 → UH1≤15, UH2≤30, 取 40 安全)，x4 决定有效长度。

## 4. 参数边界 (presets)

GR4J 文献范围 (airGR / Perrin 2003)，初版 `gr4j_v1`:
- x1 [1, 2500] mm, x2 [-5, 5] mm, x3 [1, 1000] mm, x4 [0.5, 10] day
- 雪同 PDD_PARAM_BOUNDS 的 4 个保留参。

**关键 playbook 假设**: GR4J 低参 (8) → wide bounds 可能像 **HBV-lite 有益**（非 XAJ 反噬）。v1 标准 + wide 都测，用足额预算判断 (避免 XAJ 那种欠收敛假象)。

## 5. 迭代计划 (≤10，动态)

| iter | 内容 | 审核重点 |
|---|---|---|
| 1 | GR4J forward (NumPy ref + Numba) + PDD-noice 接口 + runner; 单元自检 (质量守恒/UH 归一/退化为无雪); 子集基线 (Oudin+warmup+v1, 2000×2) | forward 方程正确? UH 卷积对? 单位一致? |
| 2 | PET 双测 (PT vs Oudin)。GR4J 无 kc → 预期 PT≥Oudin (像 HBV) | PET 方向是否符合机理? |
| 3 | warmup on/off + bounds v1 vs wide (低参可能有益) | 子集饱和审计; wide 是否过拟合 (足额预算) |
| 4-8 | 按审计修 forward bug / 调 bounds / UH 数值核对 / 负尾诊断 | 每轮独立审核+验证 |
| 收敛后 | 全 531 最优配置 5000×3 确认 | bit-exact 复现; regime 分解 |
| 余 | CemaNeige robustness (可选) / 修残留问题 | — |

**收敛即停**: 一旦 full-531 median ≥ 0.55 且审核全过，提前结束 (不必跑满 10)。

## 6. 审核机制 (每迭代后)

派**独立 Agent** (general-purpose/Explore) 审核，三维：
1. **代码逻辑**: GR4J 方程、UH 卷积、PDD 耦合、单位 (mm/m)、constraint_fn=None 是否正确跳过 ki/kg。
2. **结果合理性**: NSE 分布、regime、与 XAJ/HBV **同子集**对比是否自洽。
3. **代码↔结果↔文档对应**: metadata 与实际配置一致、参数列完整、可复现。

发现问题 → **独立验证真伪** (重跑/手算/git 实证) → 真则记入日志 + 下迭代修；假则放过。

## 7. 产物

- 代码: `src/xaj_global_pilot/gr4j_core.py`, `gr4j_numba.py`, `gr4j_model.py`, `scripts/run_gr4j_pdd_cma_repro_v01.py`, `scripts/verify_gr4j_rerun.py`
- 共享改动: `xaj_model._cmaes_multi_restart` 加 `constraint_fn=_enforce_ki_kg` 默认参数 (default-preserving, iter1 用 verify_xaj_rerun 验证 XAJ byte-exact 不变)
- 结果: `results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/gr4j_pdd_cma_*/`
- 文档: `docs/technical/gr4j_playbook_iteration_log.md` (迭代日志，每轮回顾目标)
- memory: 收尾更新 [[xaj-pdd-playbook-531]] 的姊妹记录

## 8. 成功标准 (Success Criteria) — 全部达成 (2026-06-07)

- [x] full-531 median eval NSE ≥ 0.55 → **0.6533** (远超, +0.10)
- [x] GR4J forward 单元自检通过 → 5/5 PASS (质量守恒 7.85e-17 / 对拍 2.5e-14 / UH 归一 / 退化 / 真实 basin)
- [x] bit-exact 可复现 → verify_gr4j_rerun iter1+lockdown 各 3 basin BIT-EXACT
- [x] XAJ 复现不受 constraint_fn 改动影响 → verify_xaj_rerun 3 basin BIT-EXACT
- [x] 代码/结果/文档相互对应，审核全过 → 两轮独立审核 (forward PASS + 公平性已修 3 项)
- [x] 诚实归因 (反 over-claim) → 见 iteration_log: 参数效率非因果 / PET 口径 / arid 短板 / 文献 n / 雪参不可辨识

## 9. 实施结果摘要 (2026-06-07)

- **headline**: GR4J+PDD 8 参 full-531 median **0.6533** (5000×3 lockdown == 2000×2 收敛稳定)。
- **同-PET(PT) 同条件单态**: GR4J 0.6533 > XAJ-PT 0.6232 (+0.030,63%) > HBV-PT v7 0.6138
  (+0.033 配对,70%) > SAC-SMA 0.607; 追平 FUSE(0.654), 低 mHM/HBV-upper 0.01-0.02。
  > **2026-06-08 第三轮审核修正**: HBV-PT v7 同条件基线应用 **warmup 版 0.6170** (与 GR4J/XAJ
  > `warmup_year=True` 一致; 同标定逐 basin 参数 max|Δ|=0)，而非 non-warmup 0.6138 → GR4J vs HBV
  > 改为 **+0.036(median)/+0.030(配对)/69%**。详见 `gr4j_playbook_iteration_log.md` 第三轮审核段
  > 与 memory `gr4j_playbook_531.md`。结论 GR4J>HBV 不变。
- **headline 预算口径** (修第6节审核瑕疵): 同预算公平比用 GR4J 2k×2 vs XAJ 2k×2; HBV 单态用其
  5k×3 v7; 因 GR4J 2k×2 与 5k×3 median 均 0.6533, lockdown 仅确认收敛, 不改结论。
- 杠杆: PT>Oudin (像 HBV 反 XAJ); tight v1 (wide 无益, 像 XAJ); warmup +; ensemble 不需要。
- 全程见 `docs/technical/gr4j_playbook_iteration_log.md`。Phase 2 (CemaNeige robustness) 未做
  (主线已充分; reviewer 质疑或对标 published GR4J 时再补)。
