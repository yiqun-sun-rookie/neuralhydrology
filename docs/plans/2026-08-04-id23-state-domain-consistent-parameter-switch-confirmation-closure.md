# 参数切换时不裁剪状态的正式确认实验结案

## 结论

**总体判断：支持"在本实验条件下，三个被测参数切换方向均被及时、稳定识别"。**

三个候选滤波器参数共享全部决定状态合法范围的参数（土壤最大持水量 parFC 与融雪持水比例 parCWH），真实参数候选在第 181 天与第 361 天的预定阶段边界切换后：

- 候选 1 切换到候选 2：成功 16/16，比例 1.0000，95% 精确区间 [0.794093, 1.000000]，通过。
- 候选 2 切换到候选 3：成功 16/16，比例 1.0000，95% 精确区间 [0.794093, 1.000000]，通过。
- 候选 3 切换到候选 1：成功 16/16，比例 1.0000，95% 精确区间 [0.794093, 1.000000]，通过。

最终事件成功同时满足冻结数值规则与盲态目视"清楚成功"两项要求；数值判定与目视判定零矛盾。

**范围限定（必须随结论一起引用）：**

1. 三种候选轮换均为同一循环方向，实测的是 1→2、2→3、3→1 三个有向切换；六个可能的有序候选对中，反方向的 2→1、3→2、1→3 未测试。
2. 强迫气温恒定 10 摄氏度，全部降水为降雨；积雪储量与融雪液态水在全部 12,960 个真值转移中恒为零（封存数组实测最大值 0.0）。十五维状态合同中实际活跃的是 13 个状态；四个雪相关参数（parTT、parCFMAX、parCFR、parCWH）在本条件下对结果无影响。
3. 本实验只回答"候选概率能否跟随参数切换"，不回答状态精度、预报价值、过程噪声切换或联合切换。

## 预先固定的判定

数值规则（冻结于配置，SHA-256 `a7c974608a647f7eade14a7fa0ee443f6148950cf7175103b21d91c6bb344059`）：切换后 30 天内，新真实参数候选后验概率严格大于 0.5、比第二名至少高 0.10，并连续满足 5 天。每个方向须至少 13/16 个事件成功，且成功比例双侧 95% 精确区间下限严格大于 0.5。

目视规则：用户在不知道数值判定时逐图分类（清楚成功 / 说不清 / 失败），显示顺序按种子 3704001 打乱；"清楚成功"要求切换后新真实候选形成持续可见分离的主导，且切换前它不是持续主导者。最终事件成功 = 数值成功 且 目视清楚成功。

## 响应时间

响应开始日以切换当天为第 0 天：

| 有向切换 | 成功事件 | 响应开始日中位数 | 最晚响应开始日 |
|---|---:|---:|---:|
| 候选 1 → 候选 2 | 16/16 | 0.0 | 0 |
| 候选 2 → 候选 3 | 16/16 | 0.0 | 0 |
| 候选 3 → 候选 1 | 16/16 | 0.0 | 1 |

对比已结案的过程噪声切换实验（响应中位数 5.5–10 天、最晚 20 天），参数切换在流量中的可观测性显著更强：切换当天即可识别。

## 全阶段描述性结果

仅描述整段 180 天内真实候选的表现，不是切换成功门槛：

| 真实候选 | 最高概率天数比例 | 真实候选平均后验概率 |
|---|---:|---:|
| 候选 1 | 0.999537 | 0.998979 |
| 候选 2 | 1.000000 | ≈1.000000 |
| 候选 3 | 1.000000 | ≈1.000000 |

## 真值有效性和独立核验

- 8 个匹配强迫区组 × 3 条轮换真值 × 540 天，共 12,960 次真实状态转移。
- 真实状态裁剪事件数：0；切换边界裁剪事件数：0；最大裁剪调整：0.0。
- 候选概率最大归一化误差：1.1102230246251565e-16。
- 独立核验状态：**通过**（2026-08-04）。
- 独立核验从封存原始输入（强迫、参数、随机数、初值）独立重建真值与判定，对强迫、随机数、初值、协方差、确定性真值、扰动、裁剪调整、真值状态、真值流量、观测、参数调度共 13 类数组的最大绝对重建差：**0.0**。
- 独立核验未导入生产实验核心模块、生产运行器或任何预报模块（核验记录中三项导入标志均为否）。
- 正式结果 62 项封存散列、源代码与测试 12 项散列、目视记录 2 项散列全部匹配；冻结配置散列匹配。

## 目视记录（如实陈述证据强度）

- 盲态目视 48/48 标注为"清楚成功"，且目视清单记录判定完成于数值判定公开之前。
- 第 005 幅为盲态审查时用户唯一单独评论的图（"有波动但最终由新真实候选接管，算成功"）。
- 其余 47 幅在盲态记录中的理由为"用户未报告例外"，属于整体确认而非逐张单独判断。
- 2026-08-04 结案审查时，用户直接查看第 001、005 两幅并确认通过，其余 46 幅由用户整体确认通过；该次复核为非盲态（数值结果已公开），不计为盲态判断。

## 回归测试记录

