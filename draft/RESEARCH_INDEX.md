# Research Index

本文件是当前所有研究任务的统一入口，按任务编号隔离维护。

## Mamba 研究主线

- **路线1**: ID 02 (日尺度CAMELS-US验证) → ID 01 (Caravan全球推广)
- **路线2**: ID 03 (小时尺度CAMELSH Mamba)
- **路线3**: ID 41 (MTS-Mamba, 日+小时多尺度融合迁移学习)

## 任务总表

| ID | Name | Status | Idea Doc | Code Root | Results Root | Logs Root |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 01 | caravan_global | in_progress | `draft/ideas/01_caravan_global.md` | `src/caravan_global/` | `results/01_caravan_global/` | `logs/01_caravan_global/` |
| 02 | mamba_camels_us | in_progress | `draft/ideas/02_mamba_camels_us.md` | `src/mamba_camels_us/` | `results/02_mamba_camels_us/` | `logs/02_mamba_camels_us/` |
| 03 | mamba_camelsh | in_progress | `draft/ideas/03_mamba_camelsh.md` | `src/mamba_camelsh/` | `results/03_mamba_camelsh/` | `logs/03_mamba_camelsh/` |
| 04 | namou_kuwei | completed | `draft/ideas/04_namou_kuwei.md` | `src/namou_kuwei/` | `results/04_namou_kuwei/` | `logs/04_namou_kuwei/` |
| 05 | full_531_basins | active | `draft/ideas/05_full_531_basins.md` | `src/full_531_basins/` | `results/05_full_531_basins/` | `logs/05_full_531_basins/` |
| 06 | haihe_river | data_prep | `draft/ideas/06_haihe_river.md` | `src/haihe_river/` | `results/06_haihe_river/` | `logs/06_haihe_river/` |
| 07 | hydroagent | dev | `draft/ideas/07_hydroagent.md` | `src/hydroagent/` | `results/07_hydroagent/` | `logs/07_hydroagent/` |
| 41 | mts_mamba_global_transfer | in_progress | `draft/ideas/mts_mamba_global_transfer.md` | `src/mts_mamba_global_transfer/` | `results/mts_mamba_global_transfer/` | `logs/mts_mamba_global_transfer/` |

## 候选想法（未立项）

| ID | Name | Status | Idea Doc | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| 99 | global_hourly_model | concept_draft | `draft/ideas/99_global_hourly_model.md` | 候选方案，已有占位代码目录 `src/global_hourly_model/`，结果/日志目录尚未创建 |

## 共享目录（非单一 Idea）

- 顶层 `scripts/` 已移除；请直接使用 `src/<idea>/scripts/`
- `common/`：跨 idea 的共享 HPC 工具；idea 专属脚本放 `src/<idea>/hpc/`
- `test/`：`neuralhydrology/` 核心包测试目录（单元/集成测试）
- `src/test_data/`：轻量测试数据与 quick smoke 配置（跨 idea 共用）
- `runs/`：临时运行输出中转目录，长期产物应归档到 `results/<ID>_<slug>/`
- `external/`：本地外部资源与备份（默认不纳入 Git）
- `examples/`：教程与演示，不作为 `src/` 生产配置依赖

## 快速验证入口

- Smoke 命令总览：`docs/guides/README_smoke.md`
