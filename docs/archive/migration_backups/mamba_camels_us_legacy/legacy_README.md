# CAMELS-US Mamba 实验项目

本目录包含在 CAMELS-US 日尺度数据集上运行 Mamba 模型的所有配置和实验文件。

## 📁 目录结构

```
experiments/camels_us/
├── configs/
│   ├── mamba_daily.yml          # 全量实验配置（531 流域，30 epochs）
│   ├── mamba_daily_mini.yml     # Mini Benchmark（50 流域，2 epochs）
│   └── mamba_daily_quick.yml    # 快速验证配置（100 流域，5 epochs）
├── data/
│   ├── 531_basin_list.txt       # 531 个流域列表
│   ├── 100_basin_list.txt       # 100 个流域列表
│   └── 50_basin_list.txt        # 50 个流域列表
└── README.md                     # 本文件
```

## 🚀 快速开始

### 推荐：快速验证实验（1-2 天）
```bash
nh-run train --config-file experiments/camels_us/configs/mamba_daily_quick.yml
```

### 全量实验（预计 120+ 天，不推荐）
```bash
nh-run train --config-file experiments/camels_us/configs/mamba_daily.yml
```

## 📊 实验结果

详细实验结果请参考主文档：`docs/experiments/MAMBA_CAMELS_US_EXPERIMENT.md`

## ⚠️ 注意事项

1. **训练速度**: Hugging Face Mamba sequential implementation 速度很慢，建议先运行快速验证
2. **Windows 兼容性**: 验证阶段存在 tqdm 兼容性问题
3. **GPU 显存**: 建议 batch_size ≤ 64

## 📝 相关文档

- 主实验文档: `docs/experiments/MAMBA_CAMELS_US_EXPERIMENT.md`
- 数据使用指南: `docs/DATA_USAGE_GUIDE.md`
