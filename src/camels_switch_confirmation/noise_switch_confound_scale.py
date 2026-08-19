"""NOISE-W3: how big is the storage-drift confound, in the units the experiment
actually uses.

Diagnostic only -- ZERO filter runs, ZERO preregistered claims.  The noise-switch
design separates candidates by the VARIANCE of simulated discharge: candidates are
spaced x10 in the noise multiplier m, so the discriminating signal is a x10 change
in flow ensemble variance.  The confound is that the injection is multiplicative in
SLZ, so the same m produces a different absolute spread when the store sits at a
different level -- and SLZ wanders inside the window.

This probe holds the noise level CONSTANT at m=1 for the whole 1260-day window and
measures how much the flow ensemble variance moves anyway, per 180-day stage.  The
result is directly comparable to the x10 spacing the experiment relies on:

    confound_ratio = max(stage variance) / min(stage variance)   at fixed m
    signal_ratio   = 10                                          by design

If confound_ratio approaches signal_ratio, a stage boundary can be read as a noise
switch when nothing switched.

Usage:  python -X utf8 -m camels_switch_confirmation.noise_switch_confound_scale
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
    PARAM_KEYS,
    STATE_NAMES,
    WINDOW_START,
    _window_end,
)
from camels_switch_confirmation.noise_switch_precheck import (  # noqa: E402
    G1_CSV,
    OUTPUT_ROOT as PRECHECK_ROOT,
    ROTATION,
    STAGE_DAYS,
    WINDOW_DAYS,
    _ensemble_variance,
)
from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    PARAMETER_TABLE,
    RESULTS,
)

OUTPUT_ROOT = RESULTS / "noise_switch_confound_scale_v01"
ADMISSION_CSV = PRECHECK_ROOT / "admission.csv"
DATA_ROOT = "data/camels_us"
FIXED_MULTIPLIER = 1.0
CELL_INDEX = 0          # same seed stream the precheck used for the m=1 cell
SIGNAL_RATIO = 10.0     # candidate spacing by design
WORKERS = 10

# Injection variants compared here.  "slz_mult" is the frozen precheck design.
# "slz_abs" is handoff option 2 (absolute instead of proportional amplitude).
# "suz_mult" keeps the multiplicative form but moves the injection to the upper
# zone, whose recession (parK1) is short compared with a 180-day stage.
VARIANTS = ("slz_mult", "slz_abs", "suz_mult")


def _variant_variance(rain, pet, temp, params, initial_state, multiplier,
                      basin_id, cell_index, variant):
    """Daily flow-ensemble variance under one injection variant."""
    from scl_hydro.hbv_lite_numpy import simulate_hbv_lite
    from camels_switch_confirmation.noise_switch_precheck import (
        ENSEMBLE_SIZE, SEED_ENTROPY, injection_sigma)
    from camels_switch_confirmation.g1_precheck import LAG_KERNEL

    sigma = injection_sigma(multiplier)
    generator = np.random.default_rng(
        np.random.SeedSequence((SEED_ENTROPY, int(basin_id), int(cell_index))))
    n_days = len(rain)
    states = [dict(initial_state) for _ in range(ENSEMBLE_SIZE)]
    discharge = np.empty((ENSEMBLE_SIZE, n_days), dtype=np.float64)
    # absolute amplitude anchored to the stored SLZ so that day 1 matches the
    # multiplicative design; afterwards it no longer follows the store.
    absolute_scale = float(initial_state["SLZ"]) * sigma
    for day in range(n_days):
        for member in range(ENSEMBLE_SIZE):
            simulated, state = simulate_hbv_lite(
                rain[day:day + 1], pet[day:day + 1], temp[day:day + 1],
                params, initial_state=states[member], lag_kernel=LAG_KERNEL)
            state = dict(state)
            if variant == "slz_mult":
                state["SLZ"] = state["SLZ"] * float(
                    np.exp(generator.normal(-0.5 * sigma ** 2, sigma)))
            elif variant == "slz_abs":
                state["SLZ"] = max(
                    state["SLZ"] + float(generator.normal(0.0, absolute_scale)), 0.0)
            elif variant == "suz_mult":
                state["SUZ"] = state["SUZ"] * float(
                    np.exp(generator.normal(-0.5 * sigma ** 2, sigma)))
            else:
                raise ValueError(f"unknown variant {variant!r}")
            states[member] = state
            discharge[member, day] = float(simulated[0])
    return discharge.var(axis=0)


def _run_basin(job) -> dict:
    basin_id, variant = job
    import sys as _sys
    if str(_SRC) not in _sys.path:
        _sys.path.insert(0, str(_SRC))
    from hydroagent.data_loading import load_camels_basin

    started = time.time()
    try:
        table = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
        table["basin_id"] = table["basin_id"].str.zfill(8)
        row = table[table["basin_id"] == basin_id].iloc[0]
        params = {key: float(row[f"p_{key}"]) for key in PARAM_KEYS}
        initial_state = {name: float(row[f"state_{name}"]) for name in STATE_NAMES}

        g1 = pd.read_csv(G1_CSV, dtype={"basin_id": str})
        g1["basin_id"] = g1["basin_id"].str.zfill(8)
        sigma_obs = float(g1.set_index("basin_id").loc[basin_id, "sigma_obs"])

        forcing, _obs, _area = load_camels_basin(
            basin_id, data_root=DATA_ROOT, start_date=WINDOW_START,
            end_date=_window_end(), forcing="maurer", pet_method="oudin",
            keep_obs_nan_days=True,
        )
        rain = forcing["prcp"].values.astype(np.float64)
        pet_column = "ep" if "ep" in forcing.columns else "pet"
        pet = forcing[pet_column].values.astype(np.float64)
        temp = (forcing["tmean"].values.astype(np.float64)
                if "tmean" in forcing.columns else np.zeros_like(rain))

        if variant == "slz_mult":
            spread = _ensemble_variance(rain, pet, temp, params, initial_state,
                                        FIXED_MULTIPLIER, basin_id, CELL_INDEX)
        else:
            spread = _variant_variance(rain, pet, temp, params, initial_state,
                                       FIXED_MULTIPLIER, basin_id, CELL_INDEX,
                                       variant)
        stages = np.array([spread[i * STAGE_DAYS:(i + 1) * STAGE_DAYS].mean()
                           for i in range(len(ROTATION))], dtype=np.float64)
        record = {
            "basin_id": basin_id,
            "variant": variant,
            "sigma_obs": sigma_obs,
            "fixed_multiplier": FIXED_MULTIPLIER,
            "stage_variance_min": float(stages.min()),
            "stage_variance_max": float(stages.max()),
            "confound_ratio": float(stages.max() / stages.min())
            if stages.min() > 0 else float("inf"),
            "stage7_over_stage1": float(stages[-1] / stages[0])
            if stages[0] > 0 else float("inf"),
            "signal_ratio": SIGNAL_RATIO,
            "run_status": "success",
            "error_message": "",
            "_elapsed_s": round(time.time() - started, 2),
        }
        for index, value in enumerate(stages):
            record[f"stage{index + 1}_variance"] = float(value)
            record[f"stage{index + 1}_var_ratio_to_obs"] = float(value / sigma_obs ** 2)
        return record
    except Exception as exception:  # noqa: BLE001 - recorded, never fatal
        return {"basin_id": basin_id, "variant": variant, "run_status": "failed",
                "error_message": f"{type(exception).__name__}: {exception}",
                "_elapsed_s": round(time.time() - started, 2)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--basins", nargs="*", default=None)
    parser.add_argument("--variants", nargs="*", default=list(VARIANTS))
    parser.add_argument("--workers", type=int, default=WORKERS)
    parser.add_argument("--output-root", default=str(OUTPUT_ROOT))
    arguments = parser.parse_args()

    admitted = pd.read_csv(ADMISSION_CSV, dtype={"basin_id": str})
    admitted["basin_id"] = admitted["basin_id"].str.zfill(8)
    basins = [b.zfill(8) for b in (arguments.basins or admitted["basin_id"].tolist())]

    jobs = [(b, v) for v in arguments.variants for b in basins]
    print(f"[confound-scale] basins={len(basins)} variants={arguments.variants} "
          f"fixed m={FIXED_MULTIPLIER} window={WINDOW_START}+{WINDOW_DAYS}d "
          f"stages={len(ROTATION)}x{STAGE_DAYS}d")
    if arguments.workers > 1 and len(jobs) > 1:
        with ProcessPoolExecutor(max_workers=arguments.workers) as pool:
            results = list(pool.map(_run_basin, jobs, chunksize=1))
    else:
        results = [_run_basin(job) for job in jobs]

    frame = pd.DataFrame(results)
    output_root = Path(arguments.output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    frame.to_csv(output_root / "confound_scale.csv", index=False)

    ok = frame[frame["run_status"] == "success"]
    summary = {
        "basins_requested": len(basins),
        "variants": list(arguments.variants),
        "fixed_multiplier": FIXED_MULTIPLIER,
        "signal_ratio": SIGNAL_RATIO,
        "per_variant": {},
        "failures": frame[frame["run_status"] != "success"]["basin_id"].tolist(),
    }
    for variant in arguments.variants:
        subset = ok[ok["variant"] == variant]
        if not len(subset):
            continue
        stage_columns = [f"stage{i}_variance" for i in range(1, len(ROTATION) + 1)]
        normalised = (subset[stage_columns].values
                      / subset[stage_columns].values[:, [0]])
        summary["per_variant"][variant] = {
            "basins_success": int(len(subset)),
            "confound_ratio_median": float(subset["confound_ratio"].median()),
            "confound_ratio_p90": float(subset["confound_ratio"].quantile(0.9)),
            "confound_ratio_max": float(subset["confound_ratio"].max()),
            "confound_exceeds_signal_count": int(
                (subset["confound_ratio"] >= SIGNAL_RATIO).sum()),
            "confound_exceeds_half_signal_count": int(
                (subset["confound_ratio"] >= SIGNAL_RATIO / 2).sum()),
            "stage7_over_stage1_median": float(subset["stage7_over_stage1"].median()),
            "stage_profile_median_normalised": [
                float(x) for x in np.median(normalised, axis=0)],
        }
    with open(output_root / "confound_summary.json", "w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, ensure_ascii=False)
    print(json.dumps(summary, indent=2))
    print(f"[confound-scale] wrote {output_root}")


if __name__ == "__main__":
    main()
