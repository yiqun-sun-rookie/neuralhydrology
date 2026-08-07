# 已废弃 / 未完成运行目录索引

本目录下有 **27 个** 以 `.failed` 或 `.incomplete` 结尾的残留运行目录，
合计约 **35 MB**。它们是各实验线运行中途被门拦停或异常终止的产物，
**不是任何实验的正式结果**，不得用于科学结论。

## 为什么保留而不删除、不移动

1. **不删除**：多个是失败原因的证据，登记表与结案记录里以文字引用了它们的存在。
2. **不移动**：下表标 ✔ 的条目被**冻结配置 JSON** 或**测试文件**按精确路径引用。
   冻结配置受散列锁定、事后不得改写，一旦移动就会在锁定文件里留下无法修复的悬空路径。
   因此本目录采取「原地保留 + 索引说明」，而非归档搬迁。

## 命名约定

| 后缀 | 含义 |
|---|---|
| `.failed` | 运行器完成计算但在封装或校验阶段失败，或预置门拦停 |
| `.failed_<原因>_<时间戳>` | 同上，后缀直接写明拦停原因 |
| `.incomplete` / `.incomplete.<随机串>` | 运行中途异常终止，暂存目录被原子改名保留 |
| 以 `.` 开头 | 隐藏目录，同为暂存残留 |

## 清单

| 目录 | 大小 | 已入库文件数 | 被冻结件/测试引用 |
|---|---:|---:|---|
| `candidate_likelihood_parameter_switch_development_v01.incomplete` | 1.7 MB | 6 | ✔ 15 处 |
| `.formal_result_sixteen_reproduction_v01.incomplete` | 9.7 MB | 4 | — |
| `formal_result_sixteen_reproduction_v02.failed` | 12.2 MB | 6 | — |
| `g3_daily_rolling_forecast_development_v01.failed_shape_check_20260728T155620` | <0.1 MB | 0 | — |
| `g3_daily_rolling_forecast_readout_development_v01.failed_covariance_symmetry_20260728T2334` | <0.1 MB | 0 | — |
| `g3_daily_rolling_forecast_readout_development_v01.failed_missing_source_metadata_20260728T2329` | <0.1 MB | 0 | — |
| `g3_state_domain_consistent_process_noise_switch_v01.incomplete.317807653afd4be6baf8fdc6cb241fb3` | 6.7 MB | 0 | — |
| `g3_state_weight_factorial_param_switch_v02.incomplete` | 3.9 MB | 0 | ✔ 3 处 |
| `smoke_result_04015330_v01.failed` | <0.1 MB | 1 | — |
| `state_correction_audit_fixes_tests_red_v01.failed` | <0.1 MB | 1 | — |
| `state_correction_callback_tests_red_v01.failed` | <0.1 MB | 3 | — |
| `state_correction_checksum_finalize_tests_red_v01.failed` | <0.1 MB | 2 | — |
| `state_correction_final_checkpoint_boundary_red_v01.failed` | <0.1 MB | 3 | — |
| `state_correction_gate_default_tests_red_v01.failed` | <0.1 MB | 3 | — |
| `state_correction_packaging_tests_green_v01.failed` | <0.1 MB | 3 | — |
| `state_correction_packaging_tests_green_v02.failed` | <0.1 MB | 2 | — |
| `state_correction_packaging_tests_red_v01.failed` | <0.1 MB | 3 | — |
| `state_correction_readonly_verification_v01.failed` | <0.1 MB | 1 | — |
| `state_correction_reporting_tests_red_v01.failed` | <0.1 MB | 3 | — |
| `state_correction_resource_wait_v01.failed` | <0.1 MB | 2 | — |
| `state_correction_runner_tests_red_v01.failed` | <0.1 MB | 3 | — |
| `state_correction_sixteen_v01.failed` | <0.1 MB | 1 | — |
| `state_correction_smoke_v01.failed` | 0.7 MB | 10 | — |
| `state_correction_smoke_v03.failed` | <0.1 MB | 1 | — |
| `state_correction_smoke_v04.failed` | <0.1 MB | 1 | — |
| `state_correction_tests_green_v01.failed` | <0.1 MB | 3 | — |
| `state_correction_tests_red_v01.failed` | <0.1 MB | 3 | — |

## 逐条引用来源（供搬迁前核对）

- `candidate_likelihood_parameter_switch_development_v01.incomplete`
  - `docs/plans/2026-07-21-hbv-candidate-likelihood-identifiability-handoff.md`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_process_noise_switch_confirmation_v01.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_process_noise_switch_development_v02.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_process_noise_switch_development_v03.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_process_noise_switch_development_v04.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_process_noise_switch_development_v05.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_switch_confirmation_v01.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_switch_development_v02.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_switch_development_v03.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_switch_development_v04.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_parameter_switch_development_v05.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_process_noise_switch_confirmation_v01.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_process_noise_switch_development_v02.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_process_noise_switch_development_v03.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_process_noise_switch_development_v04.json`
  - `src/hbv_multilead_joint_uncertainty/configs/candidate_likelihood_process_noise_switch_development_v05.json`
- `g3_daily_rolling_forecast_development_v01.failed_shape_check_20260728T155620`
  - `docs/plans/2026-07-28-id23-daily-rolling-forecast-development-closure.md`
- `g3_daily_rolling_forecast_readout_development_v01.failed_covariance_symmetry_20260728T2334`
  - `docs/plans/2026-07-28-id23-daily-rolling-forecast-readout-closure.md`
- `g3_daily_rolling_forecast_readout_development_v01.failed_missing_source_metadata_20260728T2329`
  - `docs/plans/2026-07-28-id23-daily-rolling-forecast-readout-closure.md`
- `g3_state_domain_consistent_process_noise_switch_v01.incomplete.317807653afd4be6baf8fdc6cb241fb3`
  - `docs/plans/2026-08-03-id23-state-domain-consistent-process-noise-switch-closure.md`
  - `src/hbv_multilead_joint_uncertainty/HANDOFF_20260805_HBV_IMM_GUIDE_REORGANIZATION.md`
- `g3_state_weight_factorial_param_switch_v02.incomplete`
  - `src/hbv_multilead_joint_uncertainty/configs/g3_lead_adaptive_readout_param_switch_v01.json`
  - `src/hbv_multilead_joint_uncertainty/configs/g3_state_weight_factorial_param_switch_v03.json`
  - `test/test_hbv_state_weight_factorial_config_contract.py`

## 若将来要清理

先解决上表 ✔ 条目的引用问题，再动手；未标 ✔ 的条目可以安全归档或删除。
冻结配置内的引用无法修改——只能连同引用它的实验一起作废，或永久保留该目录。

本索引由只读扫描生成，未移动、未删除、未修改任何运行目录。
