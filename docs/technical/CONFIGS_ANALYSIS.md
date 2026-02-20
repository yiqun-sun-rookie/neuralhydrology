# Configs 目录分析报告

## 当前规则
- 配置文件按 idea 统一放在 `src/<idea>/configs/`。
- 根目录 `configs/` 仅保留索引说明，不再作为主配置来源。

## Canonical 配置位置
- `01_caravan_global`: `src/caravan_global/configs/`
- `02_mamba_camels_us`: `src/mamba_camels_us/configs/`
- `03_mamba_camelsh`: `src/mamba_camelsh/configs/`
- `04_namou_kuwei`: `src/namou_kuwei/configs/`
- `05_full_531_basins`: `src/full_531_basins/configs/`
- `06_haihe_river`: `src/haihe_river/configs/`
- `07_hydroagent`: `src/hydroagent/configs/`
- `mts_mamba_global_transfer`: `src/mts_mamba_global_transfer/configs/`
- `99_global_hourly_model`: `src/global_hourly_model/configs/`

## 05 Full 531 当前主配置
- 推荐训练配置: `src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml`
- 对照配置: `src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_norm_base.yml`
- basin split:
- `src/full_531_basins/configs/camels_us/data_splits/531_basins_train_basins.txt`
- `src/full_531_basins/configs/camels_us/data_splits/531_basins_val_basins.txt`
- `src/full_531_basins/configs/camels_us/data_splits/531_basins_test_basins.txt`
- 快速测试 split:
- `src/full_531_basins/configs/camels_us/data_splits/1_basin.txt`

## 迁移状态
- 已将 legacy 的 `camels_us` / `full_training` 配置同步到 `src/full_531_basins/configs/`。
- 已将 Nam Ou legacy 配置同步到 `src/namou_kuwei/configs/archive_legacy/`。
- 活跃脚本与指南已改为引用 `src/<idea>/configs/...` 路径。

