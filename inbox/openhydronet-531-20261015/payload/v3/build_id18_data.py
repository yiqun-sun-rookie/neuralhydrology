"""Build the ID18 (Kratzert-2019 reverse split, Maurer forcing, 531 CAMELS-US basins) data in OpenHydroNet's zarr layout.

Every number is produced with the same logic as neuralhydrology.datasetzoo.camelsus (the local, header-tolerant version):
  * forcing  : basin_mean_forcing/maurer/**/<id>_*_forcing_leap.txt, area (m2) = 3rd header line
  * target   : usgs_streamflow/**/<id>_streamflow_qc.txt, QObs[mm/d] = 28316846.592 * cfs * 86400 / (area * 1e6), negatives -> NaN
  * statics  : camels_attributes_v2.0/camels_*.txt, the 27 attributes of the ID18 config
The data root is read-only; nothing is written outside <out_dir>.

Output layout (OpenHydroNet 'multimet' dataset):
  <out>/attributes.zarr                      (basin)                float32 x 27
  <out>/streamflow.zarr                      streamflow(basin, date)
  <out>/dynamics/MAURER/timeseries.zarr      maurer_{prcp,srad,tmax,tmin,vp}(basin, date, lead_time)
The MAURER product carries a 'perfect forecast' lead axis: lead_time = 1..LEADS days and
value[b, D, lead k] = observed forcing on day D + (k - 1), i.e. lead 1 is valid on the issue date itself
(the MultiMet convention). Lead index 0 is therefore the plain observed forcing of day D.

usage: python build_id18_data.py <camels_us_dir> <basin_list.txt> <out_dir> [--leads 7]
"""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

ATTRS = [
    'p_mean', 'pet_mean', 'aridity', 'p_seasonality', 'frac_snow', 'high_prec_freq', 'high_prec_dur', 'low_prec_freq', 'low_prec_dur',
    'elev_mean', 'slope_mean', 'area_gages2', 'frac_forest', 'lai_max', 'lai_diff', 'gvf_max', 'gvf_diff', 'soil_depth_pelletier',
    'soil_depth_statsgo', 'soil_porosity', 'soil_conductivity', 'max_water_content', 'sand_frac', 'silt_frac', 'clay_frac',
    'carbonate_rocks_frac', 'geol_permeability'
]
ATTR_FILES = ['camels_clim.txt', 'camels_geol.txt', 'camels_hydro.txt', 'camels_name.txt', 'camels_soil.txt', 'camels_topo.txt', 'camels_vege.txt']
FORCING_START, FORCING_END = '1980-01-01', '2008-12-31'
FLOW_END = '2014-12-31'
# (lower-case source column in the Maurer files) -> OpenHydroNet feature name
FORCING_COLS = {'prcp(mm/day)': 'maurer_prcp', 'srad(w/m2)': 'maurer_srad', 'tmax(c)': 'maurer_tmax', 'tmin(c)': 'maurer_tmin', 'vp(pa)': 'maurer_vp'}


def load_forcing(root: Path, basin: str):
    files = sorted((root / 'basin_mean_forcing' / 'maurer').glob(f'**/{basin}_*_forcing_leap.txt'))
    assert len(files) == 1, (basin, files)
    with open(files[0], 'r') as fp:
        fp.readline()
        fp.readline()
        area = int(fp.readline())
        df = pd.read_csv(fp, sep=r'\s+')
    if 'Year' in df.columns:
        date = pd.to_datetime(df.Year.astype(str) + '/' + df.Mnth.astype(str) + '/' + df.Day.astype(str), format='%Y/%m/%d')
    else:  # header without the date columns: year / month / day / hour are the first four index levels
        parts = df.index.to_frame(index=False) if isinstance(df.index, pd.MultiIndex) else df.index.to_series().str.split(expand=True)
        date = pd.to_datetime(parts.iloc[:, 0].astype(int).astype(str) + '/' + parts.iloc[:, 1].astype(int).astype(str) + '/' +
                              parts.iloc[:, 2].astype(int).astype(str), format='%Y/%m/%d')
    df.index = pd.DatetimeIndex(date.to_numpy(), name='date')
    df.columns = [c.lower() for c in df.columns]
    return df, area


