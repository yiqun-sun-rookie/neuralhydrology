# LSTM-on-CAMELS 训练消歧对照表(2026-06-17)

> 本仓**多个项目**都在 CAMELS-US(尤其 531)上训过 LSTM/CudaLSTM/EA-LSTM,NSE 多在 0.6–0.76,
> 极易混淆。本表是**唯一权威对照**:认错时先查这里。盘点来源:全仓 3 路 workflow(71 个 artifact)。

## ⭐ 5 秒判别钥匙

| 判别特征 | 含义 |
|---|---|
| **forcing = `maurer`** | → **ID18 公平对比**(全仓**唯一**用 maurer 的 LSTM)。其余全部 `daymet`。 |
| **seq_length = 270** | → **ID18**(全仓唯一)。其余 365(或 168/小时)。 |
| 路径含 `lstm_fair_531` / `results/18_` | → **ID18**。 |
| `daymet` + reverse split + 531 + h256 + NSE≈0.754/0.731 | → **Idea05 已废弃旧代次**(不是 ID18!最危险的李鬼,见下)。 |
| `daymet` + **temporal** split(train 1990-95/test 2000-05) | → **Idea05 活跃对抗 victim**。 |

## 各项目对照

| 项目 | 路径 | 模型 | forcing | split | basins | NSE | 用途 | 状态 |
|---|---|---|---|---|---|---|---|---|
| **ID18 公平对比** ✅本次 | `src/lstm_fair_531/` + `results/18_lstm_fair_531/` | cudalstm+static (+计划 ealstm) | **maurer** | reverse 1999-2008/1989-99 | **531** | 单 0.733 / **8-seed ens 0.759**(≈Kratzert 0.758) | 与三学派公平对比 + 531-DA DL 天花板 | **活跃/已收敛** |
| **Idea05 对抗 — 活跃 victim** | `results/05_adversarial_robustness/runs/` (`reproduce_531_nse074_*`, `full_531_temporal_*`, 及 ealstm/gru/transformer/mtslstm/arlstm 等) | 多架构 | daymet | **temporal** 1990-95/2000-05 | 531 | cudalstm ~0.74 | 对抗鲁棒性论文(当前 victim) | **活跃** |
| **Idea05 对抗 — 废弃旧代次** ⚠️ | 根 `runs/adv_*`(`adv_final_with_static_h256_*`×5, `adv_ealstm_h256_*`, `adv_cudalstm_h256_nostatic_*`, `adv_531_*`, `adv_final_*`, `ablation_531_*`) | cudalstm/ealstm h256&h128 | daymet | **reverse** 1999-2008/1989-99 | 531 | **0.754 / 0.731**(≈Kratzert) | 早期对抗 baseline | **废弃**(memory `adversarial_paper_handoff`:h256+reverse 代次已弃,改用 temporal+h128) |
| **Idea16 知识分离** | 根 `runs/ks_*`(13 个) + `src/pretrained_lstm_knowledge_separation/` | cudalstm/ealstm | daymet | reverse | 531/subset | ~0.46–0.76 | 预训练知识分离 | stale? |
| **Idea11/17 静态证伪 POC** | 根 `runs/sf_e1_fold*`, `runs/ealstm_poc_real_*`, `runs/filmlstm_poc_*` + `src/static_falsification/` | ealstm/filmlstm | daymet | reverse | k-fold subset | fold ~0.60–0.64 | 静态属性证伪 POC(已并入 ID17) | POC/stale |
| **Idea07 HydroAgent** | `results/07_hydroagent/` + `src/hydroagent/` | cudalstm/ealstm | daymet | 自有 split | **subset**(非 531) | 0.683 / 0.58;split 版 0.78;无 split 0.894(train=test!) | 可解释 agent baseline | **活跃** |
| nh 框架示例 | `examples/06-Finetuning/531_basins.yml`, `examples/05-*/1_basin.yml` | cudalstm | daymet | reverse | 531/1 | n/a(epochs=3 演示) | 框架教程 | 框架自带(勿动) |
| 已归档 mamba/MTS | `results/_archive/02_mamba_camels_us`, `_archive/03_mamba_camelsh`, `src/_archive/41_mts_mamba` | mamba/mtslstm | daymet | 多 | 531/小时 | ~0.56 | 旧探索 | **已归档** |
| 其它(非 CAMELS 流量) | 根 `runs/gwl_*`+`per_well_*`(Idea08 地下水)、`results/ylx_dl_da`(DA)、`src/scl_hydro`(SCL-LSTM) | cudalstm/lstm | 非 daymet/其它 | — | 井/其它 | — | 地下水/DA/状态连续性 | 各自独立 |

## 最危险的一组(务必记住)

`runs/adv_final_with_static_h256_*`(NSE **0.754**)、`runs/adv_ealstm_h256_*`(**0.731**)——
**reverse split + 531 + h256 + cudalstm/ealstm + NSE 几乎等于 Kratzert**,与 ID18 只差 **forcing(daymet vs maurer)** 和 **seq(365 vs 270)**。
它们是 **Idea05 的废弃代次**,**不是** ID18 的结果。引用 ID18 数字时认准 `results/18_lstm_fair_531/_reports/`(maurer)。

## 维护
- ID18 权威结果:`results/18_lstm_fair_531/ITERATION_LOG.md` + `_reports/compare_iter2_cudalstm_8seed_ens.json`。
- 新增任何 CAMELS-LSTM 训练时,请回填本表一行。
