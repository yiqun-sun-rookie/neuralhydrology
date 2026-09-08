"""Build CAMELS-US-format daily forcing files from the Caravan ERA5-Land netCDF, then verify them.

Writes two forcing products under <dest>/basin_mean_forcing/:
  era5l_caravan/          all 5 variables from Caravan ERA5-Land
  era5l_caravan_pmaurer/  4 from Caravan ERA5-Land, PRCP copied from Maurer (precipitation-decomposition arm)

Design rules (PLAN_20260907 section 4):
  * the date index of every output file is COPIED from that basin's Maurer file -- identical dates, identical row count
  * the first three header lines (lat, elev, area) are copied VERBATIM from the Maurer file; area is the QObs(mm/d)
    denominator and must not change
  * column names are identical to Maurer's, so the training config differs from the frozen one by the `forcings:`
    line only
  * vapour pressure from dewpoint by Magnus:  e[Pa] = 611.2 * exp(17.67 * Td / (Td + 243.5)),  Td in degC
  * downward shortwave has no Caravan equivalent; surface_net_solar_radiation_mean is used (declared, D3)

Verification (every check must pass or the script exits non-zero, which cancels the dependent training jobs):
  V1 file count == number of basins, for both products
  V2 header lines 1-3 byte-identical to Maurer
  V3 date index identical to Maurer (length and every date)
  V4 no NaN inside 1989-01-01..2008-09-30 (the modelled span incl. 270-day warmup before the test period)
  V5 20 random basins: written values round-trip to the netCDF source within 1e-4
  V6 precipitation cross-correlation with Maurer peaks at lag 0 for every basin
  V7 physical ranges: PRCP >= 0, SRAD >= 0, Tmax >= Tmin, Vp > 0
  V8 the hybrid product's PRCP column is byte-identical to Maurer's, and its other 4 columns to era5l_caravan's
"""
import argparse
import glob
import json
import os
import random
import sys

import numpy as np
import pandas as pd
import xarray as xr

P = argparse.ArgumentParser()
P.add_argument('--caravan', default='/data1/home/sunyiq/neuralhydrology/data/Caravan/timeseries/netcdf/camels')
P.add_argument('--maurer', required=True, help='basin_mean_forcing/maurer directory')
P.add_argument('--dest', required=True, help='basin_mean_forcing directory to write the two products into')
P.add_argument('--basins', required=True)
P.add_argument('--report', required=True)
A = P.parse_args()

MODEL_START, MODEL_END = '1989-01-01', '2008-09-30'
COLS = ['PRCP(mm/day)', 'SRAD(W/m2)', 'Tmax(C)', 'Tmin(C)', 'Vp(Pa)']
HEADER = 'Year Mnth Day Hr\t' + '\t'.join(COLS)
SRC = {'PRCP(mm/day)': 'total_precipitation_sum', 'SRAD(W/m2)': 'surface_net_solar_radiation_mean',
       'Tmax(C)': 'temperature_2m_max', 'Tmin(C)': 'temperature_2m_min'}
FAIL = []
NOTE = []


def fail(msg):
    FAIL.append(msg)
    print('FAIL ' + msg, flush=True)


def vapour_pressure_pa(td_c):
    return 611.2 * np.exp(17.67 * td_c / (td_c + 243.5))


def read_maurer(path):
    with open(path) as fh:
        head3 = [fh.readline() for _ in range(3)]
    df = pd.read_csv(path, sep=r'\s+', header=0, skiprows=3)
    df['date'] = pd.to_datetime(dict(year=df.Year, month=df.Mnth, day=df.Day))
    return head3, df.set_index('date')


def write_product(path, head3, frame):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [head3[0], head3[1], head3[2], HEADER + '\n']
    for d, r in frame.iterrows():
        lines.append(f'{d.year:04d} {d.month:02d} {d.day:02d} 12\t{r["PRCP(mm/day)"]:.4f}\t{r["SRAD(W/m2)"]:.4f}'
                     f'\t{r["Tmax(C)"]:.4f}\t{r["Tmin(C)"]:.4f}\t{r["Vp(Pa)"]:.2f}\n')
    with open(path, 'w', newline='\n') as fh:
        fh.writelines(lines)


