# 十五状态候选观测似然可辨识性诊断交接摘要

## 1. 最终目标与当前阶段

整体目标：研究十五状态水文轻量级降雨径流模型中，完整参数向量、过程噪声以及二者联合切换时，当前真实候选能否被识别，并据此判断是否值得调整交互式多模型权重机制。

已完成阶段：在完全绕开状态交互、候选权重预测和候选权重更新的条件下，完成候选逐日与累计观测对数似然诊断、开发区块、独立确认区块以及两层独立审查。

当前结论：在当前候选库、观测误差、十五日阶段、前五日适应和后十日评分条件下，真实候选不能在切换后的十个评分日内稳定超过错误候选。当前任务已经完成，不在运行中。

下一阶段尚未开始。最优先问题是先分解候选观测对数似然差，判断区分失败主要来自归一化平方创新项、预测方差对数项，还是两者共同作用；在完成该诊断前，不应直接调整交互式多模型权重机制。

## 2. 必须遵守的限制、标准和停止条件

- 仓库：`G:\github\pycharm\projects\neuralhydrology`
- 当前分支：`migration/reorg-v1`
- 当前提交：`ffbde6d9091df08363ff5b7ab0492bdd02873c42`
- 工作树很脏。不得清理、重置、覆盖、移动、提交或修改无关文件。
- 第二版三个正式实验、第五版开发实验、第一版确认实验及其预登记、配置快照和证据目录均为冻结证据；不得修改、覆盖、删除或重新运行。
- 不得使用第二版八个正式区块、第五版十二个开发区块或第一版十二个确认区块反复选择设置。
- 新的行为改动必须先有聚焦失败测试，再实现并保留通过证据。
- 新的实验必须使用新实验编号、新目录和全新随机种子；所有配置应在读取结果前同时冻结。
- 资源执行前按实际数组、并行度和输出规模估算，并检查物理内存与提交内存安全余量；不得使用统一固定内存门槛。
- 每轮先由一个独立上下文审查代码、方法和结果，再由另一个独立上下文从原始证据复算。
- 事实、推断和未知必须分开。证据不足时写“目前无法确定”。
- 若证据链、配置散列、种子隔离、长路径清单或保护文件清单存在会改变结论的缺口，立即停止并标记“暂缓”，不得继续科学解释。

本轮冻结判定标准：

1. 每个十五日阶段排除前五日，从第六日至第十五日评分并重新累计。
2. 并列按对真实候选不利处理。
3. 稳定可辨识要求最后五个评分日累计观测对数似然每天严格第一，且第十日累计似然严格超过最佳错误候选。
4. 阶段还须同时满足：稳定比例至少 `0.6666666666666666`；十二个合成区块、`20000` 次区块重采样的 95% 区间下界严格大于 `0.5`；第十日累计差中位数严格大于 `0`。
5. 第二和第三阶段必须都通过，场景才通过；第一阶段只报告。

## 3. 已完成方案、关键结果与结论

### 有效方案

- 每个候选使用独立的十五状态向量、协方差、状态转移函数和过程噪声协方差。
- 每日只调用单个修改型无迹卡尔曼滤波器的预测与观测更新；未调用交互式多模型整体步骤。
- 保存预测观测、创新、创新方差、逐候选逐日观测对数似然、阶段内累计对数似然、真实候选逐日和累计排名、首次第一日、首次第一且保持到末日所需天数、最后五日稳定标志。
- 第五版开发证据和第一版确认配置、结果通过两层独立审查。

### 第五版开发结果

| 场景 | 第二阶段稳定比例 | 第三阶段稳定比例 | 场景结论 |
|---|---:|---:|---|
| 完整参数向量 | 0.333333 | 0.416667 | 不通过 |
| 过程噪声 | 0.388889 | 0.277778 | 不通过 |
| 完整参数向量与过程噪声联合 | 0.129630 | 0.083333 | 不通过 |

### 第一版独立确认结果

