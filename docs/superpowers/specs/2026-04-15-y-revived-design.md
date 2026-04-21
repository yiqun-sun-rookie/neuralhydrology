# Y_revived: Point-scale Public Layer Attributes Rescue EA-LSTM on Dutch Groundwater

**日期**: 2026-04-15
**所属主线**: 主线 A (GWL Global / Idea 08), Direction Y_revived
**状态**: Design (pending review)

## 1. 动机与问题陈述

Heudorfer et al. 2024 HESS 在 108 口德国地下水井上用 5 个静态变体 (ENVfeat 21 属性 / TSfeat 9 时序统计 / RNDfeat9 随机整数 / RNDfeat18 随机实数 / DYNonly 无静态) 证明, EA-LSTM 的 out-of-sample NSE 基本等于无静态对照 (全部 < 0.70), 静态属性只是"unique identifiers"。Heudorfer et al. 2025 GRL 把同一结论延伸到 CAMELS-US 531 流域 streamflow。两篇都开放了同一个问题: **"how to properly establish entity awareness"**, 只证问题没给方案。

Direction Y_revived 是主线 A 的剩余空间: **不是重新建数据库** (Z 方向已因无跨国人脉排除, 见 `feedback_no_z_direction.md`), **而是用用户可自主获取的公开图层派生 point-scale 属性**, 测试能否把 Dutch 1,227 口 BRO 井上 EA-LSTM 的 OOS NSE 救回到 >> DYNonly 的水平, 实现真正的空间泛化。

**科学问题**: 在 Heudorfer 2024 实验设计的基础上增加第 6 个变体 `POINT` (point-scale 公开层属性), 能否在 OOS 上显著超过其他 5 个变体?

**一句话假设**: Heudorfer 的失败不是"静态没用", 而是"catchment-averaged 静态不够精细, point-scale 公开层属性能编码真实的 entity 差异"。

## 2. 数据

### 2.1 地下水时间序列 (已有)

- **来源**: 荷兰 BRO (Basisregistratie Ondergrond) 公开 API
- **数量**: 1,227 口井 (Phase 0 已完成 QC, 见 `data/nl/summary.json`)
- **格式**: `data/nl/merged/GLD*_merged.csv`, 每文件 5 列 (`date, gwl_m_nap, P_mm, ET_mm, T_degC`) 日分辨率
- **动态驱动**: 已和 KNMI 52 个气象站合并, P / ET / T 在井点处插值

### 2.2 井坐标 (已有)

- `data/nl/gld_index.csv`: 1,227 行 × (`gld_bro_id, lon, lat, research_first/last_date, ...`)
- **CRS**: 声明为 `EPSG:4258` (ETRS89), 而非 WGS84 EPSG:4326 — 荷兰范围内差 <1m, 标注为 limitation

### 2.3 新增公开图层 (待下载)

| 层 | 来源 | 原生 CRS | 格式 | 大小 | 用途 |
|---|---|---|---|---|---|
| REGIS II top aquifer | PDOK / TNO | EPSG:28992 | NetCDF 3D | ~500 MB | `aquifer_code` (类别) |
| RWS hoofdwatersysteem | PDOK / Rijkswaterstaat | EPSG:28992 | Shapefile | <50 MB | `dist_to_river_m` |
| SoilGrids v2.0 WRB | ISRIC REST API | **EPSG:54052 Homolosine** | COG / REST | ~100 MB | `soil_class` (类别) |
| MERIT DEM | 东京大学 | EPSG:4326 | GeoTIFF 3" | ~50 MB | `slope_deg` |
| Fan 2013 WTD | Science SM | EPSG:4326 | NetCDF 30" | ~200 MB | `wtd_m` |

总计 ~1 GB 原始 → 缓存到 `data/gwl_nl_yr/public_layers/`

## 3. 架构: 双栈 + 两阶段

### 3.1 阶段 0 — 快速信号 (~7 天)

