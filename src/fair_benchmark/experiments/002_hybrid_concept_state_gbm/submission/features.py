"""Shared, leakage-clean feature engineering for 002_hybrid (concept-state GBM).

Pure functions over the ALLOWED inputs only (5 Maurer forcings + 27 statics)
PLUS calibrated conceptual-model STATE trajectories that are themselves a
deterministic, OBSERVATION-FREE function of the allowed forcings + per-basin
GR4J-PDD parameters calibrated on the TRAIN period (legal). This file lives in
submission/ and is scanned for forbidden data access, so it contains NO
reference to observed discharge / hydro signatures: the conceptual states are
read at predict time from ../../model/concept_states.parquet (built by train.py
from forcings only) and merged in by (basin, date).

Feature blocks
--------------
1. 002_b base block (unchanged): trailing rolling precip/met stats + season +
   exponential antecedent-precip memory (API) + degree-day snow proxy +
   radiation PET / climatic water-balance.
2. NEW concept-state block: the calibrated GR4J-PDD model's INTERNAL coupled
   storages -- production/soil store S, routing store R, snow store SWE -- and
   its simulated discharge qsim_concept (+ log1p). These are adaptive nonlinear
   catchment-memory variables that fixed rolling windows cannot encode.

All base recursions are causal (current + past only); the one-year warmup
preceding the eval/target start spins them up without future information. The
conceptual states are likewise produced by a forward sim from a warmup-year
init, so they carry no future leakage.
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
API_DECAYS = [0.85, 0.93, 0.97, 0.99]
SNOW_TMELT = 0.0       # deg C threshold for snow vs rain / melt onset
SNOW_DDF = 3.0         # mm SWE melted per +1 deg C above threshold per day
LIQUID_SUM_WINDOWS = [7, 30]
CWB_WINDOWS = [30, 90]  # climatic water-balance (liquid - PET) trailing means

# --- 002_hybrid addition: calibrated conceptual-model state features ---
# Columns supplied (per basin, per date) by ../../model/concept_states.parquet.
CONCEPT_STATE_COLS = [
    "concept_S",          # GR4J production / soil-moisture store (mm)
    "concept_R",          # GR4J routing store (mm)
    "concept_swe",        # PDD snow store / snow-water-equivalent (mm)
    "concept_qsim",       # conceptual simulated discharge (mm/day)
    "concept_qsim_log",   # log1p(concept_qsim)
]


def dynamic_feature_columns() -> list:
    """Ordered list of the engineered dynamic feature names (002_b base block)."""
    cols = [f"prcp_logsum_{w}" for w in PRCP_SUM_WINDOWS]
    cols += [f"prcp_mean_{w}" for w in MET_WINDOWS]
    cols += ["tmin", "tmax", "tmean", "srad", "vp"]
    for w in MET_WINDOWS:
        cols += [f"tmean_mean_{w}", f"srad_mean_{w}", f"vp_mean_{w}"]
    cols += ["doy_sin", "doy_cos"]
    cols += [f"api_{int(k * 100)}" for k in API_DECAYS]
    cols += ["swe", "snowmelt", "liquid_input", "snowfall"]
    cols += [f"liquid_logsum_{w}" for w in LIQUID_SUM_WINDOWS]
    cols += ["pet"]
    cols += [f"cwb_mean_{w}" for w in CWB_WINDOWS]
    return cols


def feature_columns() -> list:
    """Full model feature order: base dynamic + concept states + 27 statics."""
    return dynamic_feature_columns() + list(CONCEPT_STATE_COLS) + list(STATIC_COLS)


def _exp_api(p: np.ndarray, k: float) -> np.ndarray:
    """Causal exponential antecedent precip index: a_t = k*a_{t-1} + p_t."""
    out = np.empty_like(p, dtype=np.float64)
    acc = 0.0
    for i in range(p.shape[0]):
        acc = k * acc + p[i]
        out[i] = acc
    return out


def _degree_day_snow(p: np.ndarray, tmean: np.ndarray):
    """Causal degree-day snowpack proxy. Returns (swe, melt, snowfall, liquid)."""
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
    """Radiation-based PET proxy (mm/day) from Tmin/Tmax/SRAD (allowed forcings)."""
    tmean = 0.5 * (tmin + tmax)
    trange = np.clip(tmax - tmin, 0.0, None)
    ra_mm = srad * 0.0864 / 2.45  # W/m2 -> MJ/m2/day -> mm/day water equivalent
    pet = 0.0023 * ra_mm * (tmean + 17.8) * np.sqrt(trange)
    return np.clip(pet, 0.0, None)


def basin_dynamic_features(df: pd.DataFrame) -> pd.DataFrame:
    """Engineer the 002_b base dynamic features for ONE basin."""
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


def build_forcing_frame(forcing_df: pd.DataFrame, static_row: pd.Series) -> pd.DataFrame:
    """Base feature frame for ONE basin: 002_b dynamic features + broadcast statics.

    Returns columns ['date'] + dynamic_feature_columns() + STATIC_COLS (NOT yet
    the concept-state columns -- those are merged in by attach_concept_states).
    """
    df = forcing_df.sort_values("date").reset_index(drop=True)
    dyn = basin_dynamic_features(df).reset_index(drop=True)
    frame = pd.DataFrame({"date": df["date"].to_numpy()})
    frame = pd.concat([frame, dyn], axis=1)
    for col in STATIC_COLS:
        frame[col] = float(static_row[col])
    return frame


def attach_concept_states(frame: pd.DataFrame, concept_df: pd.DataFrame) -> pd.DataFrame:
    """Left-merge the per-date conceptual-state columns onto a forcing frame.

    `concept_df` must carry a 'date' column plus CONCEPT_STATE_COLS. The merge is
    on 'date' (both already restricted to a single basin). Any unmatched rows get
    NaN concept states (the tree model tolerates NaN); in practice every eval/
    train row has a matching simulated state.
    """
    frame = frame.copy()
    frame["date"] = pd.to_datetime(frame["date"])
    c = concept_df.copy()
    c["date"] = pd.to_datetime(c["date"])
    c = c[["date"] + list(CONCEPT_STATE_COLS)]
    return frame.merge(c, on="date", how="left")


def load_statics(path) -> pd.DataFrame:
    """Read the allowed statics table, basin index as zero-padded string."""
    s = pd.read_csv(path, dtype={"gauge_id": str})
    s["gauge_id"] = s["gauge_id"].str.zfill(8)
    return s.set_index("gauge_id")[STATIC_COLS]


_HERE = Path(__file__).resolve()
BUNDLE_DIR = _HERE.parents[3] / "frozen" / "bundle"  # submission/->exp/->experiments/->fair_benchmark/
