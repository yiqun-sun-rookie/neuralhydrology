"""NOISE-G1: pre-run identifiability precheck for the noise-switch experiment.

Specification: docs/plans/2026-08-18-noise-switch-precheck-spec-v01.md
(frozen before computation; hash recorded in the results summary)

ZERO filter runs.  Method (proposed by the user): inject each noise candidate's
process perturbation into the OPEN-LOOP model, run a small ensemble, and measure
the resulting daily spread of simulated discharge.  Noise candidates share one
model and one parameter set, so they do not differ in predicted mean discharge --
they differ in predicted VARIANCE.  Discriminability is therefore a
variance-detection problem, and the analogue of the parFC footprint ratio is

    v[t]  = ensemble variance of simulated Q  +  sigma_obs**2
    KL[t] = 0.5 * ( ln(v_B/v_A) - 1 + v_A/v_B )        (zero-mean Gaussian)
    t_lik = ln(19) / mean(KL)                          (days to 19:1 odds)

which is the same ln(19)/evidence-rate form used by the frozen parFC precheck.

Usage:  python -X utf8 -m camels_switch_confirmation.noise_switch_precheck
"""

from __future__ import annotations

import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

for _variable in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
    os.environ.setdefault(_variable, "1")

import numpy as np
import pandas as pd

_SRC = Path(__file__).resolve().parents[1]
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from camels_switch_confirmation.g1_precheck import (  # noqa: E402
    LAG_KERNEL,
    PARAM_KEYS,
    SLZ_LOGNORMAL_SIGMA,
    STATE_NAMES,
    WINDOW_START,
    _window_end,
)
from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    PARAMETER_TABLE,
    RESULTS,
)
from camels_switch_confirmation.run_online_noise_real_obs import (  # noqa: E402
    design90_basins,
)

SPEC = "docs/plans/2026-08-18-noise-switch-precheck-spec-v01.md"
SPEC_SHA256 = "4b4d4266d1d24cb7a76b6f5c331fc5d117e2cd160bf01b1443bc1965a2c03d4a"
OUTPUT_ROOT = RESULTS / "noise_switch_precheck_v01"
G1_CSV = RESULTS / "g1_precheck_v01" / "g1_precheck.csv"

NOISE_CANDIDATES = (1.0, 0.1, 10.0)      # index 0 = calibrated reference scale
ROTATION = (0, 1, 2, 0, 2, 1, 0)         # 7 stages -> all 6 directed switches
STAGE_DAYS = 180
WINDOW_DAYS = STAGE_DAYS * len(ROTATION)
ENSEMBLE_SIZE = 40
SEED_ENTROPY = 20260818
T_LIK_MAX_DAYS = 90.0
MIN_ADMITTED = 10
FIXED_C = 0.0                            # soil-moisture rain coefficient held at 0
WORKERS = 10


def injection_sigma(multiplier: float) -> float:
    """Truth-injection lognormal sigma for a noise multiplier (moment match)."""
    if not np.isfinite(multiplier) or multiplier <= 0.0:
        raise ValueError("noise multiplier must be finite and positive")
    return SLZ_LOGNORMAL_SIGMA * float(np.sqrt(multiplier))


def directed_switch_pairs(rotation=ROTATION) -> list:
    """Ordered (from, to) candidate-index pairs realised by the rotation."""
    pairs = []
    for position in range(1, len(rotation)):
        pair = (rotation[position - 1], rotation[position])
        if pair not in pairs:
            pairs.append(pair)
    return pairs


def kl_variance_rate(variance_true: np.ndarray,
                     variance_rival: np.ndarray) -> float:
    """Mean per-day KL for zero-mean Gaussians differing only in variance."""
    true_values = np.asarray(variance_true, dtype=np.float64)
    rival_values = np.asarray(variance_rival, dtype=np.float64)
    if np.any(true_values <= 0.0) or np.any(rival_values <= 0.0):
        raise ValueError("variances must be strictly positive")
    ratio = true_values / rival_values
    per_day = 0.5 * (-np.log(ratio) - 1.0 + ratio)
    return float(np.mean(per_day))


def days_to_odds(kl_rate: float, odds: float = 19.0) -> float:
    """ln(odds) / evidence rate; infinite when the rate vanishes."""
    if kl_rate <= 0.0:
        return float("inf")
    return float(np.log(odds) / kl_rate)


def _ensemble_variance(rain, pet, temp, params, initial_state,
                       multiplier, basin_id, cell_index):
    """Daily variance of simulated discharge under one injected noise level."""
    from scl_hydro.hbv_lite_numpy import simulate_hbv_lite

    sigma = injection_sigma(multiplier)
    generator = np.random.default_rng(
        np.random.SeedSequence((SEED_ENTROPY, int(basin_id), int(cell_index)))
    )
    n_days = len(rain)
    states = [dict(initial_state) for _ in range(ENSEMBLE_SIZE)]
    discharge = np.empty((ENSEMBLE_SIZE, n_days), dtype=np.float64)
    for day in range(n_days):
        for member in range(ENSEMBLE_SIZE):
            simulated, state = simulate_hbv_lite(
                rain[day:day + 1], pet[day:day + 1], temp[day:day + 1],
                params, initial_state=states[member], lag_kernel=LAG_KERNEL,
            )
            state = dict(state)
            state["SLZ"] = state["SLZ"] * float(
                np.exp(generator.normal(-0.5 * sigma ** 2, sigma))
            )
            states[member] = state
            discharge[member, day] = float(simulated[0])
    return discharge.var(axis=0)


