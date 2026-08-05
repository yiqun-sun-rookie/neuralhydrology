# HBV-lite 交互式多模型验证指南整理任务交接

日期：2026-08-05  
用途：粘贴到全新 Codex 对话后，无缝继续交互式多模型方法指南整理  
上下文判断：原对话已经混合实验执行、实验结案、三次文档审核、单滤波器指南修订和下一份指南拆分，继续沿用可能影响判断，应重置上下文。

## 一、整体目标与当前阶段

### 1. 项目整体目标

在 15 状态 HBV-lite 合成降雨—径流系统中，分别建立可审计证据，回答四个不能互相替代的问题：

1. 固定候选或真值切换后，候选后验概率能否辨认真实参数或过程噪声；
2. 标准交互式多模型方法的状态、协方差、候选概率和唯一全局后验计算是否正确；
3. 只开启同化前状态与协方差交互时，完整状态是否优于无交互多滤波器对照；
4. 从每日唯一全局后验状态起报时，未来流量预报是否改善。

候选辨认、切换响应、状态精度和预报价值必须分别验证，任何一层不能替代另一层。所有结论只适用于已登记的 HBV-lite 合成条件，不能外推到其他模型或真实流域。

### 2. 当前阶段目标及其作用

当前不启动新科学实验。当前阶段是把已完成实验的有效方法经验整理成相互独立、可复用的指南，为以后设计、审核和执行实验提供统一合同。

单滤波器验证指南已经形成当前版本；候选切换概率绘图与判断指南已经单独存在。当前唯一优先任务是：从现有 466 行的“交互式多模型验证与绘图指南”中，先拆出一份只讲方法验证、不讲绘图和预报的“交互式多模型方法验证指南”。

拟议新文件：

`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_VALIDATION.md`

2026-08-05 只读核对时该文件不存在。后续是否创建，须先让用户确认拆分结构。

## 二、当前阶段的范围

### 新验证指南应保留

- 单滤波器验证是前置条件；
- 候选库、候选标签、固定参数和噪声登记；
- 候选概率预测；
- 同化前状态与协方差交互；
- 各候选滤波器的预测、更新、创新、似然和条件后验；
- 候选后验概率更新及数值归一化；
- 候选概率加权的唯一全局后验状态和协方差；
- 完全交互与无交互多滤波器的公平对照；
- 完整传播状态的精度评价；
- 实现门槛、证据保存、只读复核、停止条件和允许的结论。

### 新验证指南不应包含

- 候选切换的连续主导规则、成功率、响应时间和概率曲线画法；这些属于现有候选切换指南；
- 状态轨迹、状态误差区间图和交互诊断图的具体画法；这些以后另立状态绘图指南；
- 第1日至第7日或其他提前期的预报验证与预报图；这些以后另立预报指南；
- 单滤波器状态更新合同的重复展开；只引用已完成的单滤波器指南；
- 新实验运行、参数调整、规则重定或结果重算。

## 三、必须遵守的限制、成功标准与停止条件

### 1. 文件与工作树保护

- 工作目录：`G:\wt\id23-readout`。
- 该工作树已有大量用户修改和未跟踪文件；不得清理、还原、暂存、提交、删除、移动、复制或覆盖用户文件。
- 现有混合指南、单滤波器指南、候选切换指南和封存结果均先保持不变。
- 新文件只能使用不存在的非覆盖式路径。
- 用户确认拆分结构前只读检查，不创建或修改指南。
- 2026-08-05 核对时暂存区为空；新对话必须重新检查，不能假定状态未变化。

### 2. 科学合同

- 交互式多模型方法每次更新结束后只对外发布一个候选后验概率加权的全局后验状态和协方差；候选条件状态是内部假设。
- 无交互多滤波器对照也必须形成一个概率加权的全局后验；它不是标准完全交互方法。
- 要隔离状态与协方差交互，两组必须保持候选库、初始状态和协方差、真值、输入、观测、噪声、概率递推、似然、全局后验合成、评分日和统计方法完全相同；唯一变化是是否进行同化前状态与协方差交互。
- 单滤波器与多候选方法的比较同时改变多个因素，只能称为总体方法比较，不能归因于交互。
- 完整状态证据必须覆盖 5 个水文储量和 10 个汇流记忆，共 15 个传播状态；状态子集不能代表完整状态。
- 候选概率响应不等于状态更准，状态更准不等于预报更准。
- 用户意见和目视判断属于待验证信息，不能替代封存数值证据；目视规则必须说明是否在看数值结果前冻结。

