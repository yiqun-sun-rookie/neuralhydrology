"""
准备CAMELSH数据以适配NeuralHydrology的GenericDataset格式

GenericDataset要求:
1. data_dir/time_series/<basin_id>.nc - 时间序列数据
2. data_dir/attributes/*.csv - 静态属性
3. NC文件时间坐标名需为 'date'
"""

import os
import shutil
import xarray as xr
import pandas as pd
from pathlib import Path

def main():
    print('='*60)
    print('准备CAMELSH数据以适配NeuralHydrology')
    print('='*60)
    
    base_dir = Path(r'F:\github\pycharm\projects\neuralhydrology\data\camelsh')
    source_ts = base_dir / 'timeseries' / 'Data' / 'CAMELSH' / 'timeseries'
    
    # 目标目录
    target_ts = base_dir / 'time_series'
    target_attr = base_dir / 'attributes_nh'
    
    target_ts.mkdir(exist_ok=True)
    target_attr.mkdir(exist_ok=True)
    
    # 读取good_basins
    with open(base_dir / 'good_basins.txt') as f:
        good_basins = set(f.read().strip().split('\n'))
    print(f'筛选流域数: {len(good_basins)}')
    
    # 转换NC文件格式
    print()
    print('转换NC文件格式 (重命名时间坐标 DateTime -> date)...')
    
    source_files = list(source_ts.glob('*.nc'))
    converted = 0
    
    for i, src_file in enumerate(source_files):
        basin_id = src_file.stem
        
        # 只转换good_basins中的流域
        if basin_id not in good_basins:
            continue
            
        dst_file = target_ts / f'{basin_id}.nc'
        
        # 跳过已转换的
        if dst_file.exists():
            converted += 1
            continue
        
        if i % 200 == 0:
            print(f'  进度: {i}/{len(source_files)}')
        
        try:
            # 读取并重命名时间坐标
            ds = xr.open_dataset(src_file)
            ds = ds.rename({'DateTime': 'date'})
            
            # 保存
            ds.to_netcdf(dst_file)
            ds.close()
            converted += 1
        except Exception as e:
            print(f'  错误 {basin_id}: {e}')
    
    print(f'已转换: {converted} 个流域')
    
    # 复制属性文件
    print()
    print('复制属性文件...')
    src_attr = base_dir / 'attributes_merged.csv'
    dst_attr = target_attr / 'attributes.csv'
    shutil.copy(src_attr, dst_attr)
    print(f'属性文件已复制到: {dst_attr}')
    
    # 验证
    print()
    print('='*60)
    print('验证数据结构')
    print('='*60)
    
    nc_files = list(target_ts.glob('*.nc'))
    print(f'time_series NC文件数: {len(nc_files)}')
    
    # 检查样例文件
    sample = nc_files[0]
    ds = xr.open_dataset(sample)
    print(f'样例文件: {sample.name}')
    print(f'  坐标: {list(ds.coords)}')
    print(f'  变量: {list(ds.data_vars)}')
    ds.close()
    
    print()
    print('✅ 数据准备完成!')
    print(f'数据目录: {base_dir}')
    print(f'  - time_series/: {len(nc_files)} 个NC文件')
    print(f'  - attributes_nh/: attributes.csv')

if __name__ == '__main__':
    main()

