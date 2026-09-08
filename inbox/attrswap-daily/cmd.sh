#!/bin/bash
# forcing-swap -- READ-ONLY input sanity check, triggered because armE27 came in ~0.25 below the reference,
# roughly three times the preregistered expectation (0.05-0.10). This does NOT touch any criterion; it asks
# whether the five written columns are physically sensible relative to Maurer, i.e. whether a processing or
# unit error could explain the size of the drop. Ten basins, summary statistics only.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1
import glob
import numpy as np, pandas as pd
R = '/data1/home/sunyiq/forcing_swap_daily_2026_09/data_shadow/camels_us/basin_mean_forcing'
COLS = ['PRCP(mm/day)', 'SRAD(W/m2)', 'Tmax(C)', 'Tmin(C)', 'Vp(Pa)']


def read(prod, b):
    f = glob.glob(f'{R}/{prod}/**/{b}_*_forcing_leap.txt', recursive=True)[0]
    d = pd.read_csv(f, sep=r'\s+', header=0, skiprows=3)
    d['date'] = pd.to_datetime(dict(year=d.Year, month=d.Mnth, day=d.Day))
    return d.set_index('date')


basins = [l.strip().zfill(8) for l in
          open('/data1/home/sunyiq/forcing_swap_daily_2026_09/basin_lists/basins_529.txt') if l.strip()]
sel = basins[::len(basins) // 10][:10]
acc = {c: {'ratio': [], 'corr': [], 'sd_ratio': []} for c in COLS}
for b in sel:
    m, e = read('maurer', b), read('era5l_caravan', b)
    j = m.join(e, lsuffix='_m', rsuffix='_e').loc['1989-01-01':'2008-09-30']
    for c in COLS:
        a, z = j[f'{c}_m'], j[f'{c}_e']
        acc[c]['ratio'].append(z.mean() / a.mean() if a.mean() != 0 else np.nan)
        acc[c]['sd_ratio'].append(z.std() / a.std() if a.std() != 0 else np.nan)
        acc[c]['corr'].append(a.corr(z))
print(f'{len(sel)} basins, 1989-01-01..2008-09-30, ERA5-Land column vs the Maurer column of the same name')
print(f"{'column':14s} {'mean ratio':>22s} {'sd ratio':>14s} {'correlation':>22s}")
for c in COLS:
    r, s, k = (pd.Series(acc[c][x]) for x in ('ratio', 'sd_ratio', 'corr'))
    print(f'{c:14s} {r.median():8.3f} [{r.min():6.3f},{r.max():6.3f}] {s.median():13.3f} '
          f'{k.median():8.3f} [{k.min():6.3f},{k.max():6.3f}]')
print()
print('reference values for the two columns whose semantics differ by construction:')
print('  SRAD  Maurer/Daymet convention = mean DOWNWARD shortwave over the DAYLIT part of the day;')
print('        Caravan ERA5-Land        = 24-hour mean of NET shortwave. Both a factor (1-albedo) and a')
print('        daylight-vs-24h averaging separate them, so a ratio well below 1 is expected, not an error.')
print('  Vp    Maurer = actual vapour pressure; ours = Magnus applied to the daily mean dewpoint.')
for b in sel[:3]:
    m, e = read('maurer', b), read('era5l_caravan', b)
    j = m.join(e, lsuffix='_m', rsuffix='_e').loc['1999-10-01':'2008-09-30']
    w = j.loc[j.index.month.isin([6, 7, 8])]
    print(f'  {b}: summer SRAD maurer {w["SRAD(W/m2)_m"].mean():7.1f} era5l {w["SRAD(W/m2)_e"].mean():7.1f} | '
          f'winter SRAD maurer {j.loc[j.index.month.isin([12,1,2]), "SRAD(W/m2)_m"].mean():7.1f} '
          f'era5l {j.loc[j.index.month.isin([12,1,2]), "SRAD(W/m2)_e"].mean():7.1f}')
PY
echo "=== DONE ==="