### 3. 文档成功标准

- 验证、候选切换判断、绘图和预报四类内容边界清楚，没有重复指南；
- 使用完整、通俗名称；首次出现可写“交互式多模型方法（并行运行多个固定候选滤波器并合成一个全局后验的方法）”，之后再使用简称；
- 每个判断都能落实为输入、计算、数值门槛、证据或停止条件；
- 区分实现失败、科学结果恶化和证据不足；
- 细致程度与 207 行的单滤波器验证指南相当，但行数不是硬门槛；不加入无助于执行的重复解释；
- 不改变任何已封存实验结论。

### 4. 停止条件

出现以下任一情况时停止，不写成最终指南：

- 无法判断某段内容属于方法验证、候选切换、绘图还是预报；
- 新指南与单滤波器指南或候选切换指南产生相互矛盾的合同；
- 需要改变既有科学结果、重新运行实验或覆盖现有文件才能继续；
- 文件散列、路径、封存结果或独立核验状态与本交接不一致；
- 用户尚未确认拆分结构。

## 四、已经完成的有效方案与关键实验结论

### 1. 无状态裁剪的参数切换正式确认：通过

实验：`g3_state_domain_consistent_parameter_switch_confirmation_v01`

- 三个候选共享决定状态合法范围的土壤最大持水量和融雪持水比例。
- 8 个匹配输入区组 × 3 条轮换真值 × 540 天，共 12,960 次真值状态转移。
- 真值状态裁剪事件 0；切换边界裁剪事件 0；最大裁剪调整 0.0。
- 候选1→候选2：16/16；95% 精确区间 `[0.794093, 1.000000]`。
- 候选2→候选3：16/16；95% 精确区间 `[0.794093, 1.000000]`。
- 候选3→候选1：16/16；95% 精确区间 `[0.794093, 1.000000]`。
- 冻结数值规则：切换后30天内，新真实候选后验概率严格大于0.5、比第二名至少高0.10，并连续满足5天；每方向至少13/16，且双侧95%精确区间下限严格大于0.5。
- 响应开始日中位数分别为0、0、0天；最晚分别为0、0、1天。
- 盲态目视48/48记为“清楚成功”，数值与目视零矛盾；第005幅由用户明确说明“有波动但最终接管，算成功”。其余47幅的盲态理由是“用户未报告例外”，不是逐图单独文字论证。
- 22/22 个目标测试通过；独立核验通过；13类关键数组最大重建差均为0.0。
- 仅测试1→2、2→3、3→1三个循环方向；反方向未测试。
- 气温恒定10摄氏度，全部降水为降雨；两个雪状态全程为0，当前条件实际活跃13个状态。
- 结论只涉及候选概率跟随，不涉及状态精度、预报、过程噪声或联合识别。

### 2. 无状态裁剪的过程噪声切换：两个方向通过，一个方向失败

实验：`g3_state_domain_consistent_process_noise_switch_v01`

- 固定水文参数，只切换下层地下水状态的过程噪声标准差1、4或16毫米每天；其余14个状态过程噪声方差为0。
- 12,960 次真值状态转移，状态裁剪事件0，最大裁剪调整0.0。
- 低到中：11/16，95%精确区间 `[0.413379, 0.889830]`，未通过。
- 中到高：16/16，95%精确区间 `[0.794093, 1.000000]`，通过。
- 高到低：16/16，95%精确区间 `[0.794093, 1.000000]`，通过。
- 43项正式运行前测试通过；独立核验通过，关键真值数组最大重建差0.0。
- 失败方向不能被总体平均或其他实验掩盖。

### 3. 状态与协方差交互对完整状态的优势：无法确定

实验：`g3_fixed_process_state_interaction_global_posterior_audit_v01`

- 两组使用相同三个固定参数候选、`process_2`过程噪声、真值、输入、观测、初值、概率递推、似然和全局后验合成；只改变同化前是否交互状态与协方差。
- 主总体：8个匹配区组、每区组3个真实参数试验、540个同化日、15个状态。
- 15状态等权标准化误差：完全交互0.372601，无交互0.386961，点估计改善3.711%；配对均方误差差值区间 `[-0.040157, 0.016316]` 跨0，总体证据不足。
- 10个汇流记忆组改善7.118%，区间 `[-0.001790, -0.000733]`。
- 下层地下水状态改善36.665%；融雪液态水状态恶化27.410%。
- 15个状态中11个改善、1个恶化、3个证据不足，但该计数不能替代完整状态综合判定。
- 71项相关测试通过；独立复算和全局后验重构最大绝对差均为0。

