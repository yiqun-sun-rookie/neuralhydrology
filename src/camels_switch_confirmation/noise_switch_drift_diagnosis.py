"""NOISE-W2: what actually drives the SLZ drift inside the noise-switch window.

Diagnostic only -- ZERO filter runs, ZERO preregistered claims.  The handoff
(2026-08-18/19) recorded the drift as "the model relaxing from the calibration
end state towards the basin's natural level", with noisy and noise-free
trajectories nearly coinciding.  This probe separates the two candidate causes
by running, for every admitted basin, the SAME window three ways:

  1. noise-free open loop from the stored calibration state (initial-condition
     relaxation only);
  2. the spec-exact noisy truth trajectory (7 stages, rotation 0,1,2,0,2,1,0,
     SLZ *= exp(N(-s^2/2, s)), s = 0.02*sqrt(m)) for two seeds;
  3. the theoretical median of a pure multiplicative walk, exp(-sum s^2/2),
     which is what a mean-preserving lognormal injection does to a SINGLE
     realisation when the store has no restoring force.

It also reports the lower-zone recession parK2 and its e-folding time, because
a store whose e-folding time exceeds the window cannot relax to anything inside
the window and cannot damp an injected walk.

Usage:  python -X utf8 -m camels_switch_confirmation.noise_switch_drift_diagnosis
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
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
    STATE_NAMES,
    WINDOW_START,
    _window_end,
)
from camels_switch_confirmation.noise_switch_precheck import (  # noqa: E402
    NOISE_CANDIDATES,
    OUTPUT_ROOT as PRECHECK_ROOT,
    ROTATION,
    SEED_ENTROPY,
    STAGE_DAYS,
    WINDOW_DAYS,
    injection_sigma,
)
from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    PARAMETER_TABLE,
    RESULTS,
)

OUTPUT_ROOT = RESULTS / "noise_switch_drift_diagnosis_v01"
ADMISSION_CSV = PRECHECK_ROOT / "admission.csv"
DATA_ROOT = "data/camels_us"
SEEDS = (0, 1)
WORKERS = 10


def theoretical_log_drift(rotation=ROTATION, stage_days=STAGE_DAYS) -> float:
    """Median log-drift of a pure multiplicative walk over the full rotation."""
    total = 0.0
    for index in rotation:
        sigma = injection_sigma(NOISE_CANDIDATES[index])
        total += stage_days * 0.5 * sigma ** 2
    return -total


def _trace_noise_free(rain, pet, temp, params, state, n_days):
    from scl_hydro.hbv_lite_numpy import simulate_hbv_lite
    trace = np.empty(n_days, dtype=np.float64)
    current = dict(state)
    for day in range(n_days):
        _, current = simulate_hbv_lite(
            rain[day:day + 1], pet[day:day + 1], temp[day:day + 1],
            params, initial_state=current, lag_kernel=LAG_KERNEL)
        trace[day] = current["SLZ"]
    return trace


def _trace_noisy(rain, pet, temp, params, state, basin_id, seed):
    from scl_hydro.hbv_lite_numpy import simulate_hbv_lite
    generator = np.random.default_rng(
        np.random.SeedSequence((SEED_ENTROPY, int(basin_id), int(seed))))
    trace = np.empty(WINDOW_DAYS, dtype=np.float64)
    current = dict(state)
    day = 0
    for stage_index in ROTATION:
        sigma = injection_sigma(NOISE_CANDIDATES[stage_index])
        for _ in range(STAGE_DAYS):
            _, current = simulate_hbv_lite(
                rain[day:day + 1], pet[day:day + 1], temp[day:day + 1],
                params, initial_state=current, lag_kernel=LAG_KERNEL)
            current["SLZ"] = current["SLZ"] * np.exp(
                generator.normal(-0.5 * sigma ** 2, sigma))
            trace[day] = current["SLZ"]
            day += 1
    return trace


def _stage_means(trace):
    return np.array([trace[i * STAGE_DAYS:(i + 1) * STAGE_DAYS].mean()
                     for i in range(len(ROTATION))], dtype=np.float64)


def _run_basin(args_tuple):
    basin_id, row = args_tuple
    import sys as _sys
    if str(_SRC) not in _sys.path:
        _sys.path.insert(0, str(_SRC))
    from hydroagent.data_loading import load_camels_basin

    started = time.time()
    try:
        params = {k: float(row[f"p_{k}"]) for k in PARAM_KEYS}
        stored_state = {s: float(row[f"state_{s}"]) for s in STATE_NAMES}

        forcing, _obs, _area = load_camels_basin(
            basin_id, data_root=DATA_ROOT,
            start_date=WINDOW_START, end_date=_window_end(),
            forcing="maurer", pet_method="oudin", keep_obs_nan_days=True,
        )
        rain = forcing["prcp"].values.astype(np.float64)
        pet_col = "ep" if "ep" in forcing.columns else "pet"
        pet = forcing[pet_col].values.astype(np.float64)
        temp = (forcing["tmean"].values.astype(np.float64)
                if "tmean" in forcing.columns else np.zeros_like(rain))
        if len(rain) < WINDOW_DAYS:
            raise ValueError(f"forcing covers {len(rain)} < {WINDOW_DAYS} days")

        clean = _trace_noise_free(rain, pet, temp, params, stored_state, WINDOW_DAYS)
        clean_stages = _stage_means(clean)
        record = {
            "basin_id": basin_id,
            "park2": params["parK2"],
            "k2_efolding_days": (float(1.0 / params["parK2"])
                                 if params["parK2"] > 0 else float("inf")),
            "slz_stored": float(stored_state["SLZ"]),
            "clean_first": float(clean[0]),
            "clean_last": float(clean[-1]),
            "clean_end_over_start": float(clean[-1] / clean[0]),
            "clean_stage_span_ratio": float(clean_stages.max() / clean_stages.min()),
        }

        theoretical = float(np.exp(theoretical_log_drift()))
        record["theoretical_walk_factor"] = theoretical
        for seed in SEEDS:
            noisy = _trace_noisy(rain, pet, temp, params, stored_state, basin_id, seed)
            stages = _stage_means(noisy)
            record[f"noisy_s{seed}_end_over_start"] = float(noisy[-1] / noisy[0])
            record[f"noisy_s{seed}_stage_span_ratio"] = float(stages.max() / stages.min())
            record[f"noisy_s{seed}_over_clean_end"] = float(noisy[-1] / clean[-1])
            record[f"noisy_s{seed}_max_over_min"] = float(noisy.max() / noisy.min())
            record[f"noisy_s{seed}_median_abs_rel_gap"] = float(
                np.median(np.abs(noisy - clean) / np.maximum(clean, 1e-12)))
        record["run_status"] = "success"
        record["error_message"] = ""
        record["_elapsed_s"] = round(time.time() - started, 2)
        return record
    except Exception as exception:  # noqa: BLE001 - recorded, never fatal
        return {"basin_id": basin_id, "run_status": "failed",
                "error_message": f"{type(exception).__name__}: {exception}",
                "_elapsed_s": round(time.time() - started, 2)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--basins", nargs="*", default=None)
    parser.add_argument("--workers", type=int, default=WORKERS)
    parser.add_argument("--output-root", default=str(OUTPUT_ROOT))
    arguments = parser.parse_args()

    admitted = pd.read_csv(ADMISSION_CSV, dtype={"basin_id": str})
    admitted["basin_id"] = admitted["basin_id"].str.zfill(8)
    basins = [b.zfill(8) for b in (arguments.basins or admitted["basin_id"].tolist())]

    table = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    work = [(b, table[table["basin_id"] == b].iloc[0]) for b in basins]

    print(f"[drift-diagnosis] basins={len(basins)} seeds={SEEDS} "
          f"theoretical_walk_factor={np.exp(theoretical_log_drift()):.4f}")
    if arguments.workers > 1 and len(work) > 1:
        with ProcessPoolExecutor(max_workers=arguments.workers) as pool:
            results = list(pool.map(_run_basin, work))
    else:
        results = [_run_basin(item) for item in work]

    frame = pd.DataFrame(results)
    output_root = Path(arguments.output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    frame.to_csv(output_root / "drift_diagnosis.csv", index=False)

    ok = frame[frame["run_status"] == "success"]
    summary = {
        "basins_requested": len(basins),
        "basins_success": int(len(ok)),
        "seeds": list(SEEDS),
        "theoretical_walk_factor": float(np.exp(theoretical_log_drift())),
        "k2_efolding_days_median": float(ok["k2_efolding_days"].median()),
        "k2_at_or_below_1e-4_count": int((ok["park2"] <= 1.0001e-4).sum()),
        "k2_efolding_exceeds_window_count": int((ok["k2_efolding_days"] > WINDOW_DAYS).sum()),
        "clean_end_over_start_median": float(ok["clean_end_over_start"].median()),
        "clean_end_over_start_min": float(ok["clean_end_over_start"].min()),
        "clean_end_over_start_max": float(ok["clean_end_over_start"].max()),
        "clean_stage_span_ratio_median": float(ok["clean_stage_span_ratio"].median()),
        "failures": frame[frame["run_status"] != "success"]["basin_id"].tolist(),
    }
    for seed in SEEDS:
        summary[f"noisy_s{seed}"] = {
            "end_over_start_median": float(ok[f"noisy_s{seed}_end_over_start"].median()),
            "stage_span_ratio_median": float(ok[f"noisy_s{seed}_stage_span_ratio"].median()),
            "stage_span_ratio_p90": float(ok[f"noisy_s{seed}_stage_span_ratio"].quantile(0.9)),
            "noisy_over_clean_end_median": float(ok[f"noisy_s{seed}_over_clean_end"].median()),
            "max_over_min_median": float(ok[f"noisy_s{seed}_max_over_min"].median()),
            "median_abs_rel_gap_median": float(
                ok[f"noisy_s{seed}_median_abs_rel_gap"].median()),
        }
    with open(output_root / "drift_summary.json", "w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, ensure_ascii=False)
    print(json.dumps(summary, indent=2))
    print(f"[drift-diagnosis] wrote {output_root}")


if __name__ == "__main__":
    main()