- 封存清单指定的三个目标测试文件共 22 项测试：**22/22 通过**（2026-08-04，独立核验启动前）。
- 交接中"49 项相关测试"的组成在权威文档中无法重建（对照：过程噪声切换实验当时为 43 项）；以超集代替：目标测试加共享模块（交互式多模型、sigma 滤波器、模型适配器、状态维数、多提前期合同与实验）共 98 项，其中 88 项通过；10 项未通过者全部属于其他实验线——9 项因缺少全球流域基准线（结果目录 10）的数据文件而报错，1 项为旧多提前期合同校验中的文本文件散列比对失败，与换行符转换问题同类，均与本实验无关。
- 仓库既有 pytest 配置警告 1 项（collect_ignore_glob），与既往记录一致。

## 附带发现（结案审查中核实，供总框架引用）

1. **文本文件散列的换行符陷阱**：工作树内 133 个带散列清单的历史实验目录中，67 个的 config_snapshot.json 原样散列不匹配；把行尾 CRLF 归一化为 LF 后全部匹配（0 个残留）。内容零篡改。今后散列审计文本文件时必须行尾归一化，否则大面积误报。本实验封存于当前工作树，无此问题。
2. **状态精度不等于预报价值的最强证据**（来自已封存的单滤波器对照实验，登记表第 19、20 行）：三滤波器完全交互相对单滤波器，标准化完整状态误差改善 45.03%（五个水文储量全部改善 15.81%–68.78%），但十个汇流记忆状态全部变差 10.63%–20.83%，第 1–7 天确定性预报差 29.88%–118.59% 且配对区间全部严格排零。机制：交互改善慢变储量、污染近期出流记忆，而短提前期预报几乎只依赖出流记忆。
3. 旧理想参数切换实验按当前严格规则从封存概率重算：参数库 16/16、16/16、15/16，联合库参数边缘 16/16、15/16、15/16，与既往声称一致（本次结案审查独立复算）。
4. 新旧两条证据线的权威定位（哪些旧结果已被取代、预报价值负面结果只属旧候选库、当前线从未执行预报）见 `docs/plans/2026-08-05-id23-old-bank-evidence-scoping.md`；凡与该文件冲突的旧 summary、旧交接、旧读出，以结案记录与该文件为准。

## 六个主科学问题的更新状态

1. 固定条件辨认候选：固定参数通过；旧固定过程噪声数值通过但真值全程裁剪，证据受限。
2. **参数切换时不裁剪状态能否跟随：通过（本实验，生产 + 盲态目视 + 独立核验三关齐）。** 限于三个循环方向与暖湿无雪合成条件。
3. 过程噪声切换时不裁剪状态能否跟随:中到高、高到低通过；低到中 11/16 未通过。
4. 参数与过程噪声联合切换能否认出唯一组合：无干净确认。
5. 状态与协方差交互是否改善完整状态：总体无法确定（点估计 3.711% 改善，区间跨零；应按 13 个活跃状态口径转述）。
6. 状态与协方差交互是否改善全阶段第 1–7 天预报：无法确定（1.215%–1.667%，区间全部跨零）。

## 下一科学任务（承接既定顺序）

优先诊断"低过程噪声切到中等过程噪声"失败原因。本次结案审查从封存概率中取得的先导事实：失败方向 30 天窗内的第二名 87.5% 的天数是旧的低噪声候选（420/480 天），仅 12.5% 是高噪声候选；且"中等最难"为全阶段性质（真值为中时全阶段居首比例 81.27%，低 93.70%、高 94.79%；三档标准差 1、4、16 毫米每天在对数尺度等距，非间距问题）。诊断第一步仍按既定设计：先判断观测预测似然能否稳定区分低与中，再查概率递推与转移先验；一次只改一个因素。原因未明前不进入联合切换。

## 完整证据路径

- 冻结配置：`src/hbv_multilead_joint_uncertainty/configs/g3_state_domain_consistent_parameter_switch_confirmation_v01.json`
- 核心实现：`src/hbv_multilead_joint_uncertainty/state_domain_consistent_parameter_switch_confirmation.py`
- 正式运行器：`src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_domain_consistent_parameter_switch_confirmation.py`
- 独立核验器：`src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_domain_consistent_parameter_switch_confirmation.py`
- 正式结果：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01`
- 结论汇总：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01/summary.json`（其内 "尚未目视审查" 为封存时历史状态，以本结案记录与独立核验记录为准）
- 原始数组：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01/evidence.npz`
- 每日概率：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01/daily_probabilities.csv`
- 切换事件：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01/switch_response_events_numeric.csv`
- 分方向统计：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01/switch_response_summary_numeric.csv`
- 事件图（48 幅）：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01/event_panels/`
- 盲态目视记录：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01_visual_review_v01/visual_review.csv`
- 目视清单：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01_visual_review_v01/review_manifest.json`
- 独立核验：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01_independent_verification_v01/independent_verification.json`
- 独立核验散列：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01_independent_verification_v01/checksums.json`

## 执行记录

- 首次独立核验启动时，调用方误将工具等待时间设为 1 秒，进程约 2.4 秒后被终止（退出码 124），属执行超时而非科学指标失败；事后只读检查确认核验目录不存在、无残留进程、暂存区为空、全部封存散列未变。
- 2026-08-04 收到用户明确授权后重启：先复核前置条件（核验目录不存在、暂存区为空、77 项散列全对），再通过 22 项目标测试，随后以无短超时的后台方式完整运行独立核验一次，通过。未改配置、未换种子、未改正式结果、未改目视标签。
- 结案过程未清理、还原、暂存、提交、删除、移动、复制或覆盖任何既有用户文件；独立核验目录为核验器按规程新建。
