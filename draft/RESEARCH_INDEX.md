# Research Index

本文件是当前所有研究任务的统一入口，按任务编号隔离维护。

## 论文主线（2026-04-22 更新）

- **主力 1（精力 70%）**: ID 07 HydroAgent → 3 篇论文（诊断框架 / 自动建模环境 / Agent 旗舰）
- **主力 2**: 由战略主线 A/B1/C 承担（详见 memory `MEMORY.md`）：主线 A = ID 08 GWL Global；主线 B1 = ID 14 DML + Hypernetwork；主线 C = ID 11 Static Falsification。
  - ~~原主力 2 = ID 41 MTS-Mamba Global Transfer~~：2026-04-22 归档（Phase 2v2 empirical 输 MTSLSTM，且竞品已占位，详见 `draft/ideas/41_mts_mamba_global_transfer.md` 归档说明）。
  - ID 41 吸收过的 ID 01/02/03/06/99 也随之停滞：ID 01 已删除、ID 02/03 已归档、ID 06 已迁出 haihe 独立 repo、ID 99 已合并不再独立推进。
  - 核心模型 `neuralhydrology/modelzoo/mtsmamba.py` 保留在包里供后续任何 idea 作为 backbone 复用。

详见 `draft/IDEA_EVALUATION_2026_02.md`。

## 任务总表

| ID | Name | Status | Idea Doc | Code Root | Results Root | Logs Root |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 02 | mamba_camels_us | **archived** | `draft/ideas/02_mamba_camels_us.md` | `src/_archive/02_mamba_camels_us/` | `results/_archive/02_mamba_camels_us/` | `logs/_archive/02_mamba_camels_us/` |
| 03 | mamba_camelsh | **subsumed_by_41** | `draft/ideas/03_mamba_camelsh.md` | `src/_archive/03_mamba_camelsh/` | `results/_archive/03_mamba_camelsh/` | `logs/_archive/03_mamba_camelsh/` |
| 04 | namou_kuwei | done | `draft/ideas/04_namou_kuwei.md` | `src/namou_kuwei/` | `results/04_namou_kuwei/` | `logs/04_namou_kuwei/` |
| 05 | adversarial_robustness | active | `draft/ideas/05_adversarial_robustness.md` | `src/adversarial/` | `results/05_adversarial_robustness/` | `logs/05_adversarial_robustness/` |
| 07 | hydroagent | dev | `draft/ideas/07_hydroagent.md` | `src/hydroagent/` | `results/07_hydroagent/` | `logs/07_hydroagent/` |
| 08 | gwl_global | dev | `draft/ideas/08_gwl_global.md` | `src/gwl_global/` | `results/08_gwl_global/` | `logs/08_gwl_global/` |
| 10 | global_conceptual_model_benchmark | in_progress | `draft/ideas/10_global_conceptual_model_benchmark.md` | `src/xaj_global_pilot/`、`src/hbv_camels_us_531/` | `results/10_global_conceptual_model_benchmark/`、`results/10_xaj_global_pilot/`、`results/10_hbv_camels_us_531/` | `logs/10_hbv_camels_us_531/` |
| 11 | static_falsification | in_progress | `draft/ideas/11_static_falsification.md` | `src/static_falsification/` | `results/11_static_falsification/` (待生成) | `logs/11_static_falsification/` (待生成) |
| 14 | method_dml | poc | `draft/ideas/14_method_dml.md` | `src/method_dml/` | `results/14_method_dml/` (待生成) | `logs/14_method_dml/` (待生成) |
| 15 | spatial_routing_discovery | **archived** | `draft/ideas/15_spatial_routing_discovery.md` | `src/_archive/15_spatial_routing_discovery/` | — | — |
| 41 | mts_mamba_global_transfer | **archived** | `draft/ideas/41_mts_mamba_global_transfer.md` | `src/_archive/41_mts_mamba_global_transfer/` | `results/_archive/41_mts_mamba_global_transfer/` | `logs/_archive/41_mts_mamba_global_transfer/` |

## 候选想法（未立项）

| ID | Name | Status | Idea Doc | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| 12 | fsoi_driven_da | **brainstorm_done** | `draft/ideas/12_fsoi_driven_da.md` | FSOI 驱动的自适应 DA：Q 调优 + IMM + 在线质控，20 个子 idea，4 篇论文规划 |
| 13 | tango | **paused** | `draft/ideas/13_tango.md` | TANGO (Time-Alternating Neural-Geophysical Operator)，架构验证完成但 empirical 优势不足，代码在 `src/scl_hydro/` |
| 16 | pretrained_lstm_knowledge_separation | **design** | `draft/ideas/16_pretrained_lstm_knowledge_separation.md` | Pretrained LSTM 知识可分离性实验（头/嵌入/LSTM/全 finetune × 低/高分布偏移），复用 ID 05 的 531 basin 预训练权重。代码 `src/pretrained_lstm_knowledge_separation/`、结果 `results/16_pretrained_lstm_knowledge_separation/` |
| 99 | global_hourly_model | **merged_to_41** | `draft/ideas/99_global_hourly_model.md` | 已合并到 ID 41（MTS-Mamba），占位目录 `src/global_hourly_model/` 已于 2026-04-19 删除（git 历史可取回） |

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
