#!/usr/bin/env python3
"""
脚本5: 本地可视化已下载的 GEE CSV（ERA5-Land 日聚合），绘制指定流域的时序曲线。

前提：
  - 你已在 Google Drive 完成导出并下载到本地一个目录（例如 downloads/Caravan_Haihe_ERA5L/）。
  - CSV 列包含 reduceRegions 的均值后缀：*_mean，以及 system_index（yyyyMMdd）。

用法：
  conda run -n neuralhydrology_gpu python src/haihe_river/scripts/05_visualize_timeseries.py \
    --csv-dir downloads/Caravan_Haihe_ERA5L \
    --basin-id HB4120006920 \
    --out-png results/06_haihe_river/figures/ts_HB4120006920.png
"""

import argparse
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt


def load_merge(csv_dir: Path) -> pd.DataFrame:
    files = sorted(csv_dir.glob('*.csv'))
    dfs = []
    for f in files:
        try:
            df = pd.read_csv(f)
            dfs.append(df)
        except Exception:
            continue
    if not dfs:
        raise RuntimeError('未在目录中找到可读 CSV')
    df_all = pd.concat(dfs, axis=0, ignore_index=True)
    return df_all


def main():
    parser = argparse.ArgumentParser(description='可视化已下载的 ERA5L CSV 时序（单一 basin）')
    parser.add_argument('--csv-dir', required=True, help='本地 CSV 目录（从 Google Drive 下载）')
    parser.add_argument('--basin-id', required=True, help='目标 basin_id，例如 HB4120006920')
    parser.add_argument('--out-png', default='results/06_haihe_river/figures/ts.png', help='输出图片路径')
    args = parser.parse_args()

    csv_dir = Path(args.csv_dir)
    out_png = Path(args.out_png)
    out_png.parent.mkdir(parents=True, exist_ok=True)

    df = load_merge(csv_dir)
    # 字段名称经过 reduceRegions(mean) 后有 _mean 后缀
    # 关键列名：basin_id、system_index、total_precipitation_sum_mean、temperature_2m_mean_mean
    cols = df.columns
    basin_col = 'basin_id'
    date_col = 'system_index'
    p_col = 'total_precipitation_sum_mean'
    # 修正：ERA5-Land DAILY_AGGR 使用 band 'temperature_2m'，reduceRegions(mean) 输出列名为 'temperature_2m_mean'
    t_col = 'temperature_2m_mean'

    for required in [basin_col, date_col, p_col, t_col]:
        if required not in cols:
            raise RuntimeError(f'CSV 缺少列: {required}')

    sub = df.loc[df[basin_col] == args.basin_id].copy()
    if sub.empty:
        raise RuntimeError('未找到指定 basin 的数据，检查 basin_id 是否正确')
    sub['date'] = pd.to_datetime(sub[date_col], format='%Y%m%d')
    sub = sub.sort_values('date')

    fig, ax1 = plt.subplots(figsize=(10, 4))
    ax2 = ax1.twinx()
    ax1.plot(sub['date'], sub[p_col], color='tab:blue', label='precip (mm/d)')
    ax2.plot(sub['date'], sub[t_col], color='tab:red', alpha=0.7, label='temp (C)')
    ax1.set_ylabel('precip (mm/d)', color='tab:blue')
    ax2.set_ylabel('temp (C)', color='tab:red')
    ax1.set_xlabel('date')
    ax1.set_title(f'{args.basin_id} ERA5L daily (mean/sum)')
    fig.tight_layout()
    fig.savefig(out_png, dpi=150)
    print('[OK] 输出图片:', out_png)


if __name__ == '__main__':
    main()




