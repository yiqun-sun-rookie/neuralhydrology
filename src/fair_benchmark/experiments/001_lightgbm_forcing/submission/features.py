"""Shared, leakage-clean feature engineering for the 001 LightGBM challenger.

Pure functions over the ALLOWED inputs only (5 Maurer forcings + 27 statics).
This file lives inside submission/ and is scanned for forbidden data access, so
it deliberately contains NO reference to observed discharge / signatures. Both
train.py (train side) and predict.py (submission side) import it, guaranteeing
the train-time and predict-time feature spec are byte-for-byte identical.
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


def dynamic_feature_columns() -> list:
    """Ordered list of the engineered dynamic feature names."""
    cols = [f"prcp_logsum_{w}" for w in PRCP_SUM_WINDOWS]
    cols += [f"prcp_mean_{w}" for w in MET_WINDOWS]
    cols += ["tmin", "tmax", "tmean", "srad", "vp"]
    for w in MET_WINDOWS:
        cols += [f"tmean_mean_{w}", f"srad_mean_{w}", f"vp_mean_{w}"]
    cols += ["doy_sin", "doy_cos"]
    return cols


def feature_columns() -> list:
    """Full model feature order: engineered dynamic features then 27 statics."""
    return dynamic_feature_columns() + list(STATIC_COLS)


def basin_dynamic_features(df: pd.DataFrame) -> pd.DataFrame:
    """Engineer dynamic features for ONE basin.

    df must be sorted ascending by date and carry a 'date' column plus DYN_COLS.
    Rolling stats are trailing (current + past), min_periods=1, so the warmup
    year preceding the eval/target start fills the long windows without using
    any future information. Returns a frame indexed like df.
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
BUNDLE_DIR = _HERE.parents[3] / "frozen" / "bundle"  # submission/->001/->experiments/->fair_benchmark/
