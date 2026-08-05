# 状态域一致的过程噪声切换实验结案

## 结论

**总体判断：不支持“在本实验条件下三种过程噪声切换方向均被可靠识别”。**

固定同一套真实水文参数，只切换下层地下水状态的过程噪声标准差后：

- 低噪声切换到中噪声：成功 11/16，比例 0.6875，95% 精确区间 [0.413379, 0.889830]，未达到预先规定的至少 13/16，且区间下限没有高于 0.5。
- 中噪声切换到高噪声：成功 16/16，比例 1.0000，95% 精确区间 [0.794093, 1.000000]，通过。
- 高噪声切换到低噪声：成功 16/16，比例 1.0000，95% 精确区间 [0.794093, 1.000000]，通过。

因此，已有证据证明该滤波器组在这个干净合成条件下能够稳定跟随“中到高”和“高到低”两种切换，但不能证明它能稳定跟随全部三种切换；薄弱方向是“低到中”。

## 预先固定的判定

真实水文参数始终为同一套 `trained_center` 参数。三个候选滤波器也都使用这套参数；唯一变化是下层地下水状态的过程噪声标准差为 1、4 或 16 毫米每天，其余十四个状态的过程噪声方差均为零。

每个切换方向有 16 个匹配事件。成功定义为：切换后的 30 天内，新真实噪声候选至少连续 5 天具有最高后验概率。每个方向必须同时满足：

1. 至少 13/16 个事件成功；
2. 成功比例的双侧 95% 精确区间下限严格高于 0.5。

这个判定不要求后验概率达到 0.9。

## 响应时间

响应时间从新噪声开始当天记为第 0 天，仅在成功事件中统计：

| 真实切换 | 成功事件 | 响应开始日中位数 | 最晚响应开始日 |
|---|---:|---:|---:|
| 低到中 | 11/16 | 10.0 | 20 |
| 中到高 | 16/16 | 5.5 | 14 |
| 高到低 | 16/16 | 10.0 | 20 |

## 全阶段描述性结果

这些数值只描述全部 180 天阶段内哪个候选概率最高，不是预先固定的切换成功门槛：

| 真实噪声 | 最高概率天数比例 | 真实候选平均后验概率 |
|---|---:|---:|
| 低 | 0.937037 | 0.749890 |
| 中 | 0.812731 | 0.640188 |
| 高 | 0.947917 | 0.810983 |

## 真值有效性和独立核验

- 8 个匹配区组、3 条轮换真值、每条 540 天，共独立重建 12,960 次真实状态转移。
- 真实状态裁剪事件数：0。
- 最大真实状态裁剪调整：0.0。
- 全部候选概率的最大归一化误差：2.220446049250313e-16。
- 正式运行前回归测试：43 项通过。
- 独立核验状态：通过。
- 独立核验对强迫、随机数、暖机状态、确定性状态、实际扰动、裁剪调整、真实状态、真实流量和观测的最大绝对重建差：0.0。
- 独立核验没有导入本实验核心模块、运行器或任何预报模块。

## 证据边界

这只是温暖、偏湿的合成 HBV-lite 条件下，下层地下水单一状态过程噪声的同化实验。它不是：

- 所有状态或所有过程噪声形式的一般结论；
- 预报能力证据；
- WALRUS 或其他低地水文模型证据；
- 真实流域证据；
- 参数和噪声同时切换的联合识别证据。

## 完整证据路径

- 冻结配置：`src/hbv_multilead_joint_uncertainty/configs/g3_state_domain_consistent_process_noise_switch_v01.json`
- 核心实现：`src/hbv_multilead_joint_uncertainty/state_domain_consistent_process_noise_switch.py`
- 正式运行器：`src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_domain_consistent_process_noise_switch.py`
- 独立核验器：`src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_domain_consistent_process_noise_switch.py`
- 正式结果：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01`
- 结论汇总：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/summary.json`
- 原始数组：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/evidence.npz`
- 每日概率：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/daily_probabilities.csv`
- 切换事件：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/switch_response_events.csv`
- 分方向统计：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/switch_response_summary.csv`
- 概率响应图：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/probability_response.png`
- 判定汇总图：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/response_summary.png`
- 结果散列清单：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/checksums.json`
- 独立核验：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01_independent_verification_v01/independent_verification.json`
- 独立核验散列：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01_independent_verification_v01/checksums.json`

## 执行记录

第一次正式命令在封存源代码快照时触发 Windows 长路径错误，未发布最终结果。该未完成目录被原样保留：

`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01.incomplete.317807653afd4be6baf8fdc6cb241fb3`

修复只把源代码快照改为短文件名并增加映射清单；未改变配置、种子、噪声档位、响应定义或科学门槛。没有清理、还原、暂存、提交、删除或覆盖用户文件。
