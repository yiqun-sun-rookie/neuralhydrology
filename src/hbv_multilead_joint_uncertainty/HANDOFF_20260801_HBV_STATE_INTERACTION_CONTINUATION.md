# HBV 状态交互与单状态预报公平对照：上下文重置交接

本文件是当前任务的权威续接入口。它取代对话中的临时说法，但不修改或覆盖任何封存实验。旧文件如与本文件冲突，以本文件和对应的独立核验结果为准。

## 1. 最终目标与当前阶段

整体目标是判断：在参数不确定的合成试验中，完全交互的交互式多模型方法，是否能通过改善每日更新后的唯一全局后验状态，提高未来一日至七日流量预报。

当前只研究 HBV 降雨—径流模型（当前合成机制实验使用的概念性水文模型）。这不是 Wageningen Lowland Runoff Simulator（瓦赫宁根低地径流模拟模型，主仓库中的五状态低地水文模型）证据，也不是真实流域证据。

当前阶段目标是完成一个单因素预报实验：两种同化方法使用相同的三个固定参数模型、相同过程噪声、观测、气象强迫、初始条件和概率更新；唯一变化是观测更新前是否进行状态和协方差交互。两种方法每天都从各自唯一的、按模型后验概率合成的全局后验状态起报，并使用同一套固定中心率定参数发出一条确定性轨迹。

该预报实验尚未实现、尚未运行，因此现在不能判断完全交互与不交互谁的未来流量预报更好。

## 2. 真正的全阶段逐日滚动预报设计

三阶段合成真值只在第 180 天和第 360 天切换参数；两个切换点之间参数保持不变，并非每天切换参数。

正确评价过程如下：

1. 每个有效日完成截至当天的同化，得到当天唯一的全局后验状态。
2. 每天都从该状态重新发出未来一日至七日预报。
3. 对每个预见期分别汇总全部有效起报日，例如把所有“一日预报”与对应的一日后真值比较。
4. 主评价只保留目标日仍处于起报日同一真实参数阶段的样本；跨越下一次真实参数切换的样本不能混入主指标。
5. 配对统计以八个独立输入与噪声区块为重采样单位，不能把同一区块内每天的起报结果当作相互独立样本。
6. 主结果报告第一日至第七日全部七个预见期，不只报告第一、第三和第七日，也不按“距离参数切换多少天”作为主分组。

2026 年 7 月 28 日的实验只覆盖两次参数切换后各七个起报日，共 14 个起报日；它只能说明局部窗口，不能代表上述全阶段问题已经解决。后来完成的 540 个逐日起报点实验补齐了全阶段时间对齐，但没有隔离“状态交互”这一个因素；当前的新实验正是补这个因果缺口。

## 3. 必须遵守的比较合同、成功标准和停止条件

### 比较合同

- 标准完全交互方法内部保留三个模型条件状态，但每天最终状态是一个按模型后验概率合成的全局后验状态和协方差；这才是主要状态估计和单状态预报起点。
- 不交互对照也必须在每天更新后合成一个全局后验状态。它是“不进行状态与协方差交互的多滤波器对照”，不是标准完全交互方法。
- 三个候选参数向量固定。每天变化的是模型后验概率及由它产生的参数汇总，不得写成“真实参数每天切换”。
- 三个候选参数标识为 `equifinal_diverse_1`、`trained_center` 和 `equifinal_diverse_2`。三个真实参数场景的阶段顺序依次是：
  1. `trained_center -> equifinal_diverse_2 -> equifinal_diverse_1`；
  2. `equifinal_diverse_2 -> equifinal_diverse_1 -> trained_center`；
  3. `equifinal_diverse_1 -> trained_center -> equifinal_diverse_2`。
- 八个区块是八组相互独立的输入与噪声重复，不是八种参数场景。
- 两种方法的预报参数都固定为 `trained_center`，不得让各自参数读出不同。
- 每种方法从一个 15 维状态直接推进一条确定性水文轨迹；不得传播协方差、采样点或模型条件候选轨迹，不得在起报后使用未来流量观测。
- 覆盖八个匹配区块、三个真实参数场景、全部有效逐日起报点和第一日至第七日。
- 15 维完整计算状态包括五个水文蓄水状态和十个内部汇流记忆状态。主状态图只画五个水文状态；完整起报状态核查仍必须包含十个汇流记忆状态。
- 五个水文状态是积雪 `SNOWPACK`、融雪水 `MELTWATER`、土壤水 `SM`、上层地下水 `SUZ` 和下层地下水 `SLZ`。十个内部汇流记忆状态是 `qraw_t_minus_0` 至 `qraw_t_minus_9`，表示当前及前九个时步的原始汇流记忆，不是十个额外水文蓄水库。

### 成功标准

