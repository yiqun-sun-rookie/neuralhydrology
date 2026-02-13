# Caravan 流域数据可用性报告

## 概述

基于 HPC 训练日志 (Job 154574) 的分析结果。

| 类别 | 数量 |
|------|------|
| **原始流域总数** | 7,129 |
| **无效流域数** | 1,404 |
| **有效流域数** | **5,725** |

## 无效流域分布

| 数据集 | 无效数量 | 说明 |
|--------|----------|------|
| hysets | 1,310 | 加拿大/美国水文数据集，部分站点观测时间较短 |
| camelscl | 56 | 智利 CAMELS，部分站点数据起始较晚 |
| lamah | 38 | 欧洲 LamaH，部分站点数据不完整 |
| **总计** | **1,404** | |

## 无效原因

这些流域在训练期间 (1981-2005) 没有有效的 streamflow 数据：

1. **观测站建站较晚** - 很多 HYSETS 站点在 1990 年代甚至 2000 年后才开始观测
2. **数据记录中断** - 部分站点有长期数据缺失
3. **序列长度不足** - 需要至少 365 天连续数据用于训练

## 有效流域数据集分布 (估计)

基于 Caravan 数据集结构，有效流域主要来自：

| 数据集 | 预计有效数量 | 地区 |
|--------|-------------|------|
| camels_us | ~670 | 美国 |
| camels_aus | ~220 | 澳大利亚 |
| camels_br | ~890 | 巴西 |
| camels_gb | ~670 | 英国 |
| camels_cl | ~460 | 智利 |
| hysets | ~2,500 | 加拿大/美国 |
| lamah | ~820 | 欧洲 |
| **总计** | **~5,725** | |

## 使用说明

1. 将代码同步到 HPC
2. 运行过滤脚本生成 valid_basins.txt:
   ```bash
   python src/caravan_global/scripts/filter_basins.py
   ```
3. 或运行全面检查（推荐，更准确）:
   ```bash
   python src/caravan_global/scripts/check_basin_availability.py
   ```
4. 提交训练作业:
   ```bash
   sbatch src/caravan_global/hpc/submit_caravan.slurm
   ```

## 文件清单

```
src/caravan_global/
├── configs/
│   └── caravan_hpc.yml          # 训练配置（已更新使用 valid_basins.txt）
├── data/
│   ├── invalid_basins.txt       # 1404 个无效流域列表
│   └── basin_summary.md         # 本报告
├── hpc/
│   └── submit_caravan.slurm     # SLURM 作业脚本
└── scripts/
    ├── filter_basins.py         # 简单过滤脚本
    └── check_basin_availability.py  # 全面检查脚本
```

---
生成时间: 2026-01-27
