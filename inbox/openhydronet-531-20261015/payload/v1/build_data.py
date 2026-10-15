"""Build the CAMELS-US-531 data stores for OpenHydroNet inside ROOT/data/camels-updated-2025.

Runs on the HPC login node (network I/O only, no model compute):
  1. sparse MultiMet mirror: zarr metadata + coordinates + only the basin-chunks holding the 531 basins
  2. streamflow.zarr: USGS daily mean discharge (cfs) -> mm/d with the Caravan basin area
     (the same recipe reproduces Google's 'camels-updated-2025': checked against the tutorial Caravan data, max diff 4e-4 mm/d)
  3. attributes.zarr: Caravan camels attribute CSVs (caravan + hydroatlas + other), numeric columns, float32

usage: python build_data.py <ROOT> <basin_list.txt> <attrs_dir> [--skip-dynamics] [--skip-streamflow]
"""
import json
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr
import zarr

BASE = 'https://storage.googleapis.com/caravan-multimet/v1.1'
PRODUCTS = {
    'HRES': ['hres_surface_net_solar_radiation', 'hres_surface_net_thermal_radiation', 'hres_surface_pressure', 'hres_temperature_2m',
             'hres_total_precipitation'],
    'GRAPHCAST': ['graphcast_temperature_2m', 'graphcast_total_precipitation'],
    'IMERG': ['imerg_precipitation'],
    'CPC': ['cpc_precipitation'],
    'ERA5_LAND': ['era5land_total_precipitation', 'era5land_temperature_2m', 'era5land_surface_net_solar_radiation',
                  'era5land_surface_net_thermal_radiation', 'era5land_surface_pressure', 'era5land_u_component_of_wind_10m',
                  'era5land_v_component_of_wind_10m'],
}
USGS = ('https://waterservices.usgs.gov/nwis/dv/?format=json&sites={site}&parameterCd=00060&statCd=00003'
        '&startDT={start}&endDT={end}')
START, END = '1980-01-01', '2025-12-31'
THREADS = 4


def fetch(url, dest=None, retries=8, timeout=90):
    if dest is not None and dest.exists():
        return dest.stat().st_size
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                data = r.read()
            if dest is None:
                return data
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp = dest.with_name(dest.name + '.part')
            tmp.write_bytes(data)
            tmp.replace(dest)
            return len(data)
        except Exception as e:  # noqa: BLE001 - any network error is retried
            if getattr(e, 'code', None) == 404:
                return 0 if dest is not None else None
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f'failed after {retries} tries: {url}')


