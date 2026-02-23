# 99 - Global Hourly Model (Candidate Idea)

**状态**: merged_to_41
**创建日期**: 2026-01-13
**最后更新**: 2026-02-23

> **合并说明（2026-02-23）**: 经 idea 重新评估，本概念与 ID 41（MTS-Mamba Global Transfer）高度重叠，已合并到 ID 41。占位目录 `src/global_hourly_model/` 保留但不再活跃。详见 `draft/IDEA_EVALUATION_2026_02.md`。

---

## 研究目标

探索“全球日尺度预训练 + 小时尺度迁移”的统一框架，构建可跨区域泛化的小时级流量预报模型。

---

## 与现有任务关系

- 依赖 `01_caravan_global` 的全球日尺度预训练结果。
- 方法上与 `mts_mamba_global_transfer` 高度相关。
- 已创建占位代码目录：`src/global_hourly_model/`（当前仅保留配置骨架）。
- 若正式立项，补齐独立结果与日志目录（`results/99_global_hourly_model/`、`logs/99_global_hourly_model/`）。

---

## 当前状态

- 仅为候选想法，尚未进入正式执行阶段。
- 当前仓库中已有占位代码目录 `src/global_hourly_model/`，但尚无稳定训练脚本与实验产物。
- 尚未创建独立结果与日志目录。
- 暂不纳入活跃任务（01-07, 41）的执行和验收范围。

---

## 立项前置条件

1. `01_caravan_global` 产出稳定可复现的日尺度预训练权重。
2. `mts_mamba_global_transfer` 完成最小可训练的跨频率骨架验证。
3. 明确小时级目标数据源与评估指标（峰值误差、时移误差、NSE/KGE 等）。

---

## 备注

本文件用于保留想法和后续立项入口；正式启动后，应迁移为完整的 Idea 文档模板（Isolation Scope / Code Index / Results Index / Progress Log）。
