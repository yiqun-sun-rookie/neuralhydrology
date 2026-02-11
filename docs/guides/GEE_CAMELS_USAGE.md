# GEE CAMELS数据提取使用指南

## 🌍 概述

本指南提供在Google Earth Engine (GEE) Code Editor中运行的JavaScript代码，用于提取与CAMELS数据流域大小相似的气象数据。

## 📋 文件说明

1. **`gee_camels_extractor.js`** - 完整版提取器
   - 包含详细的数据处理和质量检查
   - 支持日数据和小时数据
   - 包含数据转换功能

2. **`gee_simple_camels.js`** - 简化版提取器
   - 快速提取基本气象数据
   - 适合初学者使用
   - 代码简洁易懂

## 🚀 快速开始

### 步骤1: 访问GEE Code Editor
1. 打开浏览器，访问 [https://code.earthengine.google.com/](https://code.earthengine.google.com/)
2. 登录您的Google账户
3. 如果首次使用，需要申请GEE访问权限

### 步骤2: 准备流域边界
您需要提供流域边界的坐标，格式如下：
```javascript
var basin_coords = [
  [-120.5, 37.0],  // 西南角 [经度, 纬度]
  [-120.0, 37.0],  // 东南角
  [-120.0, 37.5],  // 东北角
  [-120.5, 37.5],  // 西北角
  [-120.5, 37.0]   // 闭合多边形
];
```

### 步骤3: 运行代码
1. 复制 `gee_simple_camels.js` 中的代码
2. 粘贴到GEE Code Editor中
3. 修改流域坐标和时间范围
4. 点击"Run"按钮运行

## 📊 提取的数据变量

### ERA5气象变量
| ERA5变量名 | 单位 | CAMELS对应变量 | 说明 |
|------------|------|----------------|------|
| total_precipitation | mm/day | prcp(mm/day) | 日总降水 |
| mean_2m_air_temperature | K | tmean(C) | 2米平均气温 |
| minimum_2m_air_temperature | K | tmin(C) | 2米最低气温 |
| maximum_2m_air_temperature | K | tmax(C) | 2米最高气温 |
| surface_solar_radiation_downwards | J/m² | srad(W/m2) | 太阳辐射 |
| mean_2m_dewpoint_temperature | K | vp(Pa) | 露点温度 |

### 数据转换
- **温度**: K → C (减去273.15)
- **辐射**: J/m² → W/m² (除以86400)
- **水汽压**: 从露点温度计算

## 🔧 自定义设置

### 修改流域边界
```javascript
// 替换为您的实际流域坐标
var basin_coords = [
  [您的经度1, 您的纬度1],
  [您的经度2, 您的纬度2],
  [您的经度3, 您的纬度3],
  [您的经度4, 您的纬度4],
  [您的经度1, 您的纬度1]  // 闭合
];
```

### 修改时间范围
```javascript
var start_date = '2020-01-01';  // 开始日期
var end_date = '2020-12-31';    // 结束日期
```

### 修改流域ID
```javascript
var basin_id = 'your_basin_name';  // 用于文件命名
```

## 📁 输出文件

### 文件位置
- 文件将保存到您的Google Drive
- 文件夹: `CAMELS_GEE_Data`
- 文件名: `{basin_id}_era5_data.csv`

### 文件格式
```csv
date,Year,Mnth,Day,total_precipitation,mean_2m_air_temperature,...
2020-01-01,2020,1,1,2.5,285.2,...
2020-01-02,2020,1,2,0.0,286.1,...
```

## 🎯 与CAMELS数据对比

### 流域大小
- **CAMELS流域**: 通常10-10,000 km²
- **ERA5分辨率**: 约25km × 25km
- **适用性**: 适合中等以上流域

### 数据质量
- **时间分辨率**: 日数据
- **空间分辨率**: 25km
- **时间覆盖**: 1940年至今
- **更新频率**: 实时更新

## ⚠️ 注意事项

### 1. 流域大小限制
- 流域面积应大于625 km² (25km × 25km)
- 过小的流域可能数据不准确

### 2. 时间范围限制
- 建议单次提取不超过1年数据
- 长时间序列需要分批处理

### 3. 计算配额
- GEE有每日计算配额限制
- 大流域或长时间序列可能超出配额

### 4. 数据验证
- 导出后请检查数据完整性
- 对比已知气象站数据验证

## 🔍 故障排除

### 常见问题

1. **"User memory limit exceeded"**
   - 减少时间范围
   - 使用更小的流域

2. **"Computation timed out"**
   - 分批处理数据
   - 减少变量数量

3. **"No data found"**
   - 检查流域坐标是否正确
   - 确认时间范围内有数据

4. **"Export failed"**
   - 检查Google Drive空间
   - 确认导出权限

## 📈 数据后处理

### 转换为CAMELS格式
```python
import pandas as pd

# 读取GEE导出的数据
df = pd.read_csv('your_basin_era5_data.csv')

# 转换温度单位
df['tmean(C)'] = df['mean_2m_air_temperature'] - 273.15
df['tmin(C)'] = df['minimum_2m_air_temperature'] - 273.15
df['tmax(C)'] = df['maximum_2m_air_temperature'] - 273.15

# 转换辐射单位
df['srad(W/m2)'] = df['surface_solar_radiation_downwards'] / 86400

# 重命名降水列
df['prcp(mm/day)'] = df['total_precipitation']

# 保存为CAMELS格式
df[['Year', 'Mnth', 'Day', 'prcp(mm/day)', 'tmean(C)', 'tmin(C)', 'tmax(C)', 'srad(W/m2)']].to_csv(
    'camels_format_data.txt', 
    sep='\t', 
    index=False
)
```

## 🎉 总结

通过GEE Code Editor，您可以：
1. **快速提取** 全球任何流域的气象数据
2. **可视化验证** 数据质量和空间分布
3. **自动导出** 到Google Drive
4. **格式兼容** 与CAMELS数据格式

这种方法特别适合：
- 研究新流域的水文特征
- 补充缺失的气象数据
- 验证现有数据的准确性
- 扩展研究区域范围
