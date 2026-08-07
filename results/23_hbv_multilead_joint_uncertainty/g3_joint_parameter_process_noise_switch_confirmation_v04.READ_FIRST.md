# 先读这里：v04 结果目录内三处字段是封存瞬间的历史状态，不是最终状态

本文件是旁注，放在封存目录**之外**，因为目录内文件受散列清单锁定，事后不得增删改。

## 1. `summary.json` 与 `registry_entry.json` 里的状态字段已过期

这两个文件由运行器在**目视复核与独立核验之前**写入并封存，因此它们记录的是当时的状态：

| 字段 | 文件里写的（封存瞬间） | 实际最终状态 |
|---|---|---|
| `status` | `complete_pending_blinded_visual_review_and_independent_verification` | 三关全部完成 |
| `visual_review_status` | `not_yet_performed` | 已完成并封存 |
| `scientific_conclusion_withheld` | `true` | 已解盲、已结案 |
| `registry_entry.status` | 同上 `..._pending_...` | 登记表内为 `completed` |

**独立核验状态见** `..._v04_independent_verification_v01/independent_verification.json`：`status: passed`，17 项完整性检查全部为真。

## 2. `..._v04_visual_review_v01/visual_review.csv` 单独使用会得出相反结论

该文件保存的是**盲态原始标签**，其中 10 张（003、006、011、013、014、023、032、036、044、048）被记在**两个边缘**上——因为判定者当时未指明所属子图，故按保守原则双记。

- **只用这个文件算**：参数边缘 候选3→候选1 最终 **6/16**，低于门槛 13 → 得出"不通过"。
- **计入解盲后的归属澄清**：判定者事后指认这 10 张属噪声边缘（下子图），参数边缘该方向 **16/16** → 结论为"通过"。

澄清件独立封存在 `..._v04_visual_review_amendment_v01/`，其 `amendment_manifest.json` 内含完整时序披露与两种计数。**该澄清发生在数值解盲之后，独立性弱于盲态判断**——引用本实验目视关时必须同时说明这一点。

## 3. 冻结配置 `..._v04.json` 的 `status` 字段写的是 `frozen_before_run`

那是冻结时刻的值，运行后未（也不应）改写。运行确已完成。

## 权威文档

- 结案记录：`docs/plans/2026-08-05-id23-joint-parameter-process-noise-switch-confirmation-closure.md`
- 方法可靠性清单：`docs/plans/2026-08-05-id23-hbv-lite-method-reliability-checklist.md`
- 登记表：`src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`（行 `..._v04`）

凡本目录内文件与上述三者冲突，一律以上述三者为准。
