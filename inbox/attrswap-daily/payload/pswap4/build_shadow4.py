"""GPM-era contract: write the Daymet-V4 reference forcing files and the streamflow files in CAMELS-US layout.

Inputs (tables dir): daymet4_132.csv.gz (date, basin, dayl, prcp, srad, swe, tmax, tmin, vp), streamflow_cfs_132.csv.gz
(rows = date, columns = basin, cfs, empty = missing), headers_132.json (CAMELS header lines + HUC folder per basin).
Outputs under --dest (= <root>/data_shadow/camels_us):
  basin_mean_forcing/daymet4/<huc>/<basin>_lump_daymet4_forcing_leap.txt   4 header lines copied from CAMELS, then
      'YYYY MM DD 12<TAB>dayl<TAB>prcp<TAB>srad<TAB>swe<TAB>tmax<TAB>tmin<TAB>vp', 2 decimals (CAMELS convention)
  usgs_streamflow/<huc>/<basin>_streamflow_qc.txt   '<basin> YYYY MM DD <q %9.2f> A' (missing: -999.00 M)
Checks (exit 1 on any failure; report JSON always written):
  R1 file counts = number of basins (both trees); R2 no missing value in the five model inputs over the modelled span
  2015-01-04..2023-09-30; R3 tmax >= tmin share (report; failure if < 99%); R4 header area line is a positive integer;
  R5 every basin has >= 50% valid streamflow days in the train window 2015-10-01..2020-09-30 and in the test window
  2020-10-01..2023-09-30; R6 re-read 5 basins with the same parser rules NeuralHydrology uses (whitespace split,
  header line 4) and compare with the table (|diff| <= 0.005, the 2-decimal rounding).
The destination trees must not exist yet (no overwrite). No backslash literals anywhere in this file.
"""
import argparse
import gzip
import json
import os
import sys

import numpy as np
import pandas as pd

COLS = ['dayl', 'prcp', 'srad', 'swe', 'tmax', 'tmin', 'vp']
INPUTS = ['prcp', 'tmin', 'tmax', 'srad', 'vp']
MODEL_START, MODEL_END = '2015-01-04', '2023-09-30'
TRAIN, TEST = ('2015-10-01', '2020-09-30'), ('2020-10-01', '2023-09-30')
FORCING = 'daymet4'
FAIL = []


def fail(m):
    FAIL.append(m)
    print('FAIL ' + m, flush=True)


