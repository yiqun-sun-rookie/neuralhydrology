# 十五状态候选再识别时间刻画：确定性分析报告（v01）

本报告由 `run_candidate_likelihood_reidentification.py` 按读数前冻结的规则自动生成；
分类与判定规则见 `analysis_config_snapshot.json`。

## 结论（按冻结一致性规则，仅切换阶段 2、3）

- 场景 `parameter_switch` 阶段 2：开发主导失败模式 `never_first`，确认主导失败模式 `first_then_lost`，一致 = False；结论：目前无法确定主导失败模式。
- 场景 `parameter_switch` 阶段 3：开发主导失败模式 `never_first`，确认主导失败模式 `first_then_lost`，一致 = False；结论：目前无法确定主导失败模式。
- 场景 `process_noise_switch` 阶段 2：开发主导失败模式 `never_first`，确认主导失败模式 `never_first`，一致 = True；结论：never_first。
- 场景 `process_noise_switch` 阶段 3：开发主导失败模式 `never_first`，确认主导失败模式 `never_first`，一致 = True；结论：never_first。
- 场景 `parameter_process_noise_switch` 阶段 2：开发主导失败模式 `never_first`，确认主导失败模式 `never_first`，一致 = True；结论：never_first。
- 场景 `parameter_process_noise_switch` 阶段 3：开发主导失败模式 `never_first`，确认主导失败模式 `never_first`，一致 = True；结论：never_first。

## 切换阶段统计

| dataset_role | scenario | stage_number | is_switching_stage | block_count | trial_count | count_never_first | count_first_then_lost | count_stable_too_late | count_stable | fraction_never_first | fraction_first_then_lost | fraction_stable_too_late | fraction_stable | ever_first_count | median_first_day_among_ever_first | first_day_quartile_25 | first_day_quartile_75 | median_first_stable_day_among_stable | dominant_failure_label | blocks_with_zero_stable | min_block_stable_count | max_block_stable_count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| development | parameter_switch | 2 | True | 12 | 36 | 13 | 7 | 4 | 12 | 0.361111 | 0.194444 | 0.111111 | 0.333333 | 23 | 1 | 1 | 2 | 1 | never_first | 0 | 1 | 1 |
| development | parameter_switch | 3 | True | 12 | 36 | 10 | 9 | 2 | 15 | 0.277778 | 0.25 | 0.0555556 | 0.416667 | 26 | 1 | 1 | 3 | 1 | never_first | 0 | 1 | 2 |
| development | process_noise_switch | 2 | True | 12 | 36 | 11 | 7 | 4 | 14 | 0.305556 | 0.194444 | 0.111111 | 0.388889 | 25 | 2 | 1 | 3 | 1.5 | never_first | 1 | 0 | 2 |
| development | process_noise_switch | 3 | True | 12 | 36 | 10 | 8 | 8 | 10 | 0.277778 | 0.222222 | 0.222222 | 0.277778 | 26 | 2.5 | 1.25 | 5.75 | 3.5 | never_first | 4 | 0 | 2 |
| development | parameter_process_noise_switch | 2 | True | 12 | 108 | 60 | 20 | 14 | 14 | 0.555556 | 0.185185 | 0.12963 | 0.12963 | 48 | 2 | 1 | 5.25 | 3 | never_first | 2 | 0 | 2 |
| development | parameter_process_noise_switch | 3 | True | 12 | 108 | 71 | 21 | 7 | 9 | 0.657407 | 0.194444 | 0.0648148 | 0.0833333 | 37 | 3 | 1 | 8 | 2 | never_first | 4 | 0 | 2 |
| confirmation | parameter_switch | 2 | True | 12 | 36 | 12 | 13 | 3 | 8 | 0.333333 | 0.361111 | 0.0833333 | 0.222222 | 24 | 1.5 | 1 | 2 | 2 | first_then_lost | 4 | 0 | 1 |
| confirmation | parameter_switch | 3 | True | 12 | 36 | 6 | 13 | 4 | 13 | 0.166667 | 0.361111 | 0.111111 | 0.361111 | 30 | 2 | 1 | 3.75 | 1 | first_then_lost | 1 | 0 | 2 |
| confirmation | process_noise_switch | 2 | True | 12 | 36 | 15 | 5 | 4 | 12 | 0.416667 | 0.138889 | 0.111111 | 0.333333 | 21 | 1 | 1 | 3 | 1 | never_first | 3 | 0 | 2 |
| confirmation | process_noise_switch | 3 | True | 12 | 36 | 11 | 6 | 6 | 13 | 0.305556 | 0.166667 | 0.166667 | 0.361111 | 25 | 1 | 1 | 3 | 2 | never_first | 4 | 0 | 2 |
| confirmation | parameter_process_noise_switch | 2 | True | 12 | 108 | 74 | 20 | 7 | 7 | 0.685185 | 0.185185 | 0.0648148 | 0.0648148 | 34 | 3 | 1 | 7 | 1 | never_first | 5 | 0 | 1 |
| confirmation | parameter_process_noise_switch | 3 | True | 12 | 108 | 69 | 18 | 9 | 12 | 0.638889 | 0.166667 | 0.0833333 | 0.111111 | 39 | 4 | 2 | 6.5 | 4 | never_first | 2 | 0 | 3 |