- **栈**: 仅 B (neuralhydrology EA-LSTM)
- **变体**: 4 个 — `TSfeat` / `RNDfeat18` / `DYNonly` / `POINT-min`
- **Split**: 仅 PUB 5-fold (和 Heudorfer 2024 一致, 随机 80/20 井切分)
- **训练**: 4 × 5 = 20 模型 ≈ 4 个批训 runs (neuralhydrology 批训)
- **目的**: 验证 POINT 信号是否存在, 再决定是否投入阶段 1 全量工作

### 3.2 阶段 1 — 完整发表 (~3-6 周)

- **栈**: 双栈 — B (neuralhydrology) + A (Heudorfer 2024 Keras 复刻, 代码 `github.com/KITHydrogeology/152023-global-model-germanyTS4`, Zenodo `10.5281/zenodo.10628600`)
- **变体**: 6 个 — 阶段 0 的 4 个 + `ENVfeat` (21 Heudorfer 原版 env attr) + `POINT-full` (20+ 公开层属性)
- **Split**: 双 split — PUB 5-fold + spatial-block 5-fold (荷兰 bbox 切 50km × 50km 网格, 分 5 组整块留出)
- **训练**: 6 × 2 × 2 × 5 = 120 模型 ≈ 24 批训 runs
- **交叉验证**: 要求"双栈结果方向一致"且"双 split 方向一致", 任一不一致说明结果不稳

### 3.3 阶段 0 → 阶段 1 决策规则

| 阶段 0 结果 | 决策 |
|---|---|
| `median(NSE_POINT-min) - median(NSE_DYNonly) ≥ 0.05` 且 `KS test p < 0.01` | 进阶段 1, 扩展到 POINT-full + 双栈 + 双 split |
| 差值 `< 0.05` 或不显著, 但 POINT-min 方向是正的 | 先扩到 POINT-full (20+ 属性) 重跑阶段 0, 再判断 |
| 差值 ≤ 0 或方向反 | POINT 路径失败, 转主线 B Hypernetwork (Ha 2017) 作为 "how to properly establish entity awareness" 的构造性回应 |

## 4. POINT 层提取 (CRS 陷阱修正后)

### 4.1 4 个坐标系陷阱

1. **SoilGrids 原生 Homolosine**: 不能当 WGS84 采样, 会偏移数百米到几公里
   - **修正**: 用 ISRIC REST API 点查询 (`rest.isric.org/soilgrids/v2.0/properties/query`), 1,227 次 HTTP ~2 分钟
2. **距河距离必须在米制 CRS**: WGS84 lon/lat 下 shapely 算距离返回"度", 在 52°N 各向异性严重
   - **修正**: 先把井和河都投到 `EPSG:28992` (RD New, 单位米), 用 `geopandas.sjoin_nearest`
3. **MERIT DEM 坡度不能在 WGS84 下直接算**: 得到"度高程/度水平"无物理意义
   - **修正**: 预处理 `gdalwarp -t_srs EPSG:28992` → `gdaldem slope`, 再点采样
4. **BRO 坐标是 ETRS89 不是 WGS84**: 荷兰范围内差 <1m, 不影响 100m 栅格采样
   - **处理**: 代码里声明 `CRS("EPSG:4258")`, limitation 标注

### 4.2 POINT-min 5 属性 (阶段 0)

| 属性 | 来源 | 类型 | 提取方法 |
|---|---|---|---|
| `aquifer_code` | REGIS II top layer | 类别 (int → one-hot 或 embedding) | `xarray.sel` 在 RD New |
| `dist_to_river_m` | RWS hoofdwatersysteem | 连续 (米) | `sjoin_nearest` 在 RD New |
| `soil_class` | SoilGrids WRB v2.0 | 类别 (str) | ISRIC REST API |
| `slope_deg` | MERIT DEM → slope | 连续 (度) | `gdalwarp` + `gdaldem` 预处理, 再 `rasterio.sample` |
| `wtd_m` | Fan 2013 | 连续 (米) | `xarray.sel` 在 WGS84 |

