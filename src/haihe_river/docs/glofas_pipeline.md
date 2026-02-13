# GloFAS 自动化处理流水线

本文档介绍如何使用 `src/haihe_river/pipelines/glofas/run_pipeline.py` 将 GloFAS 数据下载、裁剪、出口筛选以及质控步骤串联为可复用的一键式流程，并说明所需的配置与输出内容。

---

## 1. 目录约定与输入数据

- **目录结构**（以海河为例）：
  ```
  src/haihe_river/
  ├─ configs/glofas/     # 管线 YAML 配置
  └─ pipelines/glofas/   # 管线脚本

  data/haihe/glofas/
  ├─ raw/                # GloFAS 原始 NetCDF
  ├─ work/               # 裁剪后的 NetCDF
  ├─ outputs/            # 出口点、时间序列、QC 结果
  └─ logs/               # 下载/裁剪日志
  ```
- **海河示例输入**：  
  - 大流域边界：`data/haihe/boundary/haihe_basin.shp`（WGS84）。  
  - 子流域矢量：`data/haihe/hydrobasins/lev9/haihe_hydrobasins_lev9.gpkg`（Pfafstetter `PFAF_ID` 作为 `SUB_ID`）。

迁移到其他流域时，只需在对应 `<basin>/inputs/` 下放入新的边界与子流域文件，并在配置中引用即可。

---

## 2. 管线脚本与配置

- **脚本**：`python src/haihe_river/pipelines/glofas/run_pipeline.py --config <pipeline-config>`  
- **示例配置**：`src/haihe_river/configs/glofas/pipeline_haihe.yaml`

```yaml
name: glofas_haihe_pipeline
subbasins:
  enabled: true
  config: src/haihe_river/configs/glofas/haihe_subbasins.yaml
download:
  enabled: true
  config: src/haihe_river/configs/glofas/haihe_download.yaml
clip:
  enabled: true
  config: src/haihe_river/configs/glofas/haihe_clip.yaml
outlets:
  enabled: true
  config: src/haihe_river/configs/glofas/haihe_outlets.yaml
qc_summary:
  enabled: true
  outputs_dir: data/haihe/glofas/outputs
qc_plots:
  enabled: true
  outputs_dir: data/haihe/glofas/outputs
  subbasin_file: data/haihe/hydrobasins/lev9/haihe_hydrobasins_lev9.gpkg
```

> `enabled` 字段可对任意阶段单独开关；`config`、`outputs_dir`、`subbasin_file` 等路径既可以是相对路径（相对于仓库根目录），也可以写成绝对路径。

---

## 3. 阶段说明与输出

| 阶段 | 脚本/配置 | 输入 | 输出 |
| --- | --- | --- | --- |
| 子流域 `subbasins` | `src/haihe_river/pipelines/glofas/prep_subbasins.py` + `src/haihe_river/configs/glofas/haihe_subbasins.yaml` | 大流域边界、HydroBASINS 源文件 | `artifacts/glofas/<basin>/inputs/haihe_hydrobasins_lev9.gpkg` 及列表 CSV |
| 下载 `download` | `src/haihe_river/pipelines/glofas/download_glofas.py` + `src/haihe_river/configs/glofas/haihe_download.yaml` | 流域边界（用于 bbox）、CDS 凭据 | `artifacts/glofas/<basin>/raw/*.nc`，日志在 `logs/download_*.log` |
| 裁剪 `clip` | `src/haihe_river/pipelines/glofas/clip_glofas.py` + `src/haihe_river/configs/glofas/haihe_clip.yaml` | `raw/*.nc`、流域边界 | `work/*_clip.nc`，日志 `logs/clip.log` |
| 出口 `outlets` | `src/haihe_river/pipelines/glofas/select_subbasin_outlets.py` + `src/haihe_river/configs/glofas/haihe_outlets.yaml` | 裁剪流量、上游面积、子流域矢量 | `data/haihe/glofas/outputs/subbasin_outlets.{geojson,csv}`、`data/haihe/glofas/outputs/timeseries/sub_<SUB_ID>_discharge.csv` |
| QC 统计 `qc_summary` | `src/haihe_river/pipelines/glofas/qc_summary.py` | `data/haihe/glofas/outputs/subbasin_outlets.*`、`data/haihe/glofas/outputs/timeseries/` | `data/haihe/glofas/outputs/qc/summary.json`、`subbasin_outlets_checks.csv`、`timeseries_stats.csv` |
| QC 图 `qc_plots` | `src/haihe_river/pipelines/glofas/plot_qc.py` | 上述 QC 结果和子流域矢量 | `data/haihe/glofas/outputs/qc/figures/*.png`（地图、分布、样例曲线） |

