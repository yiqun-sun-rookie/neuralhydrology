"""Build a CAMELS forcing product that differs from Daymet in the precipitation column only (PREREG_20260911, Stage 2).

Adapted from hpc_deploy/stage1_originals/build_precip_swap.py (sha256[:16] 3b3610cc7e55958a). Changes:
  * reference product is Daymet (lowercase header, files <basin>_lump_cida_forcing_leap.txt), dates are parameters;
  * the written date range is WRITE_START..WRITE_END and every Daymet date in it is written -- a missing / NaN
    source value is written as the literal 'NaN' (D9-b: never imputed, never dropped);
  * V4 is graded: NaN days inside the modelled span are tolerated up to V4_TOL of the span (per basin, max over
    basins), counted and reported; V7 keeps '>= 0' as a hard item and reports > 500 mm/day basin-days;
  * V5 tolerance 1e-4 and at least 5 small basins (< 124 km2, area from the Daymet header) among the 20;
  * the two hard checks are numbered V10 (ratio band [0.2, 5.0]) and V11 (lag-0 share > 50%); --self-aggregated
    adds the V7 scale guard (ratio band [0.5, 2.0]);
  * --from-caravan reads total_precipitation_sum by NAME from the Caravan netCDF copy (ERA5-Land arm);
  * P4 descriptive statistics (daily correlation, annual ratio, best lag) are written to the report.
The source is either --from-table (gzipped or plain CSV: rows = date, columns = 8-digit basin id, mm/day) or
--from-caravan <dir with camels_<basin>.nc>. No backslash literals are used anywhere in this file.
"""
import argparse
import glob
import gzip
import json
import os
import random
import sys

import numpy as np
import pandas as pd

PRCP_FIELD = 2  # index of prcp(mm/day) in a tab-separated Daymet data line (date, dayl, prcp, srad, swe, tmax, tmin, vp)
MODEL_START, MODEL_END, TEST_START, MIN_WARMUP = '1999-01-04', '2013-09-30', '1999-10-01', 270
WRITE_START, WRITE_END = '1999-01-01', '2013-12-31'
V4_TOL = 0.001            # fraction of modelled-span days tolerated as NaN (max over basins)
V5_TOL = 1e-4
RATIO_LO, RATIO_HI = 0.2, 5.0        # V10
SELF_LO, SELF_HI = 0.5, 2.0          # V7 scale guard for self-aggregated products
LAG0_MIN = 0.50                      # V11
EXTREME = 500.0                      # V7 report item
SMALL_KM2 = 124.0
FAIL, NOTE = [], []


def fail(m):
    FAIL.append(m)
    print('FAIL ' + m, flush=True)


def read_ref(path):
    with open(path) as fh:
        lines = fh.read().splitlines()
    head = lines[:4]
    rows = [ln.split('\t') for ln in lines[4:]]
    dates = pd.DatetimeIndex([pd.Timestamp(*[int(x) for x in r[0].split()[:3]]) for r in rows])
    area_km2 = float(head[2].strip()) / 1e6
    return head, dates, rows, area_km2


