"""P7 per-hydrological-year paired differences and climatology / persistence baselines (PREREG_20260916 section 8,
D18): computed ON THE HPC from the Stage-2 test_results.p files (read-only), returning a small JSON (< 100 KB) so that
no pickle has to travel through the mailbox. Registration items L6/Q15 (Q15 scored locally by precip3_stats.py
--p7-json). Usage: p7_hydro_year.py --stage2-runs DIR --basins F --holdout F --out JSON
  * per basin and hydrological year 2000..2004 (Oct-Sep, >= 30 valid days): NSE of every reference seed and of the
    imerg_refday / gsmap_refday / chirps seeds; paired difference per year = median over the 24 (or 9x8) ordered pairs
    of the per-basin NSE difference (public 422);
  * climatology baseline: per basin, day-of-year mean of observed flow over the TRAINING period (2004-10-01..2013-09-30)
    evaluated on the test period; persistence baseline: yesterday's observation; both as public-422 median NSE.
Written with a file-write tool (not a heredoc); the only backslashes are ordinary string escapes.
"""
import argparse
import datetime
import glob
import json
import pathlib
import pickle
import sys

import numpy as np
import pandas as pd

REF_SEEDS = list(range(100, 900, 100))
ARM_SEEDS = [100, 200, 300]
ARMS = {'imerg_refday': 'pswap2_armP_imerg_refday', 'gsmap_refday': 'pswap2_armP_gsmap_refday', 'chirps': 'pswap2_armP_chirps'}
YEARS = list(range(2000, 2005))
TRAIN0, TRAIN1 = pd.Timestamp('2004-10-01'), pd.Timestamp('2013-09-30')


def one(pat):
    hits = [h for h in sorted(glob.glob(pat)) if 'INCOMPLETE_' not in h]
    if len(hits) != 1:
        raise SystemExit('expected one match for %s, got %s' % (pat, hits))
    return hits[0]


def series_pair(xr_ds, var):
    s = xr_ds[var].to_series()
    if hasattr(s.index, 'levels'):
        s = s.droplevel(-1)
    return s


def nse(o, s):
    o = np.asarray(o, dtype=float); s = np.asarray(s, dtype=float)
    m = ~np.isnan(o) & ~np.isnan(s)
    o, s = o[m], s[m]
    den = np.sum((o - o.mean()) ** 2)
    return float(1 - np.sum((o - s) ** 2) / den) if den > 0 else np.nan


def per_year(run_dir, basins):
    p = pathlib.Path(run_dir) / 'test' / 'model_epoch030' / 'test_results.p'
    res = pickle.load(open(p, 'rb'))
    out = {}
    obs_keep = {}
    for b in basins:
        e = res.get(b) or res.get(b.lstrip('0'))
        if e is None:
            continue
        xr_ds = e['1D']['xr']
        obs = series_pair(xr_ds, 'QObs(mm/d)_obs'); sim = series_pair(xr_ds, 'QObs(mm/d)_sim')
        df = pd.DataFrame({'o': obs, 's': sim}).dropna()
        hy = df.index.year + (df.index.month >= 10).astype(int)
        r = {}
        for y in YEARS:
            d = df[hy == y]
            if len(d) >= 30:
                r[y] = nse(d.o, d.s)
        out[b] = r
        obs_keep[b] = df['o']
    return pd.DataFrame(out).T.reindex(basins), obs_keep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage2-runs', required=True)
    ap.add_argument('--basins', required=True)
    ap.add_argument('--holdout', required=True)
    ap.add_argument('--streamflow', default='', help='usgs_streamflow dir for the climatology baseline (training period)')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    b529 = [l.strip().zfill(8) for l in open(a.basins) if l.strip()]
    hold = set(l.strip().replace(chr(13), '').zfill(8) for l in open(a.holdout) if l.strip())
    pub = [b for b in b529 if b not in hold]
    assert len(pub) == 422, len(pub)
    ref = {}
    obs_test = None
    for s in REF_SEEDS:
        ref[s], ob = per_year(one('%s/ref_daymet_s%d_*' % (a.stage2_runs, s)), pub)
        obs_test = obs_test or ob
    out = {'generated': datetime.datetime.now().isoformat(timespec='seconds'), 'years': YEARS, 'public_422': len(pub), 'arms': {}}
    for key, stem in ARMS.items():
        arm = {s: per_year(one('%s/%s_s%d_*' % (a.stage2_runs, stem, s)), pub)[0] for s in ARM_SEEDS}
        per = {}
        for y in YEARS:
            meds = [float((arm[sa][y] - ref[sb][y]).dropna().median()) for sa in ARM_SEEDS for sb in REF_SEEDS]
            per[str(y)] = {'main_reading': float(np.median(meds)), 'n_pairs': len(meds), 'pair_min': float(min(meds)), 'pair_max': float(max(meds))}
        yrs = [per[str(y)]['main_reading'] for y in YEARS]
        rk = pd.Series(yrs).rank().to_numpy(); ry = pd.Series(YEARS).rank().to_numpy()
        rho = float(np.corrcoef(rk, ry)[0, 1])
        out['arms'][key] = {'per_year': per, 'spearman_vs_year': rho}
    # baselines (public 422): climatology from the training-period observations, persistence = yesterday
    if a.streamflow:
        clim_nse, pers_nse = [], []
        for b in pub:
            f = glob.glob('%s/**/%s_streamflow_qc.txt' % (a.streamflow, b), recursive=True)
            if not f:
                continue
            q = {}
            for line in open(f[0]):
                pp = line.split()
                if len(pp) < 5:
                    continue
                dtt = pd.Timestamp(int(pp[1]), int(pp[2]), int(pp[3])); v = float(pp[4])
                q[dtt] = v if v >= 0 else np.nan
            qs = pd.Series(q).sort_index()
            tr = qs.loc[TRAIN0:TRAIN1].dropna()
            clim = tr.groupby([tr.index.month, tr.index.day]).mean()
            ot = obs_test.get(b)
            if ot is None or len(ot) == 0:
                continue
            # observed flow in the test period comes from the run's own obs series (mm/d); baselines use the same units
            # only if the raw file is in the same units, so baselines are computed on the RAW cfs series over the test dates
            te = qs.reindex(ot.index)
            c = np.array([clim.get((d.month, d.day), np.nan) for d in te.index])
            clim_nse.append(nse(te.to_numpy(), c))
            pers_nse.append(nse(te.to_numpy()[1:], te.to_numpy()[:-1]))
        out['baselines_raw_units'] = {'n': len(clim_nse), 'climatology_median_nse': float(np.nanmedian(clim_nse)), 'persistence_median_nse': float(np.nanmedian(pers_nse)),
                                      'note': 'computed on the raw USGS series (cfs) over the test dates; NSE is unit-free'}
    ref_med = {str(y): float(np.nanmedian(pd.concat([ref[s][y] for s in REF_SEEDS], axis=1).median(axis=1))) for y in YEARS}
    out['reference_public_median_by_year'] = ref_med
    pathlib.Path(a.out).write_text(json.dumps(out, indent=1), encoding='utf-8')
    print(json.dumps({k: v for k, v in out.items() if k != 'arms'}, indent=1))
    for k, v in out['arms'].items():
        print(k, 'spearman_vs_year', round(v['spearman_vs_year'], 3), {y: round(v['per_year'][y]['main_reading'], 4) for y in v['per_year']})
    print('wrote', a.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
