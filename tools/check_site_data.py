#!/usr/bin/env python
"""
快速检查站点数据是否准备好
用法: python tools/check_site_data.py data/namou_kuwei_hourly
"""
import sys
from pathlib import Path
import pandas as pd

def check_site(data_dir: str):
    """检查站点数据目录"""
    p = Path(data_dir)
    errors = []
    warnings = []
    
    # 1. 检查目录结构
    required = ["time_series", "attributes", "train_basins.txt", "validation_basins.txt", "test_basins.txt"]
    for f in required:
        if not (p / f).exists():
            errors.append(f"缺少: {f}")
    
    # 2. 检查时序数据
    ts_dir = p / "time_series"
    if ts_dir.exists():
        csv_files = list(ts_dir.glob("*.csv"))
        if not csv_files:
            errors.append("time_series/ 下无 CSV 文件")
        else:
            for csv in csv_files:
                try:
                    df = pd.read_csv(csv, nrows=10)
                    if "date" not in df.columns:
                        errors.append(f"{csv.name}: 缺少 date 列")
                    if "qobs" not in df.columns:
                        warnings.append(f"{csv.name}: 缺少 qobs 列（如果是纯输入站可忽略）")
                except Exception as e:
                    errors.append(f"{csv.name}: 读取失败 - {e}")
    
    # 3. 检查属性
    attr_file = p / "attributes" / "attributes.csv"
    if attr_file.exists():
        try:
            df = pd.read_csv(attr_file)
            print(f"静态属性: {len(df.columns)-1} 个特征, {len(df)} 个流域")
        except Exception as e:
            errors.append(f"attributes.csv: {e}")
    
    # 4. 汇总
    print(f"\n{'='*50}")
    print(f"站点目录: {data_dir}")
    print(f"{'='*50}")
    
    if errors:
        print("\n[错误]")
        for e in errors:
            print(f"  ✗ {e}")
    
    if warnings:
        print("\n[警告]")
        for w in warnings:
            print(f"  ⚠ {w}")
    
    if not errors:
        print("\n✓ 数据结构检查通过")
        return True
    return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python tools/check_site_data.py <data_dir>")
        print("示例: python tools/check_site_data.py data/namou_kuwei_hourly")
        sys.exit(1)
    
    ok = check_site(sys.argv[1])
    sys.exit(0 if ok else 1)


