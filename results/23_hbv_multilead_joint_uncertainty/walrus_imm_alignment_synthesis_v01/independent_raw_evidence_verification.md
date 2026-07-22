# Layer-2 独立复算报告：walrus_imm_alignment_v02

（独立复算上下文原文存档，2026-07-22。计算严格先于查看被审输出；不 import 本仓模块，照 MATLAB 源自写实现。）

## 总结论

**零不一致。** 我在不 import 本仓任何模块的前提下，照 MATLAB 源码自写 WALRUS 一步函数与 statetran 包装，从 .mat 原始证据独立重算了 G0 全部事实、G1 全程 3649 步重放、G3 六锚点与 max|Δprob|，然后才打开密封输出对比——所有数值与 gate_results.json / g3_anchor_comparison.csv / g2_first_exceed.csv 逐位一致；g1_replay_diff.npz 的逐步差数组与我的重放**逐位相同**；g3_prob_diff.npz 的 reference_probs 与 .mat 的 imm_probs **逐位相同**；目录 9 个文件哈希全部与 checksums.json 一致；config_snapshot.json 与 src 冻结配置 SHA-256 相同（2b2251…）。判定档位"结构等价"符合预冻结分级规则（G1 过 + 锚点全过 + G2/G3 强判据未过），未见事后放宽容差。"脚本文本漂移"论断经我独立验证**成立**。

## 事实（逐项数值对照）

**证据完整性**
| 项 | 我的值 | 被审值 | 一致 |
|---|---|---|---|
| .mat SHA-256 | fd080ce0…bec609f | 配置/gate_results 记录同值 | ✔ |
| config_snapshot.json SHA-256 | 2b225198…3621775 | == src 冻结配置、== gate_results.config_sha256 | ✔ |
| 目录 9 文件哈希（alignment_report/config_snapshot/environment/g1_npz/g2_csv/g3_csv/g3_npz/gate_results/resource_preflight） | 逐个 certutil 实算 | checksums.json | 9/9 ✔ |

**G0（全部从 .mat 独立读出）**
| 项 | 我的独立值 | gate_results | 一致 |
|---|---|---|---|
| qobs == states_obs 第 5 列 | 逐位相等（max diff 0.0） | true | ✔ |
| 总长 / t1_2 / t2_3 | 3649 / 1216 / 2433 | 3649 / 1216 / 2433 | ✔ |
| 候选 11 行（1-based） | (600, 50, 1.8e7, 6) == 阶段 1 真值 | true | ✔ |
| 候选 12 行 | (400, 30, 1.6e7, 3) == 阶段 2 真值 | true | ✔ |
| r | 1.5e-05（精确） | 1.5e-05 | ✔ |
| p0 | == diag((0.001·state0)²) 逐位 | true | ✔ |
| q_s_all | 12 个 cell 全相同，== q_s_truth{1} == 1e-6·diag([140,1000,4,1200,0]) 精确 | true | ✔ |
| noise_q_truth 逐列 std vs sqrt(1e-6·diag) | 相对偏差 +0.47% / −0.84% / −1.13% / −0.28%，第 5 列全为精确 0 | true（5% 内） | ✔ |

