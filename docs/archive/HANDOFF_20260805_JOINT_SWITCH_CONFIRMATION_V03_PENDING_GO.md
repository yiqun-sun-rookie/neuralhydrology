> **已归档，勿据此行动（2026-08-05 归档）。** 本文件描述的"v03 待 GO"状态早已终结：v03 已运行完成，并因独立核验器的极性缺陷改以 **v04** 重冻结重跑、结案**通过**。本文件仅作历史记录保留。
>
> 现行权威文档：
> - 结案记录 `docs/plans/2026-08-05-id23-joint-parameter-process-noise-switch-confirmation-closure.md`
> - 方法可靠性清单（本测试线最终交付物）`docs/plans/2026-08-05-id23-hbv-lite-method-reliability-checklist.md`
> - 设计文档（含 v01→v04 全部沿革）`docs/plans/2026-08-05-id23-joint-parameter-process-noise-switch-confirmation-design.md`
>
> 凡本文件与上述三者冲突，一律以上述三者为准。第七节"未完成事项"已全部完成，不得再作为待办执行。

# 交接：联合参数—噪声切换确认 v03 待 GO（2026-08-05）

## 一、任务身份与总目标

- 项目归属：imm-save（G:\github\pycharm\projects\paper-imm-variable-params）。
- 唯一权威实验工作树：G:\wt\id23-readout（分支 codex/id23-predictive-skill-readout）。除非用户明确 GO,只读使用。
- **总目标定位（用户已确认）**：这条 HBV-lite 合成实验线是**方法测试,不是研究**,服务对象是真实流域预报系统。最终交付物 = 一张方法可靠性清单（可依赖 / 不可依赖 / 换模型警告）。
- **当前阶段**：清单只剩最后一格——联合切换确认（参数与过程噪声同时切换时,参数辨认是否不被交叉混叠降级）。该实验 v01/v02 两次冻结均在物理门前失败（零产出）,v03 配对已实测可行,**等用户 GO 冻结开跑**。
- 用户已确认的最终判定规则：事件成功 = 冻结数值规则通过 **且** 用户盲态人工审图判"清楚成功"（两个边缘分别判）。

## 二、必须遵守的限制与停止条件

1. 不清理、还原、暂存、删除、移动、复制、覆盖用户文件;封存目录只读;提交需用户同意（历史上用户说 "all" 授权过一次提交）。
2. 散列、测试、物理门、独立核验任何一环失败：停止、保留证据、不给科学结论、**不自行修复重试**（设计变更需用户重新 GO）。
3. 盲态协议：正式运行的数值判定封存在结果目录内,运行器终端只打印物理门;在用户给完 48 张图 × 2 边缘的标签之前,不得向用户展示或自己引用数值判定结果。
4. 预注册：低→中噪声边缘"预期不过 30 天窗"（依据信道极限诊断）,它失败不算方法失败、不触发停止。
5. 联合唯一组合读出仅描述性,禁止设通过/失败门,结论禁止写"能辨认唯一组合"。
6. 结论只限暖湿合成 HBV-lite;不外推真实流域/WALRUS;不合并辨认、状态精度、预报价值三层主张。
7. 回答规则：中文、结论先行、完整通俗名称、区分事实/推断/未验证、每次回复以"## 结论"结尾。

## 三、已完成并有效的结论（全部已封存/落盘）

