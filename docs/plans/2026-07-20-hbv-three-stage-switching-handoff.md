# 十五状态三阶段参数与过程噪声切换实验任务交接摘要

更新时间：2026-07-20

## 1. 整体最终目标和当前阶段

整体最终目标：在不修改冻结真实流域结果的前提下，为十五状态水文轻量级降雨径流模型建立可复现的封闭真值实验，分别检验完整十三参数向量切换、过程噪声切换、参数与过程噪声联合切换时，交互式多模型滤波能否把权重转移到当前正确候选，并检验一日、三日和七日无观测预报。

当前阶段结论：上述封闭真值验证已经完成。代码、三类第二版正式实验、独立方法审查、独立原始数组复算和综合结论均已保存。三个方法都没有通过预先登记的科学标准。因此目前不能声称模型找到了正确滤波器，也不能声称联合方法已证明改善预报。

下一阶段尚未开始。若继续研究，最优先问题不是直接调参，而是用新的开发区块检验：当前真值候选产生的观测似然是否在每次切换后的评分期内稳定高于错误候选。只有先区分“观测本身不可辨识”和“权重转移机制没有利用已有信息”，才值得调整权重保持概率、阶段长度或交互方式。

## 2. 必须遵守的限制、成功标准和停止条件

### 工作区和证据限制

- 权威代码仓库：`G:\github\pycharm\projects\neuralhydrology`。
- 当前分支：`migration/reorg-v1`；当前提交：`ffbde6d9091df08363ff5b7ab0492bdd02873c42`。
- 工作树有大量与本任务无关的用户修改和未跟踪文件。不得执行清理、重置、强制检出或覆盖操作；不得暂存或提交无关文件。
- 本任务新增的主要源代码、配置、设计文档和测试当前仍是未跟踪文件。尚未创建提交。
- 不得修改任何冻结真实流域结果、既有正式结果或第一版、第二版实验目录。新实验必须使用新实验名称和新输出目录。
- 第二版三个正式实验是唯一科学结论来源。第一版数值相同，但证据链不合格，只能保留为工程记录，不能增加样本量或支持结论。
- 不得在第二版使用的八个正式区块上反复选择设置后，再把同一批区块的结果称为确认性证据。新优化必须使用新的开发区块选择设置，再使用独立确认区块验证。
- 过程噪声候选只在物理状态投影前与真值严格对应；不得把投影后的扰动分布称为精确加性高斯候选。
- 计算不使用统一内存门槛。执行前按实际数组规模或代表性试运行估计峰值，确认当前可用内存保留任务相关安全余量；否则降低并行数量或任务规模。本实验正式运行采用单进程串行。

### 回答和判断规则

- 保持独立判断；用户倾向只能作为待验证信息。
- 使用完整、通俗名称；必须使用内部文件名时，先说明对象。
- 先给结论，再给事实、推断和未知。
- 所有结论必须有具体数值或可复算方法；证据不足时写“目前无法确定”。
- 每轮只处理一个关键且可独立检验的问题；正式结论需要独立方法审查，再由另一个独立上下文从原始证据复算。

### 已冻结的科学成功标准

每个十五日阶段排除前五日后评分。

- 完整参数向量单独切换、过程噪声单独切换：每个阶段的正确候选最大权重比例至少为 `0.6666666666666666`，且真实候选权重中位数至少为 `0.2`。
- 参数与过程噪声联合切换：每个阶段的正确联合候选最大权重比例至少为 `0.5`，参数边际正确比例至少为 `0.6666666666666666`，过程噪声边际正确比例至少为 `0.6666666666666666`，真实联合候选权重中位数至少为 `0.2`。
- 每个预报时效相对固定滤波器必须同时满足：全局均方根误差降低至少 `5%`，且以八个匹配区块为重采样单位、执行 `20000` 次重采样所得主要方法减对照方法的均方根误差差的 `95%` 区间上界小于 `0`。
- 联合方法还必须使其相对完整参数向量单独方法和过程噪声单独方法的区块误差差 `95%` 区间上界都小于 `0`。
- 三个阶段全部通过识别，且一日、三日、七日全部通过预报，才能将一个场景判为科学通过。
- 数值完整性、未来流量隔离和旧结果保护是运行有效性的必要条件，但不能代替科学成功标准。

