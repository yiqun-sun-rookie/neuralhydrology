# GR4J(+PDD) Playbook Iteration Log

**Goal (锁定，每轮回顾):** 用与 HBV-lite / XAJ-PDD **完全平等**的 repro_v01 条件搭建
GR4J(+PDD) 标定训练，≤10 迭代，每轮独立审核+独立验证问题，终点 full-531 median
eval NSE **≥ 0.55**，接近/超现有方法 (SAC-SMA 0.607, HBV-lite 0.6180, XAJ-PDD 0.6232)。

**平等条件 (byte-equal 复用):** repro_v01 split (cal 1999-2008 / eval 1989-1999),
maurer forcing, `load_camels_basin(pet_method, keep_obs_nan_days=True)`, 共享
`_cmaes_multi_restart` (seed 42+r*1000, init 0.5/0.3, warmup=min(365,len/4), loss 1-nse),
Kratzert warmup-year init, `compute_metrics`。详见
`docs/superpowers/specs/2026-06-07-gr4j-pdd-playbook-design.md`。

## 子集参照系 (39-basin, xaj_playbook_iter_subset_40.txt — 与 XAJ 同子集)

| Series (同子集) | median eval NSE | 角色 |
|---|---|---|
| XAJ iter3 (Oudin+warmup) | 0.6470 | XAJ 最优单体 |
| HBV ens_cal_best | 0.6401 | HBV 集成目标 |
| HBV-v1 single (Oudin) | 0.5447 | 公平单体目标 |
| **目标线** | **0.55** | goal 硬指标 |

注: 子集比 full-531 偏乐观 ~0.01 (XAJ audit)，headline 须以 full-531 为准。

## 模型 & 代码

- `gr4j_core.py` — NumPy 标量参考 (ground truth) + UH ordinates + PDD-noice 雪前端
- `gr4j_numba.py` — njit 加速 (与 core 对拍 |Δ|<1e-6)
- `gr4j_model.py` — 封装 + `calibrate_pdd_gr4j` (复用 `_cmaes_multi_restart`, `constraint_fn=None`) + bounds presets
- `scripts/run_gr4j_pdd_cma_repro_v01.py` — runner (XAJ runner 协议级 clone)
- `scripts/selfcheck_gr4j.py` — forward 单元自检
- 共享改动: `xaj_model._cmaes_multi_restart` 加 `constraint_fn=_enforce_ki_kg` 默认参数 (XAJ byte-identical)

**参数: 4 PDD-noice (pdd_factor_snow, refreeze_snow, temp_snow, temp_rain) + 4 GR4J (x1,x2,x3,x4) = 8**，三学派最省 (vs XAJ 20 / HBV 13)。

## 单元自检 (2026-06-07, 跑标定前) — 5/5 PASS

| 检查 | 结果 |
|---|---|
| A UH ordinates 归一 (sum=1) | max\|Δ\|=0.00 |
| B 质量守恒 (E=0,x2=0) | rel_resid=7.85e-17 |
| C core vs numba 对拍 | max\|Δq\|=2.53e-14 |
| D 无雪退化 (gr4j==pdd@温高) | max\|Δ\|=0.00 |
| E 真实 basin smoke (01013500, 默认参数未标定) | NSE=0.352, Q 量级合理 |

## 迭代表 (子集 median eval NSE)

| Iter | Config | output-subdir | 子集 median | mean | <0 | 审核状态 |
|---|---|---|---|---|---|---|
| 1 | Oudin + warmup + v1, 2000×2 | `gr4j_pdd_cma_iter1` | 0.6424 | 0.5831 | 1 | 🔍 独立审核中 (agent) |
| 2 | **PT** + warmup + v1, 2000×2 | `gr4j_pdd_cma_iter2_pt` | **0.6518** | 0.6092 | 0 | PET 对照 |

### Lever: PET (iter2)
**PT > Oudin for GR4J** (+0.0094 median, +0.026 mean, 负 NSE 1→0)。机理: GR4J 无 kc
PET 折算系数 → 不能自补偿 PET 偏差 → 偏好"正确"的 PT (Addor 2017 标准辐射-能量 PET)。
这与 **HBV 一致 (PT>Oudin)**、与 **XAJ 相反 (Oudin>PT, 因 kc 自补偿)**。三学派 PET 偏好
由"是否含 PET 折算参数"决定，是干净的机理结论。→ GR4J headline 用 **PT** (且为标准 PET)。