def read_gz_csv(path, **kw):
    with gzip.open(path, 'rt') as fh:
        return pd.read_csv(fh, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tables', required=True)
    ap.add_argument('--dest', required=True)
    ap.add_argument('--basins', required=True)
    ap.add_argument('--report', required=True)
    a = ap.parse_args()
    basins = [l.strip().zfill(8) for l in open(a.basins) if l.strip()]
    heads = json.load(open(os.path.join(a.tables, 'headers_132.json')))
    ref = read_gz_csv(os.path.join(a.tables, 'daymet4_132.csv.gz'), dtype={'basin': str}, parse_dates=['date'])
    ref['basin'] = ref['basin'].str.zfill(8)
    q = read_gz_csv(os.path.join(a.tables, 'streamflow_cfs_132.csv.gz'), index_col=0, parse_dates=True)
    q.columns = [str(c).zfill(8) for c in q.columns]
    fdir = os.path.join(a.dest, 'basin_mean_forcing', FORCING)
    sdir = os.path.join(a.dest, 'usgs_streamflow')
    for d in (fdir, sdir):
        if os.path.exists(d):
            raise SystemExit('refusing to overwrite existing ' + d)
    rep = dict(basins=len(basins), forcing=FORCING, per_basin={})
    tmax_ok, tmax_n = 0, 0
    for b in basins:
        h = heads[b]
        x = ref[ref['basin'] == b].set_index('date').sort_index()
        m = x.loc[MODEL_START:MODEL_END, INPUTS]
        nmiss = int(m.isna().sum().sum())
        if nmiss:
            fail('R2 %s: %d missing input values in the modelled span' % (b, nmiss))
        tmax_ok += int((x['tmax'] >= x['tmin']).sum())
        tmax_n += int(len(x))
        try:
            area = int(h['area'].strip())
            if area <= 0:
                raise ValueError
        except ValueError:
            fail('R4 %s: area line %r' % (b, h['area']))
        lines = [h['lat'], h['elev'], h['area'], h['columns']]
        for d, r in x.iterrows():
            vals = ['NaN' if pd.isna(r[c]) else '%.2f' % r[c] for c in COLS]
            lines.append('%04d %02d %02d 12' % (d.year, d.month, d.day) + chr(9) + chr(9).join(vals))
        p = os.path.join(fdir, h['huc'], '%s_lump_%s_forcing_leap.txt' % (b, FORCING))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w', newline=chr(10)) as fh:
            fh.write(chr(10).join(lines) + chr(10))
        s = q[b]
        sl = []
        for d, v in s.items():
            if pd.isna(v) or v < 0:
                sl.append('%s %04d %02d %02d %9.2f M' % (b, d.year, d.month, d.day, -999.0))
            else:
                sl.append('%s %04d %02d %02d %9.2f A' % (b, d.year, d.month, d.day, v))
        p2 = os.path.join(sdir, h['huc'], '%s_streamflow_qc.txt' % b)
        os.makedirs(os.path.dirname(p2), exist_ok=True)
        with open(p2, 'w', newline=chr(10)) as fh:
            fh.write(chr(10).join(sl) + chr(10))
        vt = int(s.loc[TRAIN[0]:TRAIN[1]].notna().sum())
        ve = int(s.loc[TEST[0]:TEST[1]].notna().sum())
        n_tr = len(pd.date_range(*TRAIN))
        n_te = len(pd.date_range(*TEST))
        if vt < 0.5 * n_tr or ve < 0.5 * n_te:
            fail('R5 %s: valid streamflow days train %d/%d test %d/%d' % (b, vt, n_tr, ve, n_te))
        rep['per_basin'][b] = dict(huc=h['huc'], valid_train=vt, valid_test=ve, missing_inputs=nmiss)
    nf = sum(1 for r, _, fs in os.walk(fdir) for f in fs if f.endswith('_forcing_leap.txt'))
    ns = sum(1 for r, _, fs in os.walk(sdir) for f in fs if f.endswith('_streamflow_qc.txt'))
    if nf != len(basins) or ns != len(basins):
        fail('R1 forcing files %d, streamflow files %d, expected %d' % (nf, ns, len(basins)))
    share = tmax_ok / max(tmax_n, 1)
    if share < 0.99:
        fail('R3 tmax >= tmin share %.4f < 0.99' % share)
    worst = 0.0
    for b in basins[:5]:
        h = heads[b]
        p = os.path.join(fdir, h['huc'], '%s_lump_%s_forcing_leap.txt' % (b, FORCING))
        with open(p) as fh:
            for _ in range(3):
                fh.readline()
            df = pd.read_csv(fh, sep=' +|' + chr(9), engine='python')
        df.index = pd.to_datetime(dict(year=df['Year'], month=df['Mnth'], day=df['Day']))
        x = ref[ref['basin'] == b].set_index('date').sort_index()
        worst = max(worst, float(np.nanmax(np.abs(df['prcp(mm/day)'].to_numpy() - x['prcp'].to_numpy()))))
    if worst > 0.0051:
        fail('R6 round-trip prcp max |diff| %.4f > 0.005' % worst)
    rep.update(forcing_files=nf, streamflow_files=ns, tmax_ge_tmin_share=share, roundtrip_prcp_max_abs=worst,
               failures=FAIL)
    with open(a.report, 'w') as fh:
        json.dump(rep, fh, indent=1)
    print(json.dumps({k: v for k, v in rep.items() if k != 'per_basin'}, indent=1), flush=True)
    if FAIL:
        print('checks failed: %d' % len(FAIL), flush=True)
        sys.exit(1)
    print('build_shadow4 checks passed', flush=True)


if __name__ == '__main__':
    main()
