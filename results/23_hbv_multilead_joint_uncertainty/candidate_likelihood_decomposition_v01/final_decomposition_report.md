# 十五状态候选观测似然分解：确定性分析报告（v01）

本报告由 `run_candidate_likelihood_decomposition.py` 按冻结规则自动生成，
规则见 `analysis_config_snapshot.json` 与设计文档；判定只使用第十评分日。

## 结论（按冻结一致性规则）

- 场景 `parameter_switch` 阶段 2：开发标签 `median_decomposition_inconsistent`，确认标签 `innovation_penalty_dominant`，方向一致 = False；结论：目前无法确定主要来源。
- 场景 `parameter_switch` 阶段 3：开发标签 `variance_penalty_dominant`，确认标签 `variance_penalty_dominant`，方向一致 = True；结论：错误候选第十日累计优势主要来自预测方差惩罚项。
- 场景 `process_noise_switch` 阶段 2：开发标签 `variance_penalty_dominant`，确认标签 `variance_penalty_dominant`，方向一致 = True；结论：错误候选第十日累计优势主要来自预测方差惩罚项。
- 场景 `process_noise_switch` 阶段 3：开发标签 `no_median_advantage`，确认标签 `no_median_advantage`，方向一致 = False；结论：目前无法确定主要来源。
- 场景 `parameter_process_noise_switch` 阶段 2：开发标签 `innovation_penalty_dominant`，确认标签 `innovation_penalty_dominant`，方向一致 = True；结论：错误候选第十日累计优势主要来自归一化平方创新惩罚项。
- 场景 `parameter_process_noise_switch` 阶段 3：开发标签 `variance_penalty_dominant_both_negative`，确认标签 `innovation_penalty_dominant`，方向一致 = False；结论：目前无法确定主要来源。

## 阶段级统计（切换阶段 2、3 参与判定，阶段 1 只报告）

