#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse
from pathlib import Path
import pandas as pd


def fix_file(fp: Path) -> bool:
    df = pd.read_csv(fp)
    changed = False
    # temperature K->C
    if 'temperature_2m' in df.columns and pd.to_numeric(df['temperature_2m'], errors='coerce').max() > 100:
        df['temperature_2m'] = pd.to_numeric(df['temperature_2m'], errors='coerce') - 273.15
        changed = True
    # pressure Pa->kPa
    if 'surface_pressure' in df.columns and pd.to_numeric(df['surface_pressure'], errors='coerce').max() > 2000:
        df['surface_pressure'] = pd.to_numeric(df['surface_pressure'], errors='coerce') / 1000.0
        changed = True
    # m->mm
    for col in ['total_precipitation_sum', 'potential_evaporation_sum', 'snow_depth_water_equivalent']:
        if col in df.columns:
            s = pd.to_numeric(df[col], errors='coerce')
            if s.max() <= 1.0:  # likely meters per day
                df[col] = s * 1000.0
                changed = True
    # J/m2 -> W/m2 (daily mean)
    for col in ['surface_net_solar_radiation_sum', 'surface_net_thermal_radiation_sum']:
        if col in df.columns:
            s = pd.to_numeric(df[col], errors='coerce')
            if s.max() > 1000:  # daily sum can be large in J/m2
                df[col] = s / 86400.0
                changed = True
    if changed:
        df.to_csv(fp, index=False)
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--file', required=True)
    args = ap.parse_args()
    changed = fix_file(Path(args.file))
    print('[OK] fixed' if changed else '[OK] no change needed')


if __name__ == '__main__':
    main()












