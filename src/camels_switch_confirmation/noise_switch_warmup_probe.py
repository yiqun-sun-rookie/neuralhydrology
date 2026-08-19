"""NOISE-W1: how long a warm-up removes the storage drift confound.

Diagnostic only -- ZERO filter runs, no candidate identification, no number that
feeds any preregistered claim.  It answers one question raised by the handoff
(2026-08-18/19): the noise-switch truth injection is MULTIPLICATIVE in the lower
groundwater store SLZ, but SLZ drifts by roughly 7x across the 1260-day window
when the simulation starts from the calibration table's stored end state, so a
"noise level changed" signal can be impersonated by a "storage level changed"
signal.  Option 1 of the handoff is to spin the model up before the official
window.  This probe measures how much warm-up is needed.

For every admitted basin and every candidate warm-up start it runs a
DETERMINISTIC open-loop simulation (no noise injected -- the drift is a
noise-free property, verified in the handoff) and reports

  * drift_ratio          mean SLZ of stage 1 / mean SLZ of stage 7 (180d blocks)
  * block_span_ratio     max / min over the seven 180-day block means
  * rel_dev_vs_reference median |SLZ - SLZ_ref| / SLZ_ref against the longest
                         warm-up available (initial-condition memory still alive
                         inside the official window)

and, separately, an initial-condition memory test: the same window run from
SLZ x4 versus SLZ x1, reporting the last day the two trajectories still differ
by more than 1%.

Usage:  python -X utf8 -m camels_switch_confirmation.noise_switch_warmup_probe
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
    STAGE_DAYS,
    STATE_NAMES,
    WINDOW_START,
    _window_end,
)
from camels_switch_confirmation.noise_switch_precheck import (  # noqa: E402
    OUTPUT_ROOT as PRECHECK_ROOT,
    ROTATION,
    WINDOW_DAYS,
)
from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    PARAMETER_TABLE,
    RESULTS,
)

OUTPUT_ROOT = RESULTS / "noise_switch_warmup_probe_v01"
ADMISSION_CSV = PRECHECK_ROOT / "admission.csv"
DATA_ROOT = "data/camels_us"

# Candidate warm-up starts (water years).  1980-10-01 is the longest the maurer
# forcing supports; 1989-10-01 == no warm-up == the current (confounded) design.
WARMUP_STARTS = ("1989-10-01", "1988-10-01", "1987-10-01",
                 "1986-10-01", "1984-10-01", "1980-10-01")
REFERENCE_START = WARMUP_STARTS[-1]
MEMORY_FACTOR = 4.0
MEMORY_TOLERANCE = 0.01
WORKERS = 10


def _daily_slz(rain, pet, temp, params, state, n_days):
    """Step the open-loop model day by day, recording SLZ after each day."""
    from scl_hydro.hbv_lite_numpy import simulate_hbv_lite
    trace = np.empty(n_days, dtype=np.float64)
    current = dict(state)
    for day in range(n_days):
        _, current = simulate_hbv_lite(
            rain[day:day + 1], pet[day:day + 1], temp[day:day + 1],
            params, initial_state=current, lag_kernel=LAG_KERNEL)
        trace[day] = current["SLZ"]
    return trace, current


def _block_means(trace):
    return np.array([trace[i * STAGE_DAYS:(i + 1) * STAGE_DAYS].mean()
                     for i in range(len(ROTATION))], dtype=np.float64)


def _memory_days(base, perturbed):
    """Last day on which |perturbed-base|/base still exceeds the tolerance."""
    relative = np.abs(perturbed - base) / np.maximum(base, 1e-12)
    above = np.nonzero(relative >= MEMORY_TOLERANCE)[0]
    if len(above) == 0:
        return 0
    return int(above[-1] + 1)


def _run_basin(args_tuple):
    basin_id, row = args_tuple
    import sys as _sys
    if str(_SRC) not in _sys.path:
        _sys.path.insert(0, str(_SRC))
    from hydroagent.data_loading import load_camels_basin
    from scl_hydro.hbv_lite_numpy import simulate_hbv_lite

    started = time.time()
    try:
        params = {k: float(row[f"p_{k}"]) for k in PARAM_KEYS}
        stored_state = {s: float(row[f"state_{s}"]) for s in STATE_NAMES}

        forcing, _obs, _area = load_camels_basin(
            basin_id, data_root=DATA_ROOT,
            start_date=REFERENCE_START, end_date=_window_end(),
            forcing="maurer", pet_method="oudin", keep_obs_nan_days=True,
        )
        index = pd.DatetimeIndex(forcing.index)
        rain = forcing["prcp"].values.astype(np.float64)
        pet_col = "ep" if "ep" in forcing.columns else "pet"
        pet = forcing[pet_col].values.astype(np.float64)
        temp = (forcing["tmean"].values.astype(np.float64)
                if "tmean" in forcing.columns else np.zeros_like(rain))

        window_first = int(index.get_indexer([pd.Timestamp(WINDOW_START)])[0])
        if window_first < 0:
            raise ValueError("official window start missing from forcing index")
        if len(rain) - window_first < WINDOW_DAYS:
            raise ValueError("forcing does not cover the full official window")

        traces, records = {}, []
        for start in WARMUP_STARTS:
            offset = int(index.get_indexer([pd.Timestamp(start)])[0])
            if offset < 0:
                raise ValueError(f"warm-up start {start} missing from forcing")
            warmup_days = window_first - offset
            if warmup_days:
                _, state = simulate_hbv_lite(
                    rain[offset:window_first], pet[offset:window_first],
                    temp[offset:window_first], params,
                    initial_state=stored_state, lag_kernel=LAG_KERNEL)
            else:
                state = dict(stored_state)
            trace, _ = _daily_slz(rain[window_first:window_first + WINDOW_DAYS],
                                  pet[window_first:window_first + WINDOW_DAYS],
                                  temp[window_first:window_first + WINDOW_DAYS],
                                  params, state, WINDOW_DAYS)
            traces[start] = trace
            blocks = _block_means(trace)
            records.append({
                "basin_id": basin_id,
                "warmup_start": start,
                "warmup_days": warmup_days,
                "slz_window_start": float(state["SLZ"]),
                "slz_stage1_mean": float(blocks[0]),
                "slz_stage7_mean": float(blocks[-1]),
                "drift_ratio": float(blocks[0] / blocks[-1]),
                "block_span_ratio": float(blocks.max() / blocks.min()),
                "slz_min": float(trace.min()),
                "slz_max": float(trace.max()),
            })

        reference = traces[REFERENCE_START]
        for record in records:
            deviation = np.abs(traces[record["warmup_start"]] - reference)
            record["rel_dev_vs_reference"] = float(
                np.median(deviation / np.maximum(reference, 1e-12)))
            record["max_rel_dev_vs_reference"] = float(
                np.max(deviation / np.maximum(reference, 1e-12)))

        # initial-condition memory: same window, SLZ inflated x4 at t=0
        perturbed_state = dict(stored_state)
        perturbed_state["SLZ"] = stored_state["SLZ"] * MEMORY_FACTOR
        perturbed, _ = _daily_slz(rain[window_first:window_first + WINDOW_DAYS],
                                  pet[window_first:window_first + WINDOW_DAYS],
                                  temp[window_first:window_first + WINDOW_DAYS],
                                  params, perturbed_state, WINDOW_DAYS)
        memory = _memory_days(traces[WINDOW_START], perturbed)

        for record in records:
            record["memory_days_x4"] = memory
            record["park2"] = params["parK2"]
            record["k2_efolding_days"] = (float(1.0 / params["parK2"])
                                          if params["parK2"] > 0 else float("inf"))
            record["run_status"] = "success"
            record["error_message"] = ""
            record["_elapsed_s"] = round(time.time() - started, 2)
        return records
    except Exception as exception:  # noqa: BLE001 - recorded, never fatal
        return [{
            "basin_id": basin_id, "warmup_start": "", "run_status": "failed",
            "error_message": f"{type(exception).__name__}: {exception}",
            "_elapsed_s": round(time.time() - started, 2),
        }]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--basins", nargs="*", default=None,
                        help="subset of basin ids (default: all admitted)")
    parser.add_argument("--workers", type=int, default=WORKERS)
    parser.add_argument("--output-root", default=str(OUTPUT_ROOT))
    arguments = parser.parse_args()

    admitted = pd.read_csv(ADMISSION_CSV, dtype={"basin_id": str})
    admitted["basin_id"] = admitted["basin_id"].str.zfill(8)
    basins = [b.zfill(8) for b in (arguments.basins or admitted["basin_id"].tolist())]

    table = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    rows = {b: table[table["basin_id"] == b].iloc[0] for b in basins}

    print(f"[warmup-probe] basins={len(basins)} warmup_starts={WARMUP_STARTS} "
          f"window={WINDOW_START}+{WINDOW_DAYS}d kernel={LAG_KERNEL}")
    work = [(b, rows[b]) for b in basins]
    results = []
    if arguments.workers > 1 and len(work) > 1:
        with ProcessPoolExecutor(max_workers=arguments.workers) as pool:
            for chunk in pool.map(_run_basin, work):
                results.extend(chunk)
    else:
        for item in work:
            results.extend(_run_basin(item))

    frame = pd.DataFrame(results)
    output_root = Path(arguments.output_root)
    output_root.mkdir(parents=True, exist_ok=True)
    frame.to_csv(output_root / "warmup_probe.csv", index=False)

    ok = frame[frame["run_status"] == "success"]
    unique = ok.drop_duplicates("basin_id")
    summary = {
        "basins_requested": len(basins),
        "basins_success": int(ok["basin_id"].nunique()) if len(ok) else 0,
        "warmup_starts": list(WARMUP_STARTS),
        "window_start": WINDOW_START,
        "window_days": WINDOW_DAYS,
        "stage_days": STAGE_DAYS,
        "memory_factor": MEMORY_FACTOR,
        "memory_tolerance": MEMORY_TOLERANCE,
        "memory_days_x4_median": float(unique["memory_days_x4"].median()) if len(ok) else None,
        "memory_days_x4_p90": float(unique["memory_days_x4"].quantile(0.9)) if len(ok) else None,
        "k2_efolding_days_median": float(unique["k2_efolding_days"].median()) if len(ok) else None,
        "per_warmup_median": {},
        "failures": frame[frame["run_status"] != "success"]["basin_id"].tolist(),
    }
    for start in WARMUP_STARTS:
        subset = ok[ok["warmup_start"] == start] if len(ok) else ok
        if not len(subset):
            continue
        summary["per_warmup_median"][start] = {
            "warmup_days": int(subset["warmup_days"].iloc[0]),
            "drift_ratio": float(subset["drift_ratio"].median()),
            "drift_ratio_p90": float(subset["drift_ratio"].quantile(0.9)),
            "block_span_ratio": float(subset["block_span_ratio"].median()),
            "block_span_ratio_p90": float(subset["block_span_ratio"].quantile(0.9)),
            "rel_dev_vs_reference": float(subset["rel_dev_vs_reference"].median()),
            "max_rel_dev_vs_reference_p90": float(
                subset["max_rel_dev_vs_reference"].quantile(0.9)),
        }
    with open(output_root / "warmup_summary.json", "w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, ensure_ascii=False)
    print(json.dumps(summary["per_warmup_median"], indent=2))
    print(f"[warmup-probe] wrote {output_root}")


if __name__ == "__main__":
    main()
