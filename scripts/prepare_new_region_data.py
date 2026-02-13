#!/usr/bin/env python3
"""
为新区域准备数据的脚本
"""
import os
import pandas as pd
import xarray as xr
import numpy as np
from datetime import datetime, timedelta

def create_sample_data():
    """创建示例新区域数据"""
    
    # 创建时间序列
    start_date = datetime(1990, 1, 1)
    end_date = datetime(2020, 12, 31)
    dates = pd.date_range(start=start_date, end=end_date, freq='D')
    
    # 生成示例气象数据
    np.random.seed(42)
    n_days = len(dates)
    
    # 模拟降水数据（季节性变化）
    precipitation = np.random.exponential(2.0, n_days)
    seasonal_factor = 1 + 0.5 * np.sin(2 * np.pi * np.arange(n_days) / 365.25)
    precipitation *= seasonal_factor
    
    # 模拟温度数据
    temp_base = 15 + 10 * np.sin(2 * np.pi * np.arange(n_days) / 365.25)
    temp_max = temp_base + np.random.normal(0, 2, n_days)
    temp_min = temp_base - 5 + np.random.normal(0, 2, n_days)
    
    # 模拟辐射数据
    radiation = 200 + 100 * np.sin(2 * np.pi * np.arange(n_days) / 365.25)
    radiation += np.random.normal(0, 20, n_days)
    radiation = np.maximum(radiation, 0)
    
    # 模拟湿度数据
    humidity = 60 + 20 * np.sin(2 * np.pi * np.arange(n_days) / 365.25)
    humidity += np.random.normal(0, 5, n_days)
    humidity = np.clip(humidity, 0, 100)
    
    # 创建DataArray
    data_vars = {
        'precipitation': (['date'], precipitation),
        'temperature_max': (['date'], temp_max),
        'temperature_min': (['date'], temp_min),
        'radiation': (['date'], radiation),
        'humidity': (['date'], humidity),
    }
    
    coords = {'date': dates}
    
    ds = xr.Dataset(data_vars, coords=coords)
    
    # 创建目录
    os.makedirs('data/new_region/time_series', exist_ok=True)
    os.makedirs('data/new_region/attributes', exist_ok=True)
    
    # 保存时间序列数据
    ds.to_netcdf('data/new_region/time_series/new_basin_001.nc')
    
    # 创建流域属性
    attributes = pd.DataFrame({
        'basin_id': ['new_basin_001'],
        'area_km2': [150.5],
        'slope_mean': [0.12],
        'elevation_mean': [850.0],
        'soil_type': ['clay_loam'],
        'land_cover': ['mixed_forest']
    })
    
    attributes.to_csv('data/new_region/attributes/basin_attributes.csv', index=False)
    
    print("新区域数据已创建:")
    print("- 时间序列数据: data/new_region/time_series/new_basin_001.nc")
    print("- 流域属性: data/new_region/attributes/basin_attributes.csv")
    print(f"- 数据时间范围: {start_date.date()} 到 {end_date.date()}")
    print(f"- 数据点数: {n_days} 天")

if __name__ == "__main__":
    create_sample_data()