**脚本文本 vs 工作区漂移论断**（我逐行读了 for_submit 与 synthetic/scripts/mukf 两份 main_params.m，文本相同）：
- 第 18 行文本 `q_s_truth = {1e-5·diag(tmp), 1e-3·diag(tmp), 1e-4·diag(tmp)}`，而工作区 q_s_truth{1} 实为 **1e-6**·diag（cell 2、3 与文本一致）→ cell 1 漂移属实；
- 第 20-22 行文本从 `q_s_truth{2}`（1e-3）抽噪声，但经验 std 比值：/1e-3≈0.031、/1e-5≈0.316、/**1e-6≈0.99–1.00** → 实际抽自工作区 cell 1，排除脚本两种读法；
- 第 86-89 行文本 `q_s_all = q_s_truth{2}`，工作区 q_s_all 实为 == q_s_truth{1} → 漂移属实；
- 第 19 行 r = 1e-4·state0(5) = 1.5e-5 与工作区一致（r **无**漂移）。
即 v02 修正案"两份脚本文本都无法复现已发表 .mat"的论断被独立证实。

**G1（自写移植重放 3649 步 + noise_r_truth）**
| 项 | 我的独立值 | gate_results | 一致 |
|---|---|---|---|
| max abs diff | 4.547473508864641e-13 | 同值逐位 | ✔ |
| 逐状态 max | [2.842…e-14, 2.2737…e-13, 8.8818…e-16, 4.5475…e-13, 8.3267…e-17] | 全部逐位相同 | ✔ |
| 逐步差数组 | 与 g1_replay_diff.npz 的 max_abs_diff_per_step **逐位相同**（3649 点，max|Δ|=0.0） | — | ✔ |
| 门槛 | 4.55e-13 ≪ 1e-8，pass | passed=true | ✔ |

**G3（锚点全部用我自己的代码算）**
| 锚点 | 我算 MATLAB 侧（从 .mat imm_probs） | 被审 MATLAB 侧 | 我算 Python 侧（从 python_probs） | 被审 Python 侧 | 一致 |
|---|---|---|---|---|---|
| phase1 真滤波器平均概率 | 0.33259149687632206 | 同 | 0.3325217320703219 | 同 | ✔ |
| phase1 首次登顶 | 6 | 6 | 6 | 6 | ✔ |
| phase1 稳定登顶 | 724 | 724 | 724 | 724 | ✔ |
| phase2 平均概率 | 0.3650905271830478 | 同 | 0.3672011560376654 | 同 | ✔ |
| phase2 首次登顶 | 120 | 120 | 120 | 120 | ✔ |
| phase2 稳定登顶 | 560 | 560 | 560 | 560 | ✔ |

- max|Δprob| 我算 = **0.015840744290978554**（1-based 第 706 行、滤波器 2）== gate_results 逐位；
- reference_probs 与 .mat imm_probs 逐位相同（max diff 0.0）；
- 锚点容差核算：平均概率差 7.0e-5 / 2.11e-3 < 0.01，周期差全为 0 < 5 → anchors_pass=true 成立；1.58e-2 > 1e-6 → strong_pass=false 成立。

**G2（仅内部一致性）**：g2_first_exceed.csv 12 行与 gate_results.per_filter 12 项在 CSV 打印精度（12 位有效数字）内逐项一致；12 个滤波器全部有 first_exceed → strong_pass=false 自洽。

**判定档位**：G1 pass + G2 strong fail + G3 strong fail + 锚点全过 → 按冻结分级恰为"结构等价"，与 gate_results.verdict_tier 及 alignment_report.md 一致。

## 推断

1. G1 逐步差数组与我的独立实现**逐位相同**，说明被审 Python 重放轨迹与我照 MATLAB 源独立写出的实现产生了 IEEE-754 逐位相同的轨迹——两份移植语义完全一致；残余 4.5e-13 是 MATLAB/NumPy 浮点运算次序差异的正常累积，低于门槛 5 个数量级。
2. 锚点与 max|Δprob| 的计算实现（含"稳定登顶=从该循环起 argmax 保持真到阶段末"的定义）被审方与我独立实现给出完全相同结果，锚点判定无实现性偏差。
3. 判定链条机械遵循冻结规则：G2 未过强判据被如实报告为 fail、容差未见事后放宽，报告诚实。

## 未知与限制

1. **G2 的 Python 滤波轨迹未存档**（目录内无 G2 轨迹 npz），因此 first_exceed 步数与 max_abs_diff 无法从原始证据独立复算，只能做 CSV↔JSON 内部一致性。这是存档设计限制，不是发现。（注：本报告归档后已由 walrus_imm_alignment_v02_addendum_r1 补齐轨迹与诊断。）
2. g3_prob_diff.npz 的 **python_probs 本身产自被审管线**（本仓 MUKF/IMM 实现）；我核实的是"从该数组出发的全部统计量算得正确"及"reference 侧与 .mat 逐位一致"，未独立重跑 IMM 前向（那需要独立重写 UKF/IMM，超出本层范围）。
3. MATLAB 侧未重跑（配置明确排除）；checksums.json 只能证明目录内部自洽 + config_snapshot 与 src 冻结配置一致，无更外层锚。
4. 目录内有 1 个不在 config artifacts 清单中的文件 resource_preflight.json（已被 checksums 覆盖，内容为资源预检，无害）；无缺失文件。

## 不一致明细

**无。** 所有被审数值均被独立复算命中（多数逐位相同），无一项需要"我的值 vs 被审值"分列报告。
