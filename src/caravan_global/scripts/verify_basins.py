#!/usr/bin/env python3
"""
Caravan 数据对齐分析 - 严格验证版

确保三个时期使用相同的流域集合。
"""

import pandas as pd
import numpy as np
import xarray as xr
from pathlib import Path
from tqdm import tqdm
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path(__file__).resolve().parents[3]
DATA_DIR = PROJECT_ROOT / "data" / "Caravan"
TASK_DATA_DIR = PROJECT_ROOT / "src" / "caravan_global" / "data"
TASK_RESULTS_DIR = PROJECT_ROOT / "results" / "01_caravan_global" / "analysis"
netcdf_dir = DATA_DIR / "timeseries" / "netcdf"

# ==================== 配置 ====================
SEQ_LENGTH = 365  # 序列长度

# 时间区间
TRAIN_START, TRAIN_END = "1981-01-01", "2005-12-31"
VAL_START, VAL_END = "2006-01-01", "2010-12-31"
TEST_START, TEST_END = "2011-01-01", "2020-12-31"

# 最低样本要求
MIN_TRAIN = 1000
MIN_VAL = 100
MIN_TEST = 100

# 动态输入特征
DYNAMIC_INPUTS = [
    "total_precipitation_sum",
    "temperature_2m_mean",
    "potential_evaporation_sum",
    "surface_net_solar_radiation_mean",
]

# 备用特征
ALT_INPUTS = {
    "temperature_2m_mean": ["temperature_2m_max", "temperature_2m_min"],
    "potential_evaporation_sum": ["potential_evapotranspiration_sum"],
}

TARGET = "streamflow"


def count_valid_samples(valid_mask, start_date, end_date, time_index, seq_length):
    """
    计算在指定时期内可用的样本数。
    
    深度学习样本定义:
    - 每个样本需要 seq_length 天的连续输入
    - 目标是序列最后一天的值
    - 可用样本数 = 时期内有效天数 - seq_length + 1
    """
    mask = (time_index >= start_date) & (time_index <= end_date)
    period_valid = valid_mask[mask]
    valid_days = period_valid.sum()
    samples = max(0, valid_days - seq_length + 1)
    return int(samples), int(valid_days)


def analyze_basin(nc_path):
    """分析单个流域"""
    result = {
        "basin_id": "",
        "subdataset": "",
        "data_start": None,
        "data_end": None,
        "total_days": 0,
        "input_valid_days": 0,
        "target_valid_days": 0,
        "overlap_days": 0,
        "train_valid_days": 0,
        "train_samples": 0,
        "val_valid_days": 0,
        "val_samples": 0,
        "test_valid_days": 0,
        "test_samples": 0,
        "train_ok": False,
        "val_ok": False,
        "test_ok": False,
        "all_ok": False,
        "reject_reason": "",
        "input_features_found": "",
    }
    
    try:
        ds = xr.open_dataset(nc_path)
        time = pd.to_datetime(ds["date"].values)
        
        result["data_start"] = str(time.min().date())
        result["data_end"] = str(time.max().date())
        result["total_days"] = len(time)
        
        # 检查目标变量
        if TARGET not in ds:
            result["reject_reason"] = "no_streamflow_variable"
            ds.close()
            return result
        
        target_data = ds[TARGET].values.flatten()
        target_valid = ~np.isnan(target_data) & (target_data >= 0)
        result["target_valid_days"] = int(target_valid.sum())
        
        # 检查输入特征
        found_features = []
        for feat in DYNAMIC_INPUTS:
            if feat in ds:
                found_features.append(feat)
            elif feat in ALT_INPUTS:
                for alt in ALT_INPUTS[feat]:
                    if alt in ds:
                        found_features.append(alt)
                        break
        
        result["input_features_found"] = ",".join(found_features)
        
        if len(found_features) < 3:
            result["reject_reason"] = f"only_{len(found_features)}_input_features"
            ds.close()
            return result
        
        # 计算输入有效天数
        input_valid = np.ones(len(time), dtype=bool)
        for feat in found_features:
            feat_data = ds[feat].values.flatten()
            input_valid &= ~np.isnan(feat_data)
        
        result["input_valid_days"] = int(input_valid.sum())
        
        # 输入-目标重叠
        both_valid = input_valid & target_valid
        result["overlap_days"] = int(both_valid.sum())
        
        if result["overlap_days"] < SEQ_LENGTH:
            result["reject_reason"] = f"overlap_{result['overlap_days']}_lt_seq_length"
            ds.close()
            return result
        
        # 计算各时期样本数
        time_index = pd.DatetimeIndex(time)
        
        result["train_samples"], result["train_valid_days"] = count_valid_samples(
            both_valid, TRAIN_START, TRAIN_END, time_index, SEQ_LENGTH
        )
        result["val_samples"], result["val_valid_days"] = count_valid_samples(
            both_valid, VAL_START, VAL_END, time_index, SEQ_LENGTH
        )
        result["test_samples"], result["test_valid_days"] = count_valid_samples(
            both_valid, TEST_START, TEST_END, time_index, SEQ_LENGTH
        )
        
        # 检查是否满足要求
        result["train_ok"] = result["train_samples"] >= MIN_TRAIN
        result["val_ok"] = result["val_samples"] >= MIN_VAL
        result["test_ok"] = result["test_samples"] >= MIN_TEST
        result["all_ok"] = result["train_ok"] and result["val_ok"] and result["test_ok"]
        
        if not result["train_ok"]:
            result["reject_reason"] = f"train_{result['train_samples']}_lt_{MIN_TRAIN}"
        elif not result["val_ok"]:
            result["reject_reason"] = f"val_{result['val_samples']}_lt_{MIN_VAL}"
        elif not result["test_ok"]:
            result["reject_reason"] = f"test_{result['test_samples']}_lt_{MIN_TEST}"
        else:
            result["reject_reason"] = "OK"
        
        ds.close()
        
    except Exception as e:
        result["reject_reason"] = f"error:{str(e)[:50]}"
    
    return result