每个预见期只有同时满足以下两项，才能写“完全交互改善该预见期预报”：

1. 完全交互相对不交互的均方根误差降低至少 `1%`；
2. 以“完全交互均方误差减去不交互均方误差”定义的配对差值，其 `95%` 区间上界小于 `0`。

配对区间使用 `20,000` 次按八个匹配区块重采样，随机种子为 `20260801`。独立复算的所有数值最大绝对差必须不超过 `1e-10`。

### 停止条件

- 已封存状态证据或理想真值证据的散列值不匹配：立即停止，不运行正式实验。
- 预定结果目录已经存在：立即停止，不覆盖、不删除、不续写。
- 单元测试、回归测试、数组形状、时间对齐、同阶段掩码或独立核验失败：停止，不给科学结论。
- 资源不足时不得缩减八个区块、三个场景、逐日起报点或七个预见期；应停止并报告，不得静默改变实验。
- 两个工作树都有大量用户改动：不得清理、还原、暂存、提交、删除或覆盖无关文件。

## 4. 已完成的有效实验和明确结论

### 4.1 状态交互单因素实验：已完成且可复现

实验标识：`g3_fixed_process_state_interaction_global_posterior_audit_v01`

总体为八个独立输入与噪声区块、三个真实参数场景、每个场景 540 个同化日、15 个完整计算状态。两种方法只改变观测更新前是否进行状态与协方差交互；没有执行预报。

- 15 状态等权标准化均方根误差：完全交互 `0.3726007334930354`，不交互 `0.38696080683601114`，点估计降低 `3.710989094836503%`；配对标准化均方误差差值区间为 `[-0.04015712110346715, 0.01631567708365685]`。区间跨过零，整体优劣无法确定。
- 五个水文蓄水状态的组误差：完全交互 `0.6329731983173407`，不交互 `0.6563965204656173`，点估计降低 `3.568471406835183%`；区间为 `[-0.11751653494743936, 0.051339908543345185]`。整体优劣无法确定。
- 十个汇流记忆状态的组误差：完全交互 `0.0889911512751698`，不交互 `0.09581128848460552`，降低 `7.118302360093553%`；区间为 `[-0.0017904854846486319, -0.0007328333563510099]`。完全交互改善该组状态。
- 下层地下水储量：完全交互误差 `101.11709217001341`，不交互 `159.65363109887386`，降低 `36.66470879864213%`，区间完全小于零。
- 融雪水储量：完全交互误差 `2.6249072099171906`，不交互 `2.060209275079115`，增加 `27.409736557777144%`，区间完全大于零。
- 积雪、土壤水、上层地下水储量的区间均跨过零，现有证据不能判断优劣。
- 十个汇流记忆状态分别改善 `6.511731%` 至 `8.183365%`，每个状态的区间都小于零。

准确表述只能是：不同状态的误差变化方向不同；部分状态改善，部分状态变差，其余状态证据不足。不得使用“误差重新分配”“误差冲击分配”等暗示误差守恒或转移的说法。

独立核验状态为 `passed`；所有保存数组和汇总值的最大绝对差为 `0.0`，全局后验状态和协方差重建最大绝对差均为 `0.0`。复现状态为“可复现”。

### 4.2 固定预报参数的完整方法比较：已完成，但不能归因于状态交互

实验标识：`g3_fixed_process_parameter_candidate_controlled_forecast_v01`

它比较一个固定参数滤波器与一个包含三个固定参数模型的完全交互方法。两边使用相同 `process_2` 过程噪声、相同固定 `trained_center` 预报参数、各自一个 15 维起报状态和一条确定性轨迹。由于候选模型数量和完整同化方法同时不同，这不是状态交互单因素实验。

第一日至第七日均方根误差：

| 预见期 | 一个固定参数滤波器 | 完全交互三模型全局后验 | 完全交互相对变化 |
|---|---:|---:|---:|
| 1 日 | 2.5635 | 5.6037 | +118.595% |
| 2 日 | 4.1603 | 8.0587 | +93.705% |
| 3 日 | 4.9067 | 7.9600 | +62.229% |
| 4 日 | 5.3334 | 7.9011 | +48.144% |
| 5 日 | 5.6145 | 7.8587 | +39.970% |
| 6 日 | 5.8168 | 7.8151 | +34.354% |
| 7 日 | 5.9893 | 7.7786 | +29.875% |

七个配对均方误差差值区间都高于零。事实是：在这套固定读出合同下，完全交互三模型方法没有追上单个固定参数滤波器。不能据此写成“不交互更好”，也不能把差异单独归因于状态交互。

### 4.3 其他会影响判断的已完成实验

