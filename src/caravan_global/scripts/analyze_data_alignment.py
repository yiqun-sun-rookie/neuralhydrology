#!/usr/bin/env python3
"""
Comprehensive Data Alignment Analysis for Deep Learning Training

从深度学习水文模型训练的角度，分析 Caravan 数据集的：
1. 输入特征（气象数据）与目标变量（径流）的时间对齐
2. 各时期的数据覆盖情况
3. 有效训练样本的计算
4. 静态属性的完整性

Usage (on HPC):
    python src/caravan_global/scripts/analyze_data_alignment.py

Output:
    - data/Caravan/data_alignment_report.csv    # 详细报告
    - data/Caravan/valid_basins_strict.txt      # 严格筛选的流域列表
    - data/Caravan/analysis_summary.json        # 汇总统计
"""

import os
import sys
import json
from pathlib import Path
from datetime import datetime
from collections import defaultdict
import pandas as pd
import numpy as np
from tqdm import tqdm


# =============================================================================
# 深度学习训练配置
# =============================================================================
CONFIG = {
    # 时间周期
    'train_start': '1981-01-01',
    'train_end': '2005-12-31',
    'val_start': '2006-01-01',
    'val_end': '2010-12-31',
    'test_start': '2011-01-01',
    'test_end': '2020-12-31',
    
    # 序列长度（用于 LSTM 的回溯窗口）
    'seq_length': 365,
    
    # 预测设置
    'predict_last_n': 1,  # 只预测最后一天
    
    # 动态输入特征（必须全部有效）
    'dynamic_inputs': [
        'total_precipitation_sum',       # 降水
        'surface_net_solar_radiation_mean',  # 辐射
        'temperature_2m_max',            # 最高温
        'temperature_2m_min',            # 最低温
        'dewpoint_temperature_2m_mean',  # 露点温度
    ],
    
    # 目标变量
    'target': 'streamflow',
    
    # 静态属性（必须全部有效）
    'static_attributes': [
        'ele_mt_sav',       # 高程
        'slp_dg_sav',       # 坡度
        'area',             # 面积
        'sgr_dk_sav',       # 土壤深度
        'snd_pc_sav',       # 砂含量
        'cly_pc_sav',       # 粘土含量
        'slt_pc_sav',       # 淤泥含量
        'for_pc_sse',       # 森林覆盖
        'p_mean',           # 平均降水
        'aridity_ERA5_LAND', # 干旱指数
        'frac_snow',        # 雪比例
        'high_prec_freq',   # 高降水频率
    ],
    
    # 筛选标准
    'min_train_samples': 1000,   # 训练期最少有效样本数
    'min_val_samples': 100,      # 验证期最少有效样本数
    'min_test_samples': 100,     # 测试期最少有效样本数
    'max_missing_ratio': 0.3,    # 最大缺失率
}


def find_caravan_data_dir():
    """Find Caravan data directory."""
    possible_paths = [
        Path("data/Caravan"),
        Path("/data1/home/sunyiq/neuralhydrology/data/Caravan"),
        Path.home() / "neuralhydrology" / "data" / "Caravan",
    ]
    
    for p in possible_paths:
        if p.exists() and (p / "timeseries").exists():
            return p
    
    raise FileNotFoundError("Cannot find Caravan data directory with timeseries")


def load_static_attributes(data_dir: Path) -> dict:
    """Load static attributes for all basins."""
    attrs_dir = data_dir / "attributes"
    if not attrs_dir.exists():
        print("[WARN] Attributes directory not found")
        return {}
    
    all_attrs = {}
    
    for csv_file in attrs_dir.glob("**/attributes_*.csv"):
        try:
            df = pd.read_csv(csv_file, index_col=0)
            subdataset = csv_file.stem.replace("attributes_", "")
            
            for basin_id in df.index:
                full_id = f"{subdataset}_{basin_id}"
                all_attrs[full_id] = df.loc[basin_id].to_dict()
        except Exception as e:
            print(f"[WARN] Error loading {csv_file}: {e}")
    
    return all_attrs