| 场景与阶段 | 稳定数/总数 | 稳定比例 | 95% 区块重采样区间 | 第十日累计差中位数 | 判定 |
|---|---:|---:|---:|---:|---|
| 完整参数向量，第二阶段 | 8/36 | 0.222222 | [0.138889, 0.305556] | -0.162936 | 不通过 |
| 完整参数向量，第三阶段 | 13/36 | 0.361111 | [0.277778, 0.444444] | -0.017600 | 不通过 |
| 过程噪声，第二阶段 | 12/36 | 0.333333 | [0.194444, 0.472222] | -0.321648 | 不通过 |
| 过程噪声，第三阶段 | 13/36 | 0.361111 | [0.194444, 0.527778] | +0.152906 | 不通过 |
| 完整参数向量与过程噪声联合，第二阶段 | 7/108 | 0.064815 | [0.037037, 0.092593] | -0.562452 | 不通过 |
| 完整参数向量与过程噪声联合，第三阶段 | 12/108 | 0.111111 | [0.074074, 0.157407] | -0.311935 | 不通过 |

过程噪声第三阶段只有最终累计差中位数为正；稳定比例和重采样区间下界均失败，不能改变结论。

事实：当前观测似然本身没有提供足够稳定的候选区分信号。

推断：仅改变候选权重转移或权重更新规则，不能被当前证据视为足以解决候选识别失败。

未知：改变候选间距、阶段长度、观测误差、累计窗口、真实流域数据或滤波约束后是否可辨识，目前无法确定；当前证据也不能判断任何新权重机制的预报性能。

## 4. 当前代码、配置、日志和结果路径

### 首先阅读

- `G:\github\pycharm\projects\neuralhydrology\AGENTS.md`
- `G:\github\pycharm\projects\neuralhydrology\docs\plans\2026-07-21-hbv-candidate-likelihood-identifiability-handoff.md`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01\final_synthesis.md`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01\independent_method_and_result_review.md`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01\independent_raw_evidence_verification.md`

### 设计、实现和测试

- `G:\github\pycharm\projects\neuralhydrology\docs\plans\2026-07-20-hbv-candidate-likelihood-identifiability-design.md`
- `G:\github\pycharm\projects\neuralhydrology\docs\plans\2026-07-20-hbv-candidate-likelihood-identifiability.md`
- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability.py`
- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\scripts\run_candidate_likelihood_identifiability.py`
- `G:\github\pycharm\projects\neuralhydrology\test\test_hbv_candidate_likelihood_identifiability.py`
- 独立参考传播：`G:\github\pycharm\projects\neuralhydrology\src\scl_hydro\hbv_lite_numpy.py`

### 有效开发配置与结果

- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\candidate_likelihood_parameter_switch_development_v05.json`
  - 安全散列算法校验值：`56fea0145e12ee486d71fa456a0fdee7386d5b5de304b105fd234a02ccf6314c`
- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\candidate_likelihood_process_noise_switch_development_v05.json`
  - 校验值：`623b29635b84e31048e2188f71fe28a2ad68d0709690be92e515c9481eafe33b`
- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\candidate_likelihood_parameter_process_noise_switch_development_v05.json`
  - 校验值：`cf55e09a60a3d61e16f39f15a7782f1215d1f688186a4e0419801e94b36f9926`
- 结果目录：
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_parameter_switch_development_v05`
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_process_noise_switch_development_v05`
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_parameter_process_noise_switch_development_v05`
- 开发数据种子：气象 `993001–993012`，过程噪声 `994001–994012`，观测噪声 `995001–995012`。

### 有效确认配置与结果

- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\candidate_likelihood_parameter_switch_confirmation_v01.json`
  - 校验值：`b733e3c420803533e79bb1ce8c76cb17e1c3d9c4524104a6ace9881e666df758`
- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\candidate_likelihood_process_noise_switch_confirmation_v01.json`
  - 校验值：`17dadfa137d27efa7b02a7e3cc6cfec215e095218eba700179ab6b43a4c4a2c8`
- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\candidate_likelihood_parameter_process_noise_switch_confirmation_v01.json`
  - 校验值：`35f30842dbf87d8c0868ed9d384d0846cae2d61d6e80284a38fc9404baa294cd`
