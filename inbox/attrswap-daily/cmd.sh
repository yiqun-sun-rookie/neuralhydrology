#!/bin/bash
# forcing-swap D0 -- READ-ONLY provenance of the Caravan copy on the HPC + a preview of the precip time alignment.
set -o pipefail
date "+wallclock %F %T %z"
C=/data1/home/sunyiq/neuralhydrology/data/Caravan
A=/data1/home/sunyiq/attr_swap_daily_2026_09

echo "=== A. mtimes of the camels netcdf files (are they one batch?) ==="
ls -la "$C/timeseries/netcdf/camels" | head -4
echo "--- oldest / newest ---"
ls -lt --time-style=long-iso "$C/timeseries/netcdf/camels" | tail -2
ls -lt --time-style=long-iso "$C/timeseries/netcdf/camels" | head -3
echo "--- distinct mtime days ---"
ls -l --time-style=+%Y-%m-%d "$C/timeseries/netcdf/camels" | awk '{print $6}' | sort | uniq -c | sort -rn | head -5
echo "--- other subset dirs, file counts ---"
for d in "$C"/timeseries/netcdf/*/; do echo "$(basename $d): $(ls $d 2>/dev/null | wc -l)"; done

echo "=== B. is the camels set exactly the full CAMELS-US 671? ==="
ls "$C/timeseries/netcdf/camels" | sed 's/^camels_//; s/\.nc$//' | sort > /tmp/cara_ids.$$
ls "$A/data_shadow/camels_us/usgs_streamflow"/*/ -d >/dev/null 2>&1
find "$A/data_shadow/camels_us/usgs_streamflow" -name "*_streamflow_qc.txt" 2>/dev/null | sed 's#.*/##; s/_streamflow_qc.txt//' | sort > /tmp/camels_ids.$$
echo "caravan camels ids: $(wc -l < /tmp/cara_ids.$$)   camels_us streamflow ids: $(wc -l < /tmp/camels_ids.$$)"
echo "in caravan but not in camels_us: $(comm -23 /tmp/cara_ids.$$ /tmp/camels_ids.$$ | wc -l)"
echo "in camels_us but not in caravan: $(comm -13 /tmp/cara_ids.$$ /tmp/camels_ids.$$ | wc -l)"
comm -13 /tmp/cara_ids.$$ /tmp/camels_ids.$$ | head -5
rm -f /tmp/cara_ids.$$ /tmp/camels_ids.$$

echo "=== C. netcdf global attributes (provenance written by the producer) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1 | head -40
import xarray as xr, glob
f = sorted(glob.glob('/data1/home/sunyiq/neuralhydrology/data/Caravan/timeseries/netcdf/camels/*.nc'))[0]
ds = xr.open_dataset(f)
print('file:', f)
print('global attrs:', dict(ds.attrs) if ds.attrs else '(none)')
for v in ['total_precipitation_sum', 'temperature_2m_max', 'streamflow']:
    if v in ds:
        print(v, 'attrs:', dict(ds[v].attrs))
print('encoding source:', ds.encoding.get('source', ''))
PY

echo "=== D. any generator script / notes on the HPC ==="
ls -la "$C" | head -20
for f in "$C"/*.txt; do echo "--- $(basename $f): $(wc -l < $f) lines, mtime $(stat -c %y "$f" | cut -c1-16)"; done
find /data1/home/sunyiq/neuralhydrology/src -maxdepth 3 -iname "*caravan*" 2>/dev/null | head -10

echo "=== E. PRECIP TIME ALIGNMENT PREVIEW (Caravan vs Maurer, 3 basins, lags -2..+2) ==="
python - <<'PY' 2>&1 | head -40
import glob
import numpy as np, pandas as pd, xarray as xr
A = '/data1/home/sunyiq/attr_swap_daily_2026_09/data_shadow/camels_us/basin_mean_forcing/maurer'
C = '/data1/home/sunyiq/neuralhydrology/data/Caravan/timeseries/netcdf/camels'
for b in ['01022500', '06192500', '11264500']:
    mf = glob.glob(f'{A}/**/{b}_*_forcing_leap.txt', recursive=True)
    if not mf:
        print(b, 'maurer file missing'); continue
    m = pd.read_csv(mf[0], sep=r'\s+', header=0, skiprows=3)
    m['date'] = pd.to_datetime(dict(year=m.Year, month=m.Mnth, day=m.Day))
    m = m.set_index('date')['PRCP(mm/day)']
    ds = xr.open_dataset(f'{C}/camels_{b}.nc')
    c = ds['total_precipitation_sum'].to_series()
    c.index = pd.to_datetime(c.index)
    j = pd.concat([m.rename('maurer'), c.rename('caravan')], axis=1).loc['1990-01-01':'2008-09-30'].dropna()
    r = {k: round(float(j.maurer.corr(j.caravan.shift(k))), 4) for k in (-2, -1, 0, 1, 2)}
    best = max(r, key=r.get)
    print(f'{b}: n={len(j)} corr by lag {r} -> best lag {best} | mean maurer {j.maurer.mean():.3f} caravan {j.caravan.mean():.3f} ratio {j.caravan.mean()/j.maurer.mean():.3f}')
PY
echo "=== DONE ==="
