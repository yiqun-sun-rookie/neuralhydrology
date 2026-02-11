#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
from pathlib import Path
import glob
import pandas as pd

def main():
    if len(sys.argv) < 2:
        print('usage: _diag_dir_lev9.py <root_dir>')
        sys.exit(1)
    root = Path(sys.argv[1])
    if not root.exists():
        print('not found', root)
        sys.exit(1)

    # 统计子目录与CSV数量
    subdirs = [p for p in root.iterdir() if p.is_dir()]
    if not subdirs:
        subdirs = [root]
    total = 0
    print('root', root)
    for sd in subdirs:
        n = len(list(sd.glob('*.csv')))
        total += n
        print('dir', sd, 'csv', n)

    # 读取一个示例CSV头与若干 basin_id
    any_csv = None
    for sd in subdirs:
        cs = list(sd.glob('*.csv'))
        if cs:
            any_csv = cs[0]
            break
    if any_csv is None:
        print('no csv found')
        sys.exit(0)
    print('sample', any_csv)
    head = pd.read_csv(any_csv, nrows=5)
    print('columns', list(head.columns))
    if 'basin_id' in head.columns:
        df = pd.read_csv(any_csv, usecols=['basin_id'])
        print('sample basin_id', df['basin_id'].astype(str).dropna().unique()[:10])

if __name__ == '__main__':
    main()