- 2026 年 7 月 28 日局部实验只使用两次参数切换后各第 0 至第 6 天。第一、第三、第七日均方根误差分别为：完全交互 `2.8004/5.4109/6.1529`，不交互 `3.0834/6.0395/7.3007`。该实验采用多个候选分别起报再加权的集合形式，只能作为局部历史证据。
- 后续 540 个逐日起报点、第一日至第七日的全阶段核查表明：精确真实 15 维状态配合真实阶段参数时始终最好；参数不确定性更新状态不是完整状态或预报的稳定最优。真正的直接确定性单轨迹相对单滤波器完整协方差传播误差高 `2.51%` 至 `22.61%`。这些结果说明“直接单轨迹”本身并不会自动改善预报，但仍没有隔离状态交互。

## 5. 已确认问题、已排除问题和未知问题

### 已确认

- 先前把模型条件子滤波器状态当作交互式多模型方法的多个最终状态是概念错误。标准方法每天最终输出一个全局后验状态和协方差。
- 只比较五个水文状态不足以证明完整预报起点更准；十个内部汇流记忆状态也必须纳入完整状态核查。
- “一个固定参数滤波器对完全交互三模型”的实验混合了候选数量、概率更新和状态交互，不能回答状态交互的单独作用。
- 切换后七天的阳性结果只属于局部窗口，不能说明全阶段或一般预报问题已经解决。

### 已排除

- 完成的状态交互单因素实验不存在汇总复算偏差：独立核验最大绝对差为 `0.0`。
- 两个比较方法的全局后验状态与协方差合成没有保存或重建错误：重建最大绝对差为 `0.0`。
- PowerShell 启动时出现的空 `conda` 初始化报错是环境噪声；上述读取命令的实际退出状态和证据文件均正常。正式实验仍须按每条命令的退出状态判断成败。

### 当前未知

- 完全交互与不交互哪一种的一日至七日未来流量预报更好。
- 同日状态中下层地下水改善、融雪水变差以及汇流记忆改善的合成作用，最终会改善还是损害各预见期流量。
- HBV 合成机制结论能否适用于 Wageningen Lowland Runoff Simulator 或真实流域。

## 6. 准确路径和证据散列值

当前 HBV 隔离工作树：

`G:\wt\id23-readout`

原始全阶段逐日滚动预报纠正文档：

`G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\HANDOFF_20260728_DAILY_ROLLING_FORECAST_CORRECTION.md`

本交接文档：

`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\HANDOFF_20260801_HBV_STATE_INTERACTION_CONTINUATION.md`

已完成状态交互实验：

- 状态统计代码：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\state_interaction_global_posterior_audit.py`
- 正式运行代码：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\run_g3_fixed_process_state_interaction_global_posterior_audit.py`
- 独立核验代码：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\verify_g3_fixed_process_state_interaction_global_posterior_audit.py`
- 确定性单状态预报代码：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\deterministic_unique_state_forecast.py`
- 配置：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_fixed_process_state_interaction_global_posterior_audit_v01.json`
- 登记表：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_experiment_registry.csv`
- 结果目录：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01`
- 汇总：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\summary.json`
- 原始证据：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\evidence.npz`
- 独立核验：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\independent_verification.json`
- 核验标准输出日志：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\verification_stdout.log`
- 核验标准错误日志：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\verification_stderr.log`，当前大小为 `0` 字节
- 运行环境：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\environment.json`
- 结果文件清单与散列：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\checksums.json`
- 实验收口：`G:\wt\id23-readout\docs\plans\2026-08-01-id23-state-interaction-global-posterior-audit-closure.md`
- 设计：`G:\wt\id23-readout\docs\plans\2026-08-01-id23-state-interaction-global-posterior-audit-design.md`

状态交互实验文件散列值：

