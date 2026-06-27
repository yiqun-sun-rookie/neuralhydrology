"""Shared, leakage-clean feature engineering for the 002_b XGBoost challenger.

Pure functions over the ALLOWED inputs only (5 Maurer forcings + 27 statics).
This file lives inside submission/ and is scanned for forbidden data access, so
it deliberately contains NO reference to observed discharge / signatures. Both
train.py and predict.py import it, guaranteeing the train-time and predict-time
feature spec are byte-for-byte identical.

Beyond the 001 base feature set (trailing rolling precip/met stats + season),
002_b adds physically motivated CATCHMENT-MEMORY and SNOW features that a global
tree model otherwise cannot recover from fixed rolling windows:

  * exponential antecedent precipitation indices (API) at several decay rates
    -> continuous storage memory with different time constants;
  * a degree-day snowpack proxy (accumulation when cold, melt when warm) giving
    snow-water-equivalent (SWE), daily melt, and "liquid input" (rain + melt),
    plus trailing sums of liquid input -> the actual water reaching the soil;
  * a radiation-based PET proxy (Hargreaves-style, from Tmin/Tmax/SRAD) and a
    trailing climatic water-balance proxy (liquid_input - PET).

All recursions are causal (current + past only); the one-year warmup preceding
the eval/target start spins them up without using any future information.
"""
from pathlib import Path

import numpy as np
import pandas as pd

# The 5 Maurer dynamic columns (exact names in raw forcing + frozen bundle).
DYN_COLS = ["PRCP(mm/day)", "Tmin(C)", "Tmax(C)", "SRAD(W/m2)", "Vp(Pa)"]

# The 27 CAMELS static attributes (same set + order as build_allowed_bundle.py).
STATIC_COLS = [
    "p_mean", "pet_mean", "aridity", "p_seasonality", "frac_snow",
    "high_prec_freq", "high_prec_dur", "low_prec_freq", "low_prec_dur",
    "elev_mean", "slope_mean", "area_gages2", "frac_forest", "lai_max",
    "lai_diff", "gvf_max", "gvf_diff", "soil_depth_pelletier",
    "soil_depth_statsgo", "soil_porosity", "soil_conductivity",
    "max_water_content", "sand_frac", "silt_frac", "clay_frac",
    "carbonate_rocks_frac", "geol_permeability",
]

# Trailing rolling windows (days). Trailing only -> no future leakage.
PRCP_SUM_WINDOWS = [1, 3, 7, 15, 30, 90, 180, 365]
MET_WINDOWS = [7, 30]

# --- 002_b additions ---
# Exponential API decay factors (per-day retention); time constants ~ 1/(1-k).
API_DECAYS = [0.85, 0.93, 0.97, 0.99]
# Degree-day snow proxy parameters (fixed, global; statics still individualize).
SNOW_TMELT = 0.0       # deg C threshold for snow vs rain / melt onset
SNOW_DDF = 3.0         # mm SWE melted per +1 deg C above threshold per day
LIQUID_SUM_WINDOWS = [7, 30]
CWB_WINDOWS = [30, 90]  # climatic water-balance (liquid - PET) trailing means


def dynamic_feature_columns() -> list:
    """Ordered list of the engineered dynamic feature names."""
    cols = [f"prcp_logsum_{w}" for w in PRCP_SUM_WINDOWS]
    cols += [f"prcp_mean_{w}" for w in MET_WINDOWS]
    cols += ["tmin", "tmax", "tmean", "srad", "vp"]
    for w in MET_WINDOWS:
        cols += [f"tmean_mean_{w}", f"srad_mean_{w}", f"vp_mean_{w}"]
    cols += ["doy_sin", "doy_cos"]
    # --- 002_b additions ---
    cols += [f"api_{int(k * 100)}" for k in API_DECAYS]
    cols += ["swe", "snowmelt", "liquid_input", "snowfall"]
    cols += [f"liquid_logsum_{w}" for w in LIQUID_SUM_WINDOWS]
    cols += ["pet"]
    cols += [f"cwb_mean_{w}" for w in CWB_WINDOWS]
    return cols


def feature_columns() -> list:
    """Full model feature order: engineered dynamic features then 27 statics."""
    return dynamic_feature_columns() + list(STATIC_COLS)


def _exp_api(p: np.ndarray, k: float) -> np.ndarray:
    """Causal exponential antecedent precip index: a_t = k*a_{t-1} + p_t."""
    out = np.empty_like(p, dtype=np.float64)
    acc = 0.0
    for i in range(p.shape[0]):
        acc = k * acc + p[i]
        out[i] = acc
    return out


def _degree_day_snow(p: np.ndarray, tmean: np.ndarray):
    """Causal degree-day snowpack proxy.

    Cold days (tmean <= SNOW_TMELT): precip falls as snow, accumulates in SWE.
    Warm days: potential melt = SNOW_DDF * (tmean - SNOW_TMELT), capped by SWE.
    Returns (swe, snowmelt, snowfall, liquid_input) arrays where liquid_input is
    rain + melt (the water that actually reaches the soil that day).
    """
    n = p.shape[0]
    swe = np.empty(n, dtype=np.float64)
    melt = np.empty(n, dtype=np.float64)
    snowfall = np.empty(n, dtype=np.float64)
    liquid = np.empty(n, dtype=np.float64)
    store = 0.0
    for i in range(n):
        if tmean[i] <= SNOW_TMELT:
            sf = p[i]
            rain = 0.0
        else:
            sf = 0.0
            rain = p[i]
        store += sf
        if tmean[i] > SNOW_TMELT and store > 0.0:
            m = SNOW_DDF * (tmean[i] - SNOW_TMELT)
            m = m if m < store else store
        else:
            m = 0.0
        store -= m
        swe[i] = store
        melt[i] = m
        snowfall[i] = sf
        liquid[i] = rain + m
    return swe, melt, snowfall, liquid


