#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
修正已合并的每流域CSV的单位：
- temperature_2m: K -> °C
- surface_pressure: Pa -> kPa
- total_precipitation_sum / potential_evaporation_sum / snow_depth_water_equivalent: m -> mm
- surface_net_solar_radiation_sum / surface_net_thermal_radiation_sum: J/m2(日累计) -> W/m2(日均) (÷86400)
"""
import argparse
from pathlib import Path
import pandas as pd


def fix_file(fp: Path) -> bool:
    df = pd.read_csv(fp)
    changed = False
    if 'temperature_2m' in df.columns and df['temperature_2m'].max() > 100:
        df['temperature_2m'] = pd.to_numeric(df['temperature_2m'], errors='coerce') - 273.15
        changed = True
    if 'surface_pressure' in df.columns and df['surface_pressure'].max() > 2000:
        df['surface_pressure'] = pd.to_numeric(df['surface_pressure'], errors='coerce') / 1000.0
        changed = True
    for col in ['total_precipitation_sum', 'potential_evaporation_sum', 'snow_depth_water_equivalent']:
        if col in df.columns and df[col].max() < 10 and df[col].max() <= 1.0:  # m量级，日累计通常<<1m
            df[col] = pd.to_numeric(df[col], errors='coerce') * 1000.0
            changed = True
    for col in ['surface_net_solar_radiation_sum', 'surface_net_thermal_radiation_sum']:
        if col in df.columns and df[col].max() > 1000:  # J/m2 日累计可非常大
            df[col] = pd.to_numeric(df[col], errors='coerce') / 86400.0
            changed = True
    if changed:
        df.to_csv(fp, index=False)
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', required=True, help='每流域CSV目录')
    args = ap.parse_args()

    root = Path(args.dir)
    cnt = 0
    for fp in root.glob('*.csv'):
        if fix_file(fp):
            cnt += 1
    print('[OK] 单位修正完成，修改文件数:', cnt)


if __name__ == '__main__':
    main()


