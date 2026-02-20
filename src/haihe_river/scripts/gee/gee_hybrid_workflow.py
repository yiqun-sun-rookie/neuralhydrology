#!/usr/bin/env python3
"""
GEE混合工作流程脚本
支持预览验证 + 自动化处理
"""

import ee
import pandas as pd
import numpy as np
import json
from pathlib import Path
from datetime import datetime, timedelta
import geopandas as gpd
import sys

if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

class GEEHybridWorkflow:
    """GEE混合工作流程管理器"""
    
    def __init__(self, service_account_key=None):
        """初始化GEE连接"""
        try:
            if service_account_key:
                credentials = ee.ServiceAccountCredentials(
                    service_account_key['client_email'],
                    service_account_key['private_key']
                )
                ee.Initialize(credentials)
            else:
                ee.Initialize()
            print("✅ GEE初始化成功")
        except Exception as e:
            print(f"❌ GEE初始化失败: {e}")
            raise
    
    def generate_gee_preview_code(self, basin_shapefile, start_date, end_date, 
                                 variables=None, output_format="html"):
        """
        生成GEE Code Editor预览代码
        
        Parameters
        ----------
        basin_shapefile : str
            流域边界shapefile路径
        start_date : str
            开始日期
        end_date : str
            结束日期
        variables : list
            要预览的变量列表
        output_format : str
            输出格式 ("html", "js", "python")
        """
        if variables is None:
            variables = [
                'total_precipitation',
                'mean_2m_air_temperature', 
                'surface_solar_radiation_downwards',
                'mean_2m_dewpoint_temperature'
            ]
        
        # 读取流域边界并转换为GeoJSON
        gdf = gpd.read_file(basin_shapefile)
        gdf = gdf.to_crs("EPSG:4326")
        geojson = json.loads(gdf.to_json())
        
        # 生成GEE JavaScript代码
        js_code = f"""
// GEE预览代码 - 自动生成
// 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

// 1. 定义流域边界
var basin_geometry = {json.dumps(geojson['features'][0]['geometry'])};

// 2. 定义时间范围
var start_date = '{start_date}';
var end_date = '{end_date}';

// 3. 加载ERA5数据
var era5 = ee.ImageCollection('ECMWF/ERA5/DAILY')
  .filterDate(start_date, end_date)
  .filterBounds(basin_geometry);

// 4. 选择变量
var variables = {json.dumps(variables)};
var era5_selected = era5.select(variables);

// 5. 计算流域平均值
var basin_stats = era5_selected.map(function(image) {{
  var date = image.date().format('YYYY-MM-dd');
  var stats = image.reduceRegion({{
    reducer: ee.Reducer.mean(),
    geometry: basin_geometry,
    scale: 25000,
    maxPixels: 1e9
  }});
  return ee.Feature(null, stats.set('date', date));
}});

// 6. 显示结果
print('流域统计信息:');
print(basin_stats.aggregate_array('date'));
print('数据点数量:', basin_stats.size());

// 7. 可视化设置
var vis_params = {{
  precipitation: {{min: 0, max: 50, palette: ['blue', 'lightblue', 'green', 'yellow', 'red']}},
  temperature: {{min: -20, max: 40, palette: ['blue', 'cyan', 'yellow', 'orange', 'red']}},
  radiation: {{min: 0, max: 400, palette: ['darkblue', 'blue', 'cyan', 'yellow', 'orange']}}
}};

// 8. 在地图上显示
Map.addLayer(basin_geometry, {{color: 'red'}}, '流域边界');
Map.centerObject(basin_geometry, 10);

// 9. 显示第一个时间步的数据
var first_image = era5_selected.first();
Map.addLayer(first_image.select('total_precipitation'), vis_params.precipitation, '降水');
Map.addLayer(first_image.select('mean_2m_air_temperature'), vis_params.temperature, '温度');

// 10. 导出数据预览 (可选)
// Export.table.toDrive({{
//   collection: basin_stats,
//   description: 'basin_preview_data',
//   fileFormat: 'CSV'
// }});
"""
        
        # 生成Python代码
        python_code = f"""
# GEE预览代码 - Python版本
# 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

import ee
import pandas as pd
import json

# 初始化GEE
ee.Initialize()

# 1. 定义流域边界
basin_geometry = ee.Geometry({json.dumps(geojson['features'][0]['geometry'])})

# 2. 定义时间范围
start_date = '{start_date}'
end_date = '{end_date}'

# 3. 加载ERA5数据
era5 = ee.ImageCollection('ECMWF/ERA5/DAILY')
era5_filtered = era5.filterDate(start_date, end_date).filterBounds(basin_geometry)

# 4. 选择变量
variables = {json.dumps(variables)}
era5_selected = era5_filtered.select(variables)

# 5. 计算流域平均值
def extract_daily_data(image):
    date = image.date().format('YYYY-MM-dd')
    stats = image.reduceRegion(
        reducer=ee.Reducer.mean(),
        geometry=basin_geometry,
        scale=25000,
        maxPixels=1e9
    )
    return ee.Feature(None, stats.set('date', date))

basin_stats = era5_selected.map(extract_daily_data)

# 6. 获取数据
data = basin_stats.getInfo()
print(f"数据点数量: {{len(data['features'])}}")

# 7. 转换为DataFrame
df_data = []
for feature in data['features']:
    row = feature['properties']
    if any(row.get(var) is not None for var in variables):
        row['date'] = pd.to_datetime(row['date'])
        df_data.append(row)

df = pd.DataFrame(df_data)
df = df.set_index('date').sort_index()
print("数据预览:")
print(df.head())
print("\\n数据统计:")
print(df.describe())
"""
        
        # 生成HTML预览页面
        html_code = f"""
<!DOCTYPE html>
<html>
<head>
    <title>GEE数据预览</title>
    <script src="https://code.earthengine.google.com/client-api/"></script>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        .code-block {{ background: #f5f5f5; padding: 15px; border-radius: 5px; }}
        .info {{ background: #e7f3ff; padding: 10px; border-radius: 5px; margin: 10px 0; }}
    </style>
</head>
<body>
    <h1>🌍 GEE数据预览</h1>
    
    <div class="info">
        <h3>📊 预览信息</h3>
        <p><strong>流域文件:</strong> {basin_shapefile}</p>
        <p><strong>时间范围:</strong> {start_date} 到 {end_date}</p>
        <p><strong>变量:</strong> {', '.join(variables)}</p>
        <p><strong>生成时间:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    </div>
    
    <h3>📋 使用步骤</h3>
    <ol>
        <li>复制下面的JavaScript代码</li>
        <li>在 <a href="https://code.earthengine.google.com/" target="_blank">GEE Code Editor</a> 中运行</li>
        <li>检查地图显示和数据统计</li>
        <li>确认无误后运行自动化脚本</li>
    </ol>
    
    <h3>💻 JavaScript代码</h3>
    <div class="code-block">
        <pre><code>{js_code}</code></pre>
    </div>
    
    <h3>🐍 Python代码</h3>
    <div class="code-block">
        <pre><code>{python_code}</code></pre>
    </div>
    
    <div class="info">
        <h3>✅ 预览检查清单</h3>
        <ul>
            <li>流域边界显示正确</li>
            <li>数据时间范围符合预期</li>
            <li>变量值在合理范围内</li>
            <li>无大量缺失值</li>
            <li>空间分布合理</li>
        </ul>
    </div>
</body>
</html>
"""
        
        # 保存代码文件
        output_dir = Path("gee_preview_outputs")
        output_dir.mkdir(exist_ok=True)
        
        if output_format == "html":
            output_file = output_dir / f"gee_preview_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(html_code)
        elif output_format == "js":
            output_file = output_dir / f"gee_preview_{datetime.now().strftime('%Y%m%d_%H%M%S')}.js"
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(js_code)
        elif output_format == "python":
            output_file = output_dir / f"gee_preview_{datetime.now().strftime('%Y%m%d_%H%M%S')}.py"
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(python_code)
        
        print(f"✅ 预览代码已生成: {output_file}")
        return output_file
    
    def automated_extraction(self, basin_shapefile, start_date, end_date, 
                           basin_id, output_dir="data/gee_automated", 
                           variables=None, confirm_preview=True):
        """
        自动化数据提取
        
        Parameters
        ----------
        basin_shapefile : str
            流域边界文件
        start_date : str
            开始日期
        end_date : str
            结束日期
        basin_id : str
            流域ID
        output_dir : str
            输出目录
        variables : list
            变量列表
        confirm_preview : bool
            是否要求确认预览
        """
        if confirm_preview:
            print("🔍 请先在GEE Code Editor中预览数据!")
            print("💡 运行生成的预览代码确认数据质量")
            response = input("数据预览无误? (y/n): ").lower().strip()
            if response != 'y':
                print("❌ 请先完成数据预览")
                return None
        
        if variables is None:
            variables = [
                'total_precipitation',
                'mean_2m_air_temperature',
                'surface_solar_radiation_downwards',
                'mean_2m_dewpoint_temperature',
                'u_component_of_10m_wind',
                'v_component_of_10m_wind'
            ]
        
        # 创建流域几何体
        gdf = gpd.read_file(basin_shapefile)
        gdf = gdf.to_crs("EPSG:4326")
        geojson = json.loads(gdf.to_json())
        basin_geometry = ee.Geometry(geojson['features'][0]['geometry'])
        
        print(f"🌍 开始提取数据: {basin_id}")
        print(f"📅 时间范围: {start_date} 到 {end_date}")
        print(f"📊 变量: {', '.join(variables)}")
        
        # 提取ERA5数据
        era5 = ee.ImageCollection('ECMWF/ERA5/DAILY')
        era5_filtered = era5.filterDate(start_date, end_date).filterBounds(basin_geometry)
        
        def extract_daily_data(image):
            date = image.date().format('YYYY-MM-dd')
            stats = image.select(variables).reduceRegion(
                reducer=ee.Reducer.mean(),
                geometry=basin_geometry,
                scale=25000,
                maxPixels=1e9
            )
            return ee.Feature(None, stats.set('date', date))
        
        features = era5_filtered.map(extract_daily_data)
        data = features.getInfo()
        
        # 转换为DataFrame
        df_data = []
        for feature in data['features']:
            row = feature['properties']
            if any(row.get(var) is not None for var in variables):
                row['date'] = pd.to_datetime(row['date'])
                df_data.append(row)
        
        df = pd.DataFrame(df_data)
        df = df.set_index('date').sort_index()
        
        # 格式化为NeuralHydrology格式
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # 重命名列
        column_mapping = {
            'total_precipitation': 'prcp(mm/day)',
            'mean_2m_air_temperature': 'tmean(C)',
            'surface_solar_radiation_downwards': 'srad(W/m2)',
            'mean_2m_dewpoint_temperature': 'tdew(C)',
            'u_component_of_10m_wind': 'wind_u(m/s)',
            'v_component_of_10m_wind': 'wind_v(m/s)'
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
        
        # 保存文件
        output_file = output_path / f"{basin_id}_lump_gee_forcing.txt"
        df_renamed.to_csv(output_file, sep='\t', index=False, float_format='%.6f')
        
        print(f"✅ 数据已保存到: {output_file}")
        print(f"📊 数据统计: {len(df)} 天, {len(df.columns)} 个变量")
        
        return output_file
    
    def batch_processing(self, basin_list, start_date, end_date, 
                        output_dir="data/gee_batch", skip_preview=False):
        """
        批量处理多个流域
        
        Parameters
        ----------
        basin_list : list
            流域信息列表 [{'id': 'basin_001', 'shapefile': 'path/to/basin.shp'}, ...]
        start_date : str
            开始日期
        end_date : str
            结束日期
        output_dir : str
            输出目录
        skip_preview : bool
            是否跳过预览步骤
        """
        print(f"🚀 开始批量处理 {len(basin_list)} 个流域")
        
        if not skip_preview:
            print("🔍 生成批量预览代码...")
            # 为第一个流域生成预览代码
            if basin_list:
                first_basin = basin_list[0]
                self.generate_gee_preview_code(
                    first_basin['shapefile'], 
                    start_date, 
                    end_date,
                    output_format="html"
                )
                print("💡 请预览第一个流域的数据，确认参数设置")
                response = input("继续批量处理? (y/n): ").lower().strip()
                if response != 'y':
                    print("❌ 批量处理已取消")
                    return
        
        results = []
        for i, basin_info in enumerate(basin_list, 1):
            print(f"\n📊 处理流域 {i}/{len(basin_list)}: {basin_info['id']}")
            try:
                output_file = self.automated_extraction(
                    basin_info['shapefile'],
                    start_date,
                    end_date,
                    basin_info['id'],
                    output_dir,
                    confirm_preview=False
                )
                results.append({
                    'basin_id': basin_info['id'],
                    'status': 'success',
                    'output_file': str(output_file)
                })
            except Exception as e:
                print(f"❌ 流域 {basin_info['id']} 处理失败: {e}")
                results.append({
                    'basin_id': basin_info['id'],
                    'status': 'failed',
                    'error': str(e)
                })
        
        # 保存处理结果
        results_df = pd.DataFrame(results)
        results_file = Path(output_dir) / "batch_processing_results.csv"
        results_df.to_csv(results_file, index=False)
        
        print(f"\n🎉 批量处理完成!")
        print(f"✅ 成功: {len([r for r in results if r['status'] == 'success'])} 个流域")
        print(f"❌ 失败: {len([r for r in results if r['status'] == 'failed'])} 个流域")
        print(f"📄 结果文件: {results_file}")
        
        return results

def main():
    """主函数示例"""
    print("🌍 GEE混合工作流程")
    print("=" * 50)
    
    # 初始化工作流程
    workflow = GEEHybridWorkflow()
    
    # 示例流域信息
    basin_info = {
        'shapefile': 'path/to/your/basin_boundary.shp',
        'basin_id': 'test_basin_001',
        'start_date': '2020-01-01',
        'end_date': '2020-12-31'
    }
    
    print("步骤1: 生成预览代码")
    preview_file = workflow.generate_gee_preview_code(
        basin_info['shapefile'],
        basin_info['start_date'],
        basin_info['end_date'],
        output_format="html"
    )
    
    print(f"\n步骤2: 在GEE Code Editor中预览数据")
    print(f"📄 预览文件: {preview_file}")
    print("💡 请打开预览文件，复制代码到GEE Code Editor运行")
    
    print(f"\n步骤3: 自动化数据提取")
    # 这里需要用户确认预览无误后才会执行
    output_file = workflow.automated_extraction(
        basin_info['shapefile'],
        basin_info['start_date'],
        basin_info['end_date'],
        basin_info['basin_id'],
        confirm_preview=True
    )
    
    if output_file:
        print(f"🎉 工作流程完成! 输出文件: {output_file}")

if __name__ == "__main__":
    main()

