#!/bin/bash
# forcing-swap -- diagnose the single basin that tripped stop condition V6, and clean up the orphaned arm jobs.
# READ-ONLY on data. The only state change is scancel of MY OWN nine arm jobs, whose afterok dependency can never
# be satisfied now that the gate failed; they can never run and would otherwise sit in the queue forever.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09

echo "=== A. JOB STATES ==="
ids=$(tr '\n' ',' < "$R/logs/job_ids.txt" | sed 's/,$//')
sacct -j "$ids" -X --format=JobID%9,JobName%20,State%22,ExitCode%8,Elapsed%9 2>&1

echo "=== B. WHY THE GATE STOPPED (tail of its log) ==="
f=$(ls -t "$R"/logs/slurm_fswap_gate_*.out 2>/dev/null | head -1) || true
[ -n "$f" ] && tail -12 "$f"

echo "=== C. THE ONE BASIN: 01487000 -- how big is the margin? ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python - <<'PY' 2>&1
import glob
import numpy as np, pandas as pd, xarray as xr
A = '/data1/home/sunyiq/forcing_swap_daily_2026_09/data_shadow/camels_us/basin_mean_forcing/maurer'
C = '/data1/home/sunyiq/neuralhydrology/data/Caravan/timeseries/netcdf/camels'


def series(b):
    mf = glob.glob(f'{A}/**/{b}_*_forcing_leap.txt', recursive=True)[0]
    m = pd.read_csv(mf, sep=r'\s+', header=0, skiprows=3)
    m['date'] = pd.to_datetime(dict(year=m.Year, month=m.Mnth, day=m.Day))
    m = m.set_index('date')['PRCP(mm/day)']
    c = xr.open_dataset(f'{C}/camels_{b}.nc')['total_precipitation_sum'].to_series()
    c.index = pd.to_datetime(c.index)
    return m, c


def lagtable(m, c, lo, hi, label):
    j = pd.concat([m.rename('m'), c.rename('c')], axis=1).loc[lo:hi].dropna()
    r = {k: float(j.m.corr(j.c.shift(k))) for k in (-2, -1, 0, 1, 2)}
    best = max(r, key=r.get)
    margin = r[best] - r[0]
    print(f'  {label}: n={len(j)} ' + ' '.join(f'{k:+d}:{v:.4f}' for k, v in r.items()) +
          f' | best {best:+d}, margin over lag0 = {margin:+.4f}')
    return best, margin


b = '01487000'
m, c = series(b)
print(f'basin {b} (Nassawango Creek, Maryland)')
lagtable(m, c, '1989-01-01', '2008-09-30', 'modelled span 1989-2008')
lagtable(m, c, '1989-10-01', '1999-09-30', 'test period only    ')
lagtable(m, c, '1999-10-01', '2008-09-30', 'train period only   ')
lagtable(m, c, '1980-01-01', '1988-12-31', 'outside the span    ')
j = pd.concat([m.rename('m'), c.rename('c')], axis=1).loc['1989-01-01':'2008-09-30'].dropna()
print(f'  means: maurer {j.m.mean():.3f} caravan {j.c.mean():.3f} ratio {j.c.mean()/j.m.mean():.3f}; '
      f'dry days maurer {(j.m == 0).mean()*100:.1f}% caravan {(j.c == 0).mean()*100:.1f}%')

print('=== D. MARGIN CONTEXT: 30 other basins, how close are lag0 and its runner-up? ===')
basins = [l.strip().zfill(8) for l in open('/data1/home/sunyiq/forcing_swap_daily_2026_09/basin_lists/basins_529.txt')
          if l.strip()]
step = max(1, len(basins) // 30)
margins = []
for bb in basins[::step][:30]:
    try:
        mm, cc = series(bb)
    except Exception as e:
        print(f'  {bb}: {e}'); continue
    jj = pd.concat([mm.rename('m'), cc.rename('c')], axis=1).loc['1989-01-01':'2008-09-30'].dropna()
    rr = {k: float(jj.m.corr(jj.c.shift(k))) for k in (-1, 0, 1)}
    runner = max(rr[-1], rr[1])
    margins.append(rr[0] - runner)
ms = pd.Series(margins)
print(f'  lag0 minus best neighbour over {len(ms)} sampled basins: '
      f'min {ms.min():+.4f} p10 {ms.quantile(.1):+.4f} median {ms.median():+.4f} max {ms.max():+.4f}')
print(f'  sampled basins whose margin is under 0.01: {int((ms < 0.01).sum())}/{len(ms)}')
PY

echo "=== E. CANCEL THE NINE ORPHANED ARM JOBS (explicit ids only, never -u) ==="
for j in $(tail -n +2 "$R/logs/job_ids.txt"); do
  st=$(sacct -j "$j" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$st" in
    PENDING) scancel "$j" && echo "  cancelled $j (was PENDING with an unsatisfiable dependency)";;
    *) echo "  $j is $st -- left alone";;
  esac
done
sleep 3
squeue -u "$USER" -o '%.11i %.22j %.9T' 2>&1 | grep -Ei 'fswap|JOBID' || echo '  (no fswap jobs left in the queue)'
echo "=== DONE ==="