### 4. 状态与协方差交互对第1日至第7日预报的优势：无法确定

实验：`g3_fixed_process_state_interaction_controlled_forecast_v01`

- 第1日至第7日完全交互的均方根误差点估计均低1.214613%至1.667257%。
- 七个提前期的“完全交互均方误差减无交互均方误差”95%配对区间全部跨0，因此七个提前期均未达到预定改善标准。
- 独立核验通过；最大重建差 `1.4210854715202004e-14`，容差 `1e-10`。

### 5. 其他仍影响方法边界的事实

- 旧参数切换真值的48个切换边界中16个发生状态投影，因此旧结果只能作为事后响应描述，不能替代2026-08-04完成的无裁剪正式确认。
- 参数与过程噪声的唯一联合候选尚无无裁剪正式确认。
- 单滤波器与三个参数候选的总体方法比较中，15状态等权标准化误差改善45.028%，5个水文储量均改善，但10个汇流记忆全部变差，后续第1日至第7日确定性预报差29.88%至118.59%。该比较不能归因于状态交互。
- 低过程噪声到中等过程噪声失败的原因尚未确定。封存先导事实显示，失败方向30天窗内第二名87.5%的天数是旧低噪声候选；下一科学诊断应先检查低与中候选的观测预测似然，再检查概率递推与转移先验，一次只改一个因素。当前文档阶段不执行该诊断。

## 五、当前文件、代码、配置、日志与结果路径

以下均位于 `G:\wt\id23-readout`。

### 1. 当前指南与交接

- 当前单滤波器验证指南：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\GUIDE_HBV_SINGLE_FILTER_STATE_UPDATE_VALIDATION.md`
  - 207行；SHA-256 `9AFAE7773A8BC0B6F4BAFF9328BD18FC626F61A56E3476BF0FFDB1A2FDB8463E`。
- 候选切换概率绘图与判断指南：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\GUIDE_CANDIDATE_SWITCHING_PROBABILITY_PLOTTING_AND_JUDGMENT.md`
  - 305行；SHA-256 `82F3FF050B925CCF5A814F0DF7B0C9E90F8E69340A73787D78F338A03FF770C9`。
- 当前混合指南：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_VALIDATION_AND_PLOTTING.md`
  - 466行；SHA-256 `F11CCD867CB30248647B2545DE4D09D7CCC8853316EA70DF591FB47A99932408`。
- 本交接前的旧实验交接：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\HANDOFF_20260803_HBV_EXPERIMENT_NEXT_THREAD_CLEAN_PARAMETER_SWITCH.md`
  - 其中“参数切换待运行”已经失效，应以2026-08-04结案为准。
- 旧经验总表：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\HANDOFF_20260803_HBV_FILTER_VALIDATION_EXPERIENCE_SUMMARY.md`
  - 其中“无裁剪参数切换尚未确认”已经失效，应以2026-08-04结案为准。

### 2. 共享模型与交互式多模型实现

- HBV-lite 状态转移适配器：`G:\wt\id23-readout\src\hbv_joint_uncertainty\hbv_adapter.py`
- 修正无迹滤波器：`G:\wt\id23-readout\src\hbv_joint_uncertainty\sigma_filter.py`
- 交互式多模型核心：`G:\wt\id23-readout\src\hbv_joint_uncertainty\imm.py`
- 候选库和唯一全局后验封装：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\methods.py`
- 独立合成真值路径：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\synthetic_truth.py`
- 15状态和多提前期合同：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\contracts.py`

### 3. 无裁剪参数切换

- 结案：`G:\wt\id23-readout\docs\plans\2026-08-04-id23-state-domain-consistent-parameter-switch-confirmation-closure.md`
- 配置：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_state_domain_consistent_parameter_switch_confirmation_v01.json`
- 核心：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\state_domain_consistent_parameter_switch_confirmation.py`
- 运行器：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\run_g3_state_domain_consistent_parameter_switch_confirmation.py`
- 核验器：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\verify_g3_state_domain_consistent_parameter_switch_confirmation.py`
- 正式结果：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_state_domain_consistent_parameter_switch_confirmation_v01`
- 目视记录：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_state_domain_consistent_parameter_switch_confirmation_v01_visual_review_v01\visual_review.csv`
- 独立核验：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_state_domain_consistent_parameter_switch_confirmation_v01_independent_verification_v01\independent_verification.json`
- 冻结配置 SHA-256：`a7c974608a647f7eade14a7fa0ee443f6148950cf7175103b21d91c6bb344059`。
- `summary.json`中“尚未目视审查”是封存时的历史状态；当前权威状态是结案记录与独立核验通过。

### 4. 无裁剪过程噪声切换

- 结案：`G:\wt\id23-readout\docs\plans\2026-08-03-id23-state-domain-consistent-process-noise-switch-closure.md`
- 配置：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_state_domain_consistent_process_noise_switch_v01.json`
- 核心：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\state_domain_consistent_process_noise_switch.py`
- 运行器：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\run_g3_state_domain_consistent_process_noise_switch.py`
- 核验器：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\verify_g3_state_domain_consistent_process_noise_switch.py`
- 正式结果：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_state_domain_consistent_process_noise_switch_v01`
- 独立核验：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_state_domain_consistent_process_noise_switch_v01_independent_verification_v01\independent_verification.json`
- 首次长路径失败目录原样保留：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_state_domain_consistent_process_noise_switch_v01.incomplete.317807653afd4be6baf8fdc6cb241fb3`。