def _precheck_one(basin: str) -> dict:
    from hydroagent.data_loading import load_camels_basin

    table = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    row = table[table["basin_id"] == basin].iloc[0]
    params = {key: float(row[f"p_{key}"]) for key in PARAM_KEYS}
    initial_state = {name: float(row[f"state_{name}"]) for name in STATE_NAMES}

    g1 = pd.read_csv(G1_CSV, dtype={"basin_id": str})
    g1["basin_id"] = g1["basin_id"].str.zfill(8)
    sigma_obs = float(g1.set_index("basin_id").loc[basin, "sigma_obs"])

    forcing, _, _ = load_camels_basin(
        basin, data_root="data/camels_us", start_date=WINDOW_START,
        end_date=_window_end(), forcing="maurer", pet_method="oudin",
        keep_obs_nan_days=True,
    )
    rain = forcing["prcp"].values.astype(np.float64)
    pet_column = "ep" if "ep" in forcing.columns else "pet"
    pet = forcing[pet_column].values.astype(np.float64)
    temp = (forcing["tmean"].values.astype(np.float64)
            if "tmean" in forcing.columns else np.zeros_like(rain))

    variances = {}
    for index, multiplier in enumerate(NOISE_CANDIDATES):
        spread = _ensemble_variance(rain, pet, temp, params, initial_state,
                                    multiplier, basin, index)
        variances[index] = spread + sigma_obs ** 2

    record = {
        "basin_id": basin, "sigma_obs": sigma_obs,
        "ensemble_size": ENSEMBLE_SIZE, "fixed_c": FIXED_C,
    }
    for index, multiplier in enumerate(NOISE_CANDIDATES):
        record[f"mean_flow_var_m{multiplier:g}"] = float(
            (variances[index] - sigma_obs ** 2).mean()
        )
        record[f"var_ratio_to_obs_m{multiplier:g}"] = float(
            (variances[index] - sigma_obs ** 2).mean() / sigma_obs ** 2
        )
    t_liks = []
    for source, destination in directed_switch_pairs():
        rate = kl_variance_rate(variances[destination], variances[source])
        days = days_to_odds(rate)
        label = (f"m{NOISE_CANDIDATES[source]:g}_to_m"
                 f"{NOISE_CANDIDATES[destination]:g}")
        record[f"t_lik_{label}"] = days
        record[f"direction_{label}"] = (
            "up" if NOISE_CANDIDATES[destination] > NOISE_CANDIDATES[source]
            else "down"
        )
        t_liks.append(days)
    record["t_lik_max"] = float(max(t_liks))
    record["admitted"] = bool(record["t_lik_max"] <= T_LIK_MAX_DAYS)
    return record


def main() -> None:
    basins = design90_basins()
    with ProcessPoolExecutor(max_workers=WORKERS) as pool:
        records = list(pool.map(_precheck_one, basins, chunksize=2))
    frame = pd.DataFrame(records)
    out_dir = OUTPUT_ROOT
    out_dir.mkdir(parents=True, exist_ok=True)
    frame.to_csv(out_dir / "noise_precheck.csv", index=False)
    admitted = frame[frame["admitted"]]
    admitted.to_csv(out_dir / "admission.csv", index=False)

    direction_columns = [column for column in frame.columns
                         if column.startswith("t_lik_m")]
    summary = {
        "specification": SPEC,
        "specification_sha256": SPEC_SHA256,
        "candidates_m": list(NOISE_CANDIDATES),
        "fixed_c": FIXED_C,
        "rotation": list(ROTATION),
        "stage_days": STAGE_DAYS,
        "window_days": WINDOW_DAYS,
        "ensemble_size": ENSEMBLE_SIZE,
        "seed_entropy": SEED_ENTROPY,
        "t_lik_max_days_gate": T_LIK_MAX_DAYS,
        "n_basins": int(len(frame)),
        "n_admitted": int(len(admitted)),
        "stop_condition_min_admitted": MIN_ADMITTED,
        "stop_condition_triggered": bool(len(admitted) < MIN_ADMITTED),
        "median_var_ratio_to_obs": {
            f"m{multiplier:g}": float(
                frame[f"var_ratio_to_obs_m{multiplier:g}"].median()
            )
            for multiplier in NOISE_CANDIDATES
        },
        "median_t_lik_by_directed_pair": {
            column.replace("t_lik_", ""): (
                None if not np.isfinite(frame[column]).any()
                else float(frame.loc[np.isfinite(frame[column]), column].median())
            )
            for column in direction_columns
        },
        "n_infinite_by_directed_pair": {
            column.replace("t_lik_", ""):
                int((~np.isfinite(frame[column])).sum())
            for column in direction_columns
        },
    }
    (out_dir / "precheck_summary.json").write_text(
        json.dumps(summary, indent=1), encoding="utf-8"
    )
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