### 停止条件

- 若资源估计没有安全余量，先缩小规模或并行度，不得强行启动。
- 若预先登记、配置散列、源码快照、保护路径或因果边界不合格，结果不得进入科学判断。
- 若新的诊断问题已经由独立方法审查和原始证据复算得出明确结论，应形成阶段结论；不得为了得到正结果继续在同一确认数据上试设置。
- 当前封闭真值验证目标已经完成，没有执行阻塞。

## 3. 已完成方案、关键结果和结论

### 实验设计

- 十五个状态：五个水文状态加十个径流路由记忆状态。
- 三个完整十三参数向量候选，三个过程协方差候选，联合候选库为三乘三共九个候选。
- 八个匹配合成区块；每个区块预热四十五日。
- 三个连续同化阶段均为十五日；参数或过程噪声在第十六日和第三十一日切换。
- 一日、三日、七日预报分别对应第46、48、52日；未来七日保持第三阶段真值。
- 权重因子保持概率为 `0.98`；初始协方差比例为 `0.001`。
- 正确真值候选在三个场景的每个时刻都位于对应候选库中。
- 完整参数向量场景每区块三个真值试验；过程噪声场景每区块三个真值试验；联合场景每区块九个真值试验。

### 候选识别结果

| 场景 | 第一阶段 | 第二阶段 | 第三阶段 | 结论 |
|---|---:|---:|---:|---|
| 完整参数向量正确候选比例 | `114/240 = 47.50%` | `75/240 = 31.25%` | `127/240 = 52.92%` | 三阶段均未通过 |
| 过程噪声正确候选比例 | `146/240 = 60.83%` | `143/240 = 59.58%` | `58/240 = 24.17%` | 三阶段均未通过 |
| 联合正确候选比例 | `208/720 = 28.89%` | `173/720 = 24.03%` | `61/720 = 8.47%` | 三阶段均未通过 |
| 联合参数边际正确比例 | `318/720 = 44.17%` | `263/720 = 36.53%` | `315/720 = 43.75%` | 三阶段均未通过 |
| 联合过程噪声边际正确比例 | `435/720 = 60.42%` | `387/720 = 53.75%` | `143/720 = 19.86%` | 三阶段均未通过 |
| 联合真实候选权重中位数 | `0.1621978880` | `0.1509946381` | `0.0922900071` | 三阶段均低于或未同时满足标准 |

完整参数向量场景的真实候选权重中位数为 `0.3579867424`、`0.3205011075`、`0.3948474766`；过程噪声场景为 `0.4871483646`、`0.4421123987`、`0.3021293253`。这些中位数超过 `0.2`，但正确候选比例不足，因此仍未通过。

### 一日、三日和七日预报结果

下表为主要方法相对固定滤波器的全局均方根误差改善，以及八个匹配区块误差差的 `95%` 重采样区间上界。

| 场景 | 一日：改善/上界 | 三日：改善/上界 | 七日：改善/上界 | 结论 |
|---|---:|---:|---:|---|
| 完整参数向量切换 | `6.2431% / 0.0667` | `-1.3323% / 0.0674` | `-4.7249% / 0.3260` | 三个时效均未通过 |
| 过程噪声切换 | `0.5473% / 0.0828` | `8.7751% / 0.1596` | `11.7366% / 0.1404` | 三个时效均未通过 |
| 联合切换 | `9.1239% / 0.0174` | `8.3626% / 0.0524` | `8.9558% / 0.1222` | 三个时效均未通过 |

联合方法相对完整参数向量单独方法的区间上界在一日、三日、七日分别为 `0.0560`、`0.0936`、`0.1152`；相对过程噪声单独方法分别为 `0.0244`、`0.0086`、`0.0807`。六个上界都大于零，因此没有一个时效证明联合方法具有新增价值。

