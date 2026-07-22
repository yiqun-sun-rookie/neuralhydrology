# 十五状态候选观测似然分解诊断：冻结设计（v01）

日期：2026-07-21。本文件在计算任何分解数值之前写定并冻结。分析编号 `candidate_likelihood_decomposition_v01`。

## 1. 问题

第五版开发与第一版确认已确认：真实候选的累计观测对数似然不能在切换后十个评分日内稳定超过错误候选。本轮只回答一个问题：错误候选的累计似然优势主要来自标量高斯观测对数似然的哪一个组成部分——

- 预测方差惩罚 `A = -0.5 * log(2 * pi * innovation_variance)`；
- 归一化平方创新惩罚 `B = -0.5 * innovation^2 / innovation_variance`；

以及该方向在第五版开发与第一版确认之间是否一致。

## 2. 输入（全部只读，冻结证据）

六个冻结运行目录（三场景 × 开发 v05 / 确认 v01），读取 `evidence.npz` 中的
`candidate_innovations`、`candidate_innovation_variances`、`candidate_daily_log_likelihoods`、
`cumulative_log_likelihoods`、`true_candidate_cumulative_margins`、`truth_candidate_indices`、
`stage_start_days`、`stage_end_days`、`adaptation_days`、`candidate_ids`、`block_ids`。

运行前后各做一次输入目录完整性核对：对每个输入目录用扩展长度路径重算全部文件散列，与目录内
`checksums.json` 比对；同时核对六份输入配置文件的 SHA-256 与交接文档记录一致。任何不符即停止并标记暂缓。

不修改、不覆盖、不重跑任何冻结实验；本分析无新随机数（完全确定性，不需要新种子）。

## 3. 分解定义

对每个（数据角色, 场景, 区块, 真值试验, 逐日, 候选）：

- `A_d = -0.5 * ln(2π * S_d)`，`B_d = -0.5 * ν_d² / S_d`，其中 `ν_d` 为创新、`S_d` 为创新方差。
- 恒等式门槛（完整性门槛，非科学阈值）：`max |A_d + B_d − 冻结逐日对数似然| ≤ 1e-12`。
- 评分窗口与冻结判定一致：每阶段排除前五日，第六至十五日为评分日 1–10；每阶段内对评分日分别累计
  `cumA`、`cumB`；门槛 `max |cumA + cumB − 冻结阶段累计对数似然| ≤ 1e-11`。

## 4. 比较对象（冻结规则）

- 比较基准候选 = 该（区块, 真值试验, 阶段）在**第十评分日总累计对数似然**最大的错误候选
  （与冻结判定的"第十日最佳错误候选"一致）。
- 并列处理：若多个错误候选总累计并列最大，取候选索引最小者做分解，并记录并列数（预期为 0）。
- 试验级最终分解：`ΔA = cumA_true(10) − cumA_bw(10)`，`ΔB` 同理；
  门槛 `max |ΔA + ΔB − 冻结 true_candidate_cumulative_margins[..., -1]| ≤ 1e-11`。
- 逐评分日曲线另存每候选 `cumA/cumB`（完整信息），逐日差值曲线用当日最佳错误候选（与冻结逐日 margin 口径一致），仅作展示，不参与判定。

## 5. 聚合与归因规则（冻结，判定只用第十评分日）

对每个（数据角色, 场景, 阶段 ∈ {2, 3}）：

- 主统计量：全部区块×真值试验的 `ΔA`、`ΔB`、`Δtotal = ΔA + ΔB` 的中位数。
- 辅助统计量：均值（均值分解严格可加）；`ΔA<0`、`ΔB<0` 的试验比例；每区块中位数及为负的区块数。
- 归因标签（先看 `median(Δtotal)`）：
  1. `median(Δtotal) ≥ 0` → `no_median_advantage`（该阶段第十日中位数上错误候选没有优势，不做归因）。
  2. `median(Δtotal) < 0` 且 `median(ΔA) < 0 ≤ median(ΔB)` → `variance_penalty_dominant`。
  3. `median(Δtotal) < 0` 且 `median(ΔB) < 0 ≤ median(ΔA)` → `innovation_penalty_dominant`。
  4. 两者皆负：绝对值严格较大者 → `variance_penalty_dominant_both_negative` 或
     `innovation_penalty_dominant_both_negative`；绝对值相等 → `both_negative_equal`（不归因）。
  5. 两者皆非负但 `median(Δtotal) < 0`（中位数不可加导致）→ `median_decomposition_inconsistent`（不归因）。
- 稳健性旗标：用均值重复上述归因；均值家族与中位数家族一致记 `robust=true`，否则 `robust=false`
  （主标签仍由中位数规则决定，旗标只作诚实披露）。

## 6. 开发—确认一致性规则（冻结）

对每个（场景, 阶段）：

- 提取主导家族：`variance_penalty_dominant*` → `variance`；`innovation_penalty_dominant*` → `innovation`；
  其余标签（含 `no_median_advantage`）无家族。
- 开发与确认家族相同且均非空 → 该（场景, 阶段）方向一致，可写"主要来源为 X"。
- 其余任何情形 → 该（场景, 阶段）写"目前无法确定主要来源"。
- 总结论只对方向一致的（场景, 阶段）下断言；不得跨阶段或跨场景外推。

## 7. 输出（新版本化目录，写入前经 `.incomplete` 暂存）

`results/23_hbv_multilead_joint_uncertainty/candidate_likelihood_decomposition_v01/`：

- `analysis_config_snapshot.json`（本配置逐字节快照）
- 每输入运行一份逐候选逐日分解表 `daily_components__<run>.csv`
- 每输入运行一份试验阶段分解表 `trial_stage_components__<run>.csv`
- `stage_component_summary.csv`（12 行 = 2 角色 × 3 场景 × 2 切换阶段；另含阶段 1 仅报告行）
- `development_confirmation_consistency.csv`（6 行 = 3 场景 × 2 切换阶段）
- `input_integrity_before.json` / `input_integrity_after.json`
- `integrity_checks.json`（恒等式与边际一致性门槛结果）
- `resource_preflight.json`（按实际数组形状估算，非固定门槛）
- `environment.json`、`summary.json`、`final_decomposition_report.md`、`checksums.json`

## 8. 测试先行

新模块 `src/hbv_multilead_joint_uncertainty/candidate_likelihood_decomposition.py` 的每个行为
（分解恒等式、输入校验、阶段累计与最佳错误候选分解、并列处理、归因标签、一致性判定）先写聚焦失败测试
`test/test_hbv_candidate_likelihood_decomposition.py`，观察失败后再实现。

## 9. 资源

执行前按六个 `evidence.npz` 的实际数组形状估算峰值内存（数组字节 × 安全系数 + 表格缓冲），与当前可用
物理内存和可提交内存比较后才执行；不使用统一固定内存门槛。预期总量在数十兆字节量级。

## 10. 边界

本分析只诊断"错误候选第十日累计优势的组成来源"，不判断任何权重机制、不改变可辨识性结论、不回答
"候选滤波器是否过快收敛到相似状态"（那是下一轮独立问题）。