> XAJ-bug 教训复用: PT 是 CAMELS 标准 PET，GR4J 用 PT 既最优又 benchmark-aligned，
> 避免 XAJ "Oudin 非标准" 那种可比性争议。

## iter1 独立审核 (2026-06-07, general-purpose agent, 347s/23 tool-uses)

**结论: 0.6424 可信，无 HIGH、无 bug、无泄漏。** PASS 1-8 全过:
forward 忠于 Perrin 2003 (production/perc/UH/exchange/routing 逐式核对) / 雪前端与
XAJ byte 级一致 + ice 砍除等价 / UH 归一+对拍+质量守恒 / bit-exact 可独立复现
(手算 2 basin dNSE=0) / cal·eval·warmup 三窗口零重叠 / 标定流程与 XAJ·HBV 对等 /
cal-eval gap +0.028 无过拟合 / metadata·文档·结果全吻合 / HBV-v1 基线 0.5447 同子集精确复现。

发现 4 项 (均非阻塞)，已独立验证并处置:
- **M1** 雪参大面积贴界 (temp_snow 69%/temp_rain 62%/refreeze_snow 59%) — 真，但是温暖
  流域的 **dead parameters** (雪无水文信号, 不可辨识, 不改 NSE; agent 已验退化等价)。
  非 bug → **最终文档诚实披露** (反 over-claim)。
- **M2** x2 36%贴-5 / x1 15%贴2500 / x3 15%贴1000 — 真, v1 bounds 偏紧 → **iter3 v2_wide**
  (已建 preset: x1→4000, x2→-15, x3→1500; 雪参不放因 M1 是 dead)。
- **L1** spec 写了 `verify_gr4j_rerun.py` 未建 — 真 → **已补建**。
- **L2** manifest 名 `_40` 实 39 行 — 真但无影响 (XAJ 同文件保同子集) → 忽略。

旁证: XAJ 复现 bit-exact 通过 (verify_xaj_rerun 3 basin, |dNSE|=0/param L1=0/state L1=0)
→ `constraint_fn` 改动确认 default-preserving，未污染 XAJ。

## iter3: wide bounds (应对 M2)

| Iter | Config | output-subdir | 子集 median | mean | <0 | 审核状态 |
|---|---|---|---|---|---|---|
| 3 | PT + warmup + **v2_wide**, 2000×2 | `gr4j_pdd_cma_iter3_pt_wide` | 0.6514 | 0.6029 | 0 | wide 无益 → 弃 |

### Lever: bounds (iter3)
**wide bounds 无益** (median 0.6514 vs v1 0.6518 = −0.0004, mean −0.006)。与 XAJ 一致:
tight bounds = 正则化, 是首选。M2 的贴界 (x2/x1/x3) 放宽后并未改善泛化——贴界是 CMA-ES
想逃逸, 放它逃不改善 eval (符合 J9: "贴界就加宽" 在 ≥中参模型上反噬; GR4J 这点像 XAJ 不像
HBV-lite)。→ **headline 配置锁定 = PT + warmup + v1 (tight)**。
bit-exact: iter1 01022500 verify BIT-EXACT (dNSE=0/param L1=0/state L1=0)。

## 全 531 确认 (headline = PT + warmup + v1)

| Run | Config | output-subdir | full-531 median | mean | gap | <0 | 状态 |
|---|---|---|---|---|---|---|---|
| 初步 | PT+warmup+v1, 2000×2 | `gr4j_pdd_cma_full531_pt_v1_2k` | **0.6533** | 0.6130 | 0.062 | 10 | ✅ 超目标 0.55 |
| lockdown | PT+warmup+v1, 5000×3 | `gr4j_pdd_cma_FINAL_pt_v1` | **0.6533** | 0.6102 | ~0.06 | 11 | ✅ = 2000×2 (收敛稳定) |

**全 531 (2000×2) 超目标 +0.10，同-PET(PT) 公平对比超所有单体方法:**