def load_discharge(root: Path, basin: str, area: int) -> pd.Series:
    files = sorted((root / 'usgs_streamflow').glob(f'**/{basin}_streamflow_qc.txt'))
    assert len(files) == 1, (basin, files)
    df = pd.read_csv(files[0], sep=r'\s+', header=None, names=['basin', 'Year', 'Mnth', 'Day', 'QObs', 'flag'])
    df['date'] = pd.to_datetime(df.Year.astype(str) + '/' + df.Mnth.astype(str) + '/' + df.Day.astype(str), format='%Y/%m/%d')
    df = df.set_index('date')
    q = 28316846.592 * df.QObs * 86400 / (area * 10**6)
    q[q < 0] = np.nan
    return q


def main():
    root, basins_file, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    leads = int(sys.argv[sys.argv.index('--leads') + 1]) if '--leads' in sys.argv else 7
    basins = [b.strip() for b in basins_file.read_text().split() if b.strip()]
    print(len(basins), 'basins; leads', leads, flush=True)
    fdates = pd.date_range(FORCING_START, FORCING_END, freq='D')
    qdates = pd.date_range(FORCING_START, FLOW_END, freq='D')
    F = np.full((len(basins), len(fdates), len(FORCING_COLS)), np.nan, dtype='float32')
    Q = np.full((len(basins), len(qdates)), np.nan, dtype='float32')
    for i, b in enumerate(basins):
        df, area = load_forcing(root, b)
        df = df[~df.index.duplicated(keep='first')]
        for j, col in enumerate(FORCING_COLS):
            F[i, :, j] = df[col].reindex(fdates).to_numpy(dtype='float32')
        q = load_discharge(root, b, area)
        q = q[~q.index.duplicated(keep='first')]
        Q[i] = q.reindex(qdates).to_numpy(dtype='float32')
        if (i + 1) % 100 == 0:
            print('  read', i + 1, flush=True)
    nan_forcing = int(np.isnan(F).sum())
    print('forcing NaN count', nan_forcing, '| streamflow finite fraction', float(np.isfinite(Q).mean()), flush=True)

    # statics (same table merge as nh.load_camels_us_attributes)
    dfs = [pd.read_csv(root / 'camels_attributes_v2.0' / f, sep=';', header=0, dtype={'gauge_id': str}).set_index('gauge_id') for f in ATTR_FILES]
    att = pd.concat(dfs, axis=1)
    assert all(b in att.index for b in basins)
    att = att.loc[basins, ATTRS].astype('float32')
    print('attribute NaN count', int(att.isna().sum().sum()), flush=True)

    out.mkdir(parents=True, exist_ok=True)
    coord_b = np.array(basins, dtype=object)
    xr.Dataset({c: (('basin',), att[c].to_numpy()) for c in ATTRS}, coords={'basin': coord_b}).to_zarr(out / 'attributes.zarr', mode='w-',
                                                                                                        consolidated=False)
    xr.Dataset({'streamflow': (('basin', 'date'), Q)}, coords={'basin': coord_b, 'date': qdates}).to_zarr(out / 'streamflow.zarr', mode='w-',
                                                                                                          consolidated=False)
    # perfect-forecast lead axis: value[b, D, k] = forcing[b, D + k]
    lead_td = pd.to_timedelta(np.arange(1, leads + 1), unit='D')
    data_vars = {}
    for j, name in enumerate(FORCING_COLS.values()):
        arr = np.full((len(basins), len(fdates), leads), np.nan, dtype='float32')
        for k in range(leads):
            arr[:, :len(fdates) - k, k] = F[:, k:, j]
        data_vars[name] = (('basin', 'date', 'lead_time'), arr)
    ds = xr.Dataset(data_vars, coords={'basin': coord_b, 'date': fdates, 'lead_time': lead_td})
    ds = ds.chunk({'basin': 64})
    store = out / 'dynamics' / 'MAURER' / 'timeseries.zarr'
    store.parent.mkdir(parents=True, exist_ok=True)
    ds.to_zarr(store, mode='w-', consolidated=False)
    print('BUILD_DONE', out, flush=True)


if __name__ == '__main__':
    main()