def build_dynamics(root, basins):
    out = root / 'dynamics'
    total = 0
    with ThreadPoolExecutor(THREADS) as pool:
        for product, variables in PRODUCTS.items():
            store = out / product / 'timeseries.zarr'
            zmeta = json.loads(fetch(f'{BASE}/{product}/timeseries.zarr/.zmetadata'))
            meta = zmeta['metadata']
            store.mkdir(parents=True, exist_ok=True)
            (store / '.zmetadata').write_text(json.dumps(zmeta))
            for key, val in meta.items():
                p = store / key
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(json.dumps(val))
            arrays = {k.rsplit('/', 1)[0]: v for k, v in meta.items() if k.endswith('.zarray')}
            jobs = []
            for name, m in arrays.items():  # 1-D coordinate arrays: every chunk
                if len(m['shape']) == 1:
                    jobs += [f'{name}/{i}' for i in range(-(-m['shape'][0] // m['chunks'][0]))]
            total += sum(pool.map(lambda k: fetch(f'{BASE}/{product}/timeseries.zarr/{k}', store / k), jobs))
            all_basins = list(zarr.open_array(str(store / 'basin'), mode='r')[:])
            pos = {b: i for i, b in enumerate(all_basins)}
            missing = [b for b in basins if b not in pos]
            jobs = []
            for name in variables:
                m = arrays[name]
                chunks = sorted({pos[b] // m['chunks'][0] for b in basins if b in pos})
                jobs += [f'{name}/{c}' + ''.join('.0' for _ in m['shape'][1:]) for c in chunks]
            got = sum(pool.map(lambda k: fetch(f'{BASE}/{product}/timeseries.zarr/{k}', store / k), jobs))
            total += got
            print(f'{product:10s} {len(jobs):3d} chunks {got / 1e6:8.1f} MB  basins missing: {len(missing)}', flush=True)
    print(f'dynamics total {total / 1e6:.1f} MB', flush=True)


def build_streamflow(root, basins, area_km2):
    idx = pd.date_range(START, END, freq='D')
    series = {}

    def one(b):
        site = b.split('_', 1)[1]
        raw = fetch(USGS.format(site=site, start=START, end=END))
        d = json.loads(raw)
        ts = d['value']['timeSeries']
        if not ts:
            return b, None
        vals = ts[0]['values'][0]['value']
        nodata = float(ts[0]['variable'].get('noDataValue', -999999))
        s = pd.Series([float(v['value']) for v in vals], index=pd.to_datetime([v['dateTime'][:10] for v in vals]))
        s = s[(s != nodata) & (s >= 0)]
        s = s[~s.index.duplicated(keep='first')]
        return b, s * 0.0283168 * 86400.0 / (area_km2[b] * 1e6) * 1000.0  # cfs -> mm/d

    with ThreadPoolExecutor(THREADS) as pool:
        for n, (b, s) in enumerate(pool.map(one, basins), 1):
            series[b] = s
            if n % 50 == 0:
                print(f'  usgs {n}/{len(basins)}', flush=True)
    none = [b for b, s in series.items() if s is None]
    arr = np.full((len(basins), len(idx)), np.nan, dtype='float32')
    for i, b in enumerate(basins):
        if series[b] is not None:
            arr[i] = series[b].reindex(idx).to_numpy(dtype='float32')
    ds = xr.Dataset({'streamflow': (('basin', 'date'), arr)}, coords={'basin': np.array(basins, dtype=object), 'date': idx})
    ds.attrs['Source'] = 'USGS NWIS daily mean discharge (00060, 00003), cfs -> mm/d using Caravan basin area; built by build_data.py'
    out = root / 'streamflow.zarr'
    ds.to_zarr(out, mode='w-', consolidated=False)
    fin = np.isfinite(arr)
    print(f'streamflow.zarr {arr.shape}  basins without USGS series: {none}  finite days/basin median {int(np.median(fin.sum(1)))}  '
          f'finite 2016-2025 median {int(np.median(fin[:, idx >= "2016-01-01"].sum(1)))}', flush=True)


def build_attributes(root, basins, attrs_dir):
    frames = [pd.read_csv(Path(attrs_dir) / f'attributes_{k}_camels.csv').set_index('gauge_id') for k in ('caravan', 'hydroatlas', 'other')]
    df = pd.concat(frames, axis=1).loc[basins]
    df = df.loc[:, ~df.columns.duplicated()]
    num = df.apply(pd.to_numeric, errors='coerce')
    num = num.loc[:, num.notna().any()].astype('float32')
    ds = xr.Dataset({c: (('basin',), num[c].to_numpy()) for c in num.columns}, coords={'basin': np.array(basins, dtype=object)})
    ds.to_zarr(root / 'attributes.zarr', mode='w-', consolidated=False)
    print(f'attributes.zarr {len(basins)} basins x {num.shape[1]} numeric columns', flush=True)


def main():
    root = Path(sys.argv[1]) / 'data' / 'camels-updated-2025'
    root.mkdir(parents=True, exist_ok=True)
    basins = [b.strip() for b in Path(sys.argv[2]).read_text().split() if b.strip()]
    assert len(basins) == 531, len(basins)
    attrs_dir = sys.argv[3]
    area = pd.read_csv(Path(attrs_dir) / 'attributes_other_camels.csv').set_index('gauge_id')['area'].to_dict()
    if '--skip-dynamics' not in sys.argv:
        build_dynamics(root, basins)
    if '--skip-streamflow' not in sys.argv and not (root / 'streamflow.zarr').exists():
        build_streamflow(root, basins, area)
    if not (root / 'attributes.zarr').exists():
        build_attributes(root, basins, attrs_dir)
    print('BUILD_DONE', root)


if __name__ == '__main__':
    main()
