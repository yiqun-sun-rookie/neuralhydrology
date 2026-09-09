#!/bin/bash
# READ-ONLY: ERA5-Land (Caravan pipeline) daily precipitation correlation against Maurer over all 529 basins,
# so it can be compared like-for-like with the CHIRPS number measured locally on the same 529 basins.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1
import glob
import numpy as np, pandas as pd
R = '/data1/home/sunyiq/forcing_swap_daily_2026_09/data_shadow/camels_us/basin_mean_forcing'
MS, ME = '1989-01-04', '2008-09-30'
b529 = [l.strip().zfill(8) for l in open('/data1/home/sunyiq/forcing_swap_daily_2026_09/basin_lists/basins_529.txt') if l.strip()]

def read(prod, b):
    f = glob.glob(f'{R}/{prod}/**/{b}_*_forcing_leap.txt', recursive=True)[0]
    d = pd.read_csv(f, sep=r'\s+', header=0, skiprows=3)
    d['date'] = pd.to_datetime(dict(year=d.Year, month=d.Mnth, day=d.Day))
    return d.set_index('date')['PRCP(mm/day)']

rs, ratios, lags = [], [], []
for b in b529:
    m, e = read('maurer', b).loc[MS:ME], read('era5l_caravan', b).loc[MS:ME]
    j = pd.concat([m.rename('m'), e.rename('e')], axis=1).dropna()
    rs.append(float(j.m.corr(j.e)))
    ratios.append(float(j.e.mean() / j.m.mean()))
    r = {k: float(j.m.corr(j.e.shift(k))) for k in (-2, -1, 0, 1, 2)}
    lags.append(max(r, key=r.get))
rs, ratios, lags = pd.Series(rs), pd.Series(ratios), pd.Series(lags)
print('=== ERA5-Land(Caravan) vs Maurer, 529 basins, 1989-01-04..2008-09-30 ===')
print(f'daily corr : p10 {rs.quantile(.1):.3f}  median {rs.median():.3f}  p90 {rs.quantile(.9):.3f}  min {rs.min():.3f}')
print(f'mean ratio : p10 {ratios.quantile(.1):.3f}  median {ratios.median():.3f}  p90 {ratios.quantile(.9):.3f}')
print(f'best lag 0 : {(lags==0).sum()}/529 = {(lags==0).mean()*100:.2f}%')
print('lag counts :', dict(lags.value_counts()))
PY
echo "=== DONE ==="
