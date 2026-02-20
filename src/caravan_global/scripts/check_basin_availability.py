#!/usr/bin/env python3
"""
Comprehensive basin data availability check for Caravan dataset.

Usage (on HPC):
    python src/caravan_global/scripts/check_basin_availability.py

This script:
1. Scans all basin timeseries files in Caravan dataset
2. Checks streamflow data availability for each basin
3. Filters basins based on training period requirements
4. Generates detailed report and valid basin list

Output files:
- src/caravan_global/data/valid_basins.txt: Basins suitable for training (pure list)
- results/01_caravan_global/analysis/basin_availability_report.csv: Detailed report
"""

import os
import sys
from pathlib import Path
from collections import defaultdict
import pandas as pd
import numpy as np
from tqdm import tqdm


# Configuration
TRAIN_START = "1981-01-01"
TRAIN_END = "2005-12-31"
VAL_START = "2006-01-01"
VAL_END = "2010-12-31"
TEST_START = "2011-01-01"
TEST_END = "2020-12-31"

# Minimum requirements
MIN_TRAIN_YEARS = 5  # At least 5 years of training data
MIN_TRAIN_COVERAGE = 0.5  # At least 50% data coverage in training period
SEQ_LENGTH = 365  # Need at least 365 consecutive days


def find_caravan_data_dir():
    """Find Caravan data directory."""
    possible_paths = [
        Path("data/Caravan"),
        Path("/data1/home/sunyiq/neuralhydrology/data/Caravan"),
        Path.home() / "neuralhydrology" / "data" / "Caravan",
    ]
    
    for p in possible_paths:
        if p.exists():
            return p
    
    raise FileNotFoundError("Cannot find Caravan data directory")


def get_subdatasets(data_dir: Path) -> list:
    """Get list of subdatasets in Caravan."""
    timeseries_dir = data_dir / "timeseries" / "csv"
    if not timeseries_dir.exists():
        print(f"[ERROR] Timeseries directory not found: {timeseries_dir}")
        return []
    
    subdatasets = []
    for d in timeseries_dir.iterdir():
        if d.is_dir() and not d.name.startswith('.'):
            subdatasets.append(d.name)
    
    return sorted(subdatasets)


def check_basin_data(csv_path: Path, train_start: str, train_end: str) -> dict:
    """
    Check data availability for a single basin.
    
    Returns dict with:
    - valid: bool
    - data_start: first date with data
    - data_end: last date with data
    - train_coverage: fraction of training period with data
    - total_days: total days with streamflow data
    - reason: reason if invalid
    """
    result = {
        'valid': False,
        'data_start': None,
        'data_end': None,
        'train_coverage': 0.0,
        'train_days': 0,
        'val_days': 0,
        'test_days': 0,
        'total_days': 0,
        'reason': ''
    }
    
    try:
        # Read CSV
        df = pd.read_csv(csv_path, parse_dates=['date'])
        
        if 'streamflow' not in df.columns:
            result['reason'] = 'no_streamflow_column'
            return result
        
        # Get valid streamflow data
        valid_mask = df['streamflow'].notna() & (df['streamflow'] >= 0)
        valid_df = df[valid_mask].copy()
        
        if len(valid_df) == 0:
            result['reason'] = 'no_valid_streamflow'
            return result
        
        result['data_start'] = valid_df['date'].min().strftime('%Y-%m-%d')
        result['data_end'] = valid_df['date'].max().strftime('%Y-%m-%d')
        result['total_days'] = len(valid_df)
        
        # Check training period
        train_mask = (valid_df['date'] >= train_start) & (valid_df['date'] <= train_end)
        train_df = valid_df[train_mask]
        result['train_days'] = len(train_df)
        
        # Calculate training coverage
        train_period_days = (pd.Timestamp(train_end) - pd.Timestamp(train_start)).days + 1
        result['train_coverage'] = len(train_df) / train_period_days
        
        # Check validation period
        val_mask = (valid_df['date'] >= VAL_START) & (valid_df['date'] <= VAL_END)
        result['val_days'] = len(valid_df[val_mask])
        
        # Check test period
        test_mask = (valid_df['date'] >= TEST_START) & (valid_df['date'] <= TEST_END)
        result['test_days'] = len(valid_df[test_mask])
        
        # Check if has enough consecutive data for seq_length
        if len(train_df) < SEQ_LENGTH:
            result['reason'] = f'insufficient_train_data({len(train_df)}<{SEQ_LENGTH})'
            return result
        
        # Check minimum coverage
        if result['train_coverage'] < MIN_TRAIN_COVERAGE:
            result['reason'] = f'low_coverage({result["train_coverage"]:.1%}<{MIN_TRAIN_COVERAGE:.0%})'
            return result
        
        # Check minimum years
        train_years = len(train_df) / 365
        if train_years < MIN_TRAIN_YEARS:
            result['reason'] = f'insufficient_years({train_years:.1f}<{MIN_TRAIN_YEARS})'
            return result
        
        result['valid'] = True
        result['reason'] = 'ok'
        
    except Exception as e:
        result['reason'] = f'error:{str(e)[:50]}'
    
    return result