def main():
    basins = [l.strip().zfill(8) for l in open(A.basins) if l.strip()]
    print(f'basins: {len(basins)}', flush=True)
    lags, ratios, written = {}, {}, {'era5l_caravan': 0, 'era5l_caravan_pmaurer': 0}
    nan_bad, range_bad = [], []

    for i, b in enumerate(basins):
        mfiles = glob.glob(f'{A.maurer}/**/{b}_*_forcing_leap.txt', recursive=True)
        if len(mfiles) != 1:
            fail(f'{b}: {len(mfiles)} maurer files'); continue
        mf = mfiles[0]
        huc = os.path.basename(os.path.dirname(mf))
        head3, m = read_maurer(mf)

        nc = f'{A.caravan}/camels_{b}.nc'
        if not os.path.exists(nc):
            fail(f'{b}: caravan file missing'); continue
        ds = xr.open_dataset(nc)
        c = ds[[SRC[k] for k in SRC] + ['dewpoint_temperature_2m_mean']].to_dataframe()
        c.index = pd.to_datetime(c.index)

        missing = m.index.difference(c.index)
        if len(missing):
            fail(f'{b}: caravan misses {len(missing)} of the maurer dates, first {missing[0].date()}'); continue

        out = pd.DataFrame(index=m.index)
        for k, v in SRC.items():
            out[k] = c.loc[m.index, v].to_numpy()
        out['Vp(Pa)'] = vapour_pressure_pa(c.loc[m.index, 'dewpoint_temperature_2m_mean'].to_numpy())

        span = out.loc[MODEL_START:MODEL_END]
        n_nan = int(span.isna().sum().sum())
        if n_nan:
            nan_bad.append((b, n_nan))
        bad = int((span['PRCP(mm/day)'] < 0).sum() + (span['SRAD(W/m2)'] < 0).sum() +
                  (span['Tmax(C)'] < span['Tmin(C)']).sum() + (span['Vp(Pa)'] <= 0).sum())
        if bad:
            range_bad.append((b, bad))

        mp = m.loc[span.index, 'PRCP(mm/day)']
        cp = span['PRCP(mm/day)']
        r = {k: float(mp.corr(cp.shift(k))) for k in (-2, -1, 0, 1, 2)}
        lags[b] = max(r, key=r.get)
        ratios[b] = float(cp.mean() / mp.mean()) if mp.mean() > 0 else float('nan')

        write_product(f'{A.dest}/era5l_caravan/{huc}/{b}_lump_era5l_caravan_forcing_leap.txt', head3, out)
        written['era5l_caravan'] += 1
        hyb = out.copy()
        hyb['PRCP(mm/day)'] = m.loc[out.index, 'PRCP(mm/day)'].to_numpy()
        write_product(f'{A.dest}/era5l_caravan_pmaurer/{huc}/{b}_lump_era5l_caravan_pmaurer_forcing_leap.txt', head3,
                      hyb)
        written['era5l_caravan_pmaurer'] += 1
        if (i + 1) % 100 == 0:
            print(f'  {i + 1}/{len(basins)}', flush=True)

    # ---------------- verification ----------------
    for prod in written:
        n = len(glob.glob(f'{A.dest}/{prod}/**/*_forcing_leap.txt', recursive=True))
        if n != len(basins):
            fail(f'V1 {prod}: {n} files written, expected {len(basins)}')
    if nan_bad:
        fail(f'V4 NaN inside {MODEL_START}..{MODEL_END} in {len(nan_bad)} basins, e.g. {nan_bad[:3]}')
    if range_bad:
        fail(f'V7 out-of-range values in {len(range_bad)} basins, e.g. {range_bad[:3]}')
    off = {b: l for b, l in lags.items() if l != 0}
    if off:
        fail(f'V6 precip cross-correlation peaks off lag 0 for {len(off)} basins, e.g. {list(off.items())[:5]}')

    rng = random.Random(20260907)
    for b in rng.sample(basins, min(20, len(basins))):
        f = glob.glob(f'{A.dest}/era5l_caravan/**/{b}_*_forcing_leap.txt', recursive=True)
        mf = glob.glob(f'{A.maurer}/**/{b}_*_forcing_leap.txt', recursive=True)
        if not f or not mf:
            fail(f'V2/V3/V5 {b}: output or maurer file missing'); continue
        with open(f[0]) as fh:
            h = [fh.readline() for _ in range(3)]
        with open(mf[0]) as fh:
            hm = [fh.readline() for _ in range(3)]
        if h != hm:
            fail(f'V2 {b}: header lines differ from maurer: {h} vs {hm}')
        d = pd.read_csv(f[0], sep=r'\s+', header=0, skiprows=3)
        d['date'] = pd.to_datetime(dict(year=d.Year, month=d.Mnth, day=d.Day))
        d = d.set_index('date')
        _, m = read_maurer(mf[0])
        if len(d) != len(m) or not (d.index == m.index).all():
            fail(f'V3 {b}: date index differs from maurer ({len(d)} vs {len(m)} rows)')
        ds = xr.open_dataset(f'{A.caravan}/camels_{b}.nc')
        for k, v in SRC.items():
            src = ds[v].to_series()
            src.index = pd.to_datetime(src.index)
            e = float(np.nanmax(np.abs(d[k].to_numpy() - src.loc[d.index].to_numpy())))
            if not (e < 1e-4):
                fail(f'V5 {b} {k}: max round-trip error {e:.2e} >= 1e-4')
        hy = glob.glob(f'{A.dest}/era5l_caravan_pmaurer/**/{b}_*_forcing_leap.txt', recursive=True)[0]
        dh = pd.read_csv(hy, sep=r'\s+', header=0, skiprows=3)
        e_p = float(np.nanmax(np.abs(dh['PRCP(mm/day)'].to_numpy() - m['PRCP(mm/day)'].to_numpy())))
        e_t = float(np.nanmax(np.abs(dh['Tmax(C)'].to_numpy() - d['Tmax(C)'].to_numpy())))
        if not (e_p < 1e-4 and e_t < 1e-9):
            fail(f'V8 {b}: hybrid precip err {e_p:.2e} (vs maurer) / tmax err {e_t:.2e} (vs era5l)')

    lg = pd.Series(lags)
    rt = pd.Series(ratios)
    summary = {
        'basins': len(basins), 'written': written, 'failures': FAIL,
        'lag0_share': float((lg == 0).mean()), 'lag_counts': {int(k): int(v) for k, v in lg.value_counts().items()},
        'precip_ratio_caravan_over_maurer': {'median': float(rt.median()), 'p10': float(rt.quantile(.1)),
                                             'p90': float(rt.quantile(.9))},
        'nan_basins': len(nan_bad), 'range_bad_basins': len(range_bad),
    }
    with open(A.report, 'w') as fh:
        json.dump(summary, fh, indent=1)
    print(json.dumps(summary, indent=1), flush=True)
    if FAIL:
        print(f'VERIFY FAILED: {len(FAIL)} checks', flush=True)
        sys.exit(1)
    print('VERIFY OK: all checks passed', flush=True)


if __name__ == '__main__':
    main()
