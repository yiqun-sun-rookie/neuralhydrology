# 复算报告：十五状态候选观测似然分解诊断（candidate_likelihood_decomposition_v01）

（独立复算上下文原文存档，2026-07-21。计算严格先于查看被审输出。）

## 总结论

复算一致。在未接触被审输出的前提下，仅从六个冻结 `evidence.npz` 独立复算了全部科学数值；随后与被审输出逐项对比：18 个阶段行的全部统计量与标签、6 行开发—确认一致性结论、三项恒等式、全部行数、7 个目录的散列，全部相符。唯一的差异是 1–2 ulp（≤5.7e-14）量级的浮点求和次序/序列化噪声，无科学意义。未发现任何实质不一致。

## (1) 独立算出的 6 行一致性结论（与被审 CSV/summary.json 逐字一致）

| 场景 | 阶段 | 开发标签 | 确认标签 | 结论 |
|---|---|---|---|---|
| parameter_switch | 2 | median_decomposition_inconsistent | innovation_penalty_dominant | 目前无法确定主要来源 |
| parameter_switch | 3 | variance_penalty_dominant | variance_penalty_dominant | variance |
| process_noise_switch | 2 | variance_penalty_dominant | variance_penalty_dominant | variance |
| process_noise_switch | 3 | no_median_advantage | no_median_advantage | 目前无法确定主要来源 |
| parameter_process_noise_switch | 2 | innovation_penalty_dominant | innovation_penalty_dominant | innovation |
| parameter_process_noise_switch | 3 | variance_penalty_dominant_both_negative | innovation_penalty_dominant | 目前无法确定主要来源 |

summary.json 的中文结论以 ASCII `\uXXXX` 转义存储，UTF-8 解码后与"目前无法确定主要来源"逐字相等（终端首次显示乱码是控制台渲染问题，非文件问题）。

## (2) 18 个阶段行对比（`stage_component_summary.csv`）

- 全部数值列（median/mean 的 ΔA、ΔB、Δtotal，ΔA<0、ΔB<0 比例）：最大绝对差 2.64e-15。
- 标签：18/18 逐字一致（含 1 个 `median_decomposition_inconsistent`、1 个 `variance_penalty_dominant_both_negative` 边缘标签）。
- 并列计数：所有 6 个运行、全部试验中最佳错误候选无任何并列；被审 `total_best_wrong_tie_count`=0 与复算（每试验唯一 argmax）一致。约定差异：被审按"额外并列数"（无并列记 0），复算按"并列候选总数"（无并列记 1），实质相同。
- 表内额外列（`mean_label`、`robust`、`blocks_with_negative_median_delta_*`）按推断定义复算，18 行全部吻合。

## (3) 恒等式三项误差（独立值）

| 运行 | max\|A+B−逐日似然\| | max\|cumA+cumB−冻结累计\| | max\|Δtotal−冻结末日 margin\| |
|---|---|---|---|
| param dev v05 | 1.78e-15 | 1.07e-14 | 1.24e-14 |
| procnoise dev v05 | 7.11e-15 | 2.84e-14 | 2.13e-14 |
| joint dev v05 | 2.13e-14 | 1.14e-13 | 1.07e-14 |
| param conf v01 | 3.55e-15 | 7.11e-15 | 8.88e-15 |
| procnoise conf v01 | 3.55e-15 | 1.42e-14 | 7.11e-15 |
| joint conf v01 | 7.11e-15 | 4.26e-14 | 1.07e-14 |

与被审 `integrity_checks.json` 对比：逐日项 6/6 精确相等；累计项 5/6 精确相等、margin 项 2/6 精确相等，其余差异均在 2 倍以内、绝对值 ≤2.5e-14——这是校验计算本身的求和次序差（cumsum vs 累加循环），不是数据差；被审 `all_passed: true` 成立。

## (4) 行数与散列核对

- 逐日表：三候选 4 份各 4860 行（12 区块×3 试验×45 天×3 候选）、联合 2 份各 43740 行（12×9×45×9）——全部精确符合。对全部 97,200 行做了逐值核验（比要求的抽查更强）：innovation/S/A/B/冻结逐日似然最大差 ≤7.1e-15；scoring 日标记、scoring 序号、stage 号、is_true_candidate 全对；累计列恰好只出现在评分日。
- 试验表：三候选 4 份各 108 行、联合 2 份各 324 行——精确符合；全表对比 ΔA/ΔB/Δtotal/冻结 margin 最大差 ≤7.1e-15，真值/最佳错误候选 ID 全一致。
- 散列：输出目录 23 个文件，`checksums.json` 覆盖除自身外全部 22 个，sha256 全部相符，无未覆盖文件、无悬空键。六个冻结输入目录各 31 个文件，各自 checksums.json 覆盖除自身外全部 30 个（含 `source_snapshot/` 子目录），sha256 全部相符；枚举使用 `\\?\` 扩展长度路径，联合场景目录的超长路径文件已包含。

## (5) 不一致明细

实质不一致：无。三条非实质观察（事实 + 推断分开）：

1. 事实：逐日表的 `frozen_stage_cumulative_log_likelihood` 有 559/3240（procnoise dev 评分行）与 npz `cumulative_log_likelihoods` 存在非零差，最大 5.68e-14，出现在值 −209.911 处 = 恰好 2 ulp。推断：被审写表时该列按日累加重算而非直接拷贝冻结数组（其与 CSV 内冻结逐日值的 cumsum 吻合到 4.3e-14），属求和次序噪声。
2. 事实：两个确认运行的 `margin_absolute_error` 列与"由 CSV 自身两列重算的差的绝对值"相差 1.78e-15。推断：二进制内计算后十进制序列化再重算的 1 ulp 效应。
3. 事实：`integrity_checks.json` 的 margin/累计误差与独立值有 4 处不精确相等（量级相同，均 ≤2.5e-14）。推断：同为校验器内部求和次序差。未知：被审管线的具体累加实现（未读其源码，也无需读——数值对比已闭合）。

自评（复核自身弱点后维持结论）：① 计算严格先于查看被审输出，标签规则、评分窗（每阶段去前 5 天取第 6–15 天）、真值索引取首个评分日均按冻结规则实现，且以三项恒等式对冻结数组自洽闭合，不依赖被审实现；② 并列计数与 `robust`/`mean_label` 等列的定义是推断的，但因全部 6 运行零并列、且 18 行全吻合，该推断即使有偏也不影响任何科学结论；③ ulp 级差异均给出了机制解释并验证（cumsum 复现），不存在被"机器精度"话术掩盖的系统性偏差。

复算脚本与中间结果保存在会话临时目录 `scratchpad\recompute\`（compute_independent.py、compare_audited.py、compare_daily_checksums.py、final_checks.py）。仓库内文件全程只读，未做任何修改。
