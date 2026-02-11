#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse
import pandas as pd
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--file', required=True)
    args = ap.parse_args()
    df = pd.read_csv(Path(args.file))
    cols = ['temperature_2m','surface_pressure','total_precipitation_sum','surface_net_solar_radiation_sum','potential_evaporation_sum','snow_depth_water_equivalent']
    print('file', args.file)
    for c in cols:
        if c in df.columns:
            s = pd.to_numeric(df[c], errors='coerce').dropna()
            if not s.empty:
                print(c, 'min', float(s.min()), 'max', float(s.max()))


if __name__ == '__main__':
    main()