| 方法 (full-531, repro_v01) | median | 参数 | 预算 |
|---|---|---|---|
| **GR4J+PDD (本次, PT)** | **0.6533** | **8** | 2000×2 |
| XAJ-PDD (Oudin) | 0.6372 | 20 | 2000×2 |
| XAJ-PDD (PT 同-PET) | 0.6232 | 20 | 2000×2 |
| **HBV-lite (PT, v7 同 init, 同条件)** | **0.6138** | 13 | 5000×3 |
| HBV-lite (Oudin) | 0.5995 | 13 | 5000×3 |
| HBV 9-way ens (混-PET 9× 参照) | 0.6227 | 13×9 | 5000×3 |
| SAC-SMA (Kratzert) | 0.607 | 13 | — |
| mHM / HBV-upper / FUSE | 0.665/0.678/0.654 | — | — |

同-PET(PT) 单态: **GR4J 0.6533 > XAJ 0.6232 > HBV-PT v7 0.6138** (v7=PT tight init0.5, 同条件);
GR4J 参数最省(8)、预算最省、**cal 最高(0.716) 且 eval 最高** → 真实参数效率(非欠拟合非过拟合)。
9-way ens 0.6227 是混-PET(4O+5PT)+9× 预算, 仅作 HBV 上限参照, GR4J 单态仍超它。**诚实归因(反 over-claim):
GR4J 超 XAJ/HBV 不是 playbook 功劳，是 GR4J 结构本身在 CAMELS 高效(文献已知)；playbook
贡献 = 平等条件量化 + PET 选对(PT)**。待 5000×3 lockdown + 独立审核确认。

### regime + 逐 basin head-to-head (5000×3 lockdown, 终版)
- regime: humid 0.688 / snow 0.631 / semi-humid 0.643 / **arid 0.356 (n43)**
- **arid 过拟合短板**: gap +0.127 (humid 的 2.4×), 5k×3 arid eval 反比 2k×2 低 (0.356<0.387),
  11 个负 NSE 中 7 个是 arid → 多搜拟合 cal 噪声, **不宜加预算, 论文必写**。相对仍优于 XAJ-PT
  0.321 (胜 24/43)。
- 同条件单态 head-to-head: GR4J 胜 **XAJ-PT 336/531 (63%, Δ+0.023)**, 胜 **HBV-PT v7 374/531
  (70%, Δ+0.033)**, 胜 HBV 9-way ens(混-PET) 356/531 (67%, Δ+0.030)。
- 文献 (公共子集重算, 标 n): GR4J **追平 FUSE** (n479, 逐 basin 53% 打平), **低于 mHM**
  (n492, 胜 43%) / **HBV-upper** (n531, 胜 45%) 约 0.01-0.02, 超 SAC-SMA(0.607)/VIC(0.554)。
  **GR4J 8 参追平/逼近最强文献概念模型** (低于 mHM/HBV-upper 约 0.01-0.02)。

## 复现 & 审核
- **bit-exact**: iter1 (oudin 2000×2) + lockdown (PT 5000×3) 各 3 basin verify **BIT-EXACT**
  (dNSE=0 / param L1=0 / state L1=0)。XAJ 复现也 bit-exact (constraint_fn default-preserving)。
- **第一轮独立审核 (iter1 forward): PASS** — 无 bug/泄漏/过拟合; forward 忠于 Perrin 2003;
  详见上方 "iter1 独立审核"。
- **第二轮独立审核 (lockdown 公平性): 完成 — 方向可信可发表, 已修 3 项**:
  ①HBV 同条件基线从混-PET ens 0.6227 / Oudin-v1 0.5564 改为 **HBV-PT v7 same-init 0.6138**
  (真实 Δ+0.033 配对 / +0.040 median 差, 非夸大的 +0.088); ②arid 过拟合写进 caveat;
  ③文献对比标 n。PASS 项: 同-PET/forcing/split/metric 字节对等、参数效率真实(GR4J cal 最高+gap
  不大于对手)、2k=5k 是收敛非缓存(185 cal 更好/0 更差, 407/531 参数不同)、无泄漏/作弊。
  **已独立复核** (v7=0.6138、arid gap=0.127、GR4J-v7 Δ=+0.033 实测一致)。

## 目标回顾 (goal: full-531 median ≥ 0.55)
✅ **达成且远超**: full-531 median 0.6533 (≥0.55, +0.10), 5000×3 lockdown 稳定, bit-exact,
同-PET 同条件单态超 XAJ-PT/HBV-PT/SAC-SMA。迭代用量: iter1(Oudin baseline) → iter2(PET→PT) →
iter3(bounds→v1 弃 wide) → 全531 2000×2 → 全531 5000×3 lockdown = 5 个 run, 远未及 10 上限。
**两轮独立审核完成, 结论可发表 (需带 caveat: arid 短板 / 雪参不可辨识 / 参数效率非因果 /
文献 n≠531 / PET 口径)。** 论文主打"三学派殊途同归 + GR4J 参数效率", PET 双行 + 同条件单态对比。

