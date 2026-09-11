#!/bin/bash
# READ-ONLY: Stage-2 (precip_swap2) pre-checks b and c from PLAN_20260911 v1 section 13. No writes outside /tmp.
set -o pipefail
date "+wallclock %F %T %z"
D=/data1/home/sunyiq/neuralhydrology/data/camels_us/basin_mean_forcing/daymet
C=/data1/home/sunyiq/neuralhydrology/data/Caravan/timeseries/netcdf/camels
L=/data1/home/sunyiq/precip_swap_daily_2026_09/basin_lists/basins_529.txt
echo "=== B1. daymet dir on HPC ==="
if [ -d "$D" ]; then
  echo "  exists; subdirs=$(ls -d $D/*/ 2>/dev/null | wc -l) files=$(find $D -name '*_forcing_leap.txt' | wc -l) size=$(du -sh $D 2>/dev/null | cut -f1)"
  ls $D | xargs echo | sed 's/^/  /'
else
  echo "  MISSING: $D"
fi
echo "=== B2. per-HUC merged sha256 (files concatenated in sorted name order) ==="
for h in $(ls $D 2>/dev/null); do
  n=$(ls $D/$h/*_forcing_leap.txt 2>/dev/null | wc -l)
  s=$(ls $D/$h/*_forcing_leap.txt 2>/dev/null | sort | xargs cat | sha256sum | cut -c1-16)
  echo "  $h n=$n sha=$s"
done
echo "=== B3. sample daymet file: first 5 lines + last line + CR count (01013500) ==="
f=$(find $D -name '01013500_*_forcing_leap.txt' | head -1); echo "  $f"
head -5 "$f" | sed 's/^/    /'; tail -1 "$f" | sed 's/^/    /'
echo "  CR-terminated lines: $(cat -v "$f" | grep -c 'M$')  lines: $(wc -l < "$f")"
echo "=== B4. sha256 of the 529-subset files (sorted by basin id) ==="
sub=$(for b in $(cat $L); do find $D -name "${b}_*_forcing_leap.txt"; done | sort)
echo "  n=$(echo "$sub" | grep -c .)  sha=$(echo "$sub" | xargs cat | sha256sum | cut -c1-16)"
echo "=== B5. raw archive dir (fallback D13) ==="
ls -la /data1/home/sunyiq/neuralhydrology/data/camels_us/raw 2>&1 | head -12 | sed 's/^/  /'
echo "=== C. Caravan copy: Timezone attribute + date range + precip var for the 529 basins ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1
import xarray as xr, os, collections
C='/data1/home/sunyiq/neuralhydrology/data/Caravan/timeseries/netcdf/camels'
L='/data1/home/sunyiq/precip_swap_daily_2026_09/basin_lists/basins_529.txt'
basins=[l.strip() for l in open(L) if l.strip()]
missing=[]; tzc=collections.Counter(); d0=set(); d1=set(); nov=[]
first=True
rows=[]
for b in basins:
    f=f'{C}/camels_{b}.nc'
    if not os.path.exists(f):
        missing.append(b); continue
    ds=xr.open_dataset(f)
    if first:
        print('  global attr keys:', list(ds.attrs.keys()))
        print('  n data_vars:', len(ds.data_vars), ' has total_precipitation_sum:', 'total_precipitation_sum' in ds)
        first=False
    tz=ds.attrs.get('Timezone', ds.attrs.get('timezone','?'))
    tzc[tz]+=1
    dd=ds['date'].values
    d0.add(str(dd[0])[:10]); d1.add(str(dd[-1])[:10])
    if 'total_precipitation_sum' not in ds: nov.append(b)
    rows.append(f'{b},{tz}')
    ds.close()
print('  missing files:', len(missing), missing[:5])
print('  no total_precipitation_sum:', len(nov), nov[:5])
print('  date start set:', sorted(d0), ' date end set:', sorted(d1))
print('  timezone counts:', dict(tzc))
print('  --- per-basin timezone (529 lines) ---')
for r in rows: print('  '+r)
PY
echo "=== D. MAILBOX CHANNEL SEQ ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