### 5. 状态交互与预报

- 状态结案：`G:\wt\id23-readout\docs\plans\2026-08-01-id23-state-interaction-global-posterior-audit-closure.md`
- 状态配置：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\configs\g3_fixed_process_state_interaction_global_posterior_audit_v01.json`
- 状态核心：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\state_interaction_global_posterior_audit.py`
- 状态运行器：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\run_g3_fixed_process_state_interaction_global_posterior_audit.py`
- 状态核验器：`G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\scripts\verify_g3_fixed_process_state_interaction_global_posterior_audit.py`
- 状态结果：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_global_posterior_audit_v01`
- 核验日志：上述结果目录中的 `verification_stdout.log` 和 `verification_stderr.log`。
- 预报结案：`G:\wt\id23-readout\docs\plans\2026-08-01-id23-hbv-state-interaction-controlled-forecast-closure.md`
- 预报结果：`G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty\g3_fixed_process_state_interaction_controlled_forecast_v01`

## 六、已确认问题、已排除问题及证据

### 已确认问题

1. 当前466行混合指南同时包含方法合同、候选切换、概率图、状态图和预报图，内容重复且边界不清。
2. 混合指南中的候选切换和概率绘图内容与305行候选切换指南大量重复。
3. 混合指南把预报验证和预报绘图并入交互式多模型验证，但状态证据不能替代预报证据。
4. 旧参数切换受状态投影污染；已由2026-08-04无裁剪正式确认替代。
5. 无裁剪过程噪声低到中方向确实未通过，不是绘图门槛造成的误判。
6. 当前单滤波器验证指南是在旧版本接受三次互不共享结论的只读审核后修订形成；审核发现的开环定义、时间顺序、单套量测误差结论边界、停止规则和证据链问题已写入当前版本。

### 已排除问题

1. 用户附件中的候选切换指南不是另一版本；附件与工作树文件逐字节一致，SHA-256同为 `82F3FF050B925CCF5A814F0DF7B0C9E90F8E69340A73787D78F338A03FF770C9`。
2. 参数切换正式确认不是旧状态投影造成的假响应；新实验12,960次真值转移和全部切换边界均为零裁剪。
3. 第005幅的波动不构成失败；用户在盲态审查中明确判断其最终由新真实候选接管，且数值规则通过。
4. 过程噪声切换的响应延迟不等于时间错位；真值重建和时间索引独立核验最大差为0.0。
5. 交互方法完整状态总体优势没有得到确认；3.711%只是点估计，区间跨0。

### 未验证

1. 当前SHA-256为 `9AFA...8463E` 的单滤波器最终指南，在吸收三次审核意见后只完成了结构化文本检查，没有再次进行三次独立审核。
2. “拆为交互式多模型验证指南、候选切换指南和以后单独的状态绘图指南”是当前最合理方案，但用户尚未明确确认该具体拆法。
3. 拟议新验证指南和拟议状态绘图指南均尚未创建。

## 七、未完成事项、阻塞与优先级

### 当前最高优先级

先让用户确认以下拆分：

1. 新建只讲方法验证的 `GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_VALIDATION.md`；
2. 保留现有 `GUIDE_CANDIDATE_SWITCHING_PROBABILITY_PLOTTING_AND_JUDGMENT.md`，不重复候选切换规则；
3. 状态绘图以后另立 `GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_STATE_PLOTTING.md`；
4. 预报验证和预报绘图暂不处理；
5. 旧466行混合指南暂不删除、不覆盖。

用户确认后，先只起草并审查交互式多模型方法验证指南，不同时创建绘图指南。