class Source:
    def __init__(self, a):
        self.mode = 'table' if a.from_table else 'caravan'
        if a.from_table:
            opener = gzip.open if a.from_table.endswith('.gz') else open
            with opener(a.from_table, 'rt') as fh:
                self.tab = pd.read_csv(fh, index_col=0, parse_dates=True)
            self.tab.columns = [str(c).zfill(8) for c in self.tab.columns]
            print(f'source table {len(self.tab)} days x {self.tab.shape[1]} basins '
                  f'{self.tab.index[0].date()} -> {self.tab.index[-1].date()}', flush=True)
        else:
            self.ncdir = a.from_caravan
            print(f'source Caravan netCDF dir {self.ncdir} (variable total_precipitation_sum)', flush=True)

    def series(self, b):
        if self.mode == 'table':
            if b not in self.tab.columns:
                return None
            return self.tab[b]
        import xarray as xr
        f = f'{self.ncdir}/camels_{b}.nc'
        if not os.path.exists(f):
            return None
        ds = xr.open_dataset(f)
        s = ds['total_precipitation_sum'].to_series()
        s.index = pd.DatetimeIndex(s.index).normalize()
        ds.close()
        return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('product')
    ap.add_argument('--from-table', default='')
    ap.add_argument('--from-caravan', default='')
    ap.add_argument('--ref', required=True, help='daymet directory (basin_mean_forcing/daymet)')
    ap.add_argument('--dest', required=True, help='basin_mean_forcing directory to write <product>/ into')
    ap.add_argument('--basins', required=True)
    ap.add_argument('--report', required=True)
    ap.add_argument('--self-aggregated', action='store_true')
    ap.add_argument('--seed', type=int, default=20260911)
    a = ap.parse_args()
    if bool(a.from_table) == bool(a.from_caravan):
        raise SystemExit('give exactly one of --from-table / --from-caravan')
    src = Source(a)
    basins = [l.strip().zfill(8) for l in open(a.basins) if l.strip()]
    span_days = (pd.Timestamp(MODEL_END) - pd.Timestamp(MODEL_START)).days + 1
    tol_days = int(np.floor(V4_TOL * span_days))

    lags, ratios, corrs, spans, nan_days, extreme, areas, written = {}, {}, {}, {}, {}, {}, {}, 0
    for i, b in enumerate(basins):
        rf = glob.glob(f'{a.ref}/**/{b}_*_forcing_leap.txt', recursive=True)
        if len(rf) != 1:
            fail(f'{b}: {len(rf)} reference files'); continue
        head, ridx, rows, area = read_ref(rf[0])
        areas[b] = area
        s = src.series(b)
        if s is None:
            fail(f'{b}: no source series'); continue
        keep = [j for j, d in enumerate(ridx) if pd.Timestamp(WRITE_START) <= d <= pd.Timestamp(WRITE_END)]
        out = list(head)
        vals = []
        for j in keep:
            d = ridx[j]
            v = s.get(d, np.nan)
            v = float(v) if v is not None else np.nan
            parts = list(rows[j])
            parts[PRCP_FIELD] = 'NaN' if np.isnan(v) else f'{v:.4f}'
            out.append('\t'.join(parts))
            vals.append(v)
        huc = os.path.basename(os.path.dirname(rf[0]))
        outp = f'{a.dest}/{a.product}/{huc}/{b}_lump_{a.product}_forcing_leap.txt'
        os.makedirs(os.path.dirname(outp), exist_ok=True)
        with open(outp, 'w', newline='\n') as fh:
            fh.write('\n'.join(out) + '\n')
        written += 1
        ki = ridx[keep]
        cp = pd.Series(vals, index=ki)
        valid = cp.dropna()
        spans[b] = (str(valid.index[0].date()) if len(valid) else None, str(valid.index[-1].date()) if len(valid) else None)
        mp = pd.Series([float(rows[j][PRCP_FIELD]) for j in keep], index=ki).loc[MODEL_START:MODEL_END]
        cm = cp.loc[MODEL_START:MODEL_END]
        nan_days[b] = int(cm.isna().sum())
        if (cm.dropna() < 0).any():
            fail(f'V7 {b}: {int((cm.dropna() < 0).sum())} negative values in the modelled span')
        ex = cm[cm > EXTREME]
        if len(ex):
            extreme[b] = [(str(d.date()), float(v)) for d, v in ex.items()]
        both = pd.concat([mp, cm], axis=1, keys=['r', 'c']).dropna()
        r = {k: float(both['r'].corr(both['c'].shift(k))) for k in (-2, -1, 0, 1, 2)}
        lags[b] = max(r, key=lambda k: (r[k] if not np.isnan(r[k]) else -9))
        corrs[b] = r[0]
        ratios[b] = float(both['c'].mean() / both['r'].mean()) if both['r'].mean() > 0 else float('nan')
        if (i + 1) % 100 == 0:
            print(f'  {i + 1}/{len(basins)}', flush=True)

    n = len(glob.glob(f'{a.dest}/{a.product}/**/*_forcing_leap.txt', recursive=True))
    if n != len(basins):
        fail(f'V1 wrote {n}, expected {len(basins)}')
    short = {b: s for b, s in spans.items()
             if s[0] is None or (pd.Timestamp(TEST_START) - pd.Timestamp(s[0])).days < MIN_WARMUP or s[1] < MODEL_END}
    if short:
        fail(f'V3 {len(short)} basins with insufficient coverage, e.g. {list(short.items())[:2]}')
    worst = max(nan_days.values()) if nan_days else 0
    if worst > tol_days:
        fail(f'V4 max NaN days in the modelled span = {worst} > tolerance {tol_days} ({V4_TOL:.1%} of {span_days} days)')
    NOTE.append(f'V4: NaN days in modelled span: max {worst}, basins with any NaN {sum(1 for v in nan_days.values() if v)}, '
                f'total basin-days {sum(nan_days.values())} (tolerance {tol_days}/basin)')

    rng = random.Random(a.seed)
    small = [b for b in basins if areas.get(b, 1e9) < SMALL_KM2]
    sample = rng.sample(small, min(5, len(small)))
    sample += rng.sample([b for b in basins if b not in sample], 20 - len(sample))
    for b in sample:
        f = glob.glob(f'{a.dest}/{a.product}/**/{b}_*_forcing_leap.txt', recursive=True)
        rf = glob.glob(f'{a.ref}/**/{b}_*_forcing_leap.txt', recursive=True)
        if not f or not rf:
            fail(f'V2/V5/V8 {b}: file missing'); continue
        new = open(f[0]).read().splitlines()
        old = open(rf[0]).read().splitlines()
        if new[:4] != old[:4]:
            fail(f'V2 {b}: header (4 lines) differs from Daymet')
        om = {ln.split('\t')[0]: ln.split('\t') for ln in old[4:]}
        s, bad8, errp = src.series(b), 0, 0.0
        for ln in new[4:]:
            p = ln.split('\t')
            o = om.get(p[0])
            if o is None:
                fail(f'V8 {b}: date {p[0]} not in Daymet'); break
            if [p[k] for k in range(len(p)) if k != PRCP_FIELD] != [o[k] for k in range(len(o)) if k != PRCP_FIELD]:
                bad8 += 1
            d = pd.Timestamp(*[int(x) for x in p[0].split()[:3]])
            v = s.get(d, np.nan)
            if p[PRCP_FIELD] == 'NaN':
                if v is not None and not np.isnan(float(v)):
                    errp = max(errp, 1.0)
            elif v is None or np.isnan(float(v)):
                errp = max(errp, 1.0)
            else:
                errp = max(errp, abs(float(p[PRCP_FIELD]) - float(v)))
        if bad8:
            fail(f'V8 {b}: {bad8} lines differ from Daymet outside the precipitation field')
        if not (errp < V5_TOL):
            fail(f'V5 {b}: round-trip error {errp:.2e} >= {V5_TOL}')

    lg = pd.Series(lags)
    rt = pd.Series(ratios)
    cr = pd.Series(corrs)
    off = {b: int(v) for b, v in lags.items() if v != 0}
    share = float((lg == 0).mean()) if len(lg) else 0.0
    if not (RATIO_LO <= float(rt.median()) <= RATIO_HI):
        fail(f'V10 median annual ratio to Daymet {rt.median():.3f} outside [{RATIO_LO}, {RATIO_HI}]')
    if a.self_aggregated and not (SELF_LO <= float(rt.median()) <= SELF_HI):
        fail(f'V7-scale-guard median ratio {rt.median():.3f} outside [{SELF_LO}, {SELF_HI}] (slot-hours factor?)')
    if share < LAG0_MIN:
        fail(f'V11 lag-0 share {share*100:.2f}% < {LAG0_MIN*100:.0f}%')
    NOTE.append(f'V6 (report): lag-0 share {share*100:.2f}%; other lags {dict(pd.Series(list(off.values())).value_counts()) if off else {}}')
    NOTE.append(f'V7 (report): basin-days > {EXTREME} mm: {sum(len(v) for v in extreme.values())} in {len(extreme)} basins')
    for m in NOTE:
        print('NOTE ' + m, flush=True)
    summary = dict(product=a.product, source=a.from_table or f'caravan:{a.from_caravan}', basins=len(basins), written=written,
                   model_span=[MODEL_START, MODEL_END], write_span=[WRITE_START, WRITE_END], v4_tolerance_days=tol_days,
                   failures=FAIL, notes=NOTE, lag0_share=share, v6_off_lag_basins=sorted(off.items()),
                   lag_counts={int(k): int(v) for k, v in lg.value_counts().items()},
                   ratio_over_daymet=dict(median=float(rt.median()), p10=float(rt.quantile(.1)), p90=float(rt.quantile(.9))),
                   corr_daily=dict(median=float(cr.median()), p10=float(cr.quantile(.1)), p90=float(cr.quantile(.9))),
                   nan_days_max=worst, nan_days_by_basin={b: v for b, v in nan_days.items() if v},
                   extreme_basin_days=extreme, v5_sample=sample, small_basins_in_sample=len([b for b in sample if b in small]),
                   span_example=spans.get(basins[0]))
    open(a.report, 'w', encoding='utf-8').write(json.dumps(summary, indent=1, ensure_ascii=False))
    print(json.dumps({k: v for k, v in summary.items() if k not in ('v6_off_lag_basins', 'nan_days_by_basin', 'extreme_basin_days', 'v5_sample')},
                     indent=1, ensure_ascii=False), flush=True)
    if FAIL:
        print(f'checks failed: {len(FAIL)}', flush=True)
        sys.exit(1)
    print('checks passed (V6/V7-extreme/V9 are report items)', flush=True)


if __name__ == '__main__':
    main()
