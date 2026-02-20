#!/usr/bin/env python3
"""
Google Earth Engine数据提取器
用于为NeuralHydrology准备气象强迫数据
"""

import ee
import pandas as pd
import numpy as np
import xarray as xr
from pathlib import Path
import geopandas as gpd
from datetime import datetime, timedelta
import json
import sys

if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

class GEEDataExtractor:
    """Google Earth Engine数据提取器"""
    
    def __init__(self, service_account_key=None):
        """初始化GEE连接"""
        try:
            if service_account_key:
                # 使用服务账户认证
                credentials = ee.ServiceAccountCredentials(
                    service_account_key['client_email'],
                    service_account_key['private_key']
                )
                ee.Initialize(credentials)
            else:
                # 使用用户认证
                ee.Initialize()
            print("[OK] GEE initialization succeeded")
        except Exception as e:
            print(f"[ERROR] GEE initialization failed: {e}")
            raise
    
    def extract_era5_data(self, basin_boundary, start_date, end_date, variables=None):
        """
        提取ERA5气象数据
        
        Parameters
        ----------
        basin_boundary : ee.Geometry
            流域边界几何体
        start_date : str
            开始日期 (YYYY-MM-DD)
        end_date : str
            结束日期 (YYYY-MM-DD)
        variables : list
            要提取的变量列表
            
        Returns
        -------
        pd.DataFrame
            时间序列数据
        """
        if variables is None:
            variables = [
                'total_precipitation',  # 总降水
                'mean_2m_air_temperature',  # 2米气温
                'surface_solar_radiation_downwards',  # 太阳辐射
                'mean_2m_dewpoint_temperature',  # 露点温度
                'u_component_of_10m_wind',  # 10米风速U分量
                'v_component_of_10m_wind'   # 10米风速V分量
            ]
        
        # ERA5数据集
        era5 = ee.ImageCollection('ECMWF/ERA5/DAILY')
        
        # 过滤时间和空间
        era5_filtered = era5.filterDate(start_date, end_date).filterBounds(basin_boundary)
        
        # 提取数据
        def extract_daily_data(image):
            """提取单日数据"""
            date = image.date().format('YYYY-MM-dd')
            
            # 计算流域平均值
            stats = image.select(variables).reduceRegion(
                reducer=ee.Reducer.mean(),
                geometry=basin_boundary,
                scale=25000,  # ERA5分辨率约25km
                maxPixels=1e9
            )
            
            # 添加日期
            stats = stats.set('date', date)
            return ee.Feature(None, stats)
        
        # 应用函数并获取结果
        features = era5_filtered.map(extract_daily_data)
        
        # 转换为pandas DataFrame
        data = features.getInfo()
        
        # 处理数据
        df_data = []
        for feature in data['features']:
            row = feature['properties']
            row['date'] = pd.to_datetime(row['date'])
            df_data.append(row)
        
        df = pd.DataFrame(df_data)
        df = df.set_index('date').sort_index()
        
        return df
    
    def extract_modis_data(self, basin_boundary, start_date, end_date):
        """
        提取MODIS地表数据
        
        Parameters
        ----------
        basin_boundary : ee.Geometry
            流域边界几何体
        start_date : str
            开始日期
        end_date : str
            结束日期
            
        Returns
        -------
        pd.DataFrame
            MODIS时间序列数据
        """
        # MODIS LST数据集
        modis_lst = ee.ImageCollection('MODIS/061/MOD11A1')
        
        # 过滤时间和空间
        modis_filtered = modis_lst.filterDate(start_date, end_date).filterBounds(basin_boundary)
        
        def extract_modis_data(image):
            """提取MODIS数据"""
            date = image.date().format('YYYY-MM-dd')
            
            # 选择LST波段
            lst_day = image.select('LST_Day_1km')
            lst_night = image.select('LST_Night_1km')
            
            # 计算流域平均值
            stats = ee.Image.cat([lst_day, lst_night]).reduceRegion(
                reducer=ee.Reducer.mean(),
                geometry=basin_boundary,
                scale=1000,  # MODIS分辨率1km
                maxPixels=1e9
            )
            
            stats = stats.set('date', date)
            return ee.Feature(None, stats)
        
        features = modis_filtered.map(extract_modis_data)
        data = features.getInfo()
        
        df_data = []
        for feature in data['features']:
            row = feature['properties']
            if row.get('LST_Day_1km') is not None:  # 过滤无效数据
                row['date'] = pd.to_datetime(row['date'])
                df_data.append(row)
        
        df = pd.DataFrame(df_data)
        df = df.set_index('date').sort_index()
        
        return df
    
    def create_basin_geometry(self, basin_shapefile):
        """
        从shapefile创建GEE几何体
        
        Parameters
        ----------
        basin_shapefile : str
            shapefile路径
            
        Returns
        -------
        ee.Geometry
            GEE几何体
        """
        # 读取shapefile
        gdf = gpd.read_file(basin_shapefile)
        
        # 转换为GeoJSON
        geojson = json.loads(gdf.to_json())
        
        # 创建GEE几何体
        geometry = ee.Geometry(geojson['features'][0]['geometry'])
        
        return geometry
    
    def format_for_neuralhydrology(self, df, basin_id, output_dir):
        """
        格式化数据为NeuralHydrology格式
        
        Parameters
        ----------
        df : pd.DataFrame
            时间序列数据
        basin_id : str
            流域ID
        output_dir : str
            输出目录
        """
        # 创建输出目录
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # 重命名列以匹配NeuralHydrology格式
        column_mapping = {
            'total_precipitation': 'prcp(mm/day)',
            'mean_2m_air_temperature': 'tmean(C)',
            'surface_solar_radiation_downwards': 'srad(W/m2)',
            'mean_2m_dewpoint_temperature': 'tdew(C)',
            'u_component_of_10m_wind': 'wind_u(m/s)',
            'v_component_of_10m_wind': 'wind_v(m/s)',
            'LST_Day_1km': 'lst_day(K)',
            'LST_Night_1km': 'lst_night(K)'
        }
        
        df_renamed = df.rename(columns=column_mapping)
        
        # 添加日期列
        df_renamed['Year'] = df_renamed.index.year
        df_renamed['Mnth'] = df_renamed.index.month
        df_renamed['Day'] = df_renamed.index.day
        
        # 重新排列列
        date_cols = ['Year', 'Mnth', 'Day']
        other_cols = [col for col in df_renamed.columns if col not in date_cols]
        df_renamed = df_renamed[date_cols + other_cols]
        
        # 保存为文本文件 (NeuralHydrology格式)
        output_file = output_path / f"{basin_id}_lump_gee_forcing.txt"
        df_renamed.to_csv(output_file, sep='\t', index=False, float_format='%.6f')
        
        print(f"[OK] Data saved to: {output_file}")
        
        return output_file

def main():
    """主函数示例"""
    # 初始化GEE提取器
    extractor = GEEDataExtractor()
    
    # 流域边界文件 (需要您提供)
    basin_shapefile = "path/to/your/basin_boundary.shp"
    
    # 创建流域几何体
    basin_geometry = extractor.create_basin_geometry(basin_shapefile)
    
    # 提取ERA5数据
    start_date = "2020-01-01"
    end_date = "2020-12-31"
    
    print("🌍 提取ERA5气象数据...")
    era5_data = extractor.extract_era5_data(
        basin_geometry, 
        start_date, 
        end_date
    )
    
    print("🛰️ 提取MODIS地表数据...")
    modis_data = extractor.extract_modis_data(
        basin_geometry,
        start_date,
        end_date
    )
    
    # 合并数据
    combined_data = pd.concat([era5_data, modis_data], axis=1)
    
    # 格式化为NeuralHydrology格式
    basin_id = "your_basin_id"
    output_dir = "data/gee_extracted"
    
    output_file = extractor.format_for_neuralhydrology(
        combined_data, 
        basin_id, 
        output_dir
    )
    
    print(f"[DONE] Data extraction finished. Output file: {output_file}")

if __name__ == "__main__":
    main()

