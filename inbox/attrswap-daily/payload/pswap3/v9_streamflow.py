"""V9 (PREREG_20260911 section 9, report item): per-basin count of valid streamflow days in the Stage-2 test window
(1999-10-01..2004-09-30, 1827 days) and training window (2004-10-01..2013-09-30, 3287 days).
Usage: python v9_streamflow.py <usgs_streamflow dir> <basin list> <out json>
Basins with zero valid test days are listed (expected: none). Exit non-zero only if a basin file is missing.
No backslash literals anywhere in this file.
"""
import datetime as dt
import glob
import json
import sys

sf_dir, blist, out = sys.argv[1:4]
basins = [l.strip().zfill(8) for l in open(blist) if l.strip()]
T0, T1 = dt.date(1999, 10, 1), dt.date(2004, 9, 30)
R0, R1 = dt.date(2004, 10, 1), dt.date(2013, 9, 30)
res, missing = {}, []
for b in basins:
    f = glob.glob(f'{sf_dir}/**/{b}_streamflow_qc.txt', recursive=True)
    if not f:
        missing.append(b)
        continue
    tv = rv = 0
    last = None
    for line in open(f[0]):
        p = line.split()
        if len(p) < 5:
            continue
        d = dt.date(int(p[1]), int(p[2]), int(p[3]))
        ok = float(p[4]) >= 0
        last = d
        if ok and T0 <= d <= T1:
            tv += 1
        if ok and R0 <= d <= R1:
            rv += 1
    res[b] = {'test_valid': tv, 'train_valid': rv, 'last_date': str(last)}
zero = [b for b, r in res.items() if r['test_valid'] == 0]
short = {b: r['train_valid'] for b, r in res.items() if r['train_valid'] < 3287}
summary = {'n_basins': len(basins), 'missing_files': missing, 'test_window_days': 1827, 'train_window_days': 3287,
           'test_zero_valid': zero, 'train_short': short, 'train_below_50pct': [b for b, v in short.items() if v < 3287 * 0.5],
           'per_basin': res}
json.dump(summary, open(out, 'w'), indent=1)
print(f'V9: basins {len(res)}, missing files {len(missing)}, test-zero {len(zero)}, train-short {len(short)}, '
      f'train <50%: {summary["train_below_50pct"]}')
if missing:
    sys.exit(1)
