# 将NeuralHydrology模型应用到新区域

## 1. 数据准备

### 必需数据
- **气象强迫数据**：降水、温度、辐射等
- **流域边界**：用于提取气象数据
- **流域属性**：面积、坡度、土壤类型等（可选但推荐）

### 数据格式
```
your_region/
├── time_series/
│   └── your_basin_id.nc  # 时间序列数据
├── attributes/
│   └── basin_attributes.csv  # 流域属性
└── basin_boundaries/
    └── your_basin_id.shp  # 流域边界
```

## 2. 数据预处理

### 时间序列数据格式
```python
import xarray as xr
import pandas as pd

# 创建时间序列数据
data = {
    'date': pd.date_range('1990-01-01', '2020-12-31', freq='D'),
    'precipitation': [...],  # 降水数据
    'temperature': [...],    # 温度数据
    'radiation': [...],      # 辐射数据
    'streamflow': [...]      # 径流数据（如果有）
}

# 保存为NetCDF格式
ds = xr.Dataset(data)
ds.to_netcdf('your_region/time_series/your_basin_id.nc')
```

### 流域属性格式
```csv
basin_id,area_km2,slope_mean,soil_type,land_cover
your_basin_id,100.5,0.15,clay,forest
```

## 3. 模型应用

### 使用预训练模型
```python
from neuralhydrology.evaluation.evaluate import start_evaluation

# 加载预训练模型
config_file = "runs/full_training_674_basins/config.yml"
run_dir = "runs/full_training_674_basins"

# 评估新区域
start_evaluation(
    run_dir=run_dir,
    period="test",
    basin="your_basin_id"
)
```

## 4. 预测新区域

### 创建预测配置
```yaml
experiment_name: new_region_prediction
dataset: generic  # 使用通用数据集
data_dir: path/to/your_region
basin: your_basin_id
```

## 5. 注意事项

- 确保气象数据与训练数据格式一致
- 流域属性需要标准化
- 可能需要微调模型参数
- 验证预测结果的合理性
