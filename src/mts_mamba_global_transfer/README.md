# mts_mamba_global_transfer

本目录是“本对话任务”的唯一代码入口，用于隔离 HPC 迁移与 MTS-Mamba 全球迁移学习相关资产。

## 目录约定

- `configs/`: 本任务专用配置
- `hpc/`: 本任务专用 HPC 脚本
- `results/mts_mamba_global_transfer/`: 本任务结果目录
- `logs/mts_mamba_global_transfer/`: 本任务日志目录

## Smoke 测试配置

`configs/caravan_daily_smoke_*.yml` 和 `data/smoke_*_basins.txt` 与 `src/caravan_global/` 中的同名文件共享相同的 basin 列表和模型参数，仅 `experiment_name`、`run_dir`、`basin_file` 路径不同。主来源为 `caravan_global`，本处副本用于本任务的独立 smoke 测试。

## 使用原则

1. 本任务新增脚本/配置只放在 `src/mts_mamba_global_transfer/`。
2. 运行输出只写入 `results/mts_mamba_global_transfer/`。
3. 日志只写入 `logs/mts_mamba_global_transfer/`。
4. 历史根目录 `hpc/`、`configs/` 中同名文件视为参考，不再作为本任务主入口。

## 执行入口

```bash
sed -i 's/\r$//' src/mts_mamba_global_transfer/hpc/*.slurm
sbatch src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm
```