| dataset_role | scenario | stage_number | is_switching_stage | block_count | trial_count | median_delta_variance | median_delta_innovation | median_delta_total | mean_delta_variance | mean_delta_innovation | mean_delta_total | fraction_delta_variance_negative | fraction_delta_innovation_negative | label | mean_label | robust | blocks_with_negative_median_delta_variance | blocks_with_negative_median_delta_innovation | blocks_with_negative_median_delta_total | total_best_wrong_tie_count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| development | parameter_switch | 1 | False | 12 | 36 | -0.217413 | 0.0765452 | -0.0904566 | 0.000255402 | -0.0160678 | -0.0158123 | 0.527778 | 0.472222 | variance_penalty_dominant | innovation_penalty_dominant | False | 7 | 5 | 8 | 0 |
| development | parameter_switch | 2 | True | 12 | 36 | 0.0847121 | 0.0285853 | -0.0511686 | -0.0471268 | 0.0964691 | 0.0493424 | 0.472222 | 0.472222 | median_decomposition_inconsistent | no_median_advantage | None | 5 | 6 | 8 | 0 |
| development | parameter_switch | 3 | True | 12 | 36 | -0.146772 | 0.0758001 | -0.0154057 | -0.286886 | 0.520634 | 0.233748 | 0.555556 | 0.444444 | variance_penalty_dominant | no_median_advantage | False | 8 | 4 | 7 | 0 |
| development | process_noise_switch | 1 | False | 12 | 36 | -0.914903 | 0.566777 | 0.217787 | -1.09408 | 4.05454 | 2.96046 | 0.611111 | 0.416667 | no_median_advantage | no_median_advantage | None | 10 | 3 | 4 | 0 |
| development | process_noise_switch | 2 | True | 12 | 36 | -0.631348 | 0.215638 | -0.0259056 | -0.457618 | 2.93971 | 2.48209 | 0.555556 | 0.444444 | variance_penalty_dominant | no_median_advantage | False | 8 | 5 | 6 | 0 |
| development | process_noise_switch | 3 | True | 12 | 36 | -0.788186 | 0.389891 | 0.00263691 | -0.421948 | 0.689952 | 0.268004 | 0.583333 | 0.416667 | no_median_advantage | no_median_advantage | None | 9 | 3 | 5 | 0 |
| development | parameter_process_noise_switch | 1 | False | 12 | 108 | -0.339983 | 0.0913226 | -0.311755 | -0.341841 | -0.042364 | -0.384205 | 0.592593 | 0.453704 | variance_penalty_dominant | variance_penalty_dominant_both_negative | True | 9 | 4 | 11 | 0 |
| development | parameter_process_noise_switch | 2 | True | 12 | 108 | 0.0628098 | -0.111159 | -0.326774 | 0.119366 | -0.814585 | -0.695219 | 0.472222 | 0.555556 | innovation_penalty_dominant | innovation_penalty_dominant | True | 7 | 7 | 11 | 0 |
| development | parameter_process_noise_switch | 3 | True | 12 | 108 | -0.0389175 | -0.0284574 | -0.586888 | -0.305799 | -0.532895 | -0.838695 | 0.537037 | 0.509259 | variance_penalty_dominant_both_negative | innovation_penalty_dominant_both_negative | False | 7 | 5 | 12 | 0 |
| confirmation | parameter_switch | 1 | False | 12 | 36 | -0.38711 | 0.189271 | -0.0173167 | -0.266879 | 0.270042 | 0.00316302 | 0.638889 | 0.361111 | variance_penalty_dominant | no_median_advantage | False | 11 | 1 | 7 | 0 |
| confirmation | parameter_switch | 2 | True | 12 | 36 | 0.149432 | -0.126687 | -0.162936 | 0.107211 | -0.294076 | -0.186865 | 0.444444 | 0.555556 | innovation_penalty_dominant | innovation_penalty_dominant | True | 4 | 8 | 11 | 0 |
| confirmation | parameter_switch | 3 | True | 12 | 36 | -0.175766 | 0.0532464 | -0.0175998 | -0.304325 | 0.552666 | 0.248341 | 0.527778 | 0.472222 | variance_penalty_dominant | no_median_advantage | False | 7 | 5 | 7 | 0 |
| confirmation | process_noise_switch | 1 | False | 12 | 36 | -0.865377 | 0.511186 | 0.615487 | -0.779729 | 1.76458 | 0.984855 | 0.555556 | 0.444444 | no_median_advantage | no_median_advantage | None | 8 | 4 | 4 | 0 |
| confirmation | process_noise_switch | 2 | True | 12 | 36 | -0.892768 | 0.302626 | -0.321648 | -0.777495 | 1.61859 | 0.841094 | 0.611111 | 0.416667 | variance_penalty_dominant | no_median_advantage | False | 10 | 3 | 7 | 0 |
| confirmation | process_noise_switch | 3 | True | 12 | 36 | -0.691236 | 0.235775 | 0.152906 | -0.28748 | 0.420022 | 0.132542 | 0.527778 | 0.472222 | no_median_advantage | no_median_advantage | None | 7 | 5 | 6 | 0 |
| confirmation | parameter_process_noise_switch | 1 | False | 12 | 108 | -0.435531 | 0.137246 | -0.356763 | -0.546783 | 0.0941806 | -0.452602 | 0.675926 | 0.416667 | variance_penalty_dominant | variance_penalty_dominant | True | 9 | 5 | 10 | 0 |
| confirmation | parameter_process_noise_switch | 2 | True | 12 | 108 | 0.117704 | -0.365577 | -0.562452 | -0.0326169 | -1.10729 | -1.1399 | 0.462963 | 0.583333 | innovation_penalty_dominant | innovation_penalty_dominant_both_negative | True | 5 | 8 | 12 | 0 |
| confirmation | parameter_process_noise_switch | 3 | True | 12 | 108 | 0.14237 | -0.236176 | -0.311935 | -0.0402457 | -1.01325 | -1.0535 | 0.435185 | 0.574074 | innovation_penalty_dominant | innovation_penalty_dominant_both_negative | True | 4 | 8 | 12 | 0 |

## 完整性

- 逐日分解恒等式最大绝对误差（六个运行的最大值）：2.132e-14
- 阶段累计恒等式最大绝对误差：1.137e-13
- 第十日边际分解最大绝对误差：2.487e-14
- 最佳错误候选并列总数：0
- 全部完整性门槛通过：True

## 边界

This analysis only attributes the best wrong candidate's day-10 cumulative log-likelihood advantage to its two Gaussian components. It does not modify the identifiability conclusion, does not evaluate any weight mechanism, and does not address whether candidate filters converge to similar states.
