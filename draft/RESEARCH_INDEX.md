# Research Index

本文件是当前所有研究任务的统一入口，按任务编号隔离维护。

## 论文主线（2026-02 评估后）

- **主力 1（精力 70%）**: ID 07 HydroAgent → 3 篇论文（诊断框架 / 自动建模环境 / Agent 旗舰）
- **主力 2（精力 30%）**: ID 41 MTS-Mamba Global Transfer → 1 篇 WRR 级论文
  - 依赖 ID 01（全球预训练权重）
  - 吸收 ID 02（CAMELS-US 日尺度对比）、ID 03（小时级 baseline）、ID 06（海河迁移 case study）、ID 99（全球小时模型概念）

详见 `draft/IDEA_EVALUATION_2026_02.md`。

## 任务总表

| ID | Name | Status | Idea Doc | Code Root | Results Root | Logs Root |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 01 | caravan_global | in_progress | `draft/ideas/01_caravan_global.md` | `src/caravan_global/` | `results/01_caravan_global/` | `logs/01_caravan_global/` |
| 02 | mamba_camels_us | **archived** | `draft/ideas/02_mamba_camels_us.md` | `src/mamba_camels_us/` | `results/02_mamba_camels_us/` | `logs/02_mamba_camels_us/` |
| 03 | mamba_camelsh | **subsumed_by_41** | `draft/ideas/03_mamba_camelsh.md` | `src/mamba_camelsh/` | `results/03_mamba_camelsh/` | `logs/03_mamba_camelsh/` |
| 04 | namou_kuwei | done | `draft/ideas/04_namou_kuwei.md` | `src/namou_kuwei/` | `results/04_namou_kuwei/` | `logs/04_namou_kuwei/` |
| 05 | full_531_basins | **archived** | `draft/ideas/05_full_531_basins.md` | `src/full_531_basins/` | `results/05_full_531_basins/` | `logs/05_full_531_basins/` |
| 06 | haihe_river | **subsumed_by_41** | `draft/ideas/06_haihe_river.md` | `src/haihe_river/` | `results/06_haihe_river/` | `logs/06_haihe_river/` |
| 07 | hydroagent | dev | `draft/ideas/07_hydroagent.md` | `src/hydroagent/` | `results/07_hydroagent/` | `logs/07_hydroagent/` |
| 09 | regime_switching | **scoping** | `draft/ideas/09_regime_switching.md` | `src/regime_switching/` | `results/09_regime_switching/` | `logs/09_regime_switching/` |
| 41 | mts_mamba_global_transfer | in_progress | `draft/ideas/41_mts_mamba_global_transfer.md` | `src/mts_mamba_global_transfer/` | `results/41_mts_mamba_global_transfer/` | `logs/41_mts_mamba_global_transfer/` |

## 候选想法（未立项）

| ID | Name | Status | Idea Doc | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| 08 | tieling_da_failure_boundary | **parked** | *(待建)* | 铁岭三河 DL+数据同化"失效边界"复盘。查新后新颖性偏窄且红海（~60%），暂缓；应用/报奖价值高。查新见 `draft/LIT_REVIEW_2026_07_A/C/D_*.md`。若复活，须先人工核实 Saint-Fleur 2026、h-Diffusion 全文 |
| 99 | global_hourly_model | **merged_to_41** | `draft/ideas/99_global_hourly_model.md` | 已合并到 ID 41（MTS-Mamba），占位目录 `src/global_hourly_model/` 保留但不再活跃 |

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
