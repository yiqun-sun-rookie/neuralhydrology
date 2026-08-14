"""Runnable-fix diagnostic: state-proportional SLZ process covariance.

Single-factor change against the frozen version-03B contract: the filter
process covariance mode becomes ``lower_groundwater_state_proportional`` with
multiplier 1 (first-two-moment match to the truth's multiplicative SLZ
noise), rebuilt every day from the predicted reference state exactly as the
registered ``g2_switch_confirmation`` day loop does.  Everything else --
candidates, initial moments, forcing, observations, Gaussian evidence,
transition matrix, conservative parFC mapping -- is unchanged.  Both
comparison arms run online from day zero.  Diagnostic scope: basin 07184000,
design seeds 0 and 1.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from camels_switch_confirmation.g2_switch_confirmation import (
    _atomic_save_npz,
    _build_bank,
    _evaluate_events,
    assign_common_process_covariance,
    build_state_dependent_lower_groundwater_covariance,
)
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds

EXPERIMENT_ID = "CAMELS_PARFC_SLZ_STATE_PROPORTIONAL_Q_07184000_01"
BASIN_ID = "07184000"
Q_MODE = "lower_groundwater_state_proportional"
Q_STRUCTURE = "lower_groundwater_state_only"
Q_STATE_MULTIPLIER = 1.0
ARM_MODES = {"C": "full", "P": "pairwise_path_postcollapse"}
COMMON_SOURCE_FIELDS = (
    "truth_q",
    "observations",
    "basin_id",
    "seed",
    "switch_days",
    "rotation",
    "stage_days",
    "true_candidate_indices",
    "truth_parfc",
    "candidate_parameter_names",
    "candidate_parameter_vectors",
    "observation_sigma",
    "rain",
    "pet",
    "temperature",
    "filter_observation_variance_multiplier",
    "path_initial_probabilities",
    "path_initial_states",
    "path_initial_covariances",
)


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


def _load_source(path: Path, seed: int) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as archive:
        missing = sorted(set(COMMON_SOURCE_FIELDS) - set(archive.files))
        if missing:
            raise ValueError(f"source task is missing fields: {missing}")
        source = {name: archive[name].copy() for name in COMMON_SOURCE_FIELDS}
    if str(source["basin_id"].item()) != BASIN_ID:
        raise ValueError(f"diagnostic is locked to basin {BASIN_ID}")
    if int(source["seed"].item()) != seed:
        raise ValueError(f"source seed does not match the requested seed {seed}")
    if len(source["observations"]) != 1260:
        raise ValueError("expected 1260 days")
    return source


def _members_and_initial_hydrology(source):
    names = [str(value) for value in source["candidate_parameter_names"]]
    members = [
        {name: float(value) for name, value in zip(names, row)}
        for row in source["candidate_parameter_vectors"]
    ]
    return members, source["path_initial_states"][0, :5].copy()


def run_arm(source, arm_id: str):
    members, initial_hydrology = _members_and_initial_hydrology(source)
    estimator, transitions = _build_bank(
        members,
        initial_hydrology,
        float(source["observation_sigma"].item()),
        resolve_hbv_bounds("v5"),
        q_scale=np.nan,
        q_structure=Q_STRUCTURE,
        q_mode=Q_MODE,
        q_state_multiplier=Q_STATE_MULTIPLIER,
        filter_r_multiplier=float(
            source["filter_observation_variance_multiplier"].item()
        ),
        interaction_mode=ARM_MODES[arm_id],
        parameter_state_mapping="conservative_parfc",
        model_evidence_scorer=None,
    )
    observed_states = np.asarray([item.state for item in estimator.filters])
    observed_covariances = np.asarray(
        [item.covariance for item in estimator.filters]
    )
    if not np.array_equal(observed_states, source["path_initial_states"]):
        raise ValueError("rebuilt initial states do not bitwise match the frozen task")
    if not np.array_equal(
        observed_covariances, source["path_initial_covariances"]
    ):
        raise ValueError(
            "rebuilt initial covariances do not bitwise match the frozen task"
        )
    if not np.array_equal(
        estimator.probabilities, source["path_initial_probabilities"]
    ):
        raise ValueError(
            "rebuilt initial probabilities do not bitwise match the frozen task"
        )

    n_days = len(source["observations"])
    n_candidates = len(estimator.filters)
    n_state = estimator.filters[0].n_state
    probabilities = np.empty((n_days, n_candidates), dtype=np.float64)
    log_probabilities = np.empty_like(probabilities)
    candidate_states = np.empty((n_days, n_candidates, n_state), dtype=np.float64)
    candidate_variances = np.empty((n_days, n_candidates, n_state), dtype=np.float64)
    process_variances = np.empty(n_days, dtype=np.float64)
    for day in range(n_days):
        for transition in transitions:
            transition.set_forcing(
                source["rain"][day],
                source["pet"][day],
                source["temperature"][day],
            )
        # Registered per-day protocol for the state-proportional mode
        # (g2_switch_confirmation day loop, first-contact amendment).
        predicted_reference = transitions[0](estimator.state.copy())
        common_q = build_state_dependent_lower_groundwater_covariance(
            predicted_reference[4], Q_STATE_MULTIPLIER
        )
        assign_common_process_covariance(estimator, common_q)
        process_variances[day] = estimator.filters[0].process_covariance[4, 4]
        result = estimator.step(np.array([source["observations"][day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
        for index, candidate in enumerate(estimator.filters):
            candidate_states[day, index] = candidate.state
            candidate_variances[day, index] = np.diag(candidate.covariance)
    return {
        "probabilities": probabilities,
        "log_probabilities": log_probabilities,
        "candidate_states": candidate_states,
        "candidate_variances": candidate_variances,
        "process_variances": process_variances,
    }


def _longest_run(mask) -> int:
    longest = current = 0
    for value in np.asarray(mask, dtype=bool):
        current = current + 1 if value else 0
        longest = max(longest, current)
    return int(longest)


def _metrics(probabilities, log_probabilities, true_indices, start, end) -> dict:
    probabilities = np.asarray(probabilities)[start:end]
    log_probabilities = np.asarray(log_probabilities)[start:end]
    true_indices = np.asarray(true_indices, dtype=np.int64)[start:end]
    row = np.arange(end - start)
    true_probabilities = probabilities[row, true_indices]
    true_log_probabilities = log_probabilities[row, true_indices]
    truth = np.eye(probabilities.shape[1], dtype=np.float64)[true_indices]
    return {
        "days": int(end - start),
        "mean_true_probability": float(np.mean(true_probabilities)),
        "multiclass_brier_score": float(
            np.mean(np.sum((probabilities - truth) ** 2, axis=1))
        ),
        "mean_true_negative_log_probability": float(
            np.mean(-true_log_probabilities)
        ),
        "zero_true_probability_days": int(np.sum(true_probabilities == 0.0)),
        "true_probability_below_0_01_days": int(np.sum(true_probabilities < 0.01)),
        "longest_below_0_01_run_days": _longest_run(true_probabilities < 0.01),
    }


def summarize(probabilities, log_probabilities, source) -> dict:
    switch_pairs = list(
        zip(source["switch_days"].tolist(), source["rotation"][1:].tolist())
    )
    events = [
        {
            "switch_day": int(event["switch_day"]),
            "new_member": int(event["new_member"]),
            "passed": bool(event["passed"]),
            "response_start_days": (
                None
                if event["response_start"] is None
                else int(event["response_start"])
            ),
        }
        for event in _evaluate_events(probabilities, switch_pairs)
    ]
    true_indices = source["true_candidate_indices"]
    return {
        "events_passed": int(sum(event["passed"] for event in events)),
        "events_total": len(events),
        "events": events,
        "full_period": _metrics(
            probabilities, log_probabilities, true_indices, 0, len(true_indices)
        ),
        "days_540_719": _metrics(
            probabilities, log_probabilities, true_indices, 540, 720
        ),
        "days_720_899": _metrics(
            probabilities, log_probabilities, true_indices, 720, 900
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arm", choices=sorted(ARM_MODES), required=True)
    parser.add_argument("--seed", type=int, choices=(0, 1), required=True)
    parser.add_argument("--source-task", type=Path, required=True)
    parser.add_argument("--baseline-task", type=Path, required=True)
    parser.add_argument("--output-parent", type=Path, required=True)
    args = parser.parse_args()

    source_task = args.source_task.resolve()
    baseline_task = args.baseline_task.resolve()
    output_parent = args.output_parent.resolve()
    output_parent.mkdir(parents=True, exist_ok=True)
    output_root = output_parent / f"{args.arm}_s{args.seed}"
    if output_root.exists():
        raise FileExistsError(f"output already exists: {output_root}")

    source = _load_source(source_task, args.seed)
    arrays = run_arm(source, args.arm)
    with np.load(baseline_task, allow_pickle=False) as baseline_archive:
        baseline_probabilities = baseline_archive["probabilities"].copy()
        baseline_log_probabilities = baseline_archive["log_probabilities"].copy()
        if str(baseline_archive["arm_id"].item()) != args.arm:
            raise ValueError("baseline task arm does not match the requested arm")
        if int(baseline_archive["seed"].item()) != args.seed:
            raise ValueError("baseline task seed does not match the requested seed")

    summary = {
        "experiment_id": EXPERIMENT_ID,
        "arm": args.arm,
        "interaction_mode": ARM_MODES[args.arm],
        "seed": args.seed,
        "basin_id": BASIN_ID,
        "status": "single_basin_runnable_fix_diagnostic_not_cross_basin_evidence",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "changed_factor": {
            "filter_q_mode": Q_MODE,
            "filter_q_structure": Q_STRUCTURE,
            "filter_q_state_multiplier": Q_STATE_MULTIPLIER,
            "baseline_q_mode": "fixed",
            "baseline_q_scale": 3e-08,
        },
        "model_evidence_distribution": "gaussian",
        "source_task": str(source_task),
        "source_task_sha256": _sha256_file(source_task),
        "baseline_task": str(baseline_task),
        "baseline_task_sha256": _sha256_file(baseline_task),
        "python": sys.version,
        "numpy": np.__version__,
        "proportional_q": summarize(
            arrays["probabilities"], arrays["log_probabilities"], source
        ),
        "baseline_fixed_q": summarize(
            baseline_probabilities, baseline_log_probabilities, source
        ),
    }
    output_root.mkdir(parents=False, exist_ok=False)
    _atomic_save_npz(
        output_root / "result.npz",
        basin_id=np.array(BASIN_ID),
        seed=np.array(args.seed, dtype=np.int64),
        arm_id=np.array(args.arm),
        state_interaction_mode=np.array(ARM_MODES[args.arm]),
        filter_q_mode=np.array(Q_MODE),
        filter_q_state_multiplier=np.array(Q_STATE_MULTIPLIER),
        model_evidence_distribution=np.array("gaussian"),
        true_candidate_indices=source["true_candidate_indices"].copy(),
        baseline_probabilities=baseline_probabilities,
        **arrays,
    )
    _write_json_new(output_root / "summary.json", summary)
    print(json.dumps({
        "arm": args.arm,
        "seed": args.seed,
        "events_passed_proportional": summary["proportional_q"]["events_passed"],
        "events_passed_baseline": summary["baseline_fixed_q"]["events_passed"],
        "brier_full_proportional": summary["proportional_q"]["full_period"]["multiclass_brier_score"],
        "brier_full_baseline": summary["baseline_fixed_q"]["full_period"]["multiclass_brier_score"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