- 结果目录：
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_parameter_switch_confirmation_v01`
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_process_noise_switch_confirmation_v01`
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_parameter_process_noise_switch_confirmation_v01`
- 确认数据种子：气象 `996001–996012`，过程噪声 `997001–997012`，观测噪声 `998001–998012`。

### 既有第二版正式证据，禁止修改或重跑

- 配置：
  - `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\three_stage_parameter_switch_v02.json`
  - `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\three_stage_process_noise_switch_v02.json`
  - `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\three_stage_parameter_process_noise_switch_v02.json`
- 结果：
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_parameter_switch_v02`
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_process_noise_switch_v02`
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_parameter_process_noise_switch_v02`
- 综合证据：
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\final_synthesis.md`
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\independent_raw_evidence_verification.md`
- 正式数据种子：气象 `990001–990008`，过程噪声 `991001–991008`，观测噪声 `992001–992008`。

## 5. 已确认和已排除的问题

### 已确认

- 创新恒等式最大绝对误差为 `0`。
- 标量高斯逐日观测对数似然独立复算最大误差为 `7.105427357601002e-15`。
- 确认逐候选逐日表共 `53460` 行，试验阶段表共 `540` 行；分类字段不一致数为 `0`。
- 每个确认目录有 31 个文件，`checksums.json` 覆盖除自身外的 30 项；缺失、多余和校验值不符均为 `0`。
- 每份确认配置的 59 个保护路径使用 Windows 扩展长度路径展开为 738 个文件；运行前、写入后和当前集合及校验值全部一致。
- 确认、第五版开发和第二版正式的三类数据种子交集均为 `0`。
- 最后一次完整相关测试命令结果为 `71 passed, 1 warning in 160.95s`。唯一警告是仓库既有的未知测试配置项 `collect_ignore_glob`。

### 已排除

- 已排除“状态交互或候选权重机制导致本轮似然排名”的解释：诊断没有调用这些机制。
- 已排除逐日似然公式、阶段累计重置、并列排名、首次第一、稳定判据或表格导出错误：两层独立复算一致。
- 已排除开发、确认和第二版正式种子重叠。
- 已排除普通 Windows 长路径清单造成的当前证据漏项：第五版开发和第一版确认均使用扩展长度路径并独立复核。

### 保留但不得作为科学证据的失败版本