**3 个默认**:
- REGIS II 取 **surface 层 (top aquifer)**, 阶段 1 POINT-full 再扩到 screen-depth 对齐
- RWS 只算 **hoofdwatersysteem 主水系**, 不含 kleinere wateren
- 井落到 NoData 像素 (近海/边界) 时, **500m 半径内最近有效像素**兜底; 如 500m 内仍无有效像素, 该井该属性标为 NaN 并在 `build_attributes_table.py` 里从训练集剔除 (记录被剔除的井 ID 到 `data/gwl_nl_yr/excluded_wells.json`)

### 4.3 POINT-full (阶段 1, 20+ 属性)

POINT-min 的 5 属性 + 扩展 (待定细节, 阶段 0 结果回来后锁死):
- REGIS II 多层 (top / screen depth / 下垫面)
- 距多级水系 (main / secondary / tertiary)
- SoilGrids 多深度 (0-5 / 5-15 / 15-30 cm)
- MERIT 坡向 / 曲率 / TWI
- GLHYMPS 渗透率
- ESA WorldCover 土地覆盖
- Pelletier 2016 soil thickness

## 5. 变体对照表

| 变体 | 来源 | # attr | 阶段 0 | 阶段 1 |
|---|---|---|---|---|
| `ENVfeat` | Heudorfer 2024 原版 env attr | 21 | — | ✓ |
| `TSfeat` | GWL 时序统计 (RR, Skew, P52, SDdiff, LRec, jumps, SB, med01, HPD) | 9 | ✓ | ✓ |
| `RNDfeat18` | 随机实数 (3 组 × 6 或 1 组 × 18, 阶段 1 拉 Heudorfer 代码后锁死) | 18 | ✓ | ✓ |
| `DYNonly` | 无静态 | 0 | ✓ | ✓ |
| `POINT-min` | §4.2 的 5 公开层属性 | 5 | ✓ | ✓ |
| `POINT-full` | §4.3 的 20+ 公开层属性 | 20+ | — | ✓ |

**命名说明**: Heudorfer 2024 原文和 figures 里的变体命名是 `ENVfeat / TSfeat / RNDfeat9 / RNDfeat18 / DYNonly` (从 PDF pages 16-26 读出). 与 `paper_heudorfer_2024_hess.md` memory 当前的 `ENVfeat / TSfeat / RNDint / RNDreal / NOstatic` 存在差异, 需要在拉 Heudorfer GitHub 代码后核对并回填 memory.

## 6. Split 策略

### 6.1 PUB 5-fold (两阶段都用)

1,227 井随机切 5 折, 每折 train 80% / test 20%. 和 Heudorfer 2024 protocol 一致, 数字可直接对比.

**生成脚本**: `generate_splits.py`, 固定 `random_seed=42`, 输出 `basin_lists/pub_fold_{0-4}.txt`

### 6.2 Spatial-block 5-fold (仅阶段 1)

荷兰 bbox `(3.3, 50.7, 7.3, 53.6)` 在 RD New (EPSG:28992) 下切 50km × 50km 网格. 每个网格 cell 包含的井作为一个 block. 把**非空 blocks** (有井的 cell) 按**井数量加权**贪心分 5 组, 使每组井数量尽量均衡 (目标 ±10% 方差). 每折把一组整块留出作为 OOS test.

**分配算法**: 按 block 内井数降序排序, 依次放入当前井数最少的 fold. 保证 fold 间井总数差 <10%. 固定 `random_seed=42` (若井数完全一致时决定顺序).

**目的**: 避免 PUB k-fold 随机切分把同含水层邻井分到不同折导致的空间泄漏. 荷兰井密度高, 这个泄漏在审稿时一定被攻击.