### 数值和证据核验

- 最终相关测试：`56 passed, 1 warning`，用时 `73.79` 秒。警告是仓库既有的未知测试配置项 `collect_ignore_glob`，未影响测试通过。
- 三个第二版正式目录各有三十项文件校验值；最终核对均为零项不一致。
- 每个目录记录二百九十五项受保护文件；运行前、证据主体写入后和独立复核均为零项变化。
- 独立上下文重放全部八个区块、全部真值试验和全部五十二个活动日：最终十五状态最大误差不超过 `1.1368683772161603e-13`，流量最大误差不超过 `8.881784197001252e-15`。
- 过程扰动、观测、一日/三日/七日真值目标和绝对误差的重构误差为零。
- 同化概率和、预报概率和最大偏差不超过 `3.3306690738754696e-16`；候选预报混合值最大误差为 `1.7763568394002505e-15`。
- 将未来流量观测替换为 `1000000000000` 后，同化概率、预报起点状态和预报值的最大变化均为零；未来流量没有进入预报。
- 物理投影事件：完整参数向量场景 `1172/1248 = 93.91%`，过程噪声场景 `1248/1248 = 100%`，联合场景 `3468/3744 = 92.63%`。因此过程协方差只在投影前精确对应候选。

### 与论文参考实验的关系

- `paper-imm-variable-params` 项目的当前合成参考实验包含完整参数向量切换、过程噪声切换和联合切换，不是只有噪声。
- 参考实验按阶段得到的精确候选最大权重比例：完整参数向量 `1076/1215 = 88.56%`、`1035/1216 = 85.12%`；过程噪声 `330/1215 = 27.16%`、`634/1216 = 52.14%`；联合切换按代码报告切片为 `1197/1215 = 98.52%`、`1036/1216 = 85.20%`。参数和过程噪声边界有两个相差一小时的时刻，不能混为完全同步边界。
- 已发表的2023年五状态、3649小时、两个噪声候选实验与当前十五状态三乘三实验不同；不得把当前实验称为该已发表实验的直接复现。

## 4. 当前代码、配置、日志和结果文件的准确路径

### 核心代码和测试

- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\three_stage_switching_validation.py`
- `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\scripts\run_three_stage_switching_validation.py`
- `G:\github\pycharm\projects\neuralhydrology\test\test_hbv_three_stage_switching_validation.py`
- 独立真值代码：`G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\synthetic_truth.py`
- 预报代码：`G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\forecast.py`
- 候选和滤波器构建：`G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\methods.py`

以上本轮新增的两个核心文件和测试文件当前是未跟踪文件，不能依赖当前提交恢复。

### 权威第二版配置

- 完整参数向量切换：`G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\three_stage_parameter_switch_v02.json`
- 过程噪声切换：`G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\three_stage_process_noise_switch_v02.json`
- 联合切换：`G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\three_stage_parameter_process_noise_switch_v02.json`

三个第二版配置当前均为未跟踪文件。配置安全散列算法校验值依次为：

- 完整参数向量：`3f9612d53425bdd407dea177aa55fc31720f1deb0e0d2ec9a792397b97f16dc3`
- 过程噪声：`4c73cef5c958c5093cf8ceb81d4a6a3766e39d68bac044e367c67aee1dea78bf`
- 联合：`95cd27525a2bff3e29be35cea221f0db59f5cadcd8c48a5b0168313cd8323b72`

### 权威第二版正式结果

- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_parameter_switch_v02`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_process_noise_switch_v02`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_parameter_process_noise_switch_v02`

每个目录的主要文件：`evidence.npz`、`config_snapshot.json`、`preregistration.json`、`summary.json`、`scientific_evaluation.json`、`stage_identification.csv`、`method_metrics.csv`、`paired_comparisons.csv`、`integrity_checks.json`、`future_observation_counterfactual.json`、`protected_artifact_integrity.json`、`resource_preflight.json`、`source_snapshot`、`checksums.json`。

每个正式结果目录外还有同级、不可覆盖的运行前登记文件：

- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_parameter_switch_v02.preregistered.json`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_process_noise_switch_v02.preregistered.json`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_parameter_process_noise_switch_v02.preregistered.json`

### 综合结论和独立审查

- 最终综合结论：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\final_synthesis.md`
- 结论—证据矩阵：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\claim_evidence_matrix.csv`
- 独立方法与结果审查：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\independent_method_and_result_review.md`
- 独立原始证据复算：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\independent_raw_evidence_verification.md`
- 综合目录校验清单：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\checksums.json`

### 设计、资源和论文参考审查

- 设计说明：`G:\github\pycharm\projects\neuralhydrology\docs\plans\2026-07-20-hbv-three-stage-factor-switching-design.md`
- 实施说明：`G:\github\pycharm\projects\neuralhydrology\docs\plans\2026-07-20-hbv-three-stage-factor-switching.md`
- 资源试运行：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_resource_pilot_v01\resource_pilot_measurements.json`
- 论文合成参考实验审查：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\paper_synthetic_reference_audit_v01\reference_design_audit.md`
- 论文参考阶段计数：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\paper_synthetic_reference_audit_v01\exact_candidate_argmax_by_stage.csv`
- 冻结候选来源：`G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\formal_contract_sixteen_v05`

### 不得用于权威结论的第一版结果

- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_parameter_switch_v01`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_process_noise_switch_v01`
- `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_parameter_process_noise_switch_v01`

对应的第一版配置位于 `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\configs\three_stage_*_v01.json`。保留但不得引用为科学证据。

## 5. 已确认和已排除的问题

### 已确认

1. 三种受检方法在当前冻结设置下均未稳定识别当前真值候选。
2. 三种受检方法均未达到一日、三日和七日全部时效的预报有效性标准。
3. 联合方法没有在任何时效证明超过两个单因素方法。
4. 物理状态投影频繁发生，过程协方差候选只在投影前与真值严格对应。
5. 第一版证据链不合格：运行前登记实际在计算后写入、配置散列与保存快照不一致、源码快照漏掉三个被导入的辅助脚本、保护复核时点不可靠、资源试运行文件未验证校验值。
6. Windows 曾在第一版联合结果最终目录改名时出现一次短暂文件占用。证据文件完整且等待后同一操作成功。运行器现仅对 `PermissionError` 最多尝试五次、最多等待四秒；其他错误立即透传，已有自动测试。

### 已排除

1. 已排除真值候选不在候选库：三个场景所有时刻均在库。
2. 已排除参数切换与过程噪声切换未隔离：参数场景只改完整参数向量，过程噪声场景只改过程协方差，联合场景两者同步改变。
3. 已排除未来流量泄漏：未来流量改为 `1000000000000` 后权重、预报起点状态和预报值变化均为零。
4. 已排除保存真值、观测、权重、预报混合值或预报目标的数值重构错误；全量独立复算误差见上文。
5. 已排除第二版登记后写、配置散列漂移、源码快照缺失、输出与保护目录重叠、资源试运行未验证的问题。
6. 已排除第二版运行修改冻结旧结果：每个正式目录的二百九十五项保护文件均未变化。

### 目前无法确定

1. 识别失败主要由候选观测响应不可分、物理投影、十五日阶段过短、因子保持概率 `0.98` 过强、八个区块统计能力不足或这些因素共同造成。
2. 方法在真实流域、候选缺失、参数与过程噪声不同步切换、其他阶段长度、其他观测强度、气象误差或其他权重转移概率下的表现。
3. 当前联合方法失败是否可通过改变交互方式或权重转移先验修复。没有新的独立确认实验前不得下结论。

## 6. 未完成事项、阻塞原因和最优先下一步

当前验证目标已经完成，无阻塞事项。

若继续优化，最优先的新问题应定义为：**在不进行模型混合和权重转移调节前，当前真实候选的逐日或累计观测似然能否在切换后的十个评分日内稳定超过错误候选？**

建议边界：

- 使用新的合成开发区块，不读取或选择第二版八个正式区块上的设置。
- 参数、过程噪声、联合三个场景继续隔离；正确候选继续保持在库。
- 保存每个候选逐日观测对数似然、累计对数似然、真实候选排名和达到第一名所需天数。
- 若真实候选的观测似然本身不占优，停止调整权重保持概率，结论应指向候选可辨识性不足。
- 若真实候选似然占优但交互式多模型权重没有转移，再单独检验因子保持概率、交互方式或阶段长度。
- 所有设置选择只在开发区块进行；冻结后用新的独立确认区块验证，并重复独立方法审查和原始证据复算。

如果下一任务只是写论文而不是继续实验，直接以第二版负结果为依据，使用“当前条件下未达到预定标准”，不得写成“交互式多模型方法总体无效”。

## 7. 新对话首先检查的文件和命令

### 首先阅读

1. `G:\github\pycharm\projects\neuralhydrology\AGENTS.md`
2. `G:\github\pycharm\projects\neuralhydrology\docs\plans\2026-07-20-hbv-three-stage-switching-handoff.md`
3. `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\final_synthesis.md`
4. `G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\independent_raw_evidence_verification.md`
5. `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\three_stage_switching_validation.py`
6. `G:\github\pycharm\projects\neuralhydrology\src\hbv_multilead_joint_uncertainty\scripts\run_three_stage_switching_validation.py`

### 首先执行

```powershell
Set-Location 'G:\github\pycharm\projects\neuralhydrology'
git branch --show-current
git rev-parse HEAD
git status --short --untracked-files=all
python -m pytest -p no:cacheprovider test/test_hbv_three_stage_switching_validation.py test/test_hbv_joint_method_validation.py test/test_hbv_multilead_methods.py test/test_hbv_multilead_forecast.py test/test_hbv_synthetic_truth.py -q
```

预期测试结果：`56 passed, 1 warning`。若数量或结果变化，先解释差异，不得直接沿用本摘要的“代码当前有效”结论。

不得重新运行三个第二版正式实验名称；运行器会因同级运行前登记文件和既有结果目录存在而拒绝覆盖。任何新实验必须建立新配置、新实验名称和新结果目录。

## 可直接粘贴到新对话的下一轮任务提示词

```text
对话名称：十五状态切换滤波候选可辨识性诊断

