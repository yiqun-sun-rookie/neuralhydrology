# 🌊 海河流域 (Haihe Basin) 项目

本项目围绕**海河流域**构建了一套完整的水文数据处理流水线，用于 NeuralHydrology 深度学习模型的训练与推理。

---

## 1. 目录结构

```
src/haihe_river/               # 项目代码/配置
├── README.md
├── configs/                      # 配置文件
│   ├── basin_list.txt
│   └── glofas/                   # GloFAS 管道配置
└── scripts/                      # 数据处理脚本 (27 个)

data/haihe/                       # 数据目录 (统一存放)
├── attributes/                   # 静态属性表
├── basins_individual/            # 单体流域 GeoJSON (1220 个)
├── boundary/                     # 海河大流域边界 (Shapefile)
├── dem/                          # 数字高程模型 (SRTM/Copernicus)
├── forcing/                      # ERA5-Land 强迫数据 (1215 个)
├── gee_raw/                      # GEE 导出原始 CSV (中间数据)
├── glofas/                       # GloFAS 流量数据
│   ├── raw/                      # NetCDF 原始
│   ├── work/                     # 裁剪后 NetCDF
│   ├── outputs/                  # 子流域时序 & QC
│   └── logs/                     # 日志
└── hydrobasins/                  # HydroBASINS 子流域
    ├── source/                   # 原始数据
    ├── lev9/                     # ★ 主力数据集 (1220 个)
    └── lev12/                    # 精细尺度 (2471 个)
```

---

## 2. 数据概览

### 2.1 子流域统计

| HydroBASINS 等级 | 子流域数量 | 面积中位数 (km²) | 面积 P95 (km²) | 备注 |
|-----------------|------------|------------------|----------------|------|
| Level 12        | 2471       | 139              | 218            | 精细尺度 |
| **Level 9**     | **1220**   | **206**          | **723**        | **主力数据集** |
| Level 8         | 493        | 470              | 2070           | 粗尺度 |

### 2.2 与 CAMELS-US 对比

- CAMELS-US (n=671): 中位数 341 km², P95 2921 km²
- 海河 lev9 (n=1220): 中位数 206 km², P95 722 km²
- **结论**: Level 9 最接近 CAMELS-US 分布，适合迁移学习

### 2.3 时间范围

- **ERA5-Land 强迫**: 1981-01-01 → 2020-12-30 (日尺度)
- **GloFAS 流量**: 2024-2025 (日尺度)

---

## 3. 单位规范

| 变量 | 原始单位 | 转换后单位 | 处理方式 |
|------|---------|-----------|---------|
| temperature_2m | K | °C | -273.15 |
| surface_pressure | Pa | kPa | ÷1000 |
| total_precipitation_sum | m | mm | ×1000 |
| potential_evaporation_sum | m | mm | ×1000 |
| snow_depth_water_equivalent | m | mm | ×1000 |
| 辐射变量 | J/m² (日累计) | W/m² (日均) | ÷86400 |
| 负值 | - | - | 截断为 0 |

---

## 4. 处理流水线

### 4.1 流程图

```
海河大流域边界 (boundary/)
        │
        ▼
┌───────────────────┐     ┌───────────────────┐
│ HydroBASINS lev9  │────▶│ 筛选子流域         │
│ (hydrobasins/)    │     │ (01_filter_*.py)  │
└───────────────────┘     └─────────┬─────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐         ┌─────────────────┐         ┌─────────────────┐
│ 单体 GeoJSON   │         │ GEE ERA5-Land   │         │ GloFAS 流量     │
│ (02_export_*) │         │ (Caravan NB)    │         │ (glofas/)       │
└───────┬───────┘         └────────┬────────┘         └─────────────────┘
        │                          │
        │                          ▼
        │                 ┌─────────────────┐
        │                 │ 合并 & 单位修正  │
        │                 │ (08~09_*.py)    │
        │                 └────────┬────────┘
        │                          │
        ▼                          ▼
┌───────────────────────────────────────────────────────────────────────┐
│                    forcing 落盘 (10_write_forcing_*.py)               │
│                         → data/forcing/*.txt                         │
└───────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────────────┐
│                 静态属性整合 (12_build_static_attributes.py)          │
│                      → data/attributes/attributes.csv                │
└───────────────────────────────────────────────────────────────────────┘
```