**生成脚本**: 同 `generate_splits.py`, 输出 `basin_lists/spatial_fold_{0-4}.txt`

### 6.3 双 split 叙事

论文主表用 spatial-block (更严格), 对比表用 PUB k-fold (和 Heudorfer 可比). 一致性验证 "POINT > DYNonly" 在两个 split 下方向相同.

## 7. 指标与成功准则

### 7.1 指标

- **主**: OOS basin-wise NSE, 5 折 OOS test 井 pool 后取分布 (median + IQR + CDF)
- **统计检验**: 两样本 **Kolmogorov-Smirnov test** (`scipy.stats.ks_2samp`) 比较两个变体的 OOS NSE 分布, 例如 `POINT-min vs DYNonly`. 用 KS 而非 t-test 是因为 NSE 分布长尾非正态 (负值可能, 上界 1.0)
- **辅**: OOS KGE, Pearson r, Alpha-NSE, Beta-NSE (neuralhydrology 内置)

### 7.2 阶段 0 成功准则

5 折 OOS 井全部 pool 后 (约 1,227 口 basin-wise NSE), `median(NSE_POINT-min) - median(NSE_DYNonly) ≥ 0.05` 且 `ks_2samp(NSE_POINT-min, NSE_DYNonly).pvalue < 0.01` → 信号成立, 进阶段 1

### 7.3 阶段 1 发表目标

- 双栈 (A/B) 和双 split (PUB/spatial) 下, `POINT-full > DYNonly` 方向一致
- `median(NSE_POINT-full)` 在 spatial-block OOS 下 **≥ 0.70**, 超过 Heudorfer 2024 德国 <0.70 上限
- `POINT-full > ENVfeat > {TSfeat, RNDfeat18, DYNonly}` 排序明显
- 可选: `POINT-min` 在减属性后仍 `> DYNonly`, 证明关键不在属性数量而在属性质量

## 8. 文件结构

```
src/gwl_global/
├── scripts/
│   ├── convert_merged_to_netcdf.py       # 1,227 CSV → NetCDF one-time ETL
│   ├── extract_tsfeat.py                  # 9 时序统计 (从 merged CSV)
│   ├── extract_point_min.py               # 5 公开层属性提取
│   ├── extract_point_full.py              # 阶段 1, 20+ 公开层属性 (skeleton)
│   ├── extract_envfeat.py                 # 阶段 1, Heudorfer 21 env attr (待从 Heudorfer repo 反向)
│   ├── extract_rndfeat18.py               # 18 随机实数, seed=42
│   ├── build_attributes_table.py          # 合并所有变体 → attributes.csv
│   ├── generate_splits.py                 # PUB 5-fold + spatial 5-fold
│   ├── train_y_revived_phase0.py          # neuralhydrology 批训 (阶段 0, 4 variants × 5 folds)
│   └── train_y_revived_phase1.py          # 双栈批训 (阶段 1)
└── configs/
    └── y_revived/
        ├── phase0_tsfeat_fold{0-4}.yml           # 5 configs
        ├── phase0_rndfeat18_fold{0-4}.yml        # 5 configs
        ├── phase0_dynonly_fold{0-4}.yml          # 5 configs
        ├── phase0_pointmin_fold{0-4}.yml         # 5 configs
        └── phase1_*.yml                          # 阶段 0 完成后填

data/
└── gwl_nl_yr/                             # 新目录, 不碰现有 152-well data/gwl_nl/
    ├── time_series/GLD*.nc                # 1,227 files, 一次性 ETL
    ├── attributes/attributes.csv          # 1,227 × (9+18+0+5) = 32 cols 阶段 0
    ├── public_layers/                     # 下载缓存
    │   ├── regis2/top_aquifer.nc
    │   ├── rws/hoofdwatersysteem.gpkg
    │   ├── soilgrids/wrb_dutch_bbox.tif   # 或者仅用 REST API, 本地不缓存
    │   ├── merit/
    │   │   ├── elv_dutch_rdnew.tif        # 预投到 RD New
    │   │   └── slope_dutch_rdnew.tif      # gdaldem slope 输出
    │   └── fan2013/wtd_dutch_bbox.nc
    └── basin_lists/
        ├── pub_fold_{0-4}.txt
        └── spatial_fold_{0-4}.txt         # 阶段 1 生成

results/08_gwl_global/y_revived/
├── phase0/
│   ├── runs/                              # 4 × 5 = 20 neuralhydrology run dirs
│   ├── evaluation/                        # NSE / KGE / KS test 表
│   └── figures/                           # CDF 图, median NSE bar 图
└── phase1/                                # 阶段 1 填
```

