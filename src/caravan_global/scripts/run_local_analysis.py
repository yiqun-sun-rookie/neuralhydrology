#!/usr/bin/env python3
"""
Local Data Alignment Analysis for Caravan Dataset (NetCDF format)

在本地运行，分析 Caravan 数据集的输入-目标对齐情况。

Usage:
    python src/caravan_global/scripts/run_local_analysis.py
"""

import sys
from pathlib import Path
import pandas as pd
import numpy as np
import xarray as xr
from tqdm import tqdm
import warnings
warnings.filterwarnings('ignore')


# =============================================================================
# 配置
# =============================================================================
PROJECT_ROOT = Path(__file__).resolve().parents[3]
DATA_DIR = PROJECT_ROOT / "data" / "Caravan"
TASK_DATA_DIR = PROJECT_ROOT / "src" / "caravan_global" / "data"
TASK_RESULTS_DIR = PROJECT_ROOT / "results" / "01_caravan_global" / "analysis"

CONFIG = {
    # 时间周期
    'train_start': '1981-01-01',
    'train_end': '2005-12-31',
    'val_start': '2006-01-01',
    'val_end': '2010-12-31',
    'test_start': '2011-01-01',
    'test_end': '2020-12-31',
    
    # 序列长度
    'seq_length': 365,
    
    # 动态输入特征
    'dynamic_inputs': [
        'total_precipitation_sum',
        'temperature_2m_mean',  # 可能用 mean 代替 max/min
        'potential_evaporation_sum',
        'surface_net_solar_radiation_mean',
    ],
    
    # 备用输入（如果主要输入不存在）
    'alternative_inputs': {
        'temperature_2m_mean': ['temperature_2m_max', 'temperature_2m_min'],
        'potential_evaporation_sum': ['potential_evapotranspiration_sum'],
    },
    
    # 目标变量
    'target': 'streamflow',
    
    # 筛选标准
    'min_train_samples': 1000,
    'min_val_samples': 100,
    'min_test_samples': 100,
    'max_missing_ratio': 0.3,
}


def analyze_netcdf(nc_path: Path, config: dict) -> dict:
    """分析单个流域的 NetCDF 文件"""
    result = {
        'file': nc_path.name,
        'data_start': None,
        'data_end': None,
        'input_days': 0,
        'target_days': 0,
        'overlap_days': 0,
        'train_samples': 0,
        'val_samples': 0,
        'test_samples': 0,
        'input_coverage': 0.0,
        'target_coverage': 0.0,
        'suitable': False,
        'reason': '',
        'available_vars': '',
    }
    
    try:
        ds = xr.open_dataset(nc_path)
        
        # 获取时间范围
        time = pd.to_datetime(ds['date'].values)
        result['data_start'] = str(time.min().date())
        result['data_end'] = str(time.max().date())
        
        # 列出可用变量
        available_vars = list(ds.data_vars)
        result['available_vars'] = ','.join(available_vars[:10])  # 只显示前10个
        
        # 检查目标变量
        target = config['target']
        if target not in ds:
            result['reason'] = 'no_streamflow'
            ds.close()
            return result
        
        # 获取目标数据
        target_data = ds[target].values.flatten()
        target_valid = ~np.isnan(target_data) & (target_data >= 0)
        result['target_days'] = int(np.sum(target_valid))
        
        if result['target_days'] == 0:
            result['reason'] = 'all_streamflow_nan'
            ds.close()
            return result
        
        # 检查输入特征
        input_cols = []
        for feat in config['dynamic_inputs']:
            if feat in ds:
                input_cols.append(feat)
            elif feat in config.get('alternative_inputs', {}):
                # 尝试备用特征
                for alt in config['alternative_inputs'][feat]:
                    if alt in ds:
                        input_cols.append(alt)
                        break
        
        if len(input_cols) == 0:
            result['reason'] = 'no_input_features'
            ds.close()
            return result
        
        # 计算输入有效天数（所有特征都有效）
        input_valid = np.ones(len(time), dtype=bool)
        for col in input_cols:
            col_data = ds[col].values.flatten()
            input_valid &= ~np.isnan(col_data)
        
        result['input_days'] = int(np.sum(input_valid))
        
        # 计算重叠天数
        both_valid = input_valid & target_valid
        result['overlap_days'] = int(np.sum(both_valid))
        
        if result['overlap_days'] == 0:
            result['reason'] = 'no_overlap'
            ds.close()
            return result
        
        # 创建时间索引的 DataFrame 用于按时期统计
        df = pd.DataFrame({
            'date': time,
            'valid': both_valid
        }).set_index('date')
        
        # 计算各时期样本数
        def count_samples(start: str, end: str) -> int:
            mask = (df.index >= start) & (df.index <= end)
            valid_days = df.loc[mask, 'valid'].sum()
            return max(0, int(valid_days) - config['seq_length'] + 1)
        
        result['train_samples'] = count_samples(config['train_start'], config['train_end'])
        result['val_samples'] = count_samples(config['val_start'], config['val_end'])
        result['test_samples'] = count_samples(config['test_start'], config['test_end'])
        
        # 计算覆盖率
        total_days = len(time)
        result['input_coverage'] = result['input_days'] / total_days
        result['target_coverage'] = result['target_days'] / total_days
        
        # 判断是否适合训练
        if result['train_samples'] < config['min_train_samples']:
            result['reason'] = f"train_samples<{config['min_train_samples']}"
        elif result['val_samples'] < config['min_val_samples']:
            result['reason'] = f"val_samples<{config['min_val_samples']}"
        elif result['test_samples'] < config['min_test_samples']:
            result['reason'] = f"test_samples<{config['min_test_samples']}"
        else:
            result['suitable'] = True
            result['reason'] = 'ok'
        
        ds.close()
        
    except Exception as e:
        result['reason'] = f"error:{str(e)[:50]}"
    
    return result


