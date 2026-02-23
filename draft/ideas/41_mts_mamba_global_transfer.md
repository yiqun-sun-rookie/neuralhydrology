# 41 - MTS-Mamba Global Transfer

**状态**: in_progress
**创建日期**: 2026-01-06
**最后更新**: 2026-02-23

> **整合说明（2026-02-23）**: 经 idea 重新评估，本 idea 成为 Mamba 研究主线的核心论文（WRR 级别）。已吸收以下 idea：
> - ID 02（mamba_camels_us）→ 归档，CAMELS-US 日尺度对比实验资产并入
> - ID 03（mamba_camelsh）→ 降格为本 idea 的小时级 LSTM baseline / Mamba fine-tuning target
> - ID 06（haihe_river）→ 降格为本 idea 的 data-scarce transfer case study
> - ID 99（global_hourly_model）→ 概念合并，不再独立推进
>
> 详见 `draft/IDEA_EVALUATION_2026_02.md`。

---

## 对话目的（最新）

围绕”MTS-Mamba 全球迁移学习”主线，完成三件事：

1. 将大规模训练从本地迁移到河海大学 HPC，解决算力与内存瓶颈；
2. 沉淀本对话遇到的 HPC 坑位及可复用解法；
3. 按项目规则将本任务代码、结果、日志和文档与其他任务隔离。

---

## Isolation Scope

| 类型 | 旧路径（历史） | 新路径（本任务唯一入口） | 说明 |
| :--- | :--- | :--- | :--- |
| Task Code | `common/`, `configs/caravan/`, `upload_to_hpc.ps1` | `src/mts_mamba_global_transfer/` | 本任务后续以 `src/mts_mamba_global_transfer/` 为准 |
| Task Results | `runs/`, `results/` | `results/41_mts_mamba_global_transfer/` | 本任务输出统一落盘 |
| Task Logs | `logs/` | `logs/41_mts_mamba_global_transfer/` | 本任务日志单独归档 |
| Task Docs | `TRAINING_PROGRESS.md`, `docs/technical/*` | 当前文档 + `src/mts_mamba_global_transfer/README.md` | 本任务上下文集中管理 |

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| Package Root | `src/mts_mamba_global_transfer/__init__.py` | 任务包入口 |
| Task Readme | `src/mts_mamba_global_transfer/README.md` | 本任务目录约定与执行入口 |
| HPC Setup | `src/mts_mamba_global_transfer/hpc/setup_hpc_env.sh` | 本任务 HPC 环境初始化脚本（UTF-8） |
| SLURM Submit | `src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm` | 本任务专用提交脚本 |
| Task Config | `src/mts_mamba_global_transfer/configs/caravan_daily_basemodel_hpc.yml` | 本任务训练配置 |
| Smoke Config | `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_2basins_ep1.yml` | 本地最小训练验证（2 basins, 1 epoch） |
| Smoke Basins | `src/mts_mamba_global_transfer/data/smoke_2_basins.txt` | smoke 配置用 basin 列表 |
| Smoke Config (10x3) | `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_10basins_ep3.yml` | 本地增强 smoke 验证（10 basins, 3 epochs） |
| Smoke Basins (10) | `src/mts_mamba_global_transfer/data/smoke_10_basins.txt` | 10-basin smoke 配置用 basin 列表 |

---

## Results Index

| Run ID | Date | Output Path | Notes |
| :--- | :--- | :--- | :--- |
| 41_caravan_daily_smoke_10basins_ep3_2026_0218_1802_ep3 | 2026-02-18 | `results/41_mts_mamba_global_transfer/41_caravan_daily_smoke_10basins_ep3_2026_0218_1802_ep3/` | 本地 CPU smoke 完成（10 basins, 3 epochs）: NSE=0.57383, KGE=0.52536 |
| 41_caravan_daily_smoke_2basins_ep1_2026_0218_1256_ep1 | 2026-02-18 | `results/41_mts_mamba_global_transfer/41_caravan_daily_smoke_2basins_ep1_2026_0218_1256_ep1/` | 本地 CPU smoke 训练完成（2 basins, 1 epoch） |
| caravan_global_hpc_v1 | 2026-01-06 | `results/41_mts_mamba_global_transfer/` | 本任务独立结果目录（待写入） |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2026-02-18 | 本地增强 smoke 验证通过 | 使用 `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_10basins_ep3.yml` 在 CPU 上完成 10 basins/3 epochs，验证指标 NSE=0.57383, KGE=0.52536 |
| 2026-02-18 | 本地 smoke 验证通过 | 使用 `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_2basins_ep1.yml` 在 CPU 上完成 2 basins/1 epoch，验证指标 NSE=0.44622, KGE=0.50352 |
| 2026-01-06 | 任务隔离初始化 | 建立 `draft/RESEARCH_INDEX.md` 与 `41` 任务专属目录 |
| 2026-01-06 | 对话产物归档 | 将 HPC 相关代码、配置、文档映射到 `src/mts_mamba_global_transfer/`、`results/41_mts_mamba_global_transfer/`、`logs/41_mts_mamba_global_transfer/` |
| 2026-01-06 | 规则对齐 | 对齐 `.cursor/00-project-structure.mdc` 与 `.cursor/10-hpc-workflow.mdc` 的隔离要求 |
| 2026-01-06 | HPC 经验沉淀 | 将本任务的 HPC 坑位与解决方案归档到仓库内文档体系 |