## 阶段 1（无切换，仅报告）

| dataset_role | scenario | stage_number | is_switching_stage | block_count | trial_count | count_never_first | count_first_then_lost | count_stable_too_late | count_stable | fraction_never_first | fraction_first_then_lost | fraction_stable_too_late | fraction_stable | ever_first_count | median_first_day_among_ever_first | first_day_quartile_25 | first_day_quartile_75 | median_first_stable_day_among_stable | dominant_failure_label | blocks_with_zero_stable | min_block_stable_count | max_block_stable_count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| development | parameter_switch | 1 | False | 12 | 36 | 12 | 8 | 3 | 13 | 0.333333 | 0.222222 | 0.0833333 | 0.361111 | 24 | 1 | 1 | 4 | 1 | never_first | 1 | 0 | 2 |
| development | process_noise_switch | 1 | False | 12 | 36 | 8 | 5 | 7 | 16 | 0.222222 | 0.138889 | 0.194444 | 0.444444 | 28 | 1 | 1 | 3 | 2 | never_first | 2 | 0 | 3 |
| development | parameter_process_noise_switch | 1 | False | 12 | 108 | 56 | 21 | 14 | 17 | 0.518519 | 0.194444 | 0.12963 | 0.157407 | 52 | 3 | 1 | 5 | 4 | never_first | 1 | 0 | 3 |
| confirmation | parameter_switch | 1 | False | 12 | 36 | 9 | 9 | 5 | 13 | 0.25 | 0.25 | 0.138889 | 0.361111 | 27 | 1 | 1 | 2.5 | 1 | tie:first_then_lost+never_first | 1 | 0 | 2 |
| confirmation | process_noise_switch | 1 | False | 12 | 36 | 4 | 9 | 6 | 17 | 0.111111 | 0.25 | 0.166667 | 0.472222 | 32 | 1 | 1 | 2 | 2 | first_then_lost | 1 | 0 | 3 |
| confirmation | parameter_process_noise_switch | 1 | False | 12 | 108 | 50 | 24 | 17 | 17 | 0.462963 | 0.222222 | 0.157407 | 0.157407 | 58 | 2 | 1 | 4 | 1 | never_first | 2 | 0 | 4 |

## 完整性

- `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_parameter_switch_development_v05`：首次登顶日重算不符 0，首次稳定日重算不符 0，稳定类别对冻结旗标不符 0，划分违例 0，通过 = True
- `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_process_noise_switch_development_v05`：首次登顶日重算不符 0，首次稳定日重算不符 0，稳定类别对冻结旗标不符 0，划分违例 0，通过 = True
- `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_parameter_process_noise_switch_development_v05`：首次登顶日重算不符 0，首次稳定日重算不符 0，稳定类别对冻结旗标不符 0，划分违例 0，通过 = True
- `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_parameter_switch_confirmation_v01`：首次登顶日重算不符 0，首次稳定日重算不符 0，稳定类别对冻结旗标不符 0，划分违例 0，通过 = True
- `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_process_noise_switch_confirmation_v01`：首次登顶日重算不符 0，首次稳定日重算不符 0，稳定类别对冻结旗标不符 0，划分违例 0，通过 = True
- `results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_parameter_process_noise_switch_confirmation_v01`：首次登顶日重算不符 0，首次稳定日重算不符 0，稳定类别对冻结旗标不符 0，划分违例 0，通过 = True

## 边界

This analysis only characterizes re-identification timing and failure modes of the frozen likelihood-rank evidence. It does not modify the identifiability conclusion, does not evaluate any weight mechanism, does not claim that longer horizons would rescue identification, and does not rerun any frozen experiment.