def main():
    print("=" * 70)
    print("Caravan 数据对齐分析 (本地运行)")
    print("=" * 70)
    print(f"\n数据目录: {DATA_DIR}")
    print(f"训练期: {CONFIG['train_start']} ~ {CONFIG['train_end']}")
    print(f"验证期: {CONFIG['val_start']} ~ {CONFIG['val_end']}")
    print(f"测试期: {CONFIG['test_start']} ~ {CONFIG['test_end']}")
    print()
    
    # 检查数据目录
    netcdf_dir = DATA_DIR / "timeseries" / "netcdf"
    if not netcdf_dir.exists():
        print(f"[ERROR] NetCDF 目录不存在: {netcdf_dir}")
        return 1
    
    # 获取子数据集
    subdatasets = [d.name for d in netcdf_dir.iterdir() if d.is_dir()]
    print(f"发现 {len(subdatasets)} 个子数据集: {subdatasets}")
    print()
    
    # 分析所有流域
    all_results = []
    valid_basins = []
    
    for subdataset in sorted(subdatasets):
        subdir = netcdf_dir / subdataset
        nc_files = list(subdir.glob("*.nc"))
        
        print(f"分析 {subdataset}: {len(nc_files)} 个流域...")
        
        subdataset_valid = 0
        for nc_file in tqdm(nc_files, desc=f"  {subdataset}", leave=True):
            basin_id = f"{subdataset}_{nc_file.stem}"
            
            result = analyze_netcdf(nc_file, CONFIG)
            result['basin_id'] = basin_id
            result['subdataset'] = subdataset
            
            if result['suitable']:
                valid_basins.append(basin_id)
                subdataset_valid += 1
            
            all_results.append(result)
        
        pct = subdataset_valid / len(nc_files) * 100 if nc_files else 0
        print(f"  -> 有效: {subdataset_valid}/{len(nc_files)} ({pct:.1f}%)")
    
    # 生成报告
    print()
    print("=" * 70)
    print("分析结果")
    print("=" * 70)
    
    df = pd.DataFrame(all_results)
    
    # 总体统计
    total = len(df)
    valid = len(valid_basins)
    print(f"\n总流域数: {total}")
    print(f"适合训练: {valid} ({valid/total*100:.1f}%)")
    
    # 按数据集统计
    print("\n按数据集:")
    summary = df.groupby('subdataset').agg({
        'suitable': ['sum', 'count'],
        'train_samples': 'mean',
        'overlap_days': 'mean',
    }).round(0)
    summary.columns = ['valid', 'total', 'avg_train', 'avg_overlap']
    summary['pct'] = (summary['valid'] / summary['total'] * 100).round(1)
    print(summary.to_string())
    
    # 拒绝原因
    rejected = df[~df['suitable']]
    if len(rejected) > 0:
        print("\n拒绝原因:")
        reasons = rejected['reason'].value_counts()
        for r, c in reasons.head(10).items():
            print(f"  {r}: {c}")
    
    # 有效流域统计
    valid_df = df[df['suitable']]
    if len(valid_df) > 0:
        print("\n有效流域统计:")
        print(f"  平均重叠天数: {valid_df['overlap_days'].mean():.0f}")
        print(f"  平均训练样本: {valid_df['train_samples'].mean():.0f}")
        print(f"  平均验证样本: {valid_df['val_samples'].mean():.0f}")
        print(f"  平均测试样本: {valid_df['test_samples'].mean():.0f}")
    
    # 保存结果（任务隔离）
    TASK_DATA_DIR.mkdir(parents=True, exist_ok=True)
    TASK_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    
    # 保存详细报告
    report_file = TASK_RESULTS_DIR / "data_alignment_report.csv"
    df.to_csv(report_file, index=False)
    print(f"\n[SAVED] 报告: {report_file}")
    
    # 保存有效流域（纯列表，避免注释被解析成 basin id）
    valid_file = TASK_DATA_DIR / "valid_basins.txt"
    with open(valid_file, 'w') as f:
        for b in sorted(valid_basins):
            f.write(f"{b}\n")
    print(f"[SAVED] 有效流域: {valid_file}")
    
    # 保存无效流域
    invalid_basins = df[~df['suitable']]['basin_id'].tolist()
    invalid_file = TASK_DATA_DIR / "invalid_basins.txt"
    with open(invalid_file, 'w') as f:
        for b in sorted(invalid_basins):
            f.write(f"{b}\n")
    print(f"[SAVED] 无效流域: {invalid_file}")
    
    print()
    print("=" * 70)
    print(f"完成！{valid} 个流域适合训练")
    print("=" * 70)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