def main():
    print("=" * 60)
    print("Caravan Basin Data Availability Check")
    print("=" * 60)
    print(f"Training period: {TRAIN_START} to {TRAIN_END}")
    print(f"Minimum requirements:")
    print(f"  - At least {MIN_TRAIN_YEARS} years of training data")
    print(f"  - At least {MIN_TRAIN_COVERAGE:.0%} data coverage")
    print(f"  - At least {SEQ_LENGTH} consecutive days")
    print()
    
    # Find data directory
    try:
        data_dir = find_caravan_data_dir()
        print(f"[INFO] Data directory: {data_dir}")
    except FileNotFoundError as e:
        print(f"[ERROR] {e}")
        return 1
    
    # Get subdatasets
    subdatasets = get_subdatasets(data_dir)
    print(f"[INFO] Found {len(subdatasets)} subdatasets: {subdatasets}")
    print()
    if not subdatasets:
        print("[ERROR] No Caravan subdatasets found under data_dir/timeseries/csv.")
        print("[HINT] Verify dataset layout or update the expected path in this script.")
        return 2
    
    # Check all basins
    all_results = []
    valid_basins = []
    
    for subdataset in subdatasets:
        ts_dir = data_dir / "timeseries" / "csv" / subdataset
        csv_files = list(ts_dir.glob("*.csv"))
        
        print(f"[INFO] Checking {subdataset}: {len(csv_files)} basins")
        
        subdataset_valid = 0
        for csv_file in tqdm(csv_files, desc=f"  {subdataset}", leave=False):
            basin_id = f"{subdataset}_{csv_file.stem}"
            
            result = check_basin_data(csv_file, TRAIN_START, TRAIN_END)
            result['basin_id'] = basin_id
            result['subdataset'] = subdataset
            all_results.append(result)
            
            if result['valid']:
                valid_basins.append(basin_id)
                subdataset_valid += 1
        
        if len(csv_files) > 0:
            print(f"       Valid: {subdataset_valid}/{len(csv_files)} ({subdataset_valid/len(csv_files)*100:.1f}%)")
        else:
            print("       Valid: 0/0 (no CSV files found)")
    
    print()
    print("=" * 60)
    print("Summary")
    print("=" * 60)
    
    # Summary by subdataset
    df_results = pd.DataFrame(all_results)
    if df_results.empty:
        print("[ERROR] No basin results collected. Nothing to summarize.")
        return 3
    
    summary = df_results.groupby('subdataset').agg({
        'valid': ['sum', 'count'],
        'train_coverage': 'mean',
        'train_days': 'mean'
    }).round(2)
    summary.columns = ['valid_count', 'total_count', 'avg_coverage', 'avg_train_days']
    summary['valid_pct'] = (summary['valid_count'] / summary['total_count'] * 100).round(1)
    
    print("\nBy subdataset:")
    print(summary.to_string())
    
    print(f"\nTotal valid basins: {len(valid_basins)} / {len(all_results)}")
    
    # Reasons for invalid basins
    invalid_df = df_results[~df_results['valid']]
    if len(invalid_df) > 0:
        print("\nInvalid basin reasons:")
        reason_counts = invalid_df['reason'].value_counts()
        for reason, count in reason_counts.head(10).items():
            print(f"  {reason}: {count}")
    
    # Save results to task-isolated directories
    project_root = Path(__file__).resolve().parents[3]
    task_data_dir = project_root / "src" / "caravan_global" / "data"
    task_results_dir = project_root / "results" / "01_caravan_global" / "analysis"
    task_data_dir.mkdir(parents=True, exist_ok=True)
    task_results_dir.mkdir(parents=True, exist_ok=True)
    
    # Save valid basins list
    valid_file = task_data_dir / "valid_basins.txt"
    with open(valid_file, 'w') as f:
        for basin in sorted(valid_basins):
            f.write(f"{basin}\n")
    print(f"\n[SAVED] Valid basins: {valid_file}")
    
    # Save detailed report
    report_file = task_results_dir / "basin_availability_report.csv"
    df_results.to_csv(report_file, index=False)
    print(f"[SAVED] Detailed report: {report_file}")
    
    # Save invalid basins list
    invalid_file = task_data_dir / "invalid_basins.txt"
    invalid_basins = df_results[~df_results['valid']]['basin_id'].tolist()
    with open(invalid_file, 'w') as f:
        for basin in sorted(invalid_basins):
            f.write(f"{basin}\n")
    print(f"[SAVED] Invalid basins: {invalid_file}")
    
    print()
    print("=" * 60)
    print(f"Done! Use valid_basins.txt for training.")
    print("=" * 60)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
