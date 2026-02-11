#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt


def pick_col(cols, candidates):
    for c in candidates:
        if c in cols:
            return c
    return None


def main():
    ap = argparse.ArgumentParser(description='从合并后的单流域CSV绘制时序')
    ap.add_argument('--file', required=True, help='单流域CSV路径')
    ap.add_argument('--out', required=True, help='输出PNG')
    args = ap.parse_args()

    f = Path(args.file)
    df = pd.read_csv(f)
    cols = df.columns

    date_col = pick_col(cols, ['date', 'system_index'])
    p_col = pick_col(cols, ['total_precipitation_sum', 'total_precipitation_sum_mean'])
    t_col = pick_col(cols, ['temperature_2m', 'temperature_2m_mean'])
    if not (date_col and p_col and t_col):
        raise SystemExit(f'缺少列: date={date_col}, precip={p_col}, temp={t_col}')

    if date_col == 'system_index':
        df['date'] = pd.to_datetime(df[date_col], format='%Y%m%d')
    else:
        df['date'] = pd.to_datetime(df[date_col])
    df = df.sort_values('date')

    fig, ax1 = plt.subplots(figsize=(10, 4))
    ax2 = ax1.twinx()
    ax1.plot(df['date'], df[p_col], color='tab:blue', label='precip (mm/d)')
    ax2.plot(df['date'], df[t_col], color='tab:red', alpha=0.7, label='temp (°C)')
    ax1.set_ylabel('precip (mm/d)', color='tab:blue')
    ax2.set_ylabel('temp (°C)', color='tab:red')
    ax1.set_xlabel('date')
    ax1.set_title(f.stem)
    fig.tight_layout()
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.out, dpi=150)
    print('[OK] 输出图片:', args.out)


if __name__ == '__main__':
    main()


