"""Build a CAMELS forcing product that differs from Daymet in the precipitation column only (PREREG_20260916, Stage 3).

Copy of precip_swap2_daily_2026_09/hpc_deploy/build_precip_swap2.py (sha256[:16] da27788715b0b03c) with three additions;
the Stage-2 code path (no new flag) is unchanged so that Stage-2 tables rebuild byte-identically (V25):
  * --window-arm      E1 window arms (PREREG section 1 rule (f)): V11 keeps only 'median best-lag correlation >= 0.3'
                      as a hard item; the 'best lag within +-1 day >= 95%' share becomes a report item.
  * --synthetic MODE  E2 / shift1 tables (rule K-F2 / C-F7): V11 is replaced by construction assertions.
                      MODE=noise : best lag == 0 for >= 95% of basins (zero time shift) and per-basin conservation
                                   |sum(candidate)/sum(Daymet) - 1| < 1e-6 over the write window; V7 '>500 mm' is
                                   report-only (D22); the V7 scale guard is not applied.
                      MODE=shift1: candidate[d] == Daymet[d+1] exactly (float equality after the 4-decimal write) for
                                   every basin-day in the write window, hence best lag +1 with correlation 1.
  * the report JSON records the mode and the construction-assertion outcomes;
  * the V5 sample size is min(20, n_basins) so that small-list unit tests run (20 for the 529-basin production run).
Source is --from-table (gzipped or plain CSV: rows = date, columns = 8-digit basin id, mm/day) or --from-caravan.
Written with a file-write tool (not a heredoc); the only backslashes are ordinary string escapes.
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
LAG_WITHIN1_MIN, BESTCORR_MIN = 0.95, 0.30   # V11 as amended (Amendment B)
LAG0_MIN_SYNTH = 0.95                # construction assertion (noise): zero time shift
CONS_TOL = 1e-6                      # construction assertion (noise): per-basin conservation
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
            print('source table %d days x %d basins %s -> %s' % (len(self.tab), self.tab.shape[1], self.tab.index[0].date(), self.tab.index[-1].date()), flush=True)
        else:
            self.ncdir = a.from_caravan
            print('source Caravan netCDF dir %s (variable total_precipitation_sum)' % self.ncdir, flush=True)

    def series(self, b):
        if self.mode == 'table':
            if b not in self.tab.columns:
                return None
            return self.tab[b]
        import xarray as xr
        f = '%s/camels_%s.nc' % (self.ncdir, b)
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
    ap.add_argument('--window-arm', action='store_true', help='E1 window arm: V11 lag share report-only (rule f)')
    ap.add_argument('--synthetic', choices=['noise', 'shift1'], default='', help='E2 / shift1 construction assertions replace V11')
    ap.add_argument('--seed', type=int, default=20260911)
    a = ap.parse_args()
    if bool(a.from_table) == bool(a.from_caravan):
        raise SystemExit('give exactly one of --from-table / --from-caravan')
    if a.synthetic and a.self_aggregated:
        raise SystemExit('--synthetic tables are Daymet-derived: do not combine with --self-aggregated')
    src = Source(a)
    basins = [l.strip().zfill(8) for l in open(a.basins) if l.strip()]
    span_days = (pd.Timestamp(MODEL_END) - pd.Timestamp(MODEL_START)).days + 1
    tol_days = int(np.floor(V4_TOL * span_days))

    lags, ratios, corrs, best_corrs, spans, nan_days, extreme, areas, written = {}, {}, {}, {}, {}, {}, {}, {}, 0
    cons_dev, shift_bad = {}, {}
    for i, b in enumerate(basins):
        rf = glob.glob('%s/**/%s_*_forcing_leap.txt' % (a.ref, b), recursive=True)
        if len(rf) != 1:
            fail('%s: %d reference files' % (b, len(rf))); continue
        head, ridx, rows, area = read_ref(rf[0])
        areas[b] = area
        s = src.series(b)
        if s is None:
            fail('%s: no source series' % b); continue
        keep = [j for j, d in enumerate(ridx) if pd.Timestamp(WRITE_START) <= d <= pd.Timestamp(WRITE_END)]
        out = list(head)
        vals = []
        for j in keep:
            d = ridx[j]
            v = s.get(d, np.nan)
            v = float(v) if v is not None else np.nan
            parts = list(rows[j])
            parts[PRCP_FIELD] = 'NaN' if np.isnan(v) else '%.4f' % v
            out.append('\t'.join(parts))
            vals.append(v)
        huc = os.path.basename(os.path.dirname(rf[0]))
        outp = '%s/%s/%s/%s_lump_%s_forcing_leap.txt' % (a.dest, a.product, huc, b, a.product)
        os.makedirs(os.path.dirname(outp), exist_ok=True)
        with open(outp, 'w', newline='\n') as fh:
            fh.write('\n'.join(out) + '\n')
        written += 1
        ki = ridx[keep]
        cp = pd.Series(vals, index=ki)
        valid = cp.dropna()
        spans[b] = (str(valid.index[0].date()) if len(valid) else None, str(valid.index[-1].date()) if len(valid) else None)
        ref_all = pd.Series([float(rows[j][PRCP_FIELD]) for j in keep], index=ki)
        mp = ref_all.loc[MODEL_START:MODEL_END]
        cm = cp.loc[MODEL_START:MODEL_END]
        nan_days[b] = int(cm.isna().sum())
        if (cm.dropna() < 0).any():
            fail('V7 %s: %d negative values in the modelled span' % (b, int((cm.dropna() < 0).sum())))
        ex = cm[cm > EXTREME]
        if len(ex):
            extreme[b] = [(str(d.date()), float(v)) for d, v in ex.items()]
        both = pd.concat([mp, cm], axis=1, keys=['r', 'c']).dropna()
        r = {k: float(both['r'].corr(both['c'].shift(k))) for k in (-2, -1, 0, 1, 2)}
        lags[b] = max(r, key=lambda k: (r[k] if not np.isnan(r[k]) else -9))
        corrs[b] = r[0]
        best_corrs[b] = r[lags[b]]
        ratios[b] = float(both['c'].mean() / both['r'].mean()) if both['r'].mean() > 0 else float('nan')
        if a.synthetic == 'noise':
            # conservation over the WRITE window; a NaN anywhere in the candidate column is itself a failure (audit B-6)
            cons_dev[b] = float(cp.sum(skipna=False) / ref_all.sum() - 1.0) if (ref_all.sum() > 0 and not cp.isna().any()) else float('nan')
        if a.synthetic == 'shift1':
            # candidate[d] must equal the reference value of d+1 (Daymet has 2 decimals, the table 4 -> exact)
            nxt = pd.Series([float(rows[j + 1][PRCP_FIELD]) if j + 1 < len(rows) else np.nan for j in keep], index=ki)
            shift_bad[b] = int((np.abs(cp.to_numpy() - nxt.to_numpy()) > 1e-9).sum())
        if (i + 1) % 100 == 0:
            print('  %d/%d' % (i + 1, len(basins)), flush=True)

    n = len(glob.glob('%s/%s/**/*_forcing_leap.txt' % (a.dest, a.product), recursive=True))
    if n != len(basins):
        fail('V1 wrote %d, expected %d' % (n, len(basins)))
    short = {b: s for b, s in spans.items()
             if s[0] is None or (pd.Timestamp(TEST_START) - pd.Timestamp(s[0])).days < MIN_WARMUP or s[1] < MODEL_END}
    if short:
        fail('V3 %d basins with insufficient coverage, e.g. %s' % (len(short), list(short.items())[:2]))
    worst = max(nan_days.values()) if nan_days else 0
    if worst > tol_days:
        fail('V4 max NaN days in the modelled span = %d > tolerance %d (%.1f%% of %d days)' % (worst, tol_days, V4_TOL * 100, span_days))
    NOTE.append('V4: NaN days in modelled span: max %d, basins with any NaN %d, total basin-days %d (tolerance %d/basin)' % (
        worst, sum(1 for v in nan_days.values() if v), sum(nan_days.values()), tol_days))

    rng = random.Random(a.seed)
    small = [b for b in basins if areas.get(b, 1e9) < SMALL_KM2]
    sample = rng.sample(small, min(5, len(small)))
    sample += rng.sample([b for b in basins if b not in sample], min(20, len(basins)) - len(sample))  # 20 for 529 basins; smaller lists (unit tests) take all
    for b in sample:
        f = glob.glob('%s/%s/**/%s_*_forcing_leap.txt' % (a.dest, a.product, b), recursive=True)
        rf = glob.glob('%s/**/%s_*_forcing_leap.txt' % (a.ref, b), recursive=True)
        if not f or not rf:
            fail('V2/V5/V8 %s: file missing' % b); continue
        new = open(f[0]).read().splitlines()
        old = open(rf[0]).read().splitlines()
        if new[:4] != old[:4]:
            fail('V2 %s: header (4 lines) differs from Daymet' % b)
        om = {ln.split('\t')[0]: ln.split('\t') for ln in old[4:]}
        s, bad8, errp = src.series(b), 0, 0.0
        for ln in new[4:]:
            p = ln.split('\t')
            o = om.get(p[0])
            if o is None:
                fail('V8 %s: date %s not in Daymet' % (b, p[0])); break
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
            fail('V8 %s: %d lines differ from Daymet outside the precipitation field' % (b, bad8))
        if not (errp < V5_TOL):
            fail('V5 %s: round-trip error %.2e >= %g' % (b, errp, V5_TOL))

    lg = pd.Series(lags)
    rt = pd.Series(ratios)
    cr = pd.Series(corrs)
    off = {b: int(v) for b, v in lags.items() if v != 0}
    share = float((lg == 0).mean()) if len(lg) else 0.0
    within = float((lg.abs() <= 1).mean()) if len(lg) else 0.0
    best_corr = pd.Series(best_corrs)
    if not (RATIO_LO <= float(rt.median()) <= RATIO_HI):
        fail('V10 median annual ratio to Daymet %.3f outside [%s, %s]' % (rt.median(), RATIO_LO, RATIO_HI))
    if a.self_aggregated and not (SELF_LO <= float(rt.median()) <= SELF_HI):
        fail('V7-scale-guard median ratio %.3f outside [%s, %s] (slot-hours factor?)' % (rt.median(), SELF_LO, SELF_HI))
    construction = {}
    if a.synthetic == 'noise':
        # construction assertions (PREREG section 4.1 / V16'): zero time shift, per-basin conservation; V11 not applied
        if share < LAG0_MIN_SYNTH:
            fail('SYN best-lag-0 share = %.2f%% < %g%% (time shift in a zero-shift construction)' % (share * 100, LAG0_MIN_SYNTH * 100))
        dev = pd.Series(cons_dev)
        if dev.isna().any():
            fail('SYN conservation undefined (NaN in candidate column) for %d basins' % int(dev.isna().sum()))
        if not (float(dev.abs().max()) < CONS_TOL):
            fail('SYN conservation max |sum(c)/sum(r)-1| = %.3e >= %g' % (dev.abs().max(), CONS_TOL))
        construction = dict(mode='noise', lag0_share=share, conservation_max_abs_dev=float(dev.abs().max()),
                            extreme_basin_days_gt_500mm=sum(len(v) for v in extreme.values()))
        NOTE.append('SYN (noise): lag-0 share %.2f%%, conservation max |dev| %.2e, >500 mm basin-days %d (report only, D22)' % (
            share * 100, dev.abs().max(), construction['extreme_basin_days_gt_500mm']))
    elif a.synthetic == 'shift1':
        sb = pd.Series(shift_bad)
        if int(sb.sum()) != 0:
            fail('SHIFT1 %d basin-days where candidate[d] != Daymet[d+1]' % int(sb.sum()))
        lag1 = float((lg == 1).mean()) if len(lg) else 0.0
        if lag1 < 1.0 - 1e-12:
            fail('SHIFT1 best lag +1 share = %.2f%% < 100%%' % (lag1 * 100))
        construction = dict(mode='shift1', mismatched_basin_days=int(sb.sum()), lag_plus1_share=lag1,
                            best_lag_corr_median=float(best_corr.median()))
        NOTE.append('SHIFT1: mismatched basin-days %d, best lag +1 share %.2f%%, best-lag corr median %.6f' % (int(sb.sum()), lag1 * 100, best_corr.median()))
    else:
        # V11 as amended (Amendment B): share of best lag within {-1, 0, +1} >= 95% AND median best-lag corr >= 0.3.
        # Stage-3 rule (f): for E1 window arms the lag share is report-only; only the correlation guard stays hard.
        if within < LAG_WITHIN1_MIN:
            if a.window_arm:
                NOTE.append('V11 (window arm, report only): share of best lag within +-1 day = %.2f%% < 95%%' % (within * 100))
            else:
                fail('V11 share of best lag within +-1 day = %.2f%% < 95%%' % (within * 100))
        if not (float(best_corr.median()) >= BESTCORR_MIN):
            fail('V11 median best-lag correlation %.3f < 0.3 -- no time correspondence with Daymet' % best_corr.median())
    NOTE.append('V6 (report): lag-0 share %.2f%% (informative only under Daymet); best-lag counts %s; median best-lag corr %.3f' % (
        share * 100, dict((int(k), int(v)) for k, v in lg.value_counts().items()), best_corr.median()))
    NOTE.append('V7 (report): basin-days > %s mm: %d in %d basins' % (EXTREME, sum(len(v) for v in extreme.values()), len(extreme)))
    for m in NOTE:
        print('NOTE ' + m, flush=True)
    summary = dict(product=a.product, source=a.from_table or ('caravan:' + a.from_caravan), basins=len(basins), written=written,
                   model_span=[MODEL_START, MODEL_END], write_span=[WRITE_START, WRITE_END], v4_tolerance_days=tol_days,
                   window_arm=bool(a.window_arm), synthetic=a.synthetic or None, construction=construction,
                   failures=FAIL, notes=NOTE, lag0_share=share, v6_off_lag_basins=sorted(off.items()),
                   lag_counts={int(k): int(v) for k, v in lg.value_counts().items()},
                   ratio_over_daymet=dict(median=float(rt.median()), p10=float(rt.quantile(.1)), p90=float(rt.quantile(.9))),
                   corr_daily=dict(median=float(cr.median()), p10=float(cr.quantile(.1)), p90=float(cr.quantile(.9))),
                   best_lag_corr_median=float(best_corr.median()), lag_within1_share=within,
                   nan_days_max=worst, nan_days_by_basin={b: v for b, v in nan_days.items() if v},
                   extreme_basin_days=extreme, v5_sample=sample, small_basins_in_sample=len([b for b in sample if b in small]),
                   span_example=spans.get(basins[0]))
    open(a.report, 'w', encoding='utf-8').write(json.dumps(summary, indent=1, ensure_ascii=False))
    print(json.dumps({k: v for k, v in summary.items() if k not in ('v6_off_lag_basins', 'nan_days_by_basin', 'extreme_basin_days', 'v5_sample')},
                     indent=1, ensure_ascii=False), flush=True)
    if FAIL:
        print('checks failed: %d' % len(FAIL), flush=True)
        sys.exit(1)
    print('checks passed (V6/V7-extreme/V9 are report items)', flush=True)


if __name__ == '__main__':
    main()