def _hargreaves_pet(tmin: np.ndarray, tmax: np.ndarray, srad: np.ndarray) -> np.ndarray:
    """Radiation-based PET proxy (mm/day) from Tmin/Tmax/SRAD.

    Hargreaves-style: PET = 0.0023 * Ra_eq * (Tmean + 17.8) * sqrt(Tmax - Tmin),
    with extraterrestrial radiation Ra approximated by the measured SRAD
    (W/m2 -> MJ/m2/day via *0.0864, then -> mm/day equivalent via /2.45).
    Clipped at 0. Uses only allowed forcings.
    """
    tmean = 0.5 * (tmin + tmax)
    trange = np.clip(tmax - tmin, 0.0, None)
    ra_mm = srad * 0.0864 / 2.45  # W/m2 -> MJ/m2/day -> mm/day water equivalent
    pet = 0.0023 * ra_mm * (tmean + 17.8) * np.sqrt(trange)
    return np.clip(pet, 0.0, None)


def basin_dynamic_features(df: pd.DataFrame) -> pd.DataFrame:
    """Engineer dynamic features for ONE basin.

    df must be sorted ascending by date and carry a 'date' column plus DYN_COLS.
    Rolling stats are trailing (current + past), min_periods=1; the recursive
    API / snowpack / water-balance terms are causal. The warmup year preceding
    the eval/target start spins everything up without future information.
    """
    df = df.sort_values("date")
    p = df["PRCP(mm/day)"]
    tmean = 0.5 * (df["Tmin(C)"] + df["Tmax(C)"])

    out = pd.DataFrame(index=df.index)
    for w in PRCP_SUM_WINDOWS:
        out[f"prcp_logsum_{w}"] = np.log1p(p.rolling(w, min_periods=1).sum())
    for w in MET_WINDOWS:
        out[f"prcp_mean_{w}"] = p.rolling(w, min_periods=1).mean()

    out["tmin"] = df["Tmin(C)"]
    out["tmax"] = df["Tmax(C)"]
    out["tmean"] = tmean
    out["srad"] = df["SRAD(W/m2)"]
    out["vp"] = df["Vp(Pa)"]
    for w in MET_WINDOWS:
        out[f"tmean_mean_{w}"] = tmean.rolling(w, min_periods=1).mean()
        out[f"srad_mean_{w}"] = df["SRAD(W/m2)"].rolling(w, min_periods=1).mean()
        out[f"vp_mean_{w}"] = df["Vp(Pa)"].rolling(w, min_periods=1).mean()

    doy = df["date"].dt.dayofyear.to_numpy()
    out["doy_sin"] = np.sin(2.0 * np.pi * doy / 365.25)
    out["doy_cos"] = np.cos(2.0 * np.pi * doy / 365.25)

    # --- 002_b additions: catchment memory + snow + water balance ---
    p_arr = p.to_numpy(dtype=np.float64)
    tmean_arr = tmean.to_numpy(dtype=np.float64)
    for k in API_DECAYS:
        out[f"api_{int(k * 100)}"] = _exp_api(p_arr, k)

    swe, melt, snowfall, liquid = _degree_day_snow(p_arr, tmean_arr)
    out["swe"] = swe
    out["snowmelt"] = melt
    out["liquid_input"] = liquid
    out["snowfall"] = snowfall
    liquid_s = pd.Series(liquid, index=df.index)
    for w in LIQUID_SUM_WINDOWS:
        out[f"liquid_logsum_{w}"] = np.log1p(liquid_s.rolling(w, min_periods=1).sum())

    pet = _hargreaves_pet(df["Tmin(C)"].to_numpy(dtype=np.float64),
                          df["Tmax(C)"].to_numpy(dtype=np.float64),
                          df["SRAD(W/m2)"].to_numpy(dtype=np.float64))
    out["pet"] = pet
    cwb = pd.Series(liquid - pet, index=df.index)
    for w in CWB_WINDOWS:
        out[f"cwb_mean_{w}"] = cwb.rolling(w, min_periods=1).mean()
    return out


def build_basin_frame(forcing_df: pd.DataFrame, static_row: pd.Series) -> pd.DataFrame:
    """Full feature frame for ONE basin: dynamic features + broadcast statics.

    Returns a DataFrame with columns ['date'] + feature_columns(), preserving the
    (date-sorted) row order of forcing_df.
    """
    df = forcing_df.sort_values("date").reset_index(drop=True)
    dyn = basin_dynamic_features(df).reset_index(drop=True)
    frame = pd.DataFrame({"date": df["date"].to_numpy()})
    frame = pd.concat([frame, dyn], axis=1)
    for col in STATIC_COLS:
        frame[col] = float(static_row[col])
    return frame


def load_statics(path) -> pd.DataFrame:
    """Read the allowed statics table, basin index as zero-padded string."""
    s = pd.read_csv(path, dtype={"gauge_id": str})
    s["gauge_id"] = s["gauge_id"].str.zfill(8)
    return s.set_index("gauge_id")[STATIC_COLS]


_HERE = Path(__file__).resolve()
BUNDLE_DIR = _HERE.parents[3] / "frozen" / "bundle"  # submission/->002_b/->experiments/->fair_benchmark/
