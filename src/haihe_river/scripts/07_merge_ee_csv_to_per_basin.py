#!/usr/bin/env python3
"""
将多个时间片（目录）下的 GEE 导出 CSV 分片合并为“每个流域一个时间序列 CSV”。

输入：若干目录（每个目录内含 era5l_daily_*.csv 若干分片）
输出：results/06_haihe_river/per_basin_timeseries/<basin_id>.csv

列名自适配：既支持 'temperature_2m' / 'temperature_2m_mean'，也支持 'total_precipitation_sum' / 'total_precipitation_sum_mean' 等。
"""

import argparse
from pathlib import Path
import glob
import pandas as pd
from collections import defaultdict


# 可能出现的列名集合（优先顺序从左到右）
COL_CANDIDATES = {
    'date': ['system_index', 'date', 'Date', 'time'],
    'basin': ['basin_id', 'gauge_id', 'id']
}

BAND_CANDIDATES = [
    # 累积/日量
    'total_precipitation_sum_mean', 'total_precipitation_sum',
    'surface_net_solar_radiation_sum_mean', 'surface_net_solar_radiation_sum',
    'surface_net_thermal_radiation_sum_mean', 'surface_net_thermal_radiation_sum',
    'potential_evaporation_sum_mean', 'potential_evaporation_sum',
    # 日平均/代表值
    'temperature_2m_mean', 'temperature_2m',
    'surface_pressure_mean', 'surface_pressure',
    'u_component_of_wind_10m_mean', 'u_component_of_wind_10m',
    'v_component_of_wind_10m_mean', 'v_component_of_wind_10m',
    'snow_depth_water_equivalent_mean', 'snow_depth_water_equivalent',
]


def pick_col(cols, candidates):
    for c in candidates:
        if c in cols:
            return c
    return None


def autodetect_columns(df_cols):
    date_col = pick_col(df_cols, COL_CANDIDATES['date'])
    basin_col = pick_col(df_cols, COL_CANDIDATES['basin'])
    bands = [c for c in BAND_CANDIDATES if c in df_cols]
    if not date_col or not basin_col or not bands:
        raise RuntimeError(f"列名不匹配，找到的列: {list(df_cols)}")
    return date_col, basin_col, bands


def read_some_columns(csv_path: str):
    # 先读一小段获取列名
    head = pd.read_csv(csv_path, nrows=5)
    date_col, basin_col, bands = autodetect_columns(head.columns)
    usecols = [date_col, basin_col] + bands
    df = pd.read_csv(csv_path, usecols=usecols)
    return df, date_col, basin_col, bands


def merge_directories(dirs, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)

    # 聚合到 per-basin 字典
    basin_to_frames = defaultdict(list)
    detected = None

    for folder in dirs:
        for csv_path in glob.glob(str(Path(folder) / '*.csv')):
            if Path(csv_path).stat().st_size == 0:
                continue
            if detected is None:
                df, date_col, basin_col, bands = read_some_columns(csv_path)
                detected = (date_col, basin_col, bands)
            else:
                date_col, basin_col, bands = detected
                df = pd.read_csv(csv_path, usecols=[date_col, basin_col] + bands)

            # 单位转换（就地）：ERA5-Land DAILY_AGGR 原始单位 -> 水文常用单位
            for col in bands:
                if col.startswith('temperature_2m'):
                    # K -> °C
                    df[col] = pd.to_numeric(df[col], errors='coerce') - 273.15
                elif col.startswith('surface_pressure'):
                    # Pa -> kPa
                    df[col] = pd.to_numeric(df[col], errors='coerce') / 1000.0
                elif col in ['total_precipitation_sum', 'potential_evaporation_sum']:
                    # m -> mm
                    df[col] = pd.to_numeric(df[col], errors='coerce') * 1000.0
                elif col in ['surface_net_solar_radiation_sum', 'surface_net_thermal_radiation_sum']:
                    # J/m2 (daily sum) -> W/m2 (daily mean)
                    df[col] = pd.to_numeric(df[col], errors='coerce') / 86400.0
                elif col.startswith('snow_depth_water_equivalent'):
                    # m -> mm
                    df[col] = pd.to_numeric(df[col], errors='coerce') * 1000.0

            # 规范化
            df[date_col] = pd.to_datetime(df[date_col], format='%Y%m%d', errors='coerce')
            df = df.dropna(subset=[date_col, basin_col])

            # 分流域追加
            for bid, g in df.groupby(basin_col):
                basin_to_frames[str(bid)].append(g[[date_col] + bands])

    # 写出每个流域
    written = 0
    for bid, frames in basin_to_frames.items():
        dfb = pd.concat(frames, axis=0, ignore_index=True)
        dfb = dfb.drop_duplicates(subset=[detected[0]], keep='last').sort_values(detected[0])
        dfb = dfb.rename(columns={detected[0]: 'date'})
        out_path = out_dir / f"{bid}.csv"
        dfb.to_csv(out_path, index=False)
        written += 1

    print(f"[OK] 合并完成：{written} 个流域，输出目录: {out_dir}")


def main():
    ap = argparse.ArgumentParser(description='合并 GEE ERA5L 导出 CSV 为每流域一个时间序列')
    ap.add_argument('--dirs', nargs='+', required=True, help='若干时间片目录')
    ap.add_argument('--out', default='results/06_haihe_river/per_basin_timeseries', help='输出目录')
    args = ap.parse_args()

    merge_directories(args.dirs, Path(args.out))


if __name__ == '__main__':
    main()


