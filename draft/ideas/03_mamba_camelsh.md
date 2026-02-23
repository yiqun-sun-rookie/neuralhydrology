# 03 - Mamba CAMELSH Hourly

**状态**: subsumed_by_41
**创建日期**: 2026-01-05
**最后更新**: 2026-02-23

> **降格说明（2026-02-23）**: 经 idea 重新评估，"首个大规模小时级 Mamba 验证"已被 Demiray & Demir (2025) 和 RiverMamba (2025) 抢占，单纯 Mamba vs LSTM 小时级 benchmark 不够新。本 idea 降格为 ID 41（MTS-Mamba Global Transfer）的对照实验——提供小时级 LSTM baseline 和 Mamba fine-tuning target。代码和实验资产保留，后续作为 ID 41 论文的 baseline 组件使用。详见 `draft/IDEA_EVALUATION_2026_02.md`。

---

## 研究目标

将 Mamba (State Space Model) 应用于大规模小时级水文数据集 (CAMELS-H, 455+ 流域)，探索其在长序列建模和洪水峰值捕捉方面的优势。这是首个在大规模小时级水文数据集上验证 Mamba 模型的研究。

**核心研究问题**:
1. Mamba 在大规模小时级水文数据上的表现是否优于 LSTM?
2. Mamba 的长序列建模能力 (seq_length=3000+) 是否有助于小时级预报?
3. Mamba 在捕捉洪水峰值和快速响应过程方面是否更优?

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/mamba_camelsh/` | 配置、脚本、basin lists |
| Results | `results/03_mamba_camelsh/` | 训练输出、分析 |
| Logs | `logs/03_mamba_camelsh/` | SLURM/训练日志 |
| Docs | `draft/ideas/03_mamba_camelsh.md` | 本文档 |
| Index | `draft/RESEARCH_INDEX.md` | 主索引 |
| TASK_ISOLATION | `src/mamba_camelsh/TASK_ISOLATION.md` | 详细隔离规则 |

---

## 核心配置

| 参数 | 值 |
|------|-----|
| 数据集 | CAMELS-H (Hourly) |
| 模型 | Mamba / CUDA-LSTM (基线) |
| Basin Count | 455 (全量) / 50 (mini) |
| 时间划分 | Train: 2010-2014, Val: 2015-2017, Test: 2018-2020 |
| 动态输入 | 9 个 (Rainf, Tair, SWdown, LWdown, Qair, PSurf, Wind_E, Wind_N, PotEvap) |
| 静态属性 | 13 个 |
| 目标变量 | Streamflow |

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| Model | `neuralhydrology/modelzoo/mamba.py` | Mamba 模型实现 (核心包) |
| Config (Mamba mini) | `src/mamba_camelsh/configs/camelsh_mamba_mini.yml` | Mamba 50 流域 mini benchmark |
| Config (LSTM mini) | `src/mamba_camelsh/configs/camelsh_lstm_mini.yml` | LSTM 基线 mini benchmark |
| Config (smoke) | `src/mamba_camelsh/configs/camelsh_lstm_smoke_2basins_ep1.yml` | 本地最小训练验证（2 basins, 1 epoch） |
| Config (smoke 10x3) | `src/mamba_camelsh/configs/camelsh_lstm_smoke_10basins_ep3.yml` | 本地增强 smoke 验证（10 basins, 3 epochs） |
| Legacy Configs | `src/mamba_camelsh/configs/legacy/` | 旧配置 (从 experiments/camelsh/ 迁入) |
| Basin Lists | `src/mamba_camelsh/data/` | 训练用流域列表 |
| Basin List (smoke) | `src/mamba_camelsh/data/smoke_2_basins.txt` | smoke 配置用 basin 列表 |
| Basin List (smoke 10) | `src/mamba_camelsh/data/smoke_10_basins.txt` | 10-basin smoke 配置用 basin 列表 |
| HPC Scripts | `src/mamba_camelsh/hpc/` | SLURM 提交脚本 |

---

## Results Index

| Run ID | Date | Output Path | Notes |
| :--- | :--- | :--- | :--- |
| camelsh_lstm_smoke_2basins_ep1_2026_0219_1652_ep1 | 2026-02-19 | `results/03_mamba_camelsh/camelsh_lstm_smoke_2basins_ep1_2026_0219_1652_ep1/` | 本地 CPU smoke 复验通过: NSE=0.29982, KGE=0.41511 |
| camelsh_lstm_smoke_10basins_ep3_2026_0218_1748_ep3 | 2026-02-18 | `results/03_mamba_camelsh/camelsh_lstm_smoke_10basins_ep3_2026_0218_1748_ep3/` | 本地 CPU smoke 完成: 10 basins/3 epochs, NSE=0.29384, KGE=0.48640 |
| camelsh_lstm_smoke_2basins_ep1_2026_0218_1143_ep1 | 2026-02-18 | `results/03_mamba_camelsh/camelsh_lstm_smoke_2basins_ep1_2026_0218_1143_ep1/` | 本地 CPU smoke 完成: NSE=0.29982, KGE=0.41511 |
| camelsh_v2_more_data | 2025-12-04 | - | LSTM 基线: Val NSE=0.587, Test NSE=0.558 (455 basins) |
| camelsh_mamba_tiny | 2026-01-05 | - | Mamba 验证: NSE=0.149 (50 basins, 1 epoch, CPU) |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2026-02-19 | 本地 smoke 复验通过 | 2 basins / 1 epoch / CPU 训练再次跑通，结果写入 `results/03_mamba_camelsh/camelsh_lstm_smoke_2basins_ep1_2026_0219_1652_ep1/` |
| 2026-02-18 | 本地增强 smoke 验证通过 | 10 basins / 3 epochs / CPU 训练完成，验证指标 NSE=0.29384, KGE=0.48640（训练尾部残留进程已手动结束） |
| 2026-02-18 | 本地 smoke 验证通过 | 2 basins / 1 epoch / CPU 训练完成，确认重构后入口可用 |
| 2025-11-30 | LSTM 基线启动 | camelsh_hourly_opt 实验 |
| 2025-12-04 | LSTM 基线完成 | 455 basins, seq_len=336, Val NSE=0.587, Test NSE=0.558 |
| 2026-01-05 | Mamba 集成完成 | HF transformers 后端, 配置参数已添加 |
| 2026-01-05 | Mamba tiny test | 50 basins, 1 epoch, NSE=0.149 (代码通路验证通过) |
| 2026-01-09 | tqdm 修复 | 解决 Windows 验证阶段崩溃 |
| 2026-02-10 | 目录隔离 | 合并 experiments/camelsh/ 旧配置到 src/mamba_camelsh/ |

---

## 下一步

1. 完成 LSTM Mini Benchmark (50 basins, 10 epochs)
2. 完成 Mamba Mini Benchmark (50 basins, 10 epochs)
3. Mini 结果对比分析 (NSE, KGE, 训练时间, 内存)
4. 扩展到全规模 CAMELS-H (455 basins)
5. 超长序列测试 (seq_length=3000+)
6. 极端事件分析 (洪水峰值捕捉)

### 本地最小 smoke（可复现）

```bash
python -m neuralhydrology.nh_run train --config-file src/mamba_camelsh/configs/camelsh_lstm_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/mamba_camelsh/configs/camelsh_lstm_smoke_10basins_ep3.yml --gpu -1
```
