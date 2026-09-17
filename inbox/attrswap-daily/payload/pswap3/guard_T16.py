"""T16 same-machine cross-time guard (PREREG_20260916 section 5.3 / stop condition 6).

For each E3 arm (pswap3_ep60_ref_daymet_s{100,200,300}, pswap3_ep60_era5l_refday_s{100,200,300}) read the EPOCH-30
test_metrics.csv and pair it per basin with the Stage-2 run of the same seed (ref_daymet_s<seed> / pswap2_armP_
era5l_refday_s<seed>); the reading is the public-422 median of (stage3 - stage2). Three tiers:
  CLEAN : all 6 |reading| < ABS_MAX (0.006346)              -> marker written, exit 0
  FLAG  : exactly one reading in [ABS_MAX, HARD) (HARD 0.03) -> marker written with status FLAG, exit 0
  STOP  : two or more in [ABS_MAX, HARD), or any >= HARD     -> no marker, exit 1
Usage: guard_T16.py --stage3-runs DIR --stage2-runs DIR --basins F --holdout F --out JSON --marker FILE
Written with a file-write tool (not a heredoc); the only backslashes are ordinary string escapes.
"""
import argparse
import datetime
import glob
import json
import pathlib
import sys

import numpy as np
import pandas as pd

ABS_MAX = 0.006346344947814914   # noise_floor_daymet.json abs_max (public 422)
HARD = 0.03
PAIRS = {'pswap3_ep60_ref_daymet': 'ref_daymet', 'pswap3_ep60_era5l_refday': 'pswap2_armP_era5l_refday'}
SEEDS = (100, 200, 300)


def one(pat):
    hits = [h for h in sorted(glob.glob(pat)) if 'INCOMPLETE_' not in h]
    if len(hits) != 1:
        raise SystemExit('expected exactly one run dir for %s, got %s' % (pat, hits))
    return hits[0]


def load(path, basins):
    d = pd.read_csv(path, dtype={'basin': str})
    d['basin'] = d['basin'].str.zfill(8)
    return d.set_index('basin')['NSE'].reindex(basins)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage3-runs', required=True)
    ap.add_argument('--stage2-runs', required=True)
    ap.add_argument('--basins', required=True)
    ap.add_argument('--holdout', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--marker', required=True)
    a = ap.parse_args()
    b529 = [l.strip().zfill(8) for l in open(a.basins) if l.strip()]
    hold = set(l.strip().replace(chr(13), '').zfill(8) for l in open(a.holdout) if l.strip())
    pub = [b for b in b529 if b not in hold]
    assert len(pub) == 422, len(pub)
    readings = {}
    for s3, s2 in PAIRS.items():
        for s in SEEDS:
            f3 = one('%s/%s_s%d_*/test/model_epoch030/test_metrics.csv' % (a.stage3_runs, s3, s))
            f2 = one('%s/%s_s%d_*/test/model_epoch030/test_metrics.csv' % (a.stage2_runs, s2, s))
            x = (load(f3, pub) - load(f2, pub)).dropna()
            readings['%s_s%d' % (s3, s)] = dict(stage3=f3, stage2=f2, n=int(len(x)), median=float(np.median(x)),
                                                 abs_gt_0_10_share=float(np.mean(np.abs(x) > 0.10)))
    meds = [abs(r['median']) for r in readings.values()]
    n_between = sum(1 for m in meds if ABS_MAX <= m < HARD)
    n_hard = sum(1 for m in meds if m >= HARD)
    if n_hard == 0 and n_between == 0:
        status = 'CLEAN'
    elif n_hard == 0 and n_between == 1:
        status = 'FLAG'
    else:
        status = 'STOP'
    out = dict(generated=datetime.datetime.now().isoformat(timespec='seconds'), abs_max=ABS_MAX, hard=HARD,
               readings=readings, n_between=n_between, n_hard=n_hard, status=status,
               median_of_readings=float(np.median([r['median'] for r in readings.values()])))
    pathlib.Path(a.out).write_text(json.dumps(out, indent=1), encoding='utf-8')
    print(json.dumps({k: v for k, v in out.items() if k != 'readings'}, indent=1))
    for k, r in readings.items():
        print('  %-36s median %+.6f  |d|>0.10 share %.3f' % (k, r['median'], r['abs_gt_0_10_share']))
    if status in ('CLEAN', 'FLAG'):
        pathlib.Path(a.marker).write_text('T16 %s %s\n' % (status, out['generated']), encoding='utf-8')
        print('GUARD T16', status, '-> marker written')
        return 0
    print('GUARD T16 STOP -> no marker; submission halted (PREREG 5.3)')
    return 1


if __name__ == '__main__':
    sys.exit(main())