---

## 4. 子流域提取配置

- **脚本**：`src/haihe_river/pipelines/glofas/prep_subbasins.py --config src/haihe_river/configs/glofas/haihe_subbasins.yaml`  
- **主要字段说明**：
  - `macro_basin`：大流域边界（用于 clip），需 WGS84。  
  - `hydrobasins`：HydroBASINS 原始 shp/gpkg（指定 Pfafstetter 层级）。  
  - `output_file` / `list_csv`：生成的子流域集合文件与清单，推荐直接指向 `artifacts/glofas/<basin>/inputs/`。  
  - `id_field` / `sub_id_field`：源 ID 列与 GloFAS downstream 需要的 `SUB_ID` 列（海河使用 `PFAF_ID`）。  
  - `min_overlap_ratio`：最小相交面积占比，控制是否保留边缘子流域。

示例配置：

```yaml
macro_basin: data/haihe/boundary/haihe_basin.shp
hydrobasins: data/haihe/hydrobasins/source/hybas_as_lev09_v1c.shp
output_file: data/haihe/hydrobasins/lev9/haihe_hydrobasins_lev9.gpkg
list_csv: data/haihe/hydrobasins/lev9/haihe_hydrobasins_lev9_list.csv
id_field: HYBAS_ID
sub_id_field: PFAF_ID
min_overlap_ratio: 0.05
```

运行完该阶段后，`haihe_hydrobasins_lev9.gpkg` 即可被 `haihe_outlets.yaml` 直接消费，实现与后续下载/裁剪环节的无缝衔接（目录位于 `artifacts/glofas/<basin>/inputs`）。


## 5. 运行示例

```bash
python src/haihe_river/pipelines/glofas/run_pipeline.py \
  --config src/haihe_river/configs/glofas/pipeline_haihe.yaml \
  --verbose
```

- `--verbose` 可开启 DEBUG 日志，便于排查。
- 若某阶段已完成，可在配置里将 `enabled: false`，或直接在 YAML 中切换到新的路径/阈值再次运行。

---

## 6. 自定义与迁移建议

1. **复制配置**：将 `src/haihe_river/configs/glofas/pipeline_haihe.yaml` 复制成 `pipeline_<new_basin>.yaml`，更新其中的输入/输出路径、阈值与时间范围。
2. **替换子配置**：`download/clip/outlets` 各自引用的 YAML 也可复制一份，写入新的流域名或数据路径。
3. **增量运行**：可先开启 `download` 与 `clip` 检查数据，再启用后续阶段；脚本会自动跳过已存在的文件（除非在子配置中设置 `overwrite: true`）。
4. **QC 依赖**：`qc_plots` 依赖 `qc_summary` 生成的 `timeseries_stats.csv`；若单独运行绘图脚本，请先运行统计脚本，否则会收到缺失提示。

---

## 7. 常见问题

- **CDS 权限**：确保 `~/.cdsapirc` 或环境变量中配置了可访问 GloFAS 数据集的 Token。  
- **经度范围**：如上游面积或流量文件以 `0–360` 经度存储，可在 `haihe_clip.yaml` 中保持 `convert_longitudes: true` 自动转换到 `-180–180`。  
- **阈值调参**：`src/haihe_river/configs/glofas/haihe_outlets.yaml` 中的 `ua_threshold_km2`、`mean_dis_threshold_m3s`、`search_buffer_deg` 可按流域特征调整；`select_subbasin_outlets.py` 会记录每个子流域候选数与阈值命中情况，便于 QC。
- **目录重用**：如果希望在多流域共享 `raw/` 或 `work/`，可在管线配置里直接指向相应目录；尽量保持命名中包含区域/年份等关键信息，方便区分。

---

如需进一步定制（例如添加新的后处理或可视化阶段），可在 `src/haihe_river/pipelines/glofas/run_pipeline.py` 中新增阶段函数，并在配置文件中补充对应段落，即可继续复用同一套入口。

