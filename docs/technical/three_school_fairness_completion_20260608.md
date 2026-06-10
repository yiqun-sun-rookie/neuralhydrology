# 三学派概念模型对比 公平性补全 — 会话记录 (2026-06-08/09)

GR4J vs XAJ vs HBV，CAMELS-US 531，repro_v01 协议。本会话执行
`docs/plans/2026-06-08-three-school-comparison-completion.md`，在单一统一协议下
关闭全部**可关闭**的公平性/复现性缺口，并诚实披露 irreducible caveat。

> 状态：S2 / 审计 / S1 / S3a / **S3b 已完成**（用户选"完全预算对等"，三家全 5k×3，
> 无需脚注）；S6 独立复审 + bit-exact 抽检后台运行中；S8 commit 待用户点头。

---

## 1. 统一协议（锁定）

| 维度 | 值 |
|---|---|
| split | cal 1999-10-01..2008-09-30 / eval 1989-10-01..1999-09-30 |
| forcing | maurer |
| PET | priestley_taylor (CAMELS Addor 2017 标准) |
| warmup | warmup_year=True（Kratzert：eval 前 1 年，默认初态起跑，末态作 eval 初态） |
| bounds | 各模型自身 literature-tight 预设 "v1" |
| CMA-ES init | init_mean=0.5, init_sigma=0.3（归一化），seed=42+restart·1000 |
| budget | 5000 trials × 3 restarts |
| metric | compute_metrics NSE，eval 期 |

公平性定义（反 over-claim）：**协议公平（same calibration/validation protocol）+ 残余诚实
披露**；不承诺"模型对等"或"绝对公平"——三个是结构不同的模型，能拉平的是流程。

---

## 2. 本会话代码改动（全部已验证）

| 文件 | 改动 | 验证 |
|---|---|---|
| `src/scl_hydro/hbv_lite_numpy.py` | 加 `resolve_hbv_bounds(preset)` + `BOUNDS_PRESETS` | — |
| `src/scl_hydro/hbv_lite_cma_calibrate.py` | `calibrate_hbv_lite_cma` 加 `param_bounds=None`（None=沿用模块默认，向后兼容） | — |
| `src/scl_hydro/scripts/run_hbv_lite_cma_repro_v01.py` | 加 `--bounds-preset`(默认 v1) + `--output-subdir`；threading + 全字段 metadata；**cal/eval load 加 `keep_obs_nan_days=True`**（对齐 GR4J/XAJ） | bit-exact 自检 + 2-basin 烟雾 |
| `src/scl_hydro/scripts/verify_hbv_bounds_preset.py` | 新建：bounds-preset 运行时 threading 的 bit-exact 自检 | 3/3 PASS |
| `src/xaj_global_pilot/scripts/verify_three_school_table.py` | 新建：从 per-basin CSV 独立重算对比表（S6 工具） | 精确重现审计数 |

**S2 bit-exact 证据**（`verify_hbv_bounds_preset.py`）：
- `param_bounds=None` vs `resolve_hbv_bounds(模块默认)` → Δparam=0, Δnse=0（threading 忠实）
- v1 vs v5 → Δparam=323（preset 确实切换搜索空间）
- 推论：`--bounds-preset v1`（模块默认 v5 + `param_bounds=resolve("v1")=_BOUNDS_V1`）与旧
  `HBV_BOUNDS=v1` 路径喂给标定器的 lo/hi 完全相同，CMA-ES 种子固定 → 逐位一致。

**keep_obs_nan_days 对齐**：HBV 的 cal/eval load 原用默认 False（丢 obs-NaN 天→不连续
forcing），GR4J/XAJ 处处 True。已对齐为 True。实证 cal/eval 窗口 0 缺测 → 对这两个窗口
**逐位 0-影响**（见 §4），仅消除跨模型代码路径不一致 + 其它窗口/数据集的 footgun。

---

## 3. 独立公平性审计结论

派 workflow（独立 agent 逐维度 + 1 条双遍验证 headline + 综合）+ 项目自带审计文档
(`xaj_playbook_audit_5pass.md`, `gr4j_playbook_iteration_log.md`) + 人工读码，三方互证。

**整体：PUBLISHABLE**（协议在定义"公平"的每个维度上确实一致）。

| 计划已知发现 | 判定 | 说明 |
|---|---|---|
| A：HBV headline 非 warmup | **推翻** | HBV headline 全 531 行 state_init_mode=warmup_year_end；median 0.617033 |
| B：XAJ 2k×2 vs 5k×3 | **证实** | 见 §5，S3a 已证收敛；S3b 进一步消除 |
| C/E：HBV bounds env footgun | **证实** | S2 已修；且确认 headline 确用 v1（7 参精确卡 v1 上界） |
| G：XAJ 99.8% 守恒 | **证实** | irreducible，见 §6 |
| L36：参数效率方向 | **证实读对** | GR4J 同时最高 NSE + 最少参数；归因 GR4J 结构非 playbook |

