"""Shared data loading utilities for HydroAgent experiments.

Provides load_camels_basin() used by both test scripts and the batch runner.
"""
from __future__ import annotations

import glob
import os
from pathlib import Path
from typing import Tuple, Union

import numpy as np
import pandas as pd

# Default CAMELS-US data root: <project_root>/data/camels_us
_DEFAULT_DATA_ROOT = Path(__file__).resolve().parents[2] / 'data' / 'camels_us'


def _find_file(data_root: str, subdir: str, filename: str) -> str:
    """Find a basin file by searching all HUC subdirectories.

    CAMELS-US stores files under HUC subdirectories, but the HUC code
    doesn't always match basin_id[:2]. Search all subdirs as fallback.
    """
    # Fast path: try basin_id[:2] first
    basin_id_prefix = filename[:2]
    direct = os.path.join(data_root, subdir, basin_id_prefix, filename)
    if os.path.exists(direct):
        return direct

    # Fallback: glob across all HUC dirs
    matches = glob.glob(os.path.join(data_root, subdir, '*', filename))
    if matches:
        return matches[0]

    raise FileNotFoundError(f"Cannot find {filename} under {os.path.join(data_root, subdir)}/*/")


def load_camels_basin(
    basin_id: str,
    data_root: Union[str, Path, None] = None,
    start_date: str = '1990-10-01',
    end_date: str = '1993-09-30',
) -> Tuple[pd.DataFrame, pd.Series, float]:
    """Load CAMELS-US basin forcing and observed streamflow.

    Returns:
        (forcing_df[prcp, ep, tmean], obs_mm, area_km2)
    """
    data_root = str(data_root or _DEFAULT_DATA_ROOT)

    # -- Forcing --
    forcing_path = _find_file(
        data_root, os.path.join('basin_mean_forcing', 'daymet'),
        basin_id + '_lump_cida_forcing_leap.txt'
    )
    df_forcing = pd.read_csv(forcing_path, skiprows=3, sep=r'\s+')
    df_forcing['date'] = pd.to_datetime(
        df_forcing[['Year', 'Mnth', 'Day']].rename(
            columns={'Year': 'year', 'Mnth': 'month', 'Day': 'day'}
        )
    )
    df_forcing.set_index('date', inplace=True)

    # -- Streamflow --
    streamflow_path = _find_file(
        data_root, 'usgs_streamflow',
        basin_id + '_streamflow_qc.txt'
    )
    df_sf = pd.read_csv(streamflow_path, sep=r'\s+', header=None,
                        names=['gauge_id', 'year', 'month', 'day', 'discharge_cfs', 'qc_flag'])
    df_sf['date'] = pd.to_datetime(df_sf[['year', 'month', 'day']])
    df_sf.set_index('date', inplace=True)

    forcing = df_forcing.loc[start_date:end_date].copy()
    streamflow = df_sf.loc[start_date:end_date].copy()

    # -- Area --
    topo_file = os.path.join(data_root, 'camels_attributes_v2.0', 'camels_topo.txt')
    df_topo = pd.read_csv(topo_file, sep=';')
    df_topo['gauge_id'] = df_topo['gauge_id'].astype(str).str.zfill(8)
    area_km2 = df_topo[df_topo['gauge_id'] == basin_id]['area_gages2'].values[0]

    # -- Convert cfs -> mm/day --
    conversion_factor = 2.4466 / area_km2
    streamflow['qobs_mm'] = streamflow['discharge_cfs'] * conversion_factor
    streamflow.loc[streamflow['discharge_cfs'] < 0, 'qobs_mm'] = np.nan

    # -- Prepare forcing --
    forcing_out = pd.DataFrame(index=forcing.index)
    forcing_out['prcp'] = forcing['prcp(mm/day)'].values

    tmax = forcing['tmax(C)'].values
    tmin = forcing['tmin(C)'].values
    srad = forcing['srad(W/m2)'].values
    tmean = (tmax + tmin) / 2
    delta_t = np.maximum(tmax - tmin, 0.1)
    ra_mm = srad * 0.0864 / 2.45  # W/m2 → MJ/m2/d → mm/d equivalent
    pet = 0.0023 * ra_mm * np.sqrt(delta_t) * (tmean + 17.8)
    forcing_out['ep'] = np.maximum(pet, 0)
    forcing_out['tmean'] = tmean

    # -- Align and filter NaN --
    common_idx = forcing_out.index.intersection(streamflow.index)
    forcing_out = forcing_out.loc[common_idx]
    obs = streamflow.loc[common_idx, 'qobs_mm']
    valid_mask = ~obs.isna()
    forcing_out = forcing_out.loc[valid_mask]
    obs = obs.loc[valid_mask]

    return forcing_out, obs, area_km2


def load_basin_metadata(
    basin_id: str,
    data_root: Union[str, Path, None] = None,
) -> dict:
    """Load CAMELS-US basin attributes for LLM context.

    Returns a flat dict with key physical/climatic properties that help
    an LLM choose an appropriate initial model structure.

    Raises ValueError if basin not found.
    """
    data_root = str(data_root or _DEFAULT_DATA_ROOT)
    attr_dir = os.path.join(data_root, 'camels_attributes_v2.0')

    def _read_attr(filename, columns):
        df = pd.read_csv(os.path.join(attr_dir, filename), sep=';')
        df['gauge_id'] = df['gauge_id'].astype(str).str.zfill(8)
        row = df[df['gauge_id'] == basin_id]
        if row.empty:
            raise ValueError(f"Basin {basin_id} not found in {filename}")
        result = {}
        for col in columns:
            if col in row.columns:
                val = row.iloc[0][col]
                # Strip whitespace from string values
                if isinstance(val, str):
                    val = val.strip()
                result[col] = val
        return result

    meta = {}
    meta.update(_read_attr('camels_topo.txt', ['elev_mean', 'slope_mean', 'area_gages2']))
    meta.update(_read_attr('camels_clim.txt', ['p_mean', 'pet_mean', 'aridity', 'frac_snow', 'p_seasonality']))
    meta.update(_read_attr('camels_vege.txt', ['frac_forest', 'dom_land_cover']))

    # Rename for clarity
    if 'area_gages2' in meta:
        meta['area_km2'] = meta.pop('area_gages2')

    return meta
