# 旧候选库实验证据定位说明（防误读归档）

写于 2026-08-05，参数切换不裁剪状态实验结案（2026-08-04）之后。

## 目的

本计划的结果目录中并存两条证据线。旧线的预报价值负面结果容易被误读为当前线的结论；反过来，当前线的识别成功也容易被误读为预报价值证据。本文件是两条线的权威定位说明，供以后任何会话或读者引用。

按保护条件，任何封存目录均**不移动、不删除、不改写**；归档方式为本文字定位。中央登记表既有行未改动。

## 两条证据线的定义

**旧线（旧候选库线）：**
- 候选库：equifinal_diverse_1 / trained_center / equifinal_diverse_2；
- 三个候选的土壤最大持水量（parFC）互不相同（约 565.944 / 115.411 / 485.138），融雪持水比例（parCWH）也互不相同；
- 后果：真值参数切换会触发状态裁剪（48 个切换事件中 16 个发生切换瞬间投影），切换响应规则为事后定义；
- 随机样本：种子 330 开头的封存数据（旧理想参数切换 evidence.npz，SHA-256 前缀 77f84d79），以及全部"复用封存区组"的读出与自助重抽样；
- 包含：全部预报价值实验。

**当前线（共享状态域候选库线）：**
- 候选库：三个候选的 parFC 全部等于 115.41144086847932，parCWH 全部等于 4.790858379798471e-9，切换时十五维状态不需要任何裁剪；
- 随机样本：种子 350 开头（过程噪声切换）、360 开头（候选构造）、370 开头（参数切换正式确认），与旧线严格分开；
- 冻结配置明确禁止预报：预报模块未导入、预报未执行、未使用未来观测（独立核验逐项确认）；
- 包含：参数切换正式确认（已结案，通过）、过程噪声切换（已独立核验，2/3 方向通过）。

## 逐项定位

### 一、已被当前线取代的实验

| 实验 | 仍可引用为 | 不可引用为 |
|---|---|---|
| 旧理想参数切换（g3_ideal_gate_param_switch_v01） | 参数方向响应的旁证（严格规则重算 16/16、16/16、15/16，2026-08-04 独立复算确认） | 干净的切换跟随确认——16/48 事件裁剪、规则事后定义。**已被 g3_state_domain_consistent_parameter_switch_confirmation_v01 正式取代** |
| 旧固定过程噪声识别（process_noise_identification_validation 系列） | 固定条件下噪声候选可辨认的初步数值证据 | 干净的噪声识别证据——真值全程发生状态裁剪 |
| 旧联合参数—噪声切换（three_stage_parameter_process_noise_switch 系列、candidate_likelihood_parameter_process_noise_switch 系列） | 旧条件下联合组合未获确认的记录 | 联合识别"最终失败"的结论——干净版（共享状态域候选库）尚未做，此问题状态是**未定**而非已否定 |

### 二、预报价值类——全部属旧线，当前线从未测过预报

涉及目录：g3_phase2_interaction_value_param_switch_v01、g3_forecast_weight_drift_param_switch_v01、g3_corrected_forecast_param_switch_v01、g3_highest_posterior_forecast_param_switch_v01、g3_state_weight_factorial_param_switch_v03、g3_lead_adaptive_readout_param_switch_v01、g3_temporal_posterior_readout_param_switch_v01、g3_daily_rolling_forecast_readout_development_v01、g3_post_switch_forecast_confirmation_v01、以及全部 deterministic / fixed_process 预报审计。

- **仍可引用为**：旧候选库与旧封存样本上的探索性负面结果；本计划"不宣称预报价值"这一边界的依据；"正确识别参数不等于改善预报"的经验教训（三十天平均概率读出：候选认对率 97.92% 而四个预报门全失败）。
- **不可引用为**：当前共享状态域候选库上的预报结论。当前线从未执行任何预报，预报价值在新库上是**未测**，不是"已失败"。

### 三、一条不随候选库自动消失的机制警告

单滤波器对照实验（g3_fixed_process_parameter_candidate_complete_state_audit_v01 / controlled_forecast_v01,均为旧封存样本）发现：完全交互使五个水文储量状态改善 15.81%–68.78%（标准化总体改善 45.03%），但十个汇流记忆状态全部变差 10.63%–20.83%，第 1–7 天确定性预报差 29.88%–118.59%（配对区间严格排零）。

其机制——多滤波器状态混合污染近期出流记忆，而短提前期预报几乎只依赖出流记忆——是交互操作本身的性质，**推断**不随候选库更换而消失（新库上未测，属推断而非事实）。这是"不宣称预报价值"边界应长期保留的最硬理由。

### 四、保留原定位不变的实验

- 真值参数切换状态响应因果对照（g3_truth_parameter_switch_state_response_causal_control_v01）：保留为带标注的参数突变应力测试；其 16/48 投影事件正是催生当前共享状态域设计的直接原因。
- 候选间距曲线（g2 系列）、联合方法验证（joint_method 系列）、WALRUS 对齐、MATLAB 多种子等更早期目录：历史开发记录，均不属于当前线结论来源。

## 当前唯一权威结论来源

1. 参数切换跟随：`docs/plans/2026-08-04-id23-state-domain-consistent-parameter-switch-confirmation-closure.md`（通过，含范围限定）。
2. 过程噪声切换跟随：`docs/plans/2026-08-03-id23-state-domain-consistent-process-noise-switch-closure.md`（中→高、高→低通过；低→中 11/16 未通过，过程线显示失败模式为"慢而非盲"——5 个失败事件的新真值候选均在窗外第 26–136 天完成接管，此为 2026-08-05 从封存数组算得的描述性事实，非预注册指标）。
3. 六个主科学问题的最新状态：见参数切换结案记录内"六个主科学问题的更新状态"一节。

引用规则：凡与本文件冲突的旧 summary、旧交接、旧读出，以上述结案记录与本文件为准。

## 保护声明

本说明为新增文件。未移动、删除、改写任何封存结果目录、目视记录、独立核验记录或中央登记表既有行。
