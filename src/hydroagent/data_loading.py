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


# Map forcing name -> (subdir, filename_marker) used to locate forcing files.
# Daymet files are named *_lump_cida_forcing_leap.txt; Maurer / NLDAS variants
# follow *_lump_<forcing>_forcing_leap.txt.
_FORCING_MAP = {
    'daymet': ('daymet', 'cida'),
    'maurer': ('maurer', 'maurer'),
    'maurer_extended': ('maurer_extended', 'maurer'),
    'nldas': ('nldas', 'nldas'),
    'nldas_extended': ('nldas_extended', 'nldas'),
}


def _priestley_taylor_pet_mm(srad_w_per_m2: np.ndarray, dayl_sec: np.ndarray,
                              tmean_c: np.ndarray, vp_pa: np.ndarray | None = None,
                              albedo: float = 0.23,
                              alpha_pt: float = 1.26) -> np.ndarray:
    """Daily PET in mm/d using Priestley-Taylor (1972).

    PET_PT = alpha * (Δ/(Δ+γ)) * Rn / λ

    where:
        Δ = slope of saturation vapor pressure curve [kPa/°C]
        γ = psychrometric constant ≈ 0.067 kPa/°C at sea level
        Rn = net radiation [MJ/m²/d]; here computed as
             (1-albedo)*SRAD_MJ - Rnl_simplified
        λ = 2.45 MJ/kg (latent heat of vaporization)
        alpha = 1.26 (Priestley-Taylor coefficient)

    This formulation closely tracks CAMELS-US ``camels_clim.txt::pet_mean``,
    fixing the Oudin underestimate (audit found Oudin = 0.19-0.55x of
    CAMELS-US published).

    Args:
        srad_w_per_m2: daylight-period mean SRAD [W/m²].
        dayl_sec: day length in seconds.
        tmean_c: daily mean air temp [°C].
        vp_pa: optional vapor pressure [Pa] (Maurer/Daymet provide Vp).
               If None, Rnl approximated without humidity correction.
        albedo: surface albedo [-], default 0.23 (grass).
        alpha_pt: Priestley-Taylor coefficient, default 1.26.
    """
    # Slope of saturation vapor pressure curve [kPa/°C]
    es = 0.6108 * np.exp(17.27 * tmean_c / (tmean_c + 237.3))
    delta = 4098.0 * es / (tmean_c + 237.3) ** 2

    # Psychrometric constant at sea level
    gamma = 0.067

    # Solar radiation MJ/m²/d (using actual daylight period)
    srad_mj = srad_w_per_m2 * dayl_sec / 1.0e6

    # Net shortwave (after albedo reflection)
    rns = (1.0 - albedo) * srad_mj

    # Net longwave radiation (simplified, no humidity if vp not given)
    # σ = 4.903e-9 MJ/m²/K⁴/d (Stefan-Boltzmann)
    sigma = 4.903e-9
    t_kelvin = tmean_c + 273.15
    if vp_pa is not None:
        ea_kpa = vp_pa / 1000.0
        humidity_term = 0.34 - 0.14 * np.sqrt(np.clip(ea_kpa, 0.0, None))
    else:
        humidity_term = 0.20  # midrange default
    rnl = sigma * t_kelvin ** 4 * humidity_term
    # Cap Rnl so Rn stays non-negative for low SRAD days
    rnl = np.minimum(rnl, rns * 0.85)

    rn = rns - rnl
    rn = np.clip(rn, 0.0, None)

    # Priestley-Taylor
    pet = alpha_pt * (delta / (delta + gamma)) * rn / 2.45
    return np.clip(pet, 0.0, None)


def _oudin_pet_mm(srad_w_per_m2: np.ndarray, dayl_sec: np.ndarray,
                  tmean_c: np.ndarray) -> np.ndarray:
    """Daily PET in mm/d using Oudin et al. (2005) formulation.

    Why Oudin and not Hargreaves: the CAMELS-US Maurer forcing stores
    daily mean temperature in BOTH the Tmax and Tmin columns
    (Tmax==Tmin for 100% of days, verified 2026-05-27). Hargreaves
    requires the diurnal temperature range Tmax-Tmin, which Maurer
    therefore cannot provide. Oudin only requires daily SRAD + Tmean,
    works on both Daymet and Maurer, and is a well-established
    PET formula in lumped-model hydrology benchmarks (e.g., Beck et al.
    2017, Knoben et al. 2020).

    Formula (Oudin et al. 2005, J. Hydrol. 303):

        PET = SRAD_MJ * (T + 5) / 245     if T > -5
            = 0                            otherwise

    where:
        SRAD_MJ = SRAD_W * dayl_sec / 1e6     (W/m² × s = J/m²; /1e6 → MJ/m²)
        245    = 100 × λ (λ = 2.45 MJ/kg, latent heat of vaporization)

    Args:
        srad_w_per_m2: incoming shortwave at surface, daylight-period
            mean [W/m²] (CAMELS Daymet and Maurer convention).
        dayl_sec: day length in seconds (CAMELS dayl column).
        tmean_c: daily mean air temperature [°C].

    Returns:
        PET in mm/d.
    """
    srad_mj_per_m2_per_day = srad_w_per_m2 * dayl_sec / 1.0e6
    return np.where(
        tmean_c > -5.0,
        srad_mj_per_m2_per_day * (tmean_c + 5.0) / 245.0,
        0.0,
    )


