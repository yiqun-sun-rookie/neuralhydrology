"""Shared, leakage-clean feature engineering for the 003 Echo-State + GBM challenger.

Pure functions over the ALLOWED inputs only (5 Maurer forcings + 27 statics).
This file lives inside submission/ and is scanned for forbidden data access, so
it deliberately contains NO reference to observed discharge / signatures.

The centerpiece is a GLOBAL FROZEN Echo-State reservoir: a single random
recurrent network (identical for every basin), whose weights are generated once
on the train side and saved to ../../model/reservoir.npz. Running it over a
basin's forcing produces a high-dimensional recurrent-memory STATE trajectory.
The reservoir is a deterministic, observation-free function of the allowed
forcings, so reading its states at predict time introduces no answer leakage.
A gradient-boosted tree (LightGBM) is the readout on [states + current inputs +
statics]. Both train.py and predict.py import this file so the reservoir math
and feature spec are byte-for-byte identical on both sides.
"""
from pathlib import Path

import numpy as np
import pandas as pd

try:
    from numba import njit
    _HAS_NUMBA = True
except Exception:  # pragma: no cover
    _HAS_NUMBA = False

    def njit(*a, **k):
        def wrap(f):
            return f
        return wrap

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

# The reservoir input channels, in order. The first N_NORM are standardized with
# saved train-side stats; the trailing cyclic day-of-year channels are already
# bounded in [-1, 1] and pass through unnormalized.
INPUT_COLS = ["in_prcp_log", "in_tmin", "in_tmax", "in_srad", "in_vp_log",
              "in_doy_sin", "in_doy_cos"]
N_NORM = 5  # number of leading input channels that get standardized

# Reservoir hyperparameters (defaults; the authoritative values live in the
# saved reservoir.npz / features.json so train and predict stay identical).
RESERVOIR_DEFAULTS = {
    "n_units": 160,
    "seed": 0,
    "spectral_radius": 0.9,
    "input_scaling": 1.0,
    "bias_scaling": 0.1,
    "density": 0.1,            # fraction of nonzero reservoir weights
    "leak_min": 0.02,         # per-unit leak rates sampled log-uniform in
    "leak_max": 1.0,          #   [leak_min, leak_max] -> multi-timescale memory
}


def reservoir_state_columns(n_units: int) -> list:
    return [f"res_{i}" for i in range(n_units)]


def feature_columns(n_units: int) -> list:
    """Full readout feature order: reservoir states, current inputs, statics."""
    return reservoir_state_columns(n_units) + list(INPUT_COLS) + list(STATIC_COLS)


# --------------------------------------------------------------------------- #
# Input construction                                                           #
# --------------------------------------------------------------------------- #
def build_input_matrix(forcing_df: pd.DataFrame) -> tuple:
    """Build the (T, len(INPUT_COLS)) raw (pre-normalization) reservoir input.

    forcing_df must carry a 'date' column plus DYN_COLS, sorted ascending.
    Returns (dates ndarray, U raw float64 ndarray, columns list).
    """
    df = forcing_df.sort_values("date").reset_index(drop=True)
    p = df["PRCP(mm/day)"].to_numpy(dtype=np.float64)
    tmin = df["Tmin(C)"].to_numpy(dtype=np.float64)
    tmax = df["Tmax(C)"].to_numpy(dtype=np.float64)
    srad = df["SRAD(W/m2)"].to_numpy(dtype=np.float64)
    vp = df["Vp(Pa)"].to_numpy(dtype=np.float64)
    doy = pd.to_datetime(df["date"]).dt.dayofyear.to_numpy()

    U = np.empty((len(df), len(INPUT_COLS)), dtype=np.float64)
    U[:, 0] = np.log1p(np.clip(p, 0.0, None))
    U[:, 1] = tmin
    U[:, 2] = tmax
    U[:, 3] = srad
    U[:, 4] = np.log1p(np.clip(vp, 0.0, None))
    U[:, 5] = np.sin(2.0 * np.pi * doy / 365.25)
    U[:, 6] = np.cos(2.0 * np.pi * doy / 365.25)
    return df["date"].to_numpy(), U, list(INPUT_COLS)


def normalize_inputs(U: np.ndarray, mean: np.ndarray, std: np.ndarray) -> np.ndarray:
    """Standardize the leading N_NORM channels; leave cyclic channels untouched."""
    Un = U.copy()
    safe_std = np.where(std > 1e-8, std, 1.0)
    Un[:, :N_NORM] = (U[:, :N_NORM] - mean[:N_NORM]) / safe_std[:N_NORM]
    return Un


