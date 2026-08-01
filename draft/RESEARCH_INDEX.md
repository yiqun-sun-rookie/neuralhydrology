# Research Index

本文件是当前所有研究任务的统一入口，按任务编号隔离维护。

## 论文主线（2026-04-22 更新 v2）

- **主力 1（精力 70%）**: ID 07 HydroAgent → 3 篇论文（诊断框架 / 自动建模环境 / Agent 旗舰）
  - **2026-07-23 效果合并判定（两条实验线均无正效果证据）**：
    - **纯概念线**（fair_*，15 河公平留出，CMA-ES 5000×3，repro_v01 + Priestley-Taylor PET）：AI 结构留出中位 **0.52 / 0.671**（剔 2 河数值发散），输传统模型 10/15、输 LSTM 13/15 → **干净的负结果**（样本内好、留出崩＝过拟合不泛化）。已双重独立验证。→ 原"退一步对比论文"方向 **PIVOT**。
    - **混合线**（screen_v02，12/72 单元后因内存不足停止，2 河 11 完整单元）：经两个互不通气的独立审计——55 个家族分数从原始 USGS 观测 **bit-exact 重算（误差 1e-13）、选择流程 11/11 无泄漏**（机械可信）；但存在 **PET≡0 数据 bug**（本仓 Maurer 强迫 Tmax==Tmin，Hargreaves 温差项 √(Tmax−Tmin)=0 → 蒸发输入恒为 0，砍掉所有物理 ET 通路）+ **LSTM 基线三重不对称**（预算集中 / 训练配方精调 / 无质量守恒约束）→ **架构级结论作废**（"测不出"，非"测出没效果"）。剩余 60 单元**不按原样跑**（污染协议上烧算力）。
    - **战略转向**：负结果不是死路，正是 **「可辨识性闸门」方法论文**的核心论据——无约束地让 AI 搜水文模型结构，要么过拟合不泛化（纯概念线），要么结构跨种子不复现（混合线）。让"效果"转正只有两条路：修混合线 bug 重跑（赌 <20% 翻盘）或给搜索加约束（闸门，主线方向）。
    - 证据与细节：memory `hydroagent_fair_comparison_pivot_20260722` / `hydroagent_screen_v02_audit_20260722`；混合线代码/结果在 worktree `.worktrees/hydroagent-compositional-discovery/`。
- **主力 2**: 由战略主线 A/B1 承担（详见 memory `MEMORY.md`）：
  - **主线 A** = ID 08 GWL Global（地下水 DL）
  - **主线 B1** = ID 14 DML（GWL 归因方法承载）+ **ID 17 Entity Awareness Falsification + Hypernet**（合并原 ID 11 证伪 + Hypernet 建设性回应）
  - ~~原主线 C（ID 11 Static Falsification）~~：2026-04-22 合并到 ID 17，不再独立存在。核心论点已被 Heudorfer 2024/2025 发表，单推只能 Letter；合并 Hypernet 后升级主刊 story（诊断 + 建设性回应）。
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
| 11 | static_falsification | **merged_to_17** | `draft/ideas/11_static_falsification.md` | `src/static_falsification/`（代码仍在，作为 ID 17 诊断层） | — | — |
| 14 | method_dml | poc | `draft/ideas/14_method_dml.md` | `src/method_dml/` | `results/14_method_dml/` (待生成) | `logs/14_method_dml/` (待生成) |
| 17 | entity_awareness_hypernet | **design** | `draft/ideas/17_entity_awareness_hypernet.md` | `src/static_falsification/`（诊断层）+ `src/method_hypernet/`（待建，Hypernet 层） | `results/17_entity_awareness_hypernet/` (待生成) | `logs/17_entity_awareness_hypernet/` (待生成) |
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