1. **参数切换确认（不裁剪状态）：已结案,通过。** 三方向 16/16,区间 [0.794093,1.0],响应中位第 0 天;12,960 转移零裁剪;盲态目视 48/48;独立核验 2026-08-04 通过,真值重建差 0.0。范围限定：六个方向只测循环 3 个;恒温 10 度无雪,15 状态实为 13 活跃。
2. **过程噪声切换：中→高、高→低通过（16/16）;低→中 11/16 未通过。已诊断结案：** 根源是流量信道信息极限——中档噪声流量足迹 0.0885 mm/d 仅为观测噪声 0.1780 的一半;低/中滤波器新息方差比 1.208;低→中逐日证据 +0.074,仅为其他方向的 1/4—1/5;纯似然理论上限最慢事件需 46 天 > 30 天窗;**概率递推不是抑制者**（完整递推最晚 73 天,快于无转移混合的 113 天）;失败模式"慢而非盲"（5 个失败事件全部在窗外第 26–136 天接管,阻挡者 87.5% 天数是旧低噪声候选）。诊断重跑与封存后验逐位一致（差 0.0）。
3. **旧候选库证据定位（防误读归档已落盘）**：全部预报价值负面结果只属旧库;当前线从未执行预报。警告级机制（推断）：交互污染近期汇流记忆致短预报差 29.88–118.59%（状态反而好 45.03%）,可能不随换库消失。
4. **设计准则（用户认可）**：过程噪声应按对应状态变量量级定义（真实系统现行 Q=1e-4×状态量级即如此）;本合成线维持绝对档位 1/4/16 是为保住与已封存单因子实验的可比性。
5. **文本文件散列审计必须行尾归一化**（67 处 config_snapshot 不匹配全是 CRLF 伪差,零篡改）。

## 四、联合实验 v01/v02 失败记录与 v03 方案（当前焦点）

三版共同点：参数轮换固定为 试验1(候选2→3→1)、试验2(候选3→1→2)、试验3(候选1→2→3);噪声档位 1/4/16 mm/d 只作用于下层地下水储量（SLZ,状态索引 4）;边界上参数噪声同日切换;两边缘各方向 16 事件。

- **v01 失败**（配置 sha 57eaf2b0098947c328068c7ade8884d2e07fc5a94e2784909eb25044dac96074,保留在盘,零产出）：噪声轮换 (中高低)/(高低中)/(低中高) 使候选 3 阶段配高噪声。候选 3 排水系数 parK2=0.1521,SLZ 中位仅 33 mm,±16 扰动必打负。真值可行性实测 24/24 轨迹失败。
- **v02 失败**（sha 284f32eec66fb5e01b57ec7f9ebf03192b30d7631b22b1c55d2e84a0985c2207,零产出）：高噪声改配候选 1,但**阶段继承效应**——候选 1 阶段接在候选 3 后,入场 SLZ 仅 19–36 mm 且候选 1 恢复时间常数约 175 天,6 处失败全在第 181–196/364–378 天（边界后）。
- **v03 方案（已实测可行,待 GO,配置尚未创建）**：噪声轮换 试验1(高低中)、试验2(低中高)、试验3(中高低) → 高噪声恒配候选 2（恢复快 τ≈45 天、平衡储量 452 mm）,候选 3 恒配低噪声（= 参数实验已验证零裁剪的组合）,候选 1 恒配中噪声。真值可行性检查在全部 8 个正式强迫种子 × 3 轮换上**零裁剪全通过**;真值由种子确定,故正式运行物理门必过（已验证）。边缘方向计数不变（各 3 方向 × 16 事件）。
- 已声明局限（v01 起就有）：对齐轮换只覆盖 9 种方向配对中的 3 种;真值中参数与噪声档位绑定,但滤波器组（9 候选因子化先验）不知道绑定,两边缘仍需各自挣证据。

## 五、关键路径（全部相对 G:\wt\id23-readout）

