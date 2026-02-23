# Code Index

项目已按研究任务统一到 `src/<project>/`、`results/<ID>_<project>/`、`logs/<ID>_<project>/`。

## 常用入口

| 任务 | 代码目录 | 结果目录 | 日志目录 |
|---|---|---|---|
| 01 Caravan Global | `src/caravan_global/` | `results/01_caravan_global/` | `logs/01_caravan_global/` |
| 02 Mamba CAMELS-US | `src/mamba_camels_us/` | `results/02_mamba_camels_us/` | `logs/02_mamba_camels_us/` |
| 03 Mamba CAMELSH | `src/mamba_camelsh/` | `results/03_mamba_camelsh/` | `logs/03_mamba_camelsh/` |
| 04 Nam Ou Kuwei | `src/namou_kuwei/` | `results/04_namou_kuwei/` | `logs/04_namou_kuwei/` |
| 05 Full 531 Basins | `src/full_531_basins/` | `results/05_full_531_basins/` | `logs/05_full_531_basins/` |
| 06 Haihe River | `src/haihe_river/` | `results/06_haihe_river/` | `logs/06_haihe_river/` |
| 07 HydroAgent | `src/hydroagent/` | `results/07_hydroagent/` | `logs/07_hydroagent/` |
| 41 MTS-Mamba Transfer | `src/mts_mamba_global_transfer/` | `results/41_mts_mamba_global_transfer/` | `logs/41_mts_mamba_global_transfer/` |

## 常用脚本

```bash
# Full 531 可视化
python src/full_531_basins/scripts/plot_531_baseline.py
python src/full_531_basins/scripts/plot_531_spatial.py

# CAMELSH 数据准备
python src/mamba_camelsh/scripts/prepare_camelsh.py

# Haihe GloFAS 管线
python src/haihe_river/pipelines/glofas/run_pipeline.py --config src/haihe_river/configs/glofas/pipeline_haihe.yaml
```

## 训练命令模板

```bash
python -m neuralhydrology.nh_run train --config-file <path-to-config.yml>
python -m neuralhydrology.nh_run evaluate --run-dir <run_dir> --period test
```