def check_static_attributes(basin_attrs: dict, required_attrs: list) -> dict:
    """Check if all required static attributes are valid."""
    result = {
        'all_valid': True,
        'missing': [],
        'nan_attrs': [],
    }
    
    if not basin_attrs:
        result['all_valid'] = False
        result['missing'] = required_attrs
        return result
    
    for attr in required_attrs:
        if attr not in basin_attrs:
            result['missing'].append(attr)
            result['all_valid'] = False
        elif pd.isna(basin_attrs.get(attr)):
            result['nan_attrs'].append(attr)
            result['all_valid'] = False
    
    return result


def analyze_timeseries(csv_path: Path, config: dict) -> dict:
    """
    Analyze a single basin's timeseries from deep learning perspective.
    
    核心逻辑：
    1. 检查气象数据（输入）和径流数据（目标）是否同时有效
    2. 计算每个时期的有效样本数
    3. 一个有效样本 = 连续 seq_length 天的输入 + 最后一天的目标
    """
    result = {
        'basin_id': csv_path.stem,
        
        # 数据范围
        'data_start': None,
        'data_end': None,
        
        # 气象数据（输入特征）覆盖情况
        'input_start': None,
        'input_end': None,
        'input_total_days': 0,
        
        # 径流数据（目标变量）覆盖情况
        'target_start': None,
        'target_end': None,
        'target_total_days': 0,
        
        # 共同区间（输入和目标都有效）
        'overlap_start': None,
        'overlap_end': None,
        'overlap_days': 0,
        
        # 各时期有效样本数（从深度学习角度）
        'train_samples': 0,
        'val_samples': 0,
        'test_samples': 0,
        
        # 数据质量
        'input_missing_ratio': 1.0,
        'target_missing_ratio': 1.0,
        
        # 是否适合训练
        'suitable_for_training': False,
        'reject_reason': '',
    }
    
    try:
        # 读取时间序列
        df = pd.read_csv(csv_path, parse_dates=['date'])
        df = df.set_index('date').sort_index()
        
        result['data_start'] = df.index.min().strftime('%Y-%m-%d')
        result['data_end'] = df.index.max().strftime('%Y-%m-%d')
        
        # =====================================================================
        # 1. 检查输入特征（气象数据）
        # =====================================================================
        input_cols = [c for c in config['dynamic_inputs'] if c in df.columns]
        missing_inputs = set(config['dynamic_inputs']) - set(input_cols)
        
        if missing_inputs:
            result['reject_reason'] = f"missing_inputs:{','.join(missing_inputs)}"
            return result
        
        # 所有输入特征都有效的行
        input_valid = df[input_cols].notna().all(axis=1)
        input_valid_df = df[input_valid]
        
        if len(input_valid_df) == 0:
            result['reject_reason'] = 'no_valid_input_data'
            return result
        
        result['input_start'] = input_valid_df.index.min().strftime('%Y-%m-%d')
        result['input_end'] = input_valid_df.index.max().strftime('%Y-%m-%d')
        result['input_total_days'] = len(input_valid_df)
        
        # =====================================================================
        # 2. 检查目标变量（径流）
        # =====================================================================
        target_col = config['target']
        if target_col not in df.columns:
            result['reject_reason'] = 'no_streamflow_column'
            return result
        
        # 有效的径流数据（非空且非负）
        target_valid = df[target_col].notna() & (df[target_col] >= 0)
        target_valid_df = df[target_valid]
        
        if len(target_valid_df) == 0:
            result['reject_reason'] = 'no_valid_streamflow'
            return result
        
        result['target_start'] = target_valid_df.index.min().strftime('%Y-%m-%d')
        result['target_end'] = target_valid_df.index.max().strftime('%Y-%m-%d')
        result['target_total_days'] = len(target_valid_df)
        
        # =====================================================================
        # 3. 计算共同区间（输入和目标都有效）
        # =====================================================================
        both_valid = input_valid & target_valid
        overlap_df = df[both_valid]
        
        if len(overlap_df) == 0:
            result['reject_reason'] = 'no_overlap_between_input_and_target'
            return result
        
        result['overlap_start'] = overlap_df.index.min().strftime('%Y-%m-%d')
        result['overlap_end'] = overlap_df.index.max().strftime('%Y-%m-%d')
        result['overlap_days'] = len(overlap_df)
        
        # =====================================================================
        # 4. 计算有效训练样本数
        # 
        # 深度学习样本定义：
        # - 需要连续 seq_length 天的有效输入数据
        # - 最后一天需要有效的目标值
        # - 样本数 ≈ 有效天数 - seq_length + 1（考虑缺失情况会更少）
        # =====================================================================
        seq_length = config['seq_length']
        
        def count_valid_samples(start_date: str, end_date: str) -> int:
            """Count valid training samples in a period."""
            mask = (df.index >= start_date) & (df.index <= end_date)
            period_df = df[mask]
            
            if len(period_df) < seq_length:
                return 0
            
            # 简化计算：统计在该时期内，输入和目标都有效的天数
            # 减去 seq_length 得到大致的样本数
            period_both_valid = both_valid[mask]
            valid_days = period_both_valid.sum()
            
            # 考虑到需要连续的序列，实际样本数会更少
            # 这里用一个简化的估计
            if valid_days < seq_length:
                return 0
            
            return max(0, valid_days - seq_length + 1)
        
        result['train_samples'] = count_valid_samples(
            config['train_start'], config['train_end']
        )
        result['val_samples'] = count_valid_samples(
            config['val_start'], config['val_end']
        )
        result['test_samples'] = count_valid_samples(
            config['test_start'], config['test_end']
        )
        
        # =====================================================================
        # 5. 计算缺失率
        # =====================================================================
        total_period = (pd.Timestamp(config['test_end']) - 
                       pd.Timestamp(config['train_start'])).days + 1
        
        result['input_missing_ratio'] = 1 - (result['input_total_days'] / total_period)
        result['target_missing_ratio'] = 1 - (result['target_total_days'] / total_period)
        
        # =====================================================================
        # 6. 判断是否适合训练
        # =====================================================================
        if result['train_samples'] < config['min_train_samples']:
            result['reject_reason'] = f"insufficient_train_samples({result['train_samples']}<{config['min_train_samples']})"
        elif result['val_samples'] < config['min_val_samples']:
            result['reject_reason'] = f"insufficient_val_samples({result['val_samples']}<{config['min_val_samples']})"
        elif result['test_samples'] < config['min_test_samples']:
            result['reject_reason'] = f"insufficient_test_samples({result['test_samples']}<{config['min_test_samples']})"
        elif result['target_missing_ratio'] > config['max_missing_ratio']:
            result['reject_reason'] = f"high_missing_ratio({result['target_missing_ratio']:.1%}>{config['max_missing_ratio']:.0%})"
        else:
            result['suitable_for_training'] = True
            result['reject_reason'] = 'ok'
        
    except Exception as e:
        result['reject_reason'] = f"error:{str(e)[:80]}"
    
    return result


