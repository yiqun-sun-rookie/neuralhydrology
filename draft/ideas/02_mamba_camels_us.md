# 02 - Mamba CAMELS-US Daily

**状态**: archived
**创建日期**: 2025-12-29
**最后更新**: 2026-02-23

> **归档说明（2026-02-23）**: 经 idea 重新评估，Mamba 在 CAMELS-US 日尺度的 benchmark 已被多篇文献覆盖（Demiray & Demir 2025、LightMamba 2024 等），无独立发表价值。工作量和实验资产已被 ID 41（MTS-Mamba Global Transfer）吸收。详见 `draft/IDEA_EVALUATION_2026_02.md`。

---

## 研究目标

在标准 CAMELS-US 日尺度数据集 (531 流域) 上验证 Mamba (State Space Model) 性能，与 LSTM 基准 (NSE ~0.74) 公平对比，证明 Mamba 在标准水文任务上是否达到或超过 State-of-the-Art。验证成功后将推广至全球 Caravan 数据集 (衔接 ID 01)。

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/mamba_camels_us/` | 配置、脚本、basin lists |
| Results | `results/02_mamba_camels_us/` | 训练输出、图表 |
| Logs | `logs/02_mamba_camels_us/` | SLURM/训练日志 |
| Docs | `draft/ideas/02_mamba_camels_us.md` | 本文档 |
| Index | `draft/RESEARCH_INDEX.md` | 主索引 |

---

## 核心配置

| 参数 | 值 |
|------|-----|
| 数据集 | CAMELS-US (日尺度) |
| 模型 | Mamba (HF transformers 后端) |
| Basin Count | 531 / 100 / 50 (全量/快速/mini) |
| Epochs | 30 / 5 / 2 |
| Batch Size | 64 |
| Seq Length | 365 |
| Hidden Size | 128 |
| Mamba Config | d_state=16, d_conv=4, expand=2, n_layers=2 |

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| Model | `neuralhydrology/modelzoo/mamba.py` | Mamba 模型实现 (核心包，非本任务独占) |
| Config (full) | `src/mamba_camels_us/configs/mamba_daily.yml` | 全量 531 流域配置 |
| Config (quick) | `src/mamba_camels_us/configs/mamba_daily_quick.yml` | 快速验证 100 流域配置 |
| Config (mini) | `src/mamba_camels_us/configs/mamba_daily_mini.yml` | Mini benchmark 50 流域配置 |
| Config (smoke) | `src/mamba_camels_us/configs/mamba_daily_smoke_2basins_ep1.yml` | 本地最小训练验证（2 basins, 1 epoch） |
| Config (smoke 10x3) | `src/mamba_camels_us/configs/mamba_daily_smoke_10basins_ep3.yml` | 本地增强 smoke 验证（10 basins, 3 epochs） |
| Basin List (531) | `src/mamba_camels_us/data/531_basin_list.txt` | 全量流域列表 |
| Basin List (100) | `src/mamba_camels_us/data/100_basin_list.txt` | 快速验证流域列表 |
| Basin List (50) | `src/mamba_camels_us/data/50_basin_list.txt` | Mini 流域列表 |
| Basin List (smoke) | `src/mamba_camels_us/data/smoke_2_basins.txt` | smoke 配置用 basin 列表 |
| Basin List (smoke 10) | `src/mamba_camels_us/data/smoke_10_basins.txt` | 10-basin smoke 配置用 basin 列表 |

---

## Results Index

| Run ID | Date | Output Path | Notes |
| :--- | :--- | :--- | :--- |
| mamba_daily_smoke_2basins_ep1_2026_0219_1649_ep1 | 2026-02-19 | `results/02_mamba_camels_us/mamba_daily_smoke_2basins_ep1_2026_0219_1649_ep1/` | 本地 CPU smoke 复验通过: NSE=0.05126, KGE=0.15290（Mamba fallback backend） |
| mamba_daily_smoke_10basins_ep3_2026_0218_1747_ep3 | 2026-02-18 | `results/02_mamba_camels_us/mamba_daily_smoke_10basins_ep3_2026_0218_1747_ep3/` | 本地 CPU smoke 完成: 10 basins/3 epochs, NSE=0.45637, KGE=0.48290 |
| mamba_daily_smoke_2basins_ep1_2026_0218_1142_ep1 | 2026-02-18 | `results/02_mamba_camels_us/mamba_daily_smoke_2basins_ep1_2026_0218_1142_ep1/` | 本地 CPU smoke 完成: NSE=0.05126, KGE=0.15290 |
| mamba_daily_mini_2026_0103 | 2026-01-03 | `results/02_mamba_camels_us/runs/mamba_daily_mini_2026_0103_1750_ep2/` | Mini 成功: NSE=0.396 (2 epochs) |
| mamba_daily_benchmark_2026_0105 | 2026-01-05 | `results/02_mamba_camels_us/runs/mamba_daily_benchmark_2026_0105_2150_ep30/` | Epoch 1 完成 (loss=0.031), 验证失败 (tqdm) |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2026-02-19 | 本地 smoke 复验通过 | 2 basins / 1 epoch / CPU 训练再次跑通，结果写入 `results/02_mamba_camels_us/mamba_daily_smoke_2basins_ep1_2026_0219_1649_ep1/` |
| 2026-02-18 | 本地增强 smoke 验证通过 | 10 basins / 3 epochs / CPU 训练完成，验证指标 NSE=0.45637, KGE=0.48290 |
| 2026-02-18 | 本地 smoke 验证通过 | 2 basins / 1 epoch / CPU 训练完成，确认路径与编码修复有效 |
| 2025-12-29 | 项目启动 | 创建实验配置和文档 |
| 2026-01-03 | Mini Benchmark 成功 | 50 流域 2 epochs, NSE=0.396，代码通路验证通过 |
| 2026-01-05 | 全量训练启动 | 531 流域 30 epochs, 但每 epoch 需 4+ 天 (HF sequential) |
| 2026-01-09 | 全量训练中断 | Epoch 1 完成 (loss=0.031) 但验证阶段 tqdm Windows 报错 |
| 2026-01-09 | 迁移 HPC | 创建 HPC SLURM 脚本; 需安装 mamba-ssm CUDA kernel 加速 |
| 2026-02-10 | 目录隔离 | 从 experiments/camels_us/ 迁移到 src/mamba_camels_us/ |

---

## 已知问题

- **速度瓶颈**: HF Mamba sequential implementation 极慢 (每 epoch 4+ 天)，需安装 `mamba-ssm` CUDA kernel
- **Windows tqdm**: 验证阶段 `OSError: [Errno 22]`，已在 `evaluation/tester.py` 中修复
- **检查点策略**: 建议改为每 epoch 保存

---

## 下一步

1. 在 HPC 安装 `mamba-ssm` CUDA kernel 以加速 10-50x
2. 运行快速验证 (100 流域, 5 epochs) 确认性能趋势
3. 完成全量对比: Mamba vs LSTM (531 流域, 30 epochs)
4. 成功后衔接 ID 01 (Caravan 全球推广)

### 本地最小 smoke（可复现）

```bash
python -m neuralhydrology.nh_run train --config-file src/mamba_camels_us/configs/mamba_daily_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/mamba_camels_us/configs/mamba_daily_smoke_10basins_ep3.yml --gpu -1
```