### 4.2 脚本说明

| 脚本 | 功能 |
|------|------|
| `00_prepare_haihe_srtm.py` | 下载 DEM → 生成高程与坡度栅格 |
| `01_filter_hydrobasins.py` | 从 HydroBASINS 筛选海河子流域 |
| `02_export_individual_basins.py` | 导出单体流域 GeoJSON |
| `07_merge_ee_csv_to_per_basin.py` | 合并 GEE CSV → 每流域一份 |
| `08_merge_from_root_lev9.py` | 扫描目录自动合并分片 |
| `09_fix_units_*.py` | 单位修正 |
| `10_write_forcing_from_timeseries_lev9.py` | **核心**: 生成 CAMELS 格式 forcing |
| `11_subbasin_quick_healthcheck.py` | 子流域体检 |
| `11_summarize_forcing.py` | 强迫质量汇总 |
| `12_build_static_attributes.py` | 构建静态属性表 |
| `13_plot_forcing_overview.py` | 可视化概览 |

---

## 5. 常用命令

```bash
# 切换到项目目录
cd src/haihe_river

# 1. 合并 GEE CSV（如有新数据）
python scripts/08_merge_from_root_lev9.py \
  --root <GEE_CSV_DIR> \
  --out results/06_haihe_river/per_basin_timeseries

# 2. 生成 forcing 文件
python scripts/10_write_forcing_from_timeseries_lev9.py \
  --src results/06_haihe_river/per_basin_timeseries \
  --dst data/forcing \
  --geojson-dir data/basins_individual \
  --basin-list data/basins_individual/basin_list.txt \
  --overwrite

# 3. 质量汇总
python scripts/11_summarize_forcing.py \
  --dir data/forcing \
  --out results/06_haihe_river/reports/forcing_summary.csv

# 4. 构建静态属性
python scripts/12_build_static_attributes.py \
  --summary results/06_haihe_river/reports/forcing_summary.csv \
  --hybas data/hydrobasins/lev9/haihe_hybas_lev9_list.csv \
  --out-dir data/attributes

# 5. 子流域体检
python scripts/11_subbasin_quick_healthcheck.py \
  --basins data/hydrobasins/lev9/haihe_hydrobasins_lev9.gpkg \
  --outdir results/06_haihe_river/haihe_healthcheck
```

---

## 6. NeuralHydrology 配置

完成数据准备后，配置 NeuralHydrology:

```yaml
# configs/haihe_inference.yml
experiment_name: haihe_lev9_inference
data_dir: data/haihe
forcings:
  - forcing/
static_attributes: attributes/attributes.csv
basins: basins_individual/basin_list.txt
```

---

## 7. GloFAS 数据说明

### 输入文件
- `data/boundary/haihe_basin.shp`: 海河大流域边界
- `haihe_hydrobasins_lev9.gpkg`: 1220 个子流域

### 输出文件
- `glofas/outputs/timeseries/`: 1220 个子流域流量 CSV
- `glofas/outputs/qc/`: 质控报告与图表

### 管道命令
参见 `src/haihe_river/pipelines/glofas/` 目录下的脚本。

---

## 8. 子流域体检

体检脚本 `11_subbasin_quick_healthcheck.py` 输出:

| 文件 | 说明 |
|------|------|
| `subbasin_stats.csv` | 每个子流域的面积/高程/坡度/起伏度 |
| `summary.md` | 统计摘要 |
| `figures/*.png` | 分布直方图/箱线图/ECDF |
| `maps/*.png` | GIS 风格分级设色地图 |

---

## 9. 常见问题

### Q: 出现缺失列怎么办？
A: 检查原始 CSV 或重新从 GEE 导出数据。

### Q: pyproj 警告？
A: 脚本会自动设置 `PROJ_LIB`；如仍有问题，确认环境中 `Library/share/proj` 存在。

### Q: 流域完全缺失？
A: 从 `basin_list.txt` 剔除该流域，后续补齐数据后重新处理。

---

## 10. 更新日志

- **2024-11**: 完成 lev9 子流域 ERA5-Land forcing 准备
- **2024-11**: 完成 GloFAS 流量数据处理
- **2024-11**: 项目目录整合到 `src/haihe_river/`

