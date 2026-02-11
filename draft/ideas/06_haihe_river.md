# 06 - Haihe River Basin Data Pipeline

**状态**: data_prep
**创建日期**: 2024-11-01
**最后更新**: 2026-02-10

---

## 研究目标

针对中国海河流域，构建完整的水文数据处理管线 (data pipeline)，生成 NeuralHydrology 兼容的 CAMELS 格式数据。为后续深度学习建模和全球迁移学习提供基础数据。

---

## 任务隔离边界

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/haihe_river/` | 处理脚本、配置、管线 |
| Results | `results/06_haihe_river/` | 质检输出、图表、报告 |
| Logs | `logs/06_haihe_river/` | 处理日志 |
| Docs | `draft/ideas/06_haihe_river.md` | 本文档 |
| Index | `draft/RESEARCH_INDEX.md` | 主索引 |

---

## 数据概览

### 子流域统计

| HydroBASINS 等级 | 子流域数 | 面积中位数 (km2) | 面积 P95 (km2) | 备注 |
|---|---|---|---|---|
| Level 12 | 2471 | 139 | 218 | 精细尺度 |
| **Level 9** | **1220** | **206** | **723** | **主力数据集** |
| Level 8 | 493 | 470 | 2070 | 粗尺度 |

与 CAMELS-US 对比: CAMELS-US (n=671) 中位 341 km2，Level 9 最接近，适合迁移学习。

### 时间范围

- ERA5-Land 强迫: 1981-01-01 ~ 2020-12-30 (日尺度)
- GloFAS 流量: 2024-2025 (日尺度)

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| DEM Processing | `src/haihe_river/scripts/00_prepare_haihe_srtm.py` | 数字高程处理 |
| Basin Filter | `src/haihe_river/scripts/01_filter_hydrobasins.py` | 海河子流域筛选 |
| Basin Export | `src/haihe_river/scripts/02_export_individual_basins.py` | 单体流域 GeoJSON |
| GEE CSV Merge | `src/haihe_river/scripts/07_merge_ee_csv_to_per_basin.py` | 合并 GEE 导出 |
| Unit Fix | `src/haihe_river/scripts/09_fix_units_*.py` | 单位修正 (K->C, Pa->kPa, m->mm) |
| **Forcing Gen** | `src/haihe_river/scripts/10_write_forcing_from_timeseries_lev9.py` | **核心: CAMELS 格式 forcing** |
| QC Summary | `src/haihe_river/scripts/11_summarize_forcing.py` | 强迫质量汇总 |
| Static Attrs | `src/haihe_river/scripts/12_build_static_attributes.py` | 静态属性表 |
| Visualization | `src/haihe_river/scripts/13_plot_forcing_overview.py` | 概览可视化 |
| GloFAS Pipeline | `src/haihe_river/pipelines/glofas/` | GloFAS 流量数据管线 |
| Basin Clip | `src/haihe_river/scripts/clip_hydro_subbasins.py` | 子流域裁剪 |
| Config (basin list) | `src/haihe_river/configs/basin_list.txt` | 流域列表 |
| GloFAS Config | `src/haihe_river/configs/glofas/` | GloFAS 下载配置 |

---

## Results Index

| Output | Path | Notes |
| :--- | :--- | :--- |
| Healthcheck (lev9) | `results/06_haihe_river/haihe_healthcheck_lev9/` | 质量检查结果 |
| Healthcheck (latest) | `results/06_haihe_river/haihe_healthcheck_lev9_latest/` | 最新检查 |
| Archive (lev12) | `results/06_haihe_river/archive/haihe_healthcheck_lev12/` | 历史检查 |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2024-11 | 管线建设 | 完成 lev9 子流域 ERA5-Land forcing 准备 |
| 2024-11 | GloFAS 完成 | 完成流量数据处理 |
| 2024-11 | 目录整合 | 项目目录整合到 projects/haihe/ |
| 2025-12-10 | 质检完成 | Level 9 healthcheck 运行完成 |
| 2026-02-10 | 目录迁移 | 从 projects/haihe/ 迁移到 src/haihe_river/ |

---

## 下一步

1. 确认数据清洗结果
2. 准备训练/验证/测试集划分方案
3. 搭建初步 LSTM 基线模型
4. 与 CAMELS-US 预训练模型进行迁移学习实验