请接续十五状态水文轻量级降雨径流模型的三阶段参数与过程噪声切换研究。首先完整阅读：
G:\github\pycharm\projects\neuralhydrology\AGENTS.md
G:\github\pycharm\projects\neuralhydrology\docs\plans\2026-07-20-hbv-three-stage-switching-handoff.md
G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\final_synthesis.md
G:\github\pycharm\projects\neuralhydrology\results\23_hbv_multilead_joint_uncertainty\three_stage_switching_validation_synthesis_v01\independent_raw_evidence_verification.md

第二版三个正式实验已经封存，结论是完整参数向量、过程噪声和联合方法均未达到预先登记的候选识别与一日、三日、七日预报标准。不得修改、覆盖或重新运行这些正式实验，也不得在其八个正式区块上反复选择设置。

本轮只解决一个关键问题：在不调整交互式多模型权重机制之前，当前真实候选的逐日或累计观测似然能否在切换后的十个评分日内稳定超过错误候选。先独立审查该问题的可行性、判定标准和数据边界；使用新的合成开发区块完成必要实现、测试和实验，并保存逐候选逐日观测对数似然、累计对数似然、真实候选排名和达到第一名所需天数。只有开发区块形成明确设置后，才使用新的独立确认区块验证。

保持独立判断；使用完整、通俗名称；区分事实、推断和未知；不使用固定内存门槛，执行前按实际任务估算或试运行并确认安全余量。工作树很脏，不得清理、重置、覆盖或提交无关文件。每轮完成后由一个独立上下文审查代码、方法和结果，再由另一个独立上下文从原始证据复算。自主推进，不等待逐轮确认；只有遇到必须由用户决定的阻塞，或形成完整阶段结论时才简洁报告。
```
