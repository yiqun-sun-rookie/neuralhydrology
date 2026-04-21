# Idea 14: DML for Hydrology

**状态**: poc
**创建日期**: 2026-04-13
**最后更新**: 2026-04-19
**战略主线**: 主线 B1 ★★★（外领域方法引入水文）

---

## 核心问题

能否将 Double Machine Learning（Chernozhukov et al. 2018）方法引入水文归因分析，为"某气候变量/人为活动对径流/地下水的因果效应"提供无偏估计？

## 决策目标

一周 POC，产出 go/no-go 决策：是否投入 2–3 个月做"DML for Hydrology"论文。

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/method_dml/` | POC 代码（baselines / benchmark / dgp / real_camels） |
| Results | `results/14_method_dml/` | 待生成 |
| Logs | `logs/14_method_dml/` | 待生成 |
| Spec | `docs/superpowers/specs/2026-04-13-dml-hydrology-poc.md` | 授权规范 |
| Memory | `method_dml_for_hydrology.md`、`external_methods_import.md` | 相关记忆 |

---

## 关键参考

- **DML 原论文**: Chernozhukov et al. 2018, *Econometrics Journal*, DOI:10.1111/ectj.12097
- **水文先例（唯一，截至 2026-04-13）**: Sun et al. 2025, *Water Research*, Hong Kong 近海水质

---

## 进度记录

- 2026-04-13: POC 立项，spec 完成
- 2026-04-19: 代码未纳入 git，待一周 POC 产出 go/no-go 后决定是否 commit