def main():
    print("=" * 70)
    print("Caravan 数据对齐分析 - 严格验证版")
    print("=" * 70)
    print()
    print("配置:")
    print(f"  序列长度: {SEQ_LENGTH}")
    print(f"  训练期: {TRAIN_START} ~ {TRAIN_END}")
    print(f"  验证期: {VAL_START} ~ {VAL_END}")
    print(f"  测试期: {TEST_START} ~ {TEST_END}")
    print(f"  最小训练样本: {MIN_TRAIN}")
    print(f"  最小验证样本: {MIN_VAL}")
    print(f"  最小测试样本: {MIN_TEST}")
    print()
    
    subdatasets = sorted([d.name for d in netcdf_dir.iterdir() if d.is_dir()])
    print(f"发现 {len(subdatasets)} 个子数据集: {subdatasets}")
    print()
    
    all_results = []
    
    for subdataset in subdatasets:
        subdir = netcdf_dir / subdataset
        nc_files = sorted(subdir.glob("*.nc"))
        
        print(f"分析 {subdataset}: {len(nc_files)} 个流域...")
        
        for nc_file in tqdm(nc_files, desc=f"  {subdataset}", leave=False):
            result = analyze_basin(nc_file)
            # NetCDF 文件名已经是 "subdataset_id.nc" 格式，直接使用 stem
            result["basin_id"] = nc_file.stem
            result["subdataset"] = subdataset
            all_results.append(result)
    
    print()
    print("=" * 70)
    print("分析结果")
    print("=" * 70)
    
    df = pd.DataFrame(all_results)
    
    # 统计
    total = len(df)
    all_ok = df["all_ok"].sum()
    train_ok = df["train_ok"].sum()
    val_ok = df["val_ok"].sum()
    test_ok = df["test_ok"].sum()
    
    print()
    print("总体统计:")
    print(f"  总流域数:         {total}")
    print(f"  训练期满足:       {train_ok} ({train_ok/total*100:.1f}%)")
    print(f"  验证期满足:       {val_ok} ({val_ok/total*100:.1f}%)")
    print(f"  测试期满足:       {test_ok} ({test_ok/total*100:.1f}%)")
    print(f"  三期都满足:       {all_ok} ({all_ok/total*100:.1f}%)")
    
    print()
    print("按数据集:")
    header = f"{'数据集':12s} {'三期满足':>10s} {'总数':>8s} {'有效率':>8s} {'平均训练样本':>12s}"
    print(header)
    for sub in subdatasets:
        sub_df = df[df.subdataset == sub]
        sub_ok = sub_df["all_ok"].sum()
        sub_total = len(sub_df)
        pct = sub_ok / sub_total * 100 if sub_total > 0 else 0
        avg_train = sub_df[sub_df["all_ok"]]["train_samples"].mean() if sub_ok > 0 else 0
        print(f"{sub:12s} {sub_ok:10d} {sub_total:8d} {pct:7.1f}% {avg_train:12.0f}")
    
    # 拒绝原因
    print()
    print("拒绝原因统计:")
    rejected = df[~df["all_ok"]]
    reasons = rejected["reject_reason"].apply(
        lambda x: x.split("_")[0] if "_" in x else x
    ).value_counts()
    for reason, count in reasons.head(10).items():
        print(f"  {reason}: {count}")
    
    # 验证样本统计
    print()
    print("验证: 有效流域的样本统计")
    valid_df = df[df["all_ok"]]
    print(f"  训练样本: min={valid_df.train_samples.min()}, max={valid_df.train_samples.max()}, mean={valid_df.train_samples.mean():.0f}")
    print(f"  验证样本: min={valid_df.val_samples.min()}, max={valid_df.val_samples.max()}, mean={valid_df.val_samples.mean():.0f}")
    print(f"  测试样本: min={valid_df.test_samples.min()}, max={valid_df.test_samples.max()}, mean={valid_df.test_samples.mean():.0f}")
    
    # 保存报告到任务结果目录（与 data/ 原始数据隔离）
    TASK_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    TASK_DATA_DIR.mkdir(parents=True, exist_ok=True)
    report_file = TASK_RESULTS_DIR / "data_alignment_report_v2.csv"
    df.to_csv(report_file, index=False)
    print()
    print(f"[SAVED] 报告: {report_file}")
    
    # 保存有效流域列表（纯列表格式，避免注释行被训练代码误解析）
    valid_basins = df[df["all_ok"]]["basin_id"].tolist()
    valid_file = TASK_DATA_DIR / "valid_basins_strict.txt"
    
    with open(valid_file, "w", encoding="utf-8") as f:
        for b in sorted(valid_basins):
            f.write(f"{b}\n")
    
    print(f"[SAVED] 有效流域: {valid_file} ({len(valid_basins)} basins)")
    
    # 更新训练入口使用的主列表
    main_valid_file = TASK_DATA_DIR / "valid_basins.txt"
    import shutil
    shutil.copy(valid_file, main_valid_file)
    print(f"[SAVED] 更新主文件: {main_valid_file}")
    
    print()
    print("=" * 70)
    print(f"最终结果: {len(valid_basins)} 个流域适合训练")
    print("=" * 70)
    
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