**iter1 解读 (待审核确认):** 0.6424 已 **超目标 0.55**、追平 XAJ iter3 (0.6470)、超 HBV
ens (0.6401) 与 HBV-v1 single (0.5447)。第一次迭代即达标——**结果偏好，需独立审核排除
bug/泄漏/巧合**。分布: >=0.6: 22, >=0.5: 29, >=0.3: 35, <0: 1 (04213000 −0.041), <-1: 0。

### 待审核重点 (iter1)
1. GR4J forward 是否忠于 Perrin 2003 标准方程 (production/perc/UH/exchange/routing)。
2. 标定流程是否与 XAJ runner 协议完全对等; constraint_fn=None 是否正确跳过 ki/kg。
3. 参数是否在界内/贴界; cal-eval gap; 负 NSE basin 成因。
4. 泄漏: warmup 窗口 (1988-1989) 是否碰 eval; cal/eval 重叠。
5. 代码↔结果↔文档对应。
6. XAJ 复现是否受 constraint_fn 改动影响 (需 verify_xaj_rerun byte-exact)。

---

## 第三轮独立审核 (2026-06-08, goal-driven, 不沿用前两轮)

独立重算/重跑全部关键量。**结论稳健, 4 处修正 (详见 memory `gr4j_playbook_531.md` 审核段)。**

**修正 (supersede 上文相应数字):**
- **同条件 HBV 基线 warmup 一致性**: 上文 §同条件 / §head-to-head 引 HBV-PT v7 = **0.6138**
  (非 warmup); 但 GR4J/XAJ headline 均 `warmup_year=True` → 应改用 **v7_PT_tight_warmup = 0.6170**
  (与 0.6138 **逐 basin 参数完全相同**, max|Δ|=0, 仅 eval-init 不同)。修正后 GR4J vs HBV =
  **+0.036(median)/+0.030(配对)/胜 366-531 (69%)** (原 +0.040/+0.033/70%)。GR4J vs XAJ 不变
  (+0.030 median / +0.023 配对 / 63%)。**结论 GR4J>HBV 不变。**
- **gap 不等号**: §参数效率 处两模型混用了"中位数之差"(GR4J +0.063) 与"逐basin差中位数"
  (XAJ +0.057) → 不可直接比。同定义重算: 逐basin gap GR4J **+0.048** < XAJ +0.057 < HBV(warmup)
  +0.061; 中位数之差 GR4J **+0.063** < XAJ +0.069 < HBV +0.073。两种定义 GR4J 均最小, 论点不变。

**独立 PASS (重新验证非沿用):** 数据划分三模型同源 `repro_split_periods`; 三套 CMA-ES 核逐行等价
(GR4J import XAJ 的, HBV 独立副本同 warmup-排除/objective/seed/maxfevals/归一化); `audit_obs_gaps`
实测 **0/531** 缺测天 (keep_obs_nan_days 不对称无影响); GR4J `selfcheck` 5/5 + 质量守恒 closure=1.0 +
numba==numpy 2.5e-14; HBV `_simulate_loop` 逐行匹配 hydroDL2 `_PBM` + closure=1.0; XAJ 规范结构 +
closure=0.9979 (微渗漏 caveat⑦); 三 headline median 从 CSV 精确复现 (0.6533/0.6232/0.6170);
`verify_gr4j_rerun` 2 basin **dNSE=param=state L1=0 BIT-EXACT**; 参数效率 GR4J cal 0.716 双高、
gap 两定义最小实测成立。

**复现卫生 (caveat, 非数字错误):** HBV bounds 由 env `HBV_BOUNDS` (默认 v5-宽) 控制、runner 无
`--bounds-preset`、metadata 不记 pet/warmup/bounds → 仅靠目录名复现 (headline v7 已核验实为 v1-tight);
v7_PT_tight_warmup 的 metadata `n_executed=2` 系补丁跑拼装, 但 531 行 state_init_mode 全 warmup, 数据有效。