### 后续科学任务，不并入当前文档任务

- 诊断低过程噪声切到中等过程噪声11/16失败的原因；
- 完成无裁剪的参数与过程噪声唯一联合候选确认；
- 其他气候、雪活动条件和真实流域验证。

## 八、新对话开始后的首读文件与只读命令

### 必须完整读取，按顺序

1. `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\HANDOFF_20260805_HBV_IMM_GUIDE_REORGANIZATION.md`
2. `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\GUIDE_HBV_SINGLE_FILTER_STATE_UPDATE_VALIDATION.md`
3. `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\GUIDE_CANDIDATE_SWITCHING_PROBABILITY_PLOTTING_AND_JUDGMENT.md`
4. `G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_VALIDATION_AND_PLOTTING.md`
5. `G:\wt\id23-readout\docs\plans\2026-08-04-id23-state-domain-consistent-parameter-switch-confirmation-closure.md`
6. `G:\wt\id23-readout\docs\plans\2026-08-01-id23-state-interaction-global-posterior-audit-closure.md`

### 先执行的 PowerShell 只读命令

```powershell
Set-Location 'G:\wt\id23-readout'

git status --short --untracked-files=all
git diff --cached --name-only

Get-FileHash -Algorithm SHA256 -LiteralPath `
  'src\hbv_multilead_joint_uncertainty\GUIDE_HBV_SINGLE_FILTER_STATE_UPDATE_VALIDATION.md', `
  'src\hbv_multilead_joint_uncertainty\GUIDE_CANDIDATE_SWITCHING_PROBABILITY_PLOTTING_AND_JUDGMENT.md', `
  'src\hbv_multilead_joint_uncertainty\GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_VALIDATION_AND_PLOTTING.md', `
  'docs\plans\2026-08-04-id23-state-domain-consistent-parameter-switch-confirmation-closure.md'

Test-Path -LiteralPath `
  'src\hbv_multilead_joint_uncertainty\GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_VALIDATION.md'

Test-Path -LiteralPath `
  'src\hbv_multilead_joint_uncertainty\GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_STATE_PLOTTING.md'
```

预期基线：暂存区为空；两个拟议新指南均不存在；三个现有指南散列依次为 `9AFAE7773A8BC0B6F4BAFF9328BD18FC626F61A56E3476BF0FFDB1A2FDB8463E`、`82F3FF050B925CCF5A814F0DF7B0C9E90F8E69340A73787D78F338A03FF770C9`、`F11CCD867CB30248647B2545DE4D09D7CCC8853316EA70DF591FB47A99932408`。若不一致，先报告差异，不修改文件。

## 九、可直接粘贴到新对话的下一轮任务提示词

```text
对话名称：HBV交互式多模型验证指南拆分

本任务归属项目 paper-imm-variable-params。科学证据和文档位于隔离工作树 G:\wt\id23-readout；主仓库路径为 G:\github\pycharm\projects\paper-imm-variable-params。

开始时完整读取：
G:\wt\id23-readout\src\hbv_multilead_joint_uncertainty\HANDOFF_20260805_HBV_IMM_GUIDE_REORGANIZATION.md

然后按该交接“新对话开始后的首读文件与只读命令”逐一完整读取和执行。以2026-08-04参数切换结案、过程噪声切换结案、状态交互结案和独立核验为当前权威状态；不要把旧交接中的“参数切换待运行”或旧 summary.json 中的“尚未目视审查”当作当前状态。

当前阶段不运行科学实验。唯一任务是整理交互式多模型方法验证指南，把方法验证与候选切换判断、绘图和预报分开。

拟议拆分是：
1. 新建只讲方法验证的 GUIDE_HBV_INTERACTING_MULTIPLE_MODEL_VALIDATION.md；
2. 保留现有候选切换概率绘图与判断指南，不重复其切换响应和概率图规则；
3. 状态绘图以后另立指南；
4. 预报验证和预报绘图暂不处理；
5. 旧466行混合指南暂不删除、不覆盖。

首次回复只需：
- 复述整体目标和当前文档阶段在整体目标中的作用；
- 说明新验证指南准备保留和排除的内容；
- 核对工作树、散列和两个拟议目标文件是否存在；
- 判断上述拆分是否有遗漏或冲突；
- 等待我明确确认后再创建或修改文件。

保护要求：不得清理、还原、暂存、提交、删除、移动、复制或覆盖用户文件；不得修改封存结果；不得运行新实验。散列、路径或权威结案状态不一致时停止并报告，不自行修复。
```
