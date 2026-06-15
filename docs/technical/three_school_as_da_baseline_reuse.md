# 三学派概念模型 → DA baseline 复用说明 (2026-06-14 决策)

> **决策（用户 2026-06-14）**：Idea 10 三学派对比（GR4J vs XAJ vs HBV，CAMELS-US 531）
> **不独立成文**（放弃 JoH/HESS/WRR-note 路线，见 `three_school_novelty_assessment` 记忆）；
> 其冻结结果**收编为数据同化（DA / kalmannet 线）论文的传统概念模型 baseline**。
> **0 新跑**——只复用 repro_v01 已锁定结果。
>
> 本文档**不复制** `three_school_fairness_completion_20260608.md`（那是协议/数字/caveat 的
> 权威来源），只补它没有的三件事：**(1) DA 复用兼容矩阵、(2) DA 叙事中的定位、(3) 复用陷阱**。

---

## 1. 权威来源（数字与协议在这两处，勿在本文档重抄维护）

- **协议 + 公平性 + irreducible caveat**：`docs/technical/three_school_fairness_completion_20260608.md`
- **per-basin 逐流域 NSE/参数**（531 个 CSV，gitignore）：
  - GR4J：`results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/gr4j_pdd_cma_FINAL_pt_v1/`
  - XAJ：`.../xaj_pdd_cma_FINAL_pt_v1_5k3/`
  - HBV：`.../hbv_lite_cma_FINAL_pt_v1_warmup/`
- 冻结 headline（独立复审逐位吻合，plan F12 PASS）：

  | 模型 | eval median NSE | mean | 参数 | 预算 |
  |---|---|---|---|---|
  | GR4J+PDD | **0.653287** | 0.6102 | 8 | 5k×3 |
  | XAJ+PDD | 0.619564 | 0.5748 | 20（有效<20） | 5k×3 |
  | HBV-lite | 0.617033 | 0.5802 | 13 | 5k×3 |
  | SAC-SMA | 0.607 | — | 13 | 文献参考线 |

  协议：cal WY1999–2008 / eval WY1989–1999（reverse split）/ maurer / Priestley-Taylor PET /
  1yr warmup / 共享 CMA-ES 5000×3 / NSE / bit-exact。

  > SAC-SMA 为**文献参考线**（Kratzert 2019 Table 3，**447 共同子集**，published median **0.603**；
  > 本表沿用 completion doc 转录的 0.607，0.004 差异待与 completion doc 一并核对）。三学派 median 在
  > **full-531** 上算 → 严格 head-to-head 须取 447 共同子集，本表仅作参考线对照。

---

## 2. 复用目标 = 531-DA（HBV-lite 当过程模型 f）

唯一目标：kalmannet 的 **531-DA 实验**——用本仓 HBV-lite 当 DA 过程模型 f，**按设计锚定
repro_v01**。三学派开环 NSE 与它在 **basins / split / forcing / metric 四维同协议**，
GR4J / XAJ 两行可直接作开环**天花板参考线**。

> ⚠️ **HBV 行（= f 本身）有一道口径闸门，复用前必须对齐**：repro_v01 目录里 HBV-lite 有多个
> 单变体，PET 与 bounds 不同 → 开环 median 不同：
> - **v5（Oudin + wide bounds）= 0.5995** —— kalmannet 531-DA 迁移计划 (2026-06-05) 的 *v0 推荐 f*
>   与迁移闸门（T4「开环复现 median≈0.5995 才放行」）锚的就是这一支。
> - **S1（PT + tight v1 + warmup）= 0.617033** —— 三学派表里的 HBV 行（与 GR4J/XAJ 同 PT 口径）。
>
> 二者 **PET + bounds 都不同，是两个模型实例**。f 的开环 baseline **必须与 f 实际用的变体口径一致**：
> 若 f 沿用 v0 推荐的 v5（Oudin），DA 增益要对 **0.5995** 量，**不能**借三学派的 0.617 行；若把 f
> 切到 PT/tight/warmup，则迁移闸门应同步改成 ≈0.617。**此口径选择留到 531-DA 写作时定**（见 §4 陷阱 5）。

- 迁移手册：`kalmannet/docs/plans/2026-06-05-hbv-lite-da-migration.md`（sibling 仓）。
- kalmannet 的 Project 01（Regge 小时 WALRUS）/ Project 02（Caravan 区域化）协议不同，不用这套数字。
- **现实状态**：531-DA 目前是 kalmannet 侧 *plan*、尚无成稿 → 本动作是 **forward-filing**：
  存好，等 531-DA 论文写作时落位。

---

## 3. 在 531-DA 叙事中的定位：开环概念模型天花板

三学派开环结果给 531-DA 实验一个**有目的的角色**（无需自己背创新）：

- DA 必须超越的**开环概念模型上限**：最佳开环（GR4J）median NSE **0.653**。f（HBV-lite）的开环
  起点取决于其变体口径（见 §2 闸门：v5/Oudin 0.5995 或 PT/tight 0.617）；"HBV-lite + DA" 的价值
  = 把 f 自己的开环起点推高、逼近/越过 GR4J 这条天花板线。
- 一句话能预防的审稿质疑：「f 为什么用 HBV-lite 而非最强的 GR4J？」
  → **GR4J 开环更强（配对 median Δ +0.0298 vs HBV，胜 68.9%）且预算更鲁棒**；选 HBV-lite 当 f 是
  因为它已有逐步可微 `forward_step` + 状态向量 **m=5**（≠13 标定参数）正好映射 KalmanNet `m=5`
  （工程/可微性理由），**不是**因为它是最强概念模型。这句话应写进 DA 论文以诚实交代。

---

## 4. 复用陷阱（必读，全是踩过/易踩的）

1. **别混两个 HBV**：kalmannet 的**区域化** HBV（跨流域共享网络）val median ~**0.49**；本仓
   `hbv_lite`（逐流域 CMA-ES）median **0.617**。DA 的强过程模型 f 用后者，对比表别串号。
2. **0.617 是单变量、不是集成**：三学派表里的 HBV = 单一 PT/v1/warmup 变体（≈ best-single
   PT 0.618）。**不要**和 9-way 集成 **0.6227** 混——后者混了 Oudin/PT/bounds、**不可部署**，
   不能当单一可复现 baseline，也不是 DA 用的那个 f。
3. **PET 口径模型相关**：headline 对三家锁 PT 是"最佳同协议"非"各自最佳"；XAJ 在其偏好的
   Oudin 下约 +0.03–0.04（故 PT headline 对 XAJ 偏保守）。复用时连同此 caveat 一起搬。
4. **XAJ–HBV 是统计学打平**（配对 Δ−0.0007，263 vs 268）：baseline 表里别写成"XAJ>HBV"或
   "HBV>XAJ"，写"≈打平"。GR4J 领先（胜 64.6%/68.9%）才是稳的。
5. **HBV 的开环 baseline 必须与 f 实际变体口径一致**（§2 闸门，本复用最贵踩雷点）：迁移闸门
   0.5995 是 **v5（Oudin + wide）** 的复现自检；三学派表里的 0.617 是 **PT + tight + warmup** 变体。
   两者 PET 与 bounds 都不同 → **严禁互相充当对方的开环 baseline**（DA 增益要对 f 自己那支量）。

---

## 5. 本复用动作 = 0 新跑

- 不为 Idea 10 加任何训练/标定；不画新图；不写独立稿。
- 标准 Idea 10 论文路线**封存**（见 `three_school_novelty_assessment` 记忆的最终判决）。
- 结果以本文档 + completion doc + per-basin CSV 形式**可发现、可落位**，等 531-DA 论文取用。