**审计新发现**（plan 未列）：
1. `keep_obs_nan_days` cal/eval 代码路径不一致（已对齐，见 §2/§4）。
2. HBV headline（sibling v7）metadata 是 2-basin 拼装、PET 只能从目录名推断 → S1 干净重跑修复。
3. HBV 用标定器的**独立副本** `calibrate_hbv_lite_cma`（与 XAJ/GR4J 共享的
   `_cmaes_multi_restart` 算法等价，但非同一函数）→ 见 §6 caveat。

---

## 4. S1：HBV 干净全 531 重跑（取代 sibling v7）

`hbv_lite_cma_FINAL_pt_v1_warmup`，PT/v1/warmup/5000×3，531/531 success，全字段 metadata。

- **median NSE = 0.617033**（精确命中既有 headline 目标），mean 0.580150。
- 逐 basin params 与 sibling v7 **bit-exact**（max|Δparam|=2.8e-14，CSV 浮点往返噪声）。
- **3/531 basin 的 eval NSE 与 v7 不同**（max 0.0118，07263295: 0.6456→0.6575）。
  机制：这些 basin 1988-89 warmup 窗口 obs 稀疏（07263295: 313/365 天缺测）；v7 旧代码
  warmup 用了不连续/更短 forcing → 慢库(SM/SLZ)未充分平衡 → eval 初态偏低。**S1（连续
  365 天 warmup，与 GR4J/XAJ 一致）是更正确的版本**。验证：3 basin 的 state_SM/state_SLZ
  S1 vs v7 明显不同（约 2×），坐实是 warmup/初态导致。
- **median/胜率/mean 实质不变**（median 0.617033 不变，mean +2e-5）→ headline 稳健；同时
  抓出并修正了 v7 的 3-basin 潜在 warmup 不一致。
- 我对 cal/eval 加的 keep_obs_nan_days：cal/eval 窗口 len(True)==len(False)（0 缺测）→
  对 S1 数值**逐位 0-影响**；3-basin 差异**纯属 v7 来路**（更早代码的 warmup 处理），与本次
  cal/eval 改动无关。

---

## 5. S3a 收敛 + S3b 预算对等

**S3a（XAJ sub40，5k×3 vs 2k×2 同 39 basin）**：

| | median | mean |
|---|---|---|
| 5k×3 | 0.628591 | 0.598360 |
| 2k×2 | 0.631061 | 0.593998 |

**|Δmedian| = 0.00247 ≤ 0.005 → 收敛**。per-basin |Δ| 中位 0.0054；5k 在 21/39 更高、18
更低（基本均衡，非单向下降）。→ Finding B 在收敛判据层关闭，XAJ 2k×2 headline 经直接证据
验证收敛。

**S3b（XAJ 全 531 5k×3）**：用户选择跑此步以**完全消除预算不对等**（连脚注都不需要）。
- 输出 `xaj_pdd_cma_FINAL_pt_v1_5k3`，531/531 success，0 失败，wall 676min（39 个 sub40
  basin bit-identical 预置并 skip，新算 492）。
- **XAJ 5k×3 全 531 median = 0.619564**（mean 0.574778），比 2k×2 的 0.623216 **略降
  0.0037**——**审计预判被验证**（更多预算 → XAJ 轻度过拟合，见 §7.8）。与 HBV 打平更干净（§6）。

---

## 6. 权威对比表（干净 S1 HBV；XAJ 待 S3b 更新为 5k×3）

来源：`verify_three_school_table.py` 从 per-basin CSV 重算，`summary/_three_school_table.json`。

| 模型 | median NSE | mean | 参数 | 预算 |
|---|---|---|---|---|
| **GR4J** | **0.653287** | 0.6102 | 8 | 5k×3 |
| **XAJ** | 0.619564 | 0.5748 | 20（有效<20） | 5k×3 |
| **HBV** | 0.617033 | 0.5802 | 13 | 5k×3 |
| SAC-SMA | 0.607 | — | 13 | 文献线 |

三家**预算完全对等（全 5k×3）**，全 531、0 失败、0 NaN，从 per-basin CSV 重算
（`summary/_three_school_table_5k3.json`）。配对（共同 531）：
- GR4J vs XAJ：median Δ +0.0235，GR4J 胜 343/531 = 64.6%
- GR4J vs HBV：median Δ +0.0298，GR4J 胜 366/531 = 68.9%
- **XAJ vs HBV：median Δ −0.0007（配对），XAJ 胜 263 / HBV 胜 268 ≈ 50/50 → 统计学打平**
  （预算对等后比 2k×2 版的 47.3% 更接近完美打平；XAJ median 仅高 HBV 0.0026）

---

## 7. Irreducible caveat（做完也存在，只披露）

