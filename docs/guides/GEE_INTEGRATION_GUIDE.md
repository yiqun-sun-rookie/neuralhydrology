# Google Earth Engine与NeuralHydrology集成指南

## 🌍 概述

本指南介绍如何将Google Earth Engine (GEE)的数据提取功能与NeuralHydrology水文建模框架集成，实现一致的数据输出。

## ✅ GEE的优势

### 1. 数据一致性
- **标准化格式**: 全球统一的数据格式和空间分辨率
- **自动处理**: 自动处理投影变换、重采样和时空对齐
- **质量控制**: 内置数据质量控制和验证

### 2. 丰富的数据源
- **ERA5**: 高分辨率再分析气象数据
- **MERRA-2**: NASA现代再分析数据
- **GPM**: 全球降水测量
- **MODIS**: 地表温度和植被指数
- **HydroSHEDS**: 全球水文数据集

### 3. 计算能力
- **云端处理**: 无需下载大量数据到本地
- **并行计算**: 高效的空间和时间聚合
- **实时更新**: 数据源实时更新

## 🔧 集成步骤

### 步骤1: 设置GEE环境

```bash
# 安装GEE Python API
pip install earthengine-api

# 认证GEE账户
earthengine authenticate
```

### 步骤2: 准备流域边界

```python
import geopandas as gpd

# 读取流域边界shapefile
basin_gdf = gpd.read_file("your_basin_boundary.shp")

# 确保使用WGS84坐标系
basin_gdf = basin_gdf.to_crs("EPSG:4326")
```

### 步骤3: 提取气象数据

```python
from gee_data_extractor import GEEDataExtractor

# 初始化提取器
extractor = GEEDataExtractor()

# 创建流域几何体
basin_geometry = extractor.create_basin_geometry("basin_boundary.shp")

# 提取ERA5数据
era5_data = extractor.extract_era5_data(
    basin_geometry,
    start_date="2020-01-01",
    end_date="2020-12-31"
)

# 提取MODIS数据
modis_data = extractor.extract_modis_data(
    basin_geometry,
    start_date="2020-01-01", 
    end_date="2020-12-31"
)
```

### 步骤4: 格式化数据

```python
# 合并数据
combined_data = pd.concat([era5_data, modis_data], axis=1)

# 格式化为NeuralHydrology格式
output_file = extractor.format_for_neuralhydrology(
    combined_data,
    basin_id="your_basin_id",
    output_dir="data/gee_extracted"
)
```

### 步骤5: 配置NeuralHydrology

使用提供的配置文件 `gee_integration_config.yml`:

```yaml
# 数据目录
data_dir: path/to/gee_extracted

# GEE数据输入特征
forcings:
  - gee_era5

dynamic_inputs:
  - prcp(mm/day)
  - tmean(C)
  - srad(W/m2)
  - lst_day(K)
  - lst_night(K)
```

## 📊 数据一致性保证

### 1. 空间一致性
- **统一投影**: 所有数据使用WGS84 (EPSG:4326)
- **空间聚合**: 按流域边界进行空间平均
- **分辨率匹配**: 自动处理不同数据源的分辨率差异

### 2. 时间一致性
- **时间对齐**: 统一的时间戳和频率
- **缺失值处理**: 一致的缺失值标记和处理
- **时间序列完整性**: 确保时间序列的连续性

### 3. 格式一致性
- **标准化列名**: 与NeuralHydrology期望的格式匹配
- **数据类型**: 统一的数据类型和精度
- **文件结构**: 符合NeuralHydrology的目录结构

## ⚠️ 注意事项

### 1. 数据质量
- **云覆盖**: MODIS数据可能受云层影响
- **时间延迟**: 某些数据源可能有时间延迟
- **空间分辨率**: 不同数据源的分辨率差异

### 2. 计算限制
- **配额限制**: GEE有每日计算配额限制
- **请求频率**: 避免过于频繁的API请求
- **数据量**: 大流域或长时间序列可能需要分批处理

### 3. 验证建议
- **交叉验证**: 与地面观测数据对比
- **质量检查**: 检查数据的时空连续性
- **敏感性分析**: 测试不同数据源的影响

## 🚀 高级功能

### 1. 多时间尺度
```python
# 提取不同时间分辨率的数据
hourly_data = extractor.extract_era5_hourly(basin_geometry, start_date, end_date)
daily_data = extractor.extract_era5_daily(basin_geometry, start_date, end_date)
```

### 2. 多流域批量处理
```python
# 批量处理多个流域
basin_list = ["basin_001", "basin_002", "basin_003"]
for basin_id in basin_list:
    basin_geometry = extractor.create_basin_geometry(f"{basin_id}.shp")
    data = extractor.extract_era5_data(basin_geometry, start_date, end_date)
    extractor.format_for_neuralhydrology(data, basin_id, output_dir)
```

### 3. 实时数据更新
```python
# 设置定期数据更新
import schedule

def update_data():
    # 提取最新数据
    latest_data = extractor.extract_era5_data(
        basin_geometry,
        start_date=datetime.now() - timedelta(days=7),
        end_date=datetime.now()
    )
    # 更新本地数据文件
    update_local_data(latest_data)

# 每周更新一次
schedule.every().week.do(update_data)
```

## 📈 性能优化

### 1. 缓存策略
- **本地缓存**: 缓存已提取的数据
- **增量更新**: 只提取新增数据
- **压缩存储**: 使用压缩格式存储数据

### 2. 并行处理
- **多线程**: 并行处理多个流域
- **异步请求**: 异步处理GEE API请求
- **批处理**: 批量处理数据请求

## 🔍 故障排除

### 常见问题

1. **认证失败**
   ```bash
   # 重新认证
   earthengine authenticate
   ```

2. **配额超限**
   ```python
   # 检查配额使用情况
   import ee
   ee.Initialize()
   print(ee.data.getAssetRoots())
   ```

3. **数据格式错误**
   ```python
   # 验证数据格式
   df.info()
   df.describe()
   ```

## 📚 参考资料

- [Google Earth Engine Python API](https://developers.google.com/earth-engine/guides/python_install)
- [NeuralHydrology文档](https://neuralhydrology.readthedocs.io/)
- [ERA5数据文档](https://confluence.ecmwf.int/display/CKB/ERA5%3A+data+documentation)
- [MODIS数据文档](https://modis.gsfc.nasa.gov/data/)

## 🎯 总结

通过GEE与NeuralHydrology的集成，您可以：

1. **获得一致的数据输出**: 标准化的格式和质量
2. **利用丰富的全球数据**: 多种高分辨率数据源
3. **简化数据处理流程**: 自动化的数据提取和格式化
4. **提高研究效率**: 减少数据准备时间
5. **确保数据质量**: 内置的质量控制机制

这种集成方案为水文建模研究提供了强大而灵活的数据支持。

