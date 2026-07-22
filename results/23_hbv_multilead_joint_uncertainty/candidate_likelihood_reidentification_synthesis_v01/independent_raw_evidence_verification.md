# 独立复算报告：十五状态候选再识别时间刻画（candidate_likelihood_reidentification_v01）

（独立复算上下文原文存档，2026-07-21。计算严格先于查看被审输出；输入仅为六个冻结 evidence.npz 与配置快照。）

## 总结论

**复算一致。** 在只读六个冻结 evidence.npz 与配置快照的前提下独立复算了全部科学数值，随后才打开被审输出目录逐行对比：18 个阶段行、6 行一致性、summary.json 结论、四门数值、六份试验级 CSV 全部 972 行（非抽样）、daily 汇总全部 180 行，零差异；输出目录与六个冻结输入目录哈希核对全部通过。未发现任何不一致。

## 事实

### 1. 独立算出的 6 行一致性结论（先算后比，与被审 dominant_failure_consistency.csv 逐字一致）

| 场景 | 阶段 | 开发主导 | 确认主导 | 结论 |
|---|---|---|---|---|
| parameter_switch | 2 | never_first | first_then_lost | 目前无法确定主导失败模式 |
| parameter_switch | 3 | never_first | first_then_lost | 目前无法确定主导失败模式 |
| process_noise_switch | 2 | never_first | never_first | never_first |
| process_noise_switch | 3 | never_first | never_first | never_first |
| parameter_process_noise_switch | 2 | never_first | never_first | never_first |
| parameter_process_noise_switch | 3 | never_first | never_first | never_first |

summary.json 的 6 条 conclusions（含 Unicode 转义的中文串）与上表逐条相同。

### 2. 18 个阶段行与被审 stage_reidentification_summary.csv 的差异

零差异。每行核对全部字段：四类计数与比例、ever_first_count、曾登顶首日中位数与 25/75 分位（numpy 线性插值法精确吻合，容差 1e-12 内全 0 差）、stable 首稳日中位数、主导失败标签，以及从试验表重算的 blocks_with_zero_stable / min / max_block_stable_count——18 行 × 全字段 0 不符。关键数字（双方一致）：开发联合 stage3 never_first 71/108（65.7%）、stable 9/108；确认联合 stage2 never_first 74/108（68.5%）、stable 7/108；确认 parameter_switch stage1 唯一 tie 标签 `tie:first_then_lost+never_first`（9 vs 9），tie 规则双方实现一致。

### 3. 四个完整性门槛数值（六 run 合计 1944 个单元）

- recomputed_first_day_mismatches = 0（被审 0）
- recomputed_first_stable_day_mismatches = 0（被审 0）
- stable_category_vs_frozen_flag_mismatches = 0（被审 0）
- partition_violations = 0（被审 0）

### 4. 行数核对

- 试验级 CSV：单场景 4 份各 108 数据行、联合 2 份各 324 数据行，共 972 行——逐行全量比对（含 final_cumulative_rank 直接对 evidence.npz 第 10 日 rank 复核、is_switching_stage 逻辑复核），0 不符
- daily_rank_summary.csv：180 数据行，rank_one_fraction 与 median_cumulative_rank 全量比对 0 不符
- stage 汇总 18 行、一致性 6 行，数目与内容均符

### 5. 哈希核对

- 输出目录 checksums.json：17 个文件 = 磁盘上除自身外全部文件，17/17 哈希相符
- 六个冻结输入目录：各 30 个文件（含 source_snapshot 子树），`\\?\` 扩展长度路径枚举，两个联合场景目录确含 263/264 字符超长路径文件，180 个文件哈希与各自 checksums.json 全部一致
- 配置快照中 6 个输入 config 的 SHA-256 与记录值全部相符

## 推断

- 被审分析的分位数实现与 numpy 默认线性插值一致（含 5.25、5.75、3.75、6.5 等非整数分位精确吻合），潜在方法歧义未造成实际分歧。
- 冻结数组内部自洽（first/first_stable/stable 与 ranks 完全可互推），上游生成时这些派生量出自同一 ranks。

## 未知 / 边界

- 本复算只核了所列输出与冻结规则的执行正确性；未审查 evidence.npz 上游实验（似然计算、滤波器实现）本身的科学正确性——不在本轮范围。
- 散文类输出（报告、environment 等）哈希已核但未逐句审读；数值结论以 CSV/JSON 为准。

## 不一致明细

无。