## 9. 关键风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| Heudorfer Keras 代码 TF 版本兼容 | 阶段 1 双栈不可行 | 降为 stack B 单栈, 改叙事为"我们在 neuralhydrology 上精确复现 Heudorfer 2024 实验设计" |
| REGIS II `aquifer_code` 类别过多 | one-hot 维度爆炸 | 先统计类别基数; 如 >20 类, 要么聚合到 top-level 地质分组 (具体方案参考 REGIS II 官方文档), 要么用 embedding 层替代 one-hot. 方案在提取脚本完成后锁死 |
| SoilGrids REST API rate limit | 1,227 次调用被限流 | 备份方案: 下载 Homolosine COG 本地采样 |
| 1,227 井时序质量不均 | 训练噪声大 | 预过滤 `n_obs < 1000` 或 `max_gap_days > 365`, 保留 ~1,000 口 |
| 空间泄漏仍存在于 spatial-block | 审稿攻击 | 报告两个 split 结果一致, 证明结论对 split 选择鲁棒 |
| 荷兰单域结论泛化性差 | 审稿质疑"只在荷兰" | 发表材料包含 "future work: 复现到德国 Wunsch 2021 + BRO 比利时扩展" |

## 10. 交付物

**阶段 0 交付** (~7 天):
- 1 张核心表: 4 变体 × 5 fold 的 OOS NSE median + IQR + KS test p-value
- 1 张 CDF 图: 4 变体的 basin-wise NSE 经验分布
- 1 个 decision memo: 根据成功准则写入 `memory/gwl_global_project.md` 作为"阶段 0 落地"记录

**阶段 1 交付** (~3-6 周):
- 完整 experimental table: 6 变体 × 2 栈 × 2 split × 5 fold
- 论文 figures: Figure 1 (CDF 对比), Figure 2 (scatter NSE vs attribute), Figure 3 (aquifer-stratified)
- 代码 + 数据 + 属性表公开到 Zenodo, 满足 WRR code availability 要求
- 投稿目标: WRR / HESS (主选), Nature Comms / Nature Water (进展好再冲)

## 11. 相关 memory

- `gwl_global_project.md` — 主线 A 总状态
- `paper_heudorfer_2024_hess.md` — 奠基性前作 (需要回填变体命名)
- `paper_heudorfer_2025_grl.md` — streamflow 扩展
- `feedback_no_z_direction.md` — Z 方向排除约束
- `static_falsification_project.md` — 主线 C, 和本设计共享 Heudorfer 竞品分析

## 12. 不做什么 (明确排除)

- **不做 Z 方向**: 不建跨国井元数据库 (见 `feedback_no_z_direction.md`)
- **不做 X 因果归因**: X 在另一边 session 推进
- **不扩到其他国家**: 荷兰 1,227 井已经够; 扩到德国/比利时是 future work
- **不重新设计 EA-LSTM 架构**: Hypernetwork 等架构改进属于主线 B, 本设计只改静态输入
- **不做 per-well single-basin 模型对比**: 已有 `train_per_well.py` 覆盖, 和本 PUB 全局模型是两个独立问题