- 冻结配置：`src/hbv_multilead_joint_uncertainty/configs/g3_joint_parameter_process_noise_switch_confirmation_v01.json` 与 `_v02.json`（两个失败版,保留勿动）;**v03 未创建**。
- 核心：`src/hbv_multilead_joint_uncertainty/joint_parameter_process_noise_switch_confirmation.py`（真值生成含零裁剪硬门、两边缘规则、描述性读出;测试已验证）。
- 运行器：`src/hbv_multilead_joint_uncertainty/scripts/run_g3_joint_parameter_process_noise_switch_confirmation.py`——**当前常量指向 v02**（EXPERIMENT_ID 与 CONFIG_SHA256 需改 v03）;盲态协议已内置（终端只打印物理门）。
- 核验器：`src/hbv_multilead_joint_uncertainty/scripts/verify_g3_joint_parameter_process_noise_switch_confirmation.py`——同样指向 v02 需改;用 scl_hydro.hbv_lite_numpy 独立重建,不导入生产模块;期望目视 CSV 列名 `parameter_margin_label`、`noise_margin_label`,48 行。
- 测试：`test/test_hbv_joint_parameter_process_noise_switch_confirmation.py`（10 项）——CONFIG_PATH 指向 v02 需改 v03;**注意:守护测试 test_v02_pairing_keeps_high_noise_away_from_fast_draining_candidate 断言的是 v02 配对（候选3→中、高→候选1）,对 v03 必失败,必须改写为断言 v03 配对（候选3→低、高→候选2）**。
- 已封存参考实验：`results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01{,_visual_review_v01,_independent_verification_v01}`、`g3_state_domain_consistent_process_noise_switch_v01{,_independent_verification_v01,_likelihood_diagnosis_v01}`。
- 文档：`docs/plans/2026-08-04-id23-state-domain-consistent-parameter-switch-confirmation-closure.md`（参数实验结案）、`2026-08-05-id23-old-bank-evidence-scoping.md`（新旧线定位）、`2026-08-05-id23-low-to-medium-process-noise-slow-response-diagnosis.md`（诊断）、`2026-08-05-id23-joint-parameter-process-noise-switch-confirmation-design.md`（设计,已含 v01 失败追记;v02 失败与 v03 尚未追记）。
- 登记表：`src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`（参数确认已登记;联合实验各版未登记,待 v03 结案时一并补）。
- git：已提交 0ade1ce6（当前线封存）与 23d13e90（历史积压）;**联合实验全部文件（v01/v02 配置、核心、运行器、核验器、测试、设计文档追记）尚未提交**。

## 六、已确认与已排除

- 已确认：阶段继承效应（低储量跨边界遗传给慢恢复候选,证据 = v02 失败点全在边界后 1–16 天）;v03 真值可行（正式种子全测,确定性）;两次失败均零产出、种子未消耗。
- 已排除：方法本身缺陷（失败全是真值设计问题,滤波从未跑到）;概率递推作为低→中慢因（诊断证明）。

## 七、未完成事项与下一步（按序,不可跳）

1. **等用户 GO v03**（唯一阻塞）。GO 后：复制 v02 配置改三处（experiment_id→_v03、噪声轮换→[[high,low,medium],[low,medium,high],[medium,high,low]] 的完整 id 写法 lower_groundwater_*、三个 relative_path→_v03）+ 更新 note;算新 sha;改运行器/核验器两常量;改测试 CONFIG_PATH 与守护测试断言;跑 10 项测试全绿;重跑真值可行性确认（几秒);后台启动正式运行（无短超时）。
2. 运行完成 → 只报物理门（裁剪数=0、归一化误差、48 事件）→ 分批发 48 张盲审图（每张上下两子图=参数边缘/噪声边缘）,收集用户每图两标签(clear_success/ambiguous/failure)→ 封存目视目录（visual_review.csv + review_manifest.json 含 numeric_decisions_opened_before_labels 标记 + checksums.json）。
3. 揭数值 → 后台跑核验器一次（不设短超时,先确认核验目录不存在）→ 通过则写结案记录、补登记表（v01 失败行、v02 失败行、v03 行）、更新可靠性清单成文、提交 git。
4. 结案后测试线收线;可选遗留：反方向参数切换（低优先）、加测地下水支线（未立项）。

## 八、新对话首查清单

```bash
git -C G:\wt\id23-readout status --porcelain | head -20
```
（预期:联合实验相关文件为未跟踪/未提交状态;若已提交说明有人动过,先核对）

```bash
ls G:\wt\id23-readout\results\23_hbv_multilead_joint_uncertainty | grep joint
```
（预期:空——联合实验无任何结果目录;若非空立即停止并报告用户）

```bash
cd /g/wt/id23-readout && PYTHONPATH=src python -m pytest test/test_hbv_joint_parameter_process_noise_switch_confirmation.py -q
```
（预期:对着 v02 配置 10 项通过;切 v03 后守护测试必须先改写再跑）

首读文件：本交接、设计文档（docs/plans/2026-08-05-id23-joint-...-design.md）、v02 配置（作为 v03 的模板）。