- `summary.json`: `b18abfe809839df4ffb870e54f00943a3d846c329e00f6ad474dfe50437de693`
- `evidence.npz`: `22f1b99ee0cf537e1aa7c9b414662c0b390510f2dc0d6b07bf538dd6dda33a04`
- `independent_verification.json`: `345663c14c5db53b09ca98150d562aeca877c91d8f741fd8e49d3158c84aecff`
- `config_snapshot.json`: `087bc87c00f6a8a25925c3aaa863420587df448e306222a982d11efbc34da1bf`
- 封存理想真值证据：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_ideal_gate_param_switch_v01\evidence.npz`，散列值 `77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67`

固定参数滤波器与完全交互三模型比较：

- 配置：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_fixed_process_parameter_candidate_controlled_forecast_v01.json`
- 结果目录：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_parameter_candidate_controlled_forecast_v01`
- 收口：`G:\wt\id23-readout\docs\plans\2026-08-01-id23-fixed-process-parameter-candidate-controlled-forecast-closure.md`

五个水文状态主图：

`G:\wt\id23-readout\artifacts\state_trajectory_review_20260801\five_hydrologic_state_trajectories_three_scenarios.png`

全阶段状态、参数和传播形式核查收口：

`G:\wt\id23-readout\docs\plans\2026-07-31-id23-deterministic-unique-state-attribution-closure.md`

当前待执行预报计划：

`G:\wt\id23-readout\docs\superpowers\plans\2026-08-01-id23-hbv-state-interaction-forecast-control.md`

计划中的实验标识：`g3_fixed_process_state_interaction_controlled_forecast_v01`

计划中的配置文件和结果目录截至 2026 年 8 月 1 日均不存在：

- `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_fixed_process_state_interaction_controlled_forecast_v01.json`
- `G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_controlled_forecast_v01`

主仓库为：

`G:\github\pycharm\projects\paper-imm-variable-params`

该主仓库当前实现的是 Wageningen Lowland Runoff Simulator 五状态模型；不能把当前 HBV 结果直接写成该模型的结果。

## 7. 未完成事项、阻塞和唯一下一步

未完成事项是实现并运行 `g3_fixed_process_state_interaction_controlled_forecast_v01`，随后用完全独立的代码复算轨迹、掩码、每个预见期指标、配对区间和判断标签。

当前没有已知外部阻塞。阻塞科学结论的唯一原因是该实验尚未实现、尚未运行。其复现状态为“未运行”。

最高优先级下一步不是重做切换后七天实验，也不是再次比较一个滤波器与三个模型，而是严格执行已经冻结的状态交互单因素预报计划。正式结果通过独立核验后，再判断完全交互是否在某些或全部预见期改善流量预报。

## 8. 新对话开始后首先检查的文件和命令

```powershell
Set-Location 'G:\wt\id23-readout'

Get-Content -LiteralPath 'G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\HANDOFF_20260801_HBV_STATE_INTERACTION_CONTINUATION.md' -Raw
Get-Content -LiteralPath 'G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\HANDOFF_20260728_DAILY_ROLLING_FORECAST_CORRECTION.md' -Raw
Get-Content -LiteralPath 'G:\wt\id23-readout\docs\superpowers\plans\2026-08-01-id23-hbv-state-interaction-forecast-control.md' -Raw
Get-Content -LiteralPath 'G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\summary.json' -Raw
Get-Content -LiteralPath 'G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\independent_verification.json' -Raw

Get-FileHash -Algorithm SHA256 'G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\summary.json'
Get-FileHash -Algorithm SHA256 'G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\evidence.npz'
Get-FileHash -Algorithm SHA256 'G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01\independent_verification.json'

Test-Path 'G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_fixed_process_state_interaction_controlled_forecast_v01.json'
Test-Path 'G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_controlled_forecast_v01'
git status --short

python -m pytest test/test_hbv_state_interaction_global_posterior_audit.py test/test_hbv_state_interaction_global_posterior_audit_runner.py test/test_hbv_state_interaction_global_posterior_audit_verifier.py test/test_hbv_deterministic_unique_state_forecast.py -q
```

预期：三个散列值分别与第 6 节一致；两个 `Test-Path` 都返回 `False`；基线测试通过。若不符合，停止正式实验并先解释差异。

## 9. 可直接粘贴到新对话的下一轮任务提示词

```text
对话名称：HBV 状态交互的单状态预报公平对照

请先完整读取以下三个文件：
1. G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\HANDOFF_20260801_HBV_STATE_INTERACTION_CONTINUATION.md
2. G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\HANDOFF_20260728_DAILY_ROLLING_FORECAST_CORRECTION.md
3. G:\wt\id23-readout\docs\superpowers\plans\2026-08-01-id23-hbv-state-interaction-forecast-control.md

先简明复述真正的全阶段逐日滚动预报设计和当前证据边界：不能把参数切换后七天的局部结果说成一般问题已经解决，不能把 HBV 合成结果说成 Wageningen Lowland Runoff Simulator 或真实流域结果。

然后按计划实现并执行 g3_fixed_process_state_interaction_controlled_forecast_v01。唯一变化因素必须是同化前是否进行状态和协方差交互；两种方法必须使用各自唯一的全局后验状态、相同固定 trained_center 参数、相同强迫和目标，直接发出一条不传播协方差或候选轨迹的确定性预报。覆盖八个匹配区块、三个场景、所有有效逐日起报点和第一日至第七日；主指标排除跨真实参数阶段的目标，不按距切换多少天分组。

开始前核对封存散列值、目标配置和结果目录不存在、工作树改动；不得清理、还原、暂存、提交、删除或覆盖用户文件。测试或独立核验失败就停止，不给科学结论。完成后先给明确结论，再给每个预见期的两种均方根误差、相对变化、配对均方误差差值区间、判断和完整证据路径。不得使用“误差重新分配”或“误差冲击分配”等含糊说法。
```
