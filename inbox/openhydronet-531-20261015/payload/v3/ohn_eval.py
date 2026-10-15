"""Per-basin NSE of an OpenHydroNet test_results.zarr, by forecast step, on target days inside a window.

Result layout (verified against the observed record): row `date d` = issue date, `time_step tau` = flow of calendar day d - 1 + tau.
So tau = 0 is day d-1 (inputs up to d-1: plain simulation), tau = 1 is day d (inputs include day d), tau >= 2 uses perfect-forecast forcing.

usage: python ohn_eval.py <test_results.zarr> <window_start> <window_end> <out.csv>
Prints a compact summary and writes basin,n_<tau>,nse_<tau> columns.
"""
import sys

import numpy as np
import pandas as pd
import xarray as xr

zarr_path, w0, w1, out = sys.argv[1], pd.Timestamp(sys.argv[2]), pd.Timestamp(sys.argv[3]), sys.argv[4]
ds = xr.open_zarr(zarr_path, consolidated=False)
if 'freq' in ds.dims:
    ds = ds.isel(freq=0)
obs, sim = ds['streamflow_obs'], ds['streamflow_sim']
if 'samples' in sim.dims:  # probabilistic output: use the sample mean
    sim = sim.mean('samples')
basins = [str(b) for b in ds.basin.values]
taus = [int(t) for t in ds.time_step.values]
dates = pd.DatetimeIndex(ds.date.values)
rows = []
O = obs.transpose('basin', 'date', 'time_step').values.astype('float64')
Sm = sim.transpose('basin', 'date', 'time_step').values.astype('float64')
for tau in taus:
    target = dates + pd.Timedelta(days=tau - 1)
    keep = (target >= w0) & (target <= w1)
    o, s = O[:, keep, tau], Sm[:, keep, tau]
    ok = np.isfinite(o) & np.isfinite(s)
    nse, n = [], []
    for i in range(len(basins)):
        oi, si = o[i][ok[i]], s[i][ok[i]]
        n.append(len(oi))
        nse.append(1.0 - np.sum((si - oi) ** 2) / np.sum((oi - oi.mean()) ** 2) if len(oi) > 2 and np.var(oi) > 0 else np.nan)
    rows.append((tau, np.array(nse), np.array(n)))
df = pd.DataFrame({'basin': basins})
for tau, nse, n in rows:
    df[f'n_{tau}'] = n
    df[f'nse_{tau}'] = nse
df.to_csv(out, index=False)
print('basins', len(basins), '| window', w0.date(), w1.date())
for tau, nse, n in rows:
    print(f'time_step {tau}: median NSE {np.nanmedian(nse):.4f}  mean {np.nanmean(nse):.4f}  basins>0.5: {int(np.nansum(nse > 0.5))}  median days {int(np.median(n))}')