def main():
    print("=" * 70)
    print("Caravan 数据对齐分析 - 深度学习训练视角")
    print("=" * 70)
    print()
    print("分析目标:")
    print("  1. 气象数据（输入）与径流数据（目标）的时间对齐")
    print("  2. 各训练/验证/测试时期的有效样本数")
    print("  3. 静态属性的完整性检查")
    print("  4. 筛选适合深度学习训练的流域")
    print()
    
    # =========================================================================
    # 配置信息
    # =========================================================================
    print("训练配置:")
    print(f"  训练期: {CONFIG['train_start']} ~ {CONFIG['train_end']}")
    print(f"  验证期: {CONFIG['val_start']} ~ {CONFIG['val_end']}")
    print(f"  测试期: {CONFIG['test_start']} ~ {CONFIG['test_end']}")
    print(f"  序列长度: {CONFIG['seq_length']} 天")
    print()
    print("输入特征 (气象数据):")
    for feat in CONFIG['dynamic_inputs']:
        print(f"    - {feat}")
    print()
    print("筛选标准:")
    print(f"  最少训练样本: {CONFIG['min_train_samples']}")
    print(f"  最少验证样本: {CONFIG['min_val_samples']}")
    print(f"  最少测试样本: {CONFIG['min_test_samples']}")
    print(f"  最大缺失率: {CONFIG['max_missing_ratio']:.0%}")
    print()
    
    # =========================================================================
    # 查找数据目录
    # =========================================================================
    try:
        data_dir = find_caravan_data_dir()
        print(f"[INFO] 数据目录: {data_dir}")
    except FileNotFoundError as e:
        print(f"[ERROR] {e}")
        return 1
    
    # =========================================================================
    # 加载静态属性
    # =========================================================================
    print("[INFO] 加载静态属性...")
    static_attrs = load_static_attributes(data_dir)
    print(f"[INFO] 已加载 {len(static_attrs)} 个流域的静态属性")
    print()
    
    # =========================================================================
    # 分析所有流域
    # =========================================================================
    timeseries_dir = data_dir / "timeseries" / "csv"
    subdatasets = [d.name for d in timeseries_dir.iterdir() 
                   if d.is_dir() and not d.name.startswith('.')]
    
    print(f"[INFO] 发现 {len(subdatasets)} 个子数据集: {sorted(subdatasets)}")
    print()
    
    all_results = []
    valid_basins = []
    
    for subdataset in sorted(subdatasets):
        ts_dir = timeseries_dir / subdataset
        csv_files = list(ts_dir.glob("*.csv"))
        
        print(f"[INFO] 分析 {subdataset}: {len(csv_files)} 个流域")
        
        subdataset_valid = 0
        for csv_file in tqdm(csv_files, desc=f"  {subdataset}", leave=False):
            basin_id = f"{subdataset}_{csv_file.stem}"
            
            # 分析时间序列
            result = analyze_timeseries(csv_file, CONFIG)
            result['basin_id'] = basin_id
            result['subdataset'] = subdataset
            
            # 检查静态属性
            basin_attrs = static_attrs.get(basin_id, {})
            static_check = check_static_attributes(basin_attrs, CONFIG['static_attributes'])
            result['static_attrs_valid'] = static_check['all_valid']
            result['static_missing'] = ','.join(static_check['missing']) if static_check['missing'] else ''
            result['static_nan'] = ','.join(static_check['nan_attrs']) if static_check['nan_attrs'] else ''
            
            # 最终判断（时序有效 + 静态属性有效）
            if result['suitable_for_training'] and static_check['all_valid']:
                valid_basins.append(basin_id)
                subdataset_valid += 1
            elif result['suitable_for_training'] and not static_check['all_valid']:
                result['suitable_for_training'] = False
                result['reject_reason'] = f"invalid_static_attrs:{result['static_missing'] or result['static_nan']}"
            
            all_results.append(result)
        
        valid_pct = subdataset_valid / len(csv_files) * 100 if csv_files else 0
        print(f"       有效: {subdataset_valid}/{len(csv_files)} ({valid_pct:.1f}%)")
    
    # =========================================================================
    # 生成报告
    # =========================================================================
    print()
    print("=" * 70)
    print("分析结果")
    print("=" * 70)
    
    df_results = pd.DataFrame(all_results)
    
    # 总体统计
    total_basins = len(df_results)
    total_valid = len(valid_basins)
    print(f"\n总流域数: {total_basins}")
    print(f"适合训练: {total_valid} ({total_valid/total_basins*100:.1f}%)")
    
    # 按子数据集统计
    print("\n按数据集统计:")
    summary = df_results.groupby('subdataset').agg({
        'suitable_for_training': ['sum', 'count'],
        'train_samples': 'mean',
        'overlap_days': 'mean',
    }).round(0)
    summary.columns = ['valid', 'total', 'avg_train_samples', 'avg_overlap_days']
    summary['valid_pct'] = (summary['valid'] / summary['total'] * 100).round(1)
    print(summary.to_string())
    
    # 拒绝原因统计
    rejected = df_results[~df_results['suitable_for_training']]
    if len(rejected) > 0:
        print("\n拒绝原因分布:")
        # 提取主要原因
        def get_main_reason(r):
            if r.startswith('insufficient'):
                return r.split('(')[0]
            elif r.startswith('missing_inputs'):
                return 'missing_inputs'
            elif r.startswith('invalid_static'):
                return 'invalid_static_attrs'
            else:
                return r.split(':')[0] if ':' in r else r
        
        reasons = rejected['reject_reason'].apply(get_main_reason).value_counts()
        for reason, count in reasons.head(10).items():
            print(f"  {reason}: {count}")
    
    # 数据对齐统计
    valid_df = df_results[df_results['suitable_for_training']]
    if len(valid_df) > 0:
        print("\n有效流域的数据对齐情况:")
        print(f"  平均重叠天数: {valid_df['overlap_days'].mean():.0f} 天")
        print(f"  平均训练样本: {valid_df['train_samples'].mean():.0f}")
        print(f"  平均验证样本: {valid_df['val_samples'].mean():.0f}")
        print(f"  平均测试样本: {valid_df['test_samples'].mean():.0f}")
        print(f"  输入缺失率: {valid_df['input_missing_ratio'].mean()*100:.1f}%")
        print(f"  目标缺失率: {valid_df['target_missing_ratio'].mean()*100:.1f}%")
    
    # =========================================================================
    # 保存结果
    # =========================================================================
    output_dir = data_dir
    
    # 保存详细报告
    report_file = output_dir / "data_alignment_report.csv"
    df_results.to_csv(report_file, index=False)
    print(f"\n[SAVED] 详细报告: {report_file}")
    
    # 保存有效流域列表
    valid_file = output_dir / "valid_basins_strict.txt"
    with open(valid_file, 'w') as f:
        f.write(f"# Caravan 有效流域列表 (严格筛选)\n")
        f.write(f"# 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"# 筛选标准:\n")
        f.write(f"#   - 训练期: {CONFIG['train_start']} ~ {CONFIG['train_end']}\n")
        f.write(f"#   - 最少训练样本: {CONFIG['min_train_samples']}\n")
        f.write(f"#   - 最少验证样本: {CONFIG['min_val_samples']}\n")
        f.write(f"#   - 最少测试样本: {CONFIG['min_test_samples']}\n")
        f.write(f"#   - 所有输入特征和静态属性完整\n")
        f.write(f"# 总数: {len(valid_basins)}\n")
        for basin in sorted(valid_basins):
            f.write(f"{basin}\n")
    print(f"[SAVED] 有效流域: {valid_file}")
    
    # 保存汇总统计
    summary_data = {
        'generated_at': datetime.now().isoformat(),
        'config': CONFIG,
        'total_basins': total_basins,
        'valid_basins': total_valid,
        'valid_ratio': total_valid / total_basins,
        'by_subdataset': summary.to_dict(),
        'reject_reasons': rejected['reject_reason'].apply(get_main_reason).value_counts().to_dict() if len(rejected) > 0 else {},
    }
    summary_file = output_dir / "analysis_summary.json"
    with open(summary_file, 'w') as f:
        json.dump(summary_data, f, indent=2, default=str)
    print(f"[SAVED] 汇总统计: {summary_file}")
    
    # 同时生成一个兼容的 valid_basins.txt
    compat_file = output_dir / "valid_basins.txt"
    with open(compat_file, 'w') as f:
        f.write(f"# Valid Caravan basins for training\n")
        f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"# Total: {len(valid_basins)}\n")
        for basin in sorted(valid_basins):
            f.write(f"{basin}\n")
    print(f"[SAVED] 兼容格式: {compat_file}")
    
    print()
    print("=" * 70)
    print(f"分析完成！共 {total_valid} 个流域适合训练")
    print("=" * 70)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
