"""Ensemble evaluation of several OpenHydroNet runs that share the same test period and basins.

Result layout (verified): row `date d` = issue date, `time_step tau` = flow of calendar day d - 1 + tau.
For every time_step tau the member simulations are averaged, then the per-basin NSE of that mean is computed on target days
inside [window_start, window_end]. Also prints the ensemble-size curve (mean over all member subsets of the median per-basin NSE)
for tau = 0 and writes per-basin NSE of the single members and of the full ensemble.

usage: python ohn_ens_eval.py <window_start> <window_end> <out_prefix> <test_results.zarr> [<test_results.zarr> ...]
"""
import itertools
import sys

import numpy as np
import pandas as pd
import xarray as xr

w0, w1, out = pd.Timestamp(sys.argv[1]), pd.Timestamp(sys.argv[2]), sys.argv[3]
paths = sys.argv[4:]


def load(p):
    ds = xr.open_zarr(p, consolidated=False)
    if 'freq' in ds.dims:
        ds = ds.isel(freq=0)
    sim, obs = ds['streamflow_sim'], ds['streamflow_obs']
    if 'samples' in sim.dims:
        sim = sim.mean('samples')
    return (list(map(str, ds.basin.values)), pd.DatetimeIndex(ds.date.values), [int(t) for t in ds.time_step.values],
            obs.transpose('basin', 'date', 'time_step').values.astype('float32'), sim.transpose('basin', 'date', 'time_step').values.astype('float32'))


def nse_per_basin(o, s):
    ok = np.isfinite(o) & np.isfinite(s)
    res = np.full(o.shape[0], np.nan)
    for i in range(o.shape[0]):
        oi, si = o[i][ok[i]].astype('float64'), s[i][ok[i]].astype('float64')
        if len(oi) > 2 and np.var(oi) > 0:
            res[i] = 1.0 - np.sum((si - oi) ** 2) / np.sum((oi - oi.mean()) ** 2)
    return res


basins = dates = taus = O = None
sims = []
for p in paths:
    b, d, t, o, s = load(p)
    if O is None:
        basins, dates, taus, O = b, d, t, o
    else:
        assert b == basins and d.equals(dates) and t == taus, p
        both = np.isfinite(O) & np.isfinite(o)
        assert np.allclose(O[both], o[both], rtol=0, atol=1e-6), f'observations differ in {p}'
    sims.append(s)
    print('loaded', p.split('/')[-4] if len(p.split('/')) > 4 else p, o.shape, flush=True)
S = np.stack(sims)  # member, basin, date, step
print('members', S.shape[0], '| basins', len(basins), '| window', w0.date(), w1.date(), flush=True)

cols = {'basin': basins}
print('ensemble (all members) median NSE by time_step, and the single members at the same step:')
for tau in taus:
    target = dates + pd.Timedelta(days=tau - 1)
    keep = (target >= w0) & (target <= w1)
    o = O[:, keep, tau]
    ens = nse_per_basin(o, S[:, :, keep, tau].mean(axis=0))
    cols[f'ens_{tau}'] = ens
    singles = [nse_per_basin(o, S[m][:, keep, tau]) for m in range(S.shape[0])]
    if tau == 0:
        for m, v in enumerate(singles):
            cols[f'm{m}_0'] = v
    print(f'  time_step {tau}: ensemble {np.nanmedian(ens):.4f} | members ' + ' '.join(f'{np.nanmedian(v):.4f}' for v in singles), flush=True)

# ensemble-size curve at tau = 0
tau = 0
target = dates + pd.Timedelta(days=tau - 1)
keep = (target >= w0) & (target <= w1)
o0 = O[:, keep, 0]
M = S[:, :, keep, 0]
print('ensemble-size curve at time_step 0 (mean over all subsets of the median per-basin NSE):')
for n in range(1, S.shape[0] + 1):
    meds = [np.nanmedian(nse_per_basin(o0, M[list(c)].mean(axis=0))) for c in itertools.combinations(range(S.shape[0]), n)]
    print(f'  N={n}: {np.mean(meds):.4f}  (min {np.min(meds):.4f}, max {np.max(meds):.4f}, subsets {len(meds)})', flush=True)

pd.DataFrame(cols).to_csv(out + '_per_basin.csv', index=False)
print('wrote', out + '_per_basin.csv')