def _find_forcing_col(df: pd.DataFrame, prefix: str) -> str:
    """Case-insensitive forcing column lookup.

    Daymet uses lowercase ('prcp(mm/day)', 'tmax(C)') while Maurer uses
    uppercase ('PRCP(mm/day)', 'Tmax(C)'). Match on lowercase prefix.
    """
    target = prefix.lower()
    for col in df.columns:
        if str(col).lower().startswith(target):
            return col
    raise KeyError(f'No forcing column starts with {prefix!r} (have: {list(df.columns)})')


def load_camels_basin(
    basin_id: str,
    data_root: Union[str, Path, None] = None,
    start_date: str = '1990-10-01',
    end_date: str = '1993-09-30',
    forcing: str = 'daymet',
    pet_method: str = 'oudin',
) -> Tuple[pd.DataFrame, pd.Series, float]:
    """Load CAMELS-US basin forcing and observed streamflow.

    Args:
        forcing: One of 'daymet', 'maurer', 'maurer_extended', 'nldas',
            'nldas_extended'. Default 'daymet' preserves prior behaviour.
            'maurer_extended' is required to align with the published
            CAMELS benchmark on HydroShare (Newman/Kratzert 2019).

    Returns:
        (forcing_df[prcp, ep, tmean], obs_mm, area_km2)
    """
    data_root = str(data_root or _DEFAULT_DATA_ROOT)

    if forcing not in _FORCING_MAP:
        raise ValueError(f'Unknown forcing {forcing!r}; expected one of {list(_FORCING_MAP)}')
    subdir, marker = _FORCING_MAP[forcing]

    # -- Forcing --
    forcing_path = _find_file(
        data_root, os.path.join('basin_mean_forcing', subdir),
        f'{basin_id}_lump_{marker}_forcing_leap.txt'
    )
    df_forcing = pd.read_csv(forcing_path, skiprows=3, sep=r'\s+')
    # A small number of CAMELS-US maurer files have a defective header line
    # missing the leading Year/Mnth/Day/Hr column names (data rows still
    # contain those columns). Detect and patch by re-reading with
    # header=None and prepending the four missing date columns.
    if 'Year' not in df_forcing.columns:
        df_forcing = pd.read_csv(forcing_path, skiprows=4, sep=r'\s+', header=None)
        with open(forcing_path, 'r', encoding='utf-8') as fh:
            for _ in range(3):
                fh.readline()
            var_names = fh.readline().strip().split()
        df_forcing.columns = ['Year', 'Mnth', 'Day', 'Hr'] + var_names
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

    # -- Topo (area only — Oudin PET doesn't need latitude) --
    topo_file = os.path.join(data_root, 'camels_attributes_v2.0', 'camels_topo.txt')
    df_topo = pd.read_csv(topo_file, sep=';')
    df_topo['gauge_id'] = df_topo['gauge_id'].astype(str).str.zfill(8)
    area_km2 = df_topo[df_topo['gauge_id'] == basin_id]['area_gages2'].values[0]

    # -- Convert cfs -> mm/day --
    conversion_factor = 2.4466 / area_km2
    streamflow['qobs_mm'] = streamflow['discharge_cfs'] * conversion_factor
    streamflow.loc[streamflow['discharge_cfs'] < 0, 'qobs_mm'] = np.nan

    # -- Prepare forcing (case-insensitive — Daymet uses lowercase, Maurer uppercase) --
    forcing_out = pd.DataFrame(index=forcing.index)
    forcing_out['prcp'] = forcing[_find_forcing_col(forcing, 'prcp')].values

    tmax = forcing[_find_forcing_col(forcing, 'tmax')].values
    tmin = forcing[_find_forcing_col(forcing, 'tmin')].values
    srad = forcing[_find_forcing_col(forcing, 'srad')].values
    dayl = forcing[_find_forcing_col(forcing, 'dayl')].values
    tmean = (tmax + tmin) / 2

    # PET method selection. Default 'oudin' for backward compat with
    # existing results (v1-v5 of HBV-lite, xaj_pdd repro_v01 broken-PET).
    # 'priestley_taylor' fixes audit-4 finding that Oudin still underestimates
    # PET 2-5x vs CAMELS published `pet_mean`.
    if pet_method == 'oudin':
        pet = _oudin_pet_mm(srad, dayl, tmean)
    elif pet_method == 'priestley_taylor':
        # Try to get Vp (Maurer 'Vp(Pa)', Daymet 'vp(Pa)') for humidity term
        try:
            vp_col = _find_forcing_col(forcing, 'vp')
            vp = forcing[vp_col].values
        except KeyError:
            vp = None
        pet = _priestley_taylor_pet_mm(srad, dayl, tmean, vp_pa=vp)
    else:
        raise ValueError(f"Unknown pet_method: {pet_method}")
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
