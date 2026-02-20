#!/usr/bin/env python3
"""
GEE快速开始脚本
简化版本，适合快速测试
"""

import ee
import pandas as pd
from pathlib import Path
import sys

if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

def quick_gee_setup():
    """快速设置GEE"""
    print("🔧 设置Google Earth Engine...")
    
    try:
        # 初始化GEE (需要先运行 earthengine authenticate)
        ee.Initialize()
        print("✅ GEE初始化成功")
        return True
    except Exception as e:
        print(f"❌ GEE初始化失败: {e}")
        print("💡 请先运行: earthengine authenticate")
        return False

def extract_simple_data(basin_coords, start_date, end_date):
    """
    提取简单气象数据
    
    Parameters
    ----------
    basin_coords : list
        流域边界坐标 [[lon1, lat1], [lon2, lat2], ...]
    start_date : str
        开始日期 "YYYY-MM-DD"
    end_date : str
        结束日期 "YYYY-MM-DD"
    """
    # 创建流域几何体
    basin_geometry = ee.Geometry.Polygon(basin_coords)
    
    # ERA5数据集
    era5 = ee.ImageCollection('ECMWF/ERA5/DAILY')
    
    # 过滤数据
    era5_filtered = era5.filterDate(start_date, end_date).filterBounds(basin_geometry)
    
    # 提取数据
    def extract_daily(image):
        date = image.date().format('YYYY-MM-dd')
        stats = image.select(['total_precipitation', 'mean_2m_air_temperature']).reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=basin_geometry,
            scale=25000,
            maxPixels=1e9
        )
        return ee.Feature(None, stats.set('date', date))
    
    # 获取数据
    features = era5_filtered.map(extract_daily)
    data = features.getInfo()
    
    # 转换为DataFrame
    df_data = []
    for feature in data['features']:
        row = feature['properties']
        if row.get('total_precipitation') is not None:
            row['date'] = pd.to_datetime(row['date'])
            df_data.append(row)
    
    df = pd.DataFrame(df_data)
    df = df.set_index('date').sort_index()
    
    return df

def save_for_neuralhydrology(df, basin_id, output_dir="data/gee_simple"):
    """保存为NeuralHydrology格式"""
    # 创建输出目录
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # 重命名列
    df_renamed = df.rename(columns={
        'total_precipitation': 'prcp(mm/day)',
        'mean_2m_air_temperature': 'tmean(C)'
    })
    
    # 添加日期列
    df_renamed['Year'] = df_renamed.index.year
    df_renamed['Mnth'] = df_renamed.index.month
    df_renamed['Day'] = df_renamed.index.day
    
    # 重新排列列
    date_cols = ['Year', 'Mnth', 'Day']
    other_cols = [col for col in df_renamed.columns if col not in date_cols]
    df_renamed = df_renamed[date_cols + other_cols]
    
    # 保存文件
    output_file = Path(output_dir) / f"{basin_id}_lump_gee_forcing.txt"
    df_renamed.to_csv(output_file, sep='\t', index=False, float_format='%.6f')
    
    print(f"✅ 数据已保存到: {output_file}")
    return output_file

def main():
    """主函数"""
    print("🚀 GEE快速开始")
    print("=" * 50)
    
    # 1. 设置GEE
    if not quick_gee_setup():
        return
    
    # 2. 定义流域边界 (示例: 一个小流域)
    # 格式: [[经度1, 纬度1], [经度2, 纬度2], ...]
    basin_coords = [
        [-120.5, 37.0],
        [-120.0, 37.0], 
        [-120.0, 37.5],
        [-120.5, 37.5],
        [-120.5, 37.0]
    ]
    
    # 3. 设置时间范围
    start_date = "2020-01-01"
    end_date = "2020-12-31"
    
    print(f"🌍 提取数据: {start_date} 到 {end_date}")
    
    # 4. 提取数据
    try:
        df = extract_simple_data(basin_coords, start_date, end_date)
        print(f"📊 提取了 {len(df)} 天的数据")
        print(f"📈 数据列: {list(df.columns)}")
        
        # 5. 保存数据
        basin_id = "test_basin"
        output_file = save_for_neuralhydrology(df, basin_id)
        
        print("\n🎉 完成!")
        print(f"📁 输出目录: {output_file.parent}")
        print(f"📄 输出文件: {output_file.name}")
        
    except Exception as e:
        print(f"❌ 数据提取失败: {e}")

if __name__ == "__main__":
    main()

