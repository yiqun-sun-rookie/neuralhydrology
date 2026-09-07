#!/bin/bash
# attrswap-daily seq=10 -- READ-ONLY: Caravan camels coverage of our 529 basins, variables, dates. Light header reads only.
set -o pipefail
date "+wallclock %F %T %z"
C=/data1/home/sunyiq/neuralhydrology/data/Caravan
B=/data1/home/sunyiq/attr_swap_daily_2026_09/basin_lists/basins_529.txt
echo "=== A. counts ==="; echo "camels nc files: $(ls $C/timeseries/netcdf/camels 2>/dev/null | wc -l)"
for f in 531_basin_list.txt all_basins.txt camels_clean_basins.txt valid_basins.txt; do echo "$f: $(wc -l < $C/$f) lines; head: $(head -2 $C/$f | tr '\n' ' ')"; done
echo "=== B. coverage of our 529 ==="; have=0; miss=""; while read b; do [ -z "$b" ] && continue; if [ -f "$C/timeseries/netcdf/camels/camels_${b}.nc" ]; then have=$((have+1)); else miss="$miss $b"; fi; done < "$B"; echo "present: $have / 529"; echo "missing:$miss" | head -c 600; echo
echo "=== C. variables + dates of one file (nh_final python, header only) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null; conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1 | head -60
import xarray as xr
ds = xr.open_dataset('/data1/home/sunyiq/neuralhydrology/data/Caravan/timeseries/netcdf/camels/camels_01013500.nc')
print('dims', dict(ds.sizes)); print('date', str(ds.date.values[0])[:10], '->', str(ds.date.values[-1])[:10])
for v in ds.data_vars: print(v, ds[v].attrs.get('unit', ds[v].attrs.get('units', '')), '|', float(ds[v].isel(date=slice(0,3650)).mean()) if ds[v].dtype.kind=='f' else '')
PY
echo "=== D. attributes_other head (area/lat) ==="; head -3 $C/attributes/camels/attributes_other_camels.csv | cut -c1-300
echo "=== DONE ==="