# --------------------------------------------------------------------------- #
# Frozen reservoir construction + simulation                                   #
# --------------------------------------------------------------------------- #
def build_reservoir(n_inputs: int, params: dict) -> dict:
    """Generate the frozen reservoir weights (dense W_in, sparse W, bias, leaks).

    Deterministic given params['seed']. Spectral radius of W is rescaled to the
    target. Returned dict is what gets saved to reservoir.npz.
    """
    p = dict(RESERVOIR_DEFAULTS)
    p.update(params or {})
    n = int(p["n_units"])
    rng = np.random.default_rng(int(p["seed"]))

    # Dense input weights, scaled.
    w_in = rng.uniform(-1.0, 1.0, size=(n, n_inputs)) * float(p["input_scaling"])

    # Sparse reservoir matrix, then rescale to target spectral radius.
    w = rng.uniform(-1.0, 1.0, size=(n, n))
    density = float(p["density"])
    mask = rng.random(size=(n, n)) < density
    w = w * mask
    eig = np.linalg.eigvals(w)
    rho = float(np.max(np.abs(eig)))
    if rho > 1e-8:
        w = w * (float(p["spectral_radius"]) / rho)

    bias = rng.uniform(-1.0, 1.0, size=n) * float(p["bias_scaling"])

    # Per-unit leak rates: log-uniform in [leak_min, leak_max] -> mixed memory
    # timescales (fast storm response + slow baseflow recession in one reservoir).
    lo, hi = np.log(float(p["leak_min"])), np.log(float(p["leak_max"]))
    leak = np.exp(rng.uniform(lo, hi, size=n))

    return {
        "w_in": w_in.astype(np.float64),
        "w": w.astype(np.float64),
        "bias": bias.astype(np.float64),
        "leak": leak.astype(np.float64),
        "params": p,
    }


@njit(cache=True, fastmath=True)
def _run_reservoir_core(U, w_in, w, bias, leak):
    T = U.shape[0]
    n = w.shape[0]
    X = np.zeros((T, n))
    x = np.zeros(n)
    for t in range(T):
        u = U[t]
        pre = w_in @ u + w @ x + bias
        a = np.tanh(pre)
        x = (1.0 - leak) * x + leak * a
        X[t] = x
    return X


def run_reservoir(U_norm: np.ndarray, res: dict) -> np.ndarray:
    """Run the frozen reservoir over a single basin's normalized inputs.

    U_norm: (T, n_inputs). Returns states X: (T, n_units). State starts at 0;
    callers must include a warmup span so the zero-init transient decays before
    the target/eval window (mirrors the warmup-year idiom of the 001 baseline).
    """
    return _run_reservoir_core(
        np.ascontiguousarray(U_norm, dtype=np.float64),
        np.ascontiguousarray(res["w_in"], dtype=np.float64),
        np.ascontiguousarray(res["w"], dtype=np.float64),
        np.ascontiguousarray(res["bias"], dtype=np.float64),
        np.ascontiguousarray(res["leak"], dtype=np.float64),
    )


def build_basin_frame(forcing_df: pd.DataFrame, static_row: pd.Series,
                      res: dict, mean: np.ndarray, std: np.ndarray) -> pd.DataFrame:
    """Full readout feature frame for ONE basin: states + current inputs + statics.

    Returns a DataFrame with columns ['date'] + feature_columns(n_units),
    preserving the (date-sorted) row order of forcing_df.
    """
    dates, U, _ = build_input_matrix(forcing_df)
    U_norm = normalize_inputs(U, mean, std)
    X = run_reservoir(U_norm, res)

    n_units = X.shape[1]
    state_cols = reservoir_state_columns(n_units)
    blocks = {"date": dates}
    state_df = pd.DataFrame(X.astype(np.float32), columns=state_cols)
    input_df = pd.DataFrame(U_norm.astype(np.float32), columns=list(INPUT_COLS))
    static_vals = np.array([float(static_row[c]) for c in STATIC_COLS], dtype=np.float32)
    static_df = pd.DataFrame(np.tile(static_vals, (len(dates), 1)), columns=list(STATIC_COLS))
    frame = pd.concat([pd.DataFrame(blocks), state_df, input_df, static_df], axis=1)
    return frame


def load_statics(path) -> pd.DataFrame:
    """Read the allowed statics table, basin index as zero-padded string."""
    s = pd.read_csv(path, dtype={"gauge_id": str})
    s["gauge_id"] = s["gauge_id"].str.zfill(8)
    return s.set_index("gauge_id")[STATIC_COLS]


def load_reservoir(npz_path) -> dict:
    """Reload the frozen reservoir saved by train.py."""
    d = np.load(npz_path, allow_pickle=True)
    return {
        "w_in": d["w_in"], "w": d["w"], "bias": d["bias"], "leak": d["leak"],
        "params": d["params"].item() if "params" in d else {},
    }


_HERE = Path(__file__).resolve()
BUNDLE_DIR = _HERE.parents[3] / "frozen" / "bundle"  # submission/->003/->experiments/->fair_benchmark/