---

## 当前执行入口

```bash
# 提交本任务作业（在 HPC 上）
sed -i 's/\r$//' src/mts_mamba_global_transfer/hpc/*.slurm
sbatch src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm
```

### 本地最小 smoke（可复现）

```bash
python -m neuralhydrology.nh_run train --config-file src/mts_mamba_global_transfer/configs/caravan_daily_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/mts_mamba_global_transfer/configs/caravan_daily_smoke_10basins_ep3.yml --gpu -1
```

---

## 对话成果（代码 / 结果 / 文档）

### 代码资产

- `src/mts_mamba_global_transfer/configs/caravan_daily_basemodel_hpc.yml`
- `src/mts_mamba_global_transfer/hpc/setup_hpc_env.sh`
- `src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm`
- `src/mts_mamba_global_transfer/hpc/upload_to_hpc.ps1`

### 结果与日志资产

- `results/41_mts_mamba_global_transfer/41_caravan_daily_smoke_2basins_ep1_2026_0219_1716_ep1/`
- 本地 smoke 验证指标（2026-02-19）：`NSE=0.44622`, `KGE=0.50352`
- `logs/41_mts_mamba_global_transfer/`（HPC 作业日志目录，仍可用于后续集群运行）

### 文档资产

- 本任务主文档：`draft/ideas/41_mts_mamba_global_transfer.md`
- 任务总入口：`draft/RESEARCH_INDEX.md`
- 计划文档：`.cursor/plans/mts-mamba全球迁移学习聚焦计划_41f8c99e.plan.md`

---

## 已识别并解决的 HPC 坑（摘要）

1. **本地 OOM**：32GB 无法承载 Caravan 全流域加载 -> 切换 HPC，申请 128GB+ 内存。
2. **SSH 登录限制**：密码 + OTP 使非交互登录困难 -> 使用外部原生 CMD 手动 SSH。
3. **终端兼容性**：集成终端与交互菜单不兼容（`TERM ERROR`/`Connection closed`）-> 外部 CMD 登录。
4. **大文件传输**：数据量大 -> 本地压缩后 `scp` 上传，HPC 端解压。
5. **调度规范**：禁止登录节点直跑 -> 统一通过 `sbatch` 提交 Slurm 脚本。

---

## 下一步计划（可直接执行）

1. 登录 HPC 检查最近一次 Caravan 作业的状态、日志、权重。
2. 修复 Mamba 在 Windows/HPC 的兼容性问题（tqdm、CUDA kernel）。
3. 在 `neuralhydrology/modelzoo/mtsmamba.py` 搭建最小可训练版本。
4. 实现 Mamba 跨频率状态传递（Daily -> Hourly）。
5. 先跑 CAMELS-US mini 烟雾测试，再跑全量对比实验。
6. 执行 US -> GB/AUS 迁移验证，整理论文图表与指标。

---

## 最终目标（论文）

验证并证明：**MTS-Mamba + Caravan 全球日预训练** 可在小时级洪水预报上优于 MTS-LSTM，尤其在洪峰时间与洪水形态刻画上更优，并具备跨区域泛化能力（US -> GB/AUS）。

---

## 新对话一键接手提示

复制下面内容即可开启下一次会话：

```text
继续任务 mts_mamba_global_transfer。
先做三件事：
1) 登录 HPC 检查最近一次 Caravan 作业的完成状态，并汇总关键日志；
2) 在 neuralhydrology/modelzoo/mtsmamba.py 创建最小可训练模型骨架；
3) 给出 CAMELS-US mini 的可运行命令和结果输出路径。
要求：仅使用 src/mts_mamba_global_transfer、results/41_mts_mamba_global_transfer、logs/41_mts_mamba_global_transfer 作为任务路径。
```
