"""Day-540 state-SUBSET truth-mean counterfactuals (which states are necessary?).

Extends the frozen fifteen-state day-540 counterfactual: replace only a named
subset of the dominant source candidate's state mean with synthetic truth at
day 540, everything else unchanged.  Diagnostic only, not an operational
method.  Locked to basin 07184000, design seed 0, Gaussian evidence,
pairwise-path post-observation collapse.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from camels_switch_confirmation.g2_switch_confirmation import _atomic_save_npz
from camels_switch_confirmation.run_day540_truth_state_counterfactual import (
    BASIN_ID,
    INTERVENTION_DAY,
    INTERVENTION_SOURCE_INDEX,
    SEED,
    _build_gaussian_path_estimator,
    _events,
    _load_source,
    _metrics,
    _truth_replay_from_source,
)

EXPERIMENT_ID = "CAMELS_PARFC_DAY540_STATE_SUBSET_COUNTERFACTUAL_07184000_S0_01"
EXPECTED_SOURCE_TASK_SHA256 = (
    "8b9a6766e7c2c5b5bba344dbf2033fbff55dacb31ff3de51383f542b23c00beb"
)
WINDOW_DAYS = 1260
VARIANTS: dict[str, tuple[int, ...]] = {
    "sm_only": (2,),
    "slz_only": (4,),
    "sm_slz": (2, 4),
    "routing_only": tuple(range(5, 15)),
    "all_but_sm": (0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14),
}


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json_new(path: Path, payload: dict) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def run_variant(source, truth, indices: tuple[int, ...]):
    """Online rerun with a day-540 subset-of-state-mean replacement."""
    estimator, transitions = _build_gaussian_path_estimator(source)
    n_days, n_candidates = source["probabilities"].shape
    probabilities = np.empty((n_days, n_candidates), dtype=np.float64)
    log_probabilities = np.empty_like(probabilities)
    source_states = np.empty((n_days, n_candidates, 15), dtype=np.float64)
    record = {}
    for day in range(n_days):
        current_states = np.asarray(
            [candidate.state.copy() for candidate in estimator.filters]
        )
        if day <= INTERVENTION_DAY:
            if not np.array_equal(
                current_states, source["path_source_states"][day]
            ) or not np.array_equal(
                estimator.probabilities, source["path_source_probabilities"][day]
            ):
                raise AssertionError(
                    f"pre-intervention state diverged from the frozen source on day {day}"
                )
        if day == INTERVENTION_DAY:
            candidate = estimator.filters[INTERVENTION_SOURCE_INDEX]
            probabilities_before = estimator.probabilities.copy()
            if int(np.argmax(probabilities_before)) != INTERVENTION_SOURCE_INDEX:
                raise AssertionError("dominant source candidate is not the expected index")
            state_before = candidate.state.copy()
            replaced = state_before.copy()
            replaced[list(indices)] = truth.source_states[day][list(indices)]
            candidate.state = replaced
            record = {
                "intervention_day": np.array(INTERVENTION_DAY, dtype=np.int64),
                "intervention_source_index": np.array(
                    INTERVENTION_SOURCE_INDEX, dtype=np.int64
                ),
                "intervention_state_indices": np.asarray(indices, dtype=np.int64),
                "intervention_state_before": state_before,
                "intervention_state_after": replaced.copy(),
                "intervention_truth_source_state": truth.source_states[day].copy(),
                "intervention_probabilities": probabilities_before,
            }
            current_states = np.asarray(
                [candidate.state.copy() for candidate in estimator.filters]
            )
        source_states[day] = current_states
        for transition in transitions:
            transition.set_forcing(
                source["rain"][day],
                source["pet"][day],
                source["temperature"][day],
            )
        result = estimator.step(np.array([source["observations"][day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
    if not record:
        raise AssertionError("the day-540 intervention was not applied")
    return probabilities, log_probabilities, source_states, record


def summarize(probabilities, log_probabilities, source) -> dict:
    events = _events(probabilities, source)
    true_indices = source["true_candidate_indices"]
    day540_event = next(e for e in events if e["switch_day"] == INTERVENTION_DAY)
    day720_event = next(e for e in events if e["switch_day"] == 720)
    return {
        "events_passed": int(sum(e["passed"] for e in events)),
        "events_total": len(events),
        "events": events,
        "day540_event": day540_event,
        "day720_event": day720_event,
        "days_540_719": _metrics(
            probabilities, log_probabilities, true_indices, 540, 720
        ),
        "days_720_899": _metrics(
            probabilities, log_probabilities, true_indices, 720, 900
        ),
        "full_period": _metrics(
            probabilities, log_probabilities, true_indices, 0, WINDOW_DAYS
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=sorted(VARIANTS), required=True)
    parser.add_argument("--source-task", type=Path, required=True)
    parser.add_argument("--output-parent", type=Path, required=True)
    args = parser.parse_args()

    source_task = args.source_task.resolve()
    observed_hash = _sha256_file(source_task)
    if observed_hash != EXPECTED_SOURCE_TASK_SHA256:
        raise ValueError(
            f"source task hash mismatch: {observed_hash}"
        )
    output_parent = args.output_parent.resolve()
    output_parent.mkdir(parents=True, exist_ok=True)
    output_root = output_parent / args.variant
    if output_root.exists():
        raise FileExistsError(f"variant output already exists: {output_root}")

    source = _load_source(source_task)
    truth = _truth_replay_from_source(source)
    indices = VARIANTS[args.variant]
    probabilities, log_probabilities, source_states, record = run_variant(
        source, truth, indices
    )
    summary = {
        "experiment_id": EXPERIMENT_ID,
        "variant": args.variant,
        "replaced_state_indices": list(indices),
        "basin_id": BASIN_ID,
        "seed": SEED,
        "status": "single_truth_state_subset_counterfactual_not_operational_method",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_task": str(source_task),
        "source_task_sha256": observed_hash,
        "python": sys.version,
        "numpy": np.__version__,
        "result": summarize(probabilities, log_probabilities, source),
        "baseline": summarize(
            source["probabilities"], source["log_probabilities"], source
        ),
    }
    output_root.mkdir(parents=False, exist_ok=False)
    _atomic_save_npz(
        output_root / "counterfactual.npz",
        probabilities=probabilities,
        log_probabilities=log_probabilities,
        source_states=source_states,
        baseline_probabilities=source["probabilities"].copy(),
        true_candidate_indices=source["true_candidate_indices"].copy(),
        basin_id=np.array(BASIN_ID),
        seed=np.array(SEED, dtype=np.int64),
        variant=np.array(args.variant),
        **record,
    )
    _write_json_new(output_root / "summary.json", summary)
    print(json.dumps({
        "variant": args.variant,
        "events_passed": summary["result"]["events_passed"],
        "day540_passed": summary["result"]["day540_event"]["passed"],
        "day720_passed": summary["result"]["day720_event"]["passed"],
        "mean_true_p_540_719": summary["result"]["days_540_719"]["mean_true_probability"],
        "zero_days_540_719": summary["result"]["days_540_719"]["zero_true_probability_days"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