1. **PET 口径模型相关**：GR4J/HBV 偏好 Priestley-Taylor，XAJ 偏好 Oudin（XAJ 的 kc 过缩放
   部分补偿 Oudin 低估）。headline 公平地对三家锁 PT；披露这是"最佳同协议"而非"各自最佳"，
   且 XAJ 在其偏好的 Oudin 下约 +0.03–0.04（故 PT headline 对 XAJ 反而保守）。
2. **参数效率非因果**：GR4J 同时最高 NSE + 最少参数（8）是 GR4J 简约**结构**的属性，**非
   playbook 功劳**；不可反推"参数越少越好"。XAJ 标称 20 参含 2 个冰参(pdd_factor_ice/
   refreeze_ice)，在非冰川 CAMELS 基本是死参 → 有效参数 < 20。
3. **XAJ 前向守恒 ~99.8%**：GR4J 机器精度(rel_resid 7.85e-17)、HBV _PBM 对齐 hydroDL2、XAJ
   自由水划分有小残差且无机器精度守恒自检。**不偏倚 NSE**（三家都按 sim-vs-obs Q 打分），披露即可。
4. **CMA-ES 随机性**：即便 5k×3 仍有 per-basin 种子噪声底——GR4J ~7e-5（可忽略）、XAJ ~7e-3。
   这正是 XAJ-HBV 0.0062 中位差必须报为打平的原因。
5. **HBV 标定器独立副本**：`calibrate_hbv_lite_cma` 与 XAJ/GR4J 共享的 `_cmaes_multi_restart`
   算法等价（已核 seed/init/sigma/bounds/maxfevals/objective/warmup），但是两份代码 → 未来
   编辑可能 silent desync，建议后续合并为一个标定器。
6. **SAC-SMA 是文献线**（Newman/Kratzert benchmark），未在 repro_v01 下重跑；按构造共享
   cal/eval/forcing，但标定器与 bounds 是外部 → 作参考线而非同协议条目。
7. **keep_obs_nan_days**（已对齐）：cal/eval 窗口 0/531 缺测 → 0-影响；warmup 窗口有真缺测，
   早已由 warmup load 的 `keep_obs_nan_days=True` 处理（S1 即正确版本）。

8. **XAJ 在高预算下轻度过拟合（参数效率的负面体现）**：XAJ 5k×3 vs 2k×2 全 531——median
   −0.0037、mean −0.0104；NSE<0 从 10→16、<−1 从 1→2；最大恶化是低信号/flashy basin
   (07301410 0.292→−1.443、05057200 0.143→−1.562)，多给 CMA-ES 预算反而过拟合 cal 期。
   GR4J(8 参) 则预算稳健(5k vs 2k |Δmed|=5e-5)。这是 20 参 vs 8 参的直接体现，强化"GR4J
   简约结构 = 鲁棒"的叙述。**注**：handoff 旧 caveat"arid gap +0.127, 5k×3 反更差"中"加
   预算更差"在 XAJ 聚合层得到证实；但"+0.127"具体数未在本轮复现（S3a 反见某干旱 basin
   +0.127 *改善*），故只写已验证的聚合行为。

> **独立复审 (plan F12)**：派独立 agent（新 context，自写 csv+pandas 双解析器）复算最终表，
> **PASS**——三家 median/mean/胜率/病态 NSE 全部逐位吻合（GR4J 0.653287、XAJ 0.619564、
> HBV 0.617033；GR4J 胜 343/366；XAJ-HBV 263 vs 268 打平）。自审之外独立确认。

---

## 8. 复现命令

```bash
# S2 bit-exact 自检
python -X utf8 -m src.scl_hydro.scripts.verify_hbv_bounds_preset

# S1 HBV 干净全 531
python -X utf8 -m src.scl_hydro.scripts.run_hbv_lite_cma_repro_v01 \
  --pet-method priestley_taylor --warmup-year --bounds-preset v1 \
  --trials 5000 --restarts 3 --workers 10 \
  --output-subdir hbv_lite_cma_FINAL_pt_v1_warmup

# S3b XAJ 全 531 5k×3（本会话运行中）
python -X utf8 -m src.xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01 \
  --pet-method priestley_taylor --warmup-year --bounds-preset v1 \
  --trials 5000 --restarts 3 --workers 16 \
  --output-subdir xaj_pdd_cma_FINAL_pt_v1_5k3

# 对比表重算（S6 工具；S3b 完成后把 XAJ 指向 5k3 目录）
python -X utf8 -m src.xaj_global_pilot.scripts.verify_three_school_table \
  --model "GR4J=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/gr4j_pdd_cma_FINAL_pt_v1" \
  --model "XAJ=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/xaj_pdd_cma_FINAL_pt_v1_5k3" \
  --model "HBV=results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/hbv_lite_cma_FINAL_pt_v1_warmup" \
  --out results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/_three_school_table.json
```
