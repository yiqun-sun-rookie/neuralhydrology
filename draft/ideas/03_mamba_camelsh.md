# 03 - Mamba CAMELSH Hourly

**状态**: in_progress
**创建日期**: 2026-01-05
**最后更新**: 2026-02-10

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
| Legacy Configs | `src/mamba_camelsh/configs/legacy/` | 旧配置 (从 experiments/camelsh/ 迁入) |
| Basin Lists | `src/mamba_camelsh/data/` | 训练用流域列表 |
| HPC Scripts | `src/mamba_camelsh/hpc/` | SLURM 提交脚本 |

---

## Results Index

| Run ID | Date | Output Path | Notes |
| :--- | :--- | :--- | :--- |
| camelsh_v2_more_data | 2025-12-04 | - | LSTM 基线: Val NSE=0.587, Test NSE=0.558 (455 basins) |
| camelsh_mamba_tiny | 2026-01-05 | - | Mamba 验证: NSE=0.149 (50 basins, 1 epoch, CPU) |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
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