- 第一版参数开发运行因源码快照目标路径达到 Windows 普通路径限制而失败，保留：
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_parameter_switch_development_v01.incomplete`
  - `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_parameter_switch_development_v01.preregistered.json`
- 第二版开发目录的目录校验清单漏掉长路径源码快照文件，不能作为最终证据。
- 第三版开发目录的保护文件清单漏掉两个长路径文件，不能授权确认。
- 第四版开发的跨场景配置保护顺序不自洽，不能作为最终证据。
- 第一至第四版目录必须保留为工程记录，不得删除或据此选择设置；最终有效开发版本只有第五版。

### 轻微已知问题

资源预检对保存数值数组少计少量标量和索引：三候选场景各少计 `3312` 字节，约 `0.281%`；联合场景少计 `9792` 字节，约 `0.216%`。运行所需可用内存记录为 34.19–44.28 兆字节，执行前可用物理内存为 4.13–4.23 吉字节，因此不影响既有运行安全或结论。后续若修改运行器，应先新增失败测试，并在新版本中修正；不得改写已封存证据。

## 6. 未完成事项、阻塞和下一步

当前候选似然可辨识性任务没有未完成事项，也没有阻塞。

最优先的下一步尚未实施：对冻结的开发和确认原始数组做只读似然分解，逐候选逐日保存并比较以下两部分：

1. 预测方差惩罚：`-0.5 * log(2 * pi * innovation_variance)`。
2. 归一化平方创新惩罚：`-0.5 * innovation^2 / innovation_variance`。

目标是定量判断错误候选的累计似然优势主要来自哪一项，以及该方向在第五版开发与第一版确认中是否一致。该诊断不得修改或重跑冻结实验，不得事后选择阈值；若两部分贡献方向不稳定，应明确写“目前无法确定主要来源”。

候选滤波器因持续同化相同观测而是否过快收敛到相似状态，是后续另一轮问题，不应与首次似然分解混在同一轮。

## 7. 新对话首先检查的文件和命令

在 PowerShell 中执行：

```powershell
Set-Location -LiteralPath 'G:\github\pycharm\projects\neuralhydrology'
Get-Content -Raw -LiteralPath 'AGENTS.md'
Get-Content -Raw -LiteralPath 'docs\plans\2026-07-21-hbv-candidate-likelihood-identifiability-handoff.md'
Get-Content -Raw -LiteralPath 'results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01\final_synthesis.md'
Get-Content -Raw -LiteralPath 'results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01\independent_raw_evidence_verification.md'
git status --short
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
```

在修改任何代码前，重新核对冻结综合文件校验值：

```powershell
$synthesis = 'results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01'
$manifest = Get-Content -Raw -LiteralPath (Join-Path $synthesis 'checksums.json') | ConvertFrom-Json
foreach ($entry in $manifest.PSObject.Properties) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $synthesis $entry.Name)).Hash.ToLowerInvariant()
    [pscustomobject]@{ File = $entry.Name; Match = ($actual -ceq $entry.Value) }
}
```

仅在需要验证当前实现时运行，不得运行冻结实验：

```powershell
python -m pytest -p no:cacheprovider test/test_hbv_candidate_likelihood_identifiability.py test/test_hbv_three_stage_switching_validation.py test/test_hbv_joint_method_validation.py test/test_hbv_multilead_methods.py test/test_hbv_multilead_forecast.py test/test_hbv_synthetic_truth.py -q
```

## 可直接粘贴到新对话的下一轮任务提示词

```text
对话名称：十五状态候选观测似然分解诊断

请接续十五状态水文轻量级降雨径流模型候选观测似然可辨识性研究。首先完整阅读：

G:\github\pycharm\projects\neuralhydrology\AGENTS.md
G:\github\pycharm\projects\neuralhydrology\docs\plans\2026-07-21-hbv-candidate-likelihood-identifiability-handoff.md
G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01\final_synthesis.md
G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01\independent_method_and_result_review.md
G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\candidate_likelihood_identifiability_synthesis_v01\independent_raw_evidence_verification.md

当前已确认：在完全不使用状态交互、候选权重预测或权重更新时，完整参数向量、过程噪声和联合候选在切换后的十个评分日内均未达到稳定可辨识标准。第二版正式实验、第五版开发实验和第一版确认实验均已冻结，禁止修改、覆盖、删除或重新运行，也不得用这些区块反复选择设置。

本轮只解决一个问题：从冻结的第五版开发和第一版确认原始数组只读复算标量高斯观测对数似然的两个组成部分——预测方差惩罚 `-0.5 * log(2 * pi * innovation_variance)` 与归一化平方创新惩罚 `-0.5 * innovation^2 / innovation_variance`——逐候选逐日保存两项、阶段累计贡献、真实候选相对最佳错误候选的贡献差，并判断错误候选优势主要来自哪一项，以及开发与确认方向是否一致。不得调整交互式多模型权重机制，不得重跑冻结实验，不得事后选择阈值；方向不稳定时明确写“目前无法确定主要来源”。输出必须写入新的版本化分析目录。

工作树很脏，不得清理、重置、覆盖或提交无关文件。执行前按实际任务估算资源，不使用固定内存门槛。任何代码改动先写聚焦失败测试。完成后由一个独立上下文审查代码、方法和结果，再由另一个独立上下文从原始证据复算。自主推进；仅在遇到必须由用户决定的阻塞或形成完整阶段结论时简洁报告。
```
