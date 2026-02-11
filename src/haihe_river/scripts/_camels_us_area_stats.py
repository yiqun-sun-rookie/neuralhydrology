#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import pandas as pd
from pathlib import Path

path = Path('data/CAMELS_US/camels_attributes_v2.0/basin_physical_characteristics.txt')
if not path.exists():
    raise SystemExit(f'file not found: {path}')

# 尝试用灵活分隔读取
df = pd.read_csv(path, sep=';|\t|,|\s+', engine='python')
cols_lower = [c.lower() for c in df.columns]

candidates = [
    'area_gauged', 'area_gaged', 'area_gauged_km2',
    'drainage_area_km2', 'drainage_area', 'area', 'size(km2)', 'size'
]
area_col = None
for cand in candidates:
    if cand in cols_lower:
        area_col = df.columns[cols_lower.index(cand)]
        break
if area_col is None:
    # 兜底：包含 area 或 size，并且包含 km 或 gaug/drain
    for i, cl in enumerate(cols_lower):
        if (('area' in cl) or ('size' in cl)) and ('km' in cl or 'gaug' in cl or 'drain' in cl):
            area_col = df.columns[i]
            break
if area_col is None:
    raise SystemExit(f'area column not found. columns: {list(df.columns)[:10]} ...')

s = pd.to_numeric(df[area_col], errors='coerce').dropna()
q = s.quantile([0.05, 0.25, 0.5, 0.75, 0.95])

print('column', area_col)
print('n', len(s))
print('min', round(s.min(), 2))
print('max', round(s.max(), 2))
print('mean', round(s.mean(), 2))
print('median', round(s.median(), 2))
for p, v in q.items():
    print(f'q{int(p*100):02d}', round(v, 2))


