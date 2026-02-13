#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
扫描 lev9 根目录，自动发现包含 CSV 的目录（或根目录本身），调用 07_merge_ee_csv_to_per_basin.merge_directories
将所有分片合并为“每流域一个时间序列 CSV”。
"""
import argparse
from pathlib import Path
# no external imports required

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True, help='lev9 根目录，内含各时间片CSV或扁平CSV')
    ap.add_argument('--out', default='results/06_haihe_river/per_basin_timeseries_lev9', help='输出目录')
    args = ap.parse_args()

    root = Path(args.root)
    # 收集包含CSV的目录
    candidate_dirs = []
    subdirs = [p for p in root.iterdir() if p.is_dir()]
    if subdirs:
        for sd in subdirs:
            if list(sd.glob('*.csv')):
                candidate_dirs.append(sd)
    else:
        candidate_dirs = [root]

    if not candidate_dirs:
        raise SystemExit('未找到CSV目录')

    # 延迟导入避免路径问题
    import importlib.util
    mod_path = Path(__file__).resolve().parent / '07_merge_ee_csv_to_per_basin.py'
    if not mod_path.exists():
        raise FileNotFoundError(f'缺少依赖脚本: {mod_path}')
    spec = importlib.util.spec_from_file_location('merge_mod', mod_path)
    merge_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(merge_mod)

    merge_mod.merge_directories([str(p) for p in candidate_dirs], Path(args.out))

if __name__ == '__main__':
    main()


