# 本目录已被 v04 取代，且其核验报告的 `status: failed` 不是实验失败

本文件是旁注，放在封存目录**之外**，因为目录内文件受散列清单锁定，事后不得增删改。

## 结论先说

- **权威结果是 v04，不是 v03。** 请使用 `..._v04`。
- **v03 的运行本身是干净的**：真值零裁剪（12,960 次转移）、边界零裁剪、归一化误差 3.33e-16、48 个切换事件、盲态目视按协议完成并封存。
- **v03 与 v04 逐位相同**：27 个证据数组最大绝对差全为 0，两个数值判定 CSV 逐行相同，48 张事件图的字节散列完全相同。取代的原因与科学内容无关。

## `..._v03_independent_verification_v01/independent_verification.json` 里的 `status: failed` 是什么

**是核验器自身的缺陷，不是数据完整性问题。** 该报告的 17 项检查中，14 项实质检查全部通过——独立重建真值与两个边缘的最大绝对差均为 **0.0**、零裁剪、归一化、判定一致性、目视 48 行、全部散列匹配。

判为 failed 的唯一原因：三个条目

```
production_experiment_module_imported: false
production_runner_imported:            false
forecast_module_imported:              false
```

以 `false` 表示"**正确地**未导入"，而判定汇总要求每个条目为真。该核验器因此**在结构上永远不可能返回 passed**；且这三项是硬编码常量，从未验证任何事。缺陷长期未暴露，因为 v01、v02 零产出、核验器从未真正运行过。

## 为什么要重跑而不是就地修

核验器自身的散列写在本目录 `source_manifest.json` 里。就地修补会使源码散列检查变成**真**失败。故修复核验器后以 v04 重冻结重跑，让修复后的核验器进入新的源码清单，散列链保持完整。

修复内容：三个条目改为正向命名 `..._not_imported`；取值改为运行时读取 `sys.modules` 实测；汇总恢复为 `all(integrity.values())`；新增类型闸拒绝非布尔条目；新增 2 项回归守护测试。

## 本目录为何完整保留

`independent_verification.json` 是上述缺陷的**证据**，不得删除。v03 的结果、目视、核验三个目录一并原样保留。

## 权威文档

- 结案记录：`docs/plans/2026-08-05-id23-joint-parameter-process-noise-switch-confirmation-closure.md`
- 设计文档（v01→v04 沿革）：`docs/plans/2026-08-05-id23-joint-parameter-process-noise-switch-confirmation-design.md`
- 登记表：`src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`（行 `..._v03` 状态为 `superseded`）
