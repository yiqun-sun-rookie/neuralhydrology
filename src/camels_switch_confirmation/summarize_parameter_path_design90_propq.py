"""03C Design90 proportional-Q verifier and dual-window summarizer.

Recomputes every event decision from the saved per-task probabilities at the
registered primary (30-day) and secondary (90-day) response windows, splits
pass rates by transition type and capacity direction, evaluates the frozen
probability-quality gates, and pairs every task against the frozen 03B
fixed-Q result.  Read-only over both result roots; writes one verification
directory inside the 03C root.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from camels_switch_confirmation import run_parameter_path_design90_propq as propq
from camels_switch_confirmation import run_parameter_path_mechanism as base
from camels_switch_confirmation.g2_switch_confirmation import (
    CONSECUTIVE_DAYS,
    MARGIN_INCLUSIVE,
    PROB_THRESHOLD_EXCLUSIVE,
)

_REPO_ROOT = Path(__file__).resolve().parents[2]

FROZEN_03B_ROOT = Path(
    "results/23_camels_switch_confirmation/"
    "camels_parfc_transition_path_03b_design90_s01_20260811_local"
)
EXPECTED_03B_FINGERPRINT = (
    "57d8fef9037c29d0a68f915d5337f3be7bfab2224ebada575be6161e070126e6"
)
WINDOWS = (30, 90)
SEVERE_NLL = 100.0


def _evaluate_events_window(probs, switch_pairs, window_days):
    """The registered 5-day/0.5/margin rule at an arbitrary window width."""
    events = []
    n_days = probs.shape[0]
    for switch_day, new_idx in switch_pairs:
        window_end = min(switch_day + window_days, n_days)
        passed, start = False, None
        latest_start = window_end - CONSECUTIVE_DAYS
        for t0 in range(switch_day, latest_start + 1):
            seg = probs[t0:t0 + CONSECUTIVE_DAYS]
            new_p = seg[:, new_idx]
            others = np.delete(seg, new_idx, axis=1).max(axis=1)
            if np.all(new_p > PROB_THRESHOLD_EXCLUSIVE) and \
               np.all(new_p - others >= MARGIN_INCLUSIVE):
                passed, start = True, t0 - switch_day
                break
        events.append({"switch_day": int(switch_day), "new_member": int(new_idx),
                       "passed": bool(passed), "response_start": start})
    return events


def _task_record(npz_path: Path, expected_q_mode: str) -> dict:
    with np.load(npz_path, allow_pickle=False) as archive:
        probs = archive["probabilities"].copy()
        log_probs = archive["log_probabilities"].copy()
        true_idx = archive["true_candidate_indices"].astype(np.int64).copy()
        truth_parfc = archive["truth_parfc"].copy()
        switch_days = archive["switch_days"].astype(np.int64).copy()
        rotation = archive["rotation"].astype(np.int64).copy()
        basin_id = str(archive["basin_id"].item())
        seed = int(archive["seed"].item())
        arm_id = str(archive["arm_id"].item())
        q_mode = str(archive["filter_q_mode"].item())
    if q_mode != expected_q_mode:
        raise ValueError(f"{npz_path} q_mode is {q_mode}, expected {expected_q_mode}")
    if probs.shape != (1260, 3) or len(switch_days) != 6:
        raise ValueError(f"{npz_path} has an unexpected shape")
    row = np.arange(len(probs))
    true_p = probs[row, true_idx]
    true_nll = -log_probs[row, true_idx]
    onehot = np.eye(3)[true_idx]
    record = {
        "basin_id": basin_id,
        "seed": seed,
        "arm_id": arm_id,
        "zero_true_probability_days": int(np.sum(true_p == 0.0)),
        "true_probability_below_0_01_days": int(np.sum(true_p < 0.01)),
        "severe_negative_log_probability_days": int(np.sum(true_nll > SEVERE_NLL)),
        "mean_true_negative_log_probability": float(np.mean(true_nll)),
        "multiclass_brier": float(np.mean(np.sum((probs - onehot) ** 2, axis=1))),
    }
    switch_pairs = list(zip(switch_days.tolist(), rotation[1:].tolist()))
    for window in WINDOWS:
        events = _evaluate_events_window(probs, switch_pairs, window)
        record[f"events_passed_w{window}"] = int(
            sum(event["passed"] for event in events)
        )
        for index, event in enumerate(events):
            switch_day = event["switch_day"]
            old_parfc = float(truth_parfc[switch_day - 1])
            new_parfc = float(truth_parfc[switch_day])
            direction = "increase" if new_parfc > old_parfc else "decrease"
            record[f"event{index}_w{window}_pass"] = bool(event["passed"])
            record[f"event{index}_w{window}_start"] = (
                -1 if event["response_start"] is None else int(event["response_start"])
            )
            if window == WINDOWS[0]:
                record[f"event{index}_switch_day"] = switch_day
                record[f"event{index}_new_member"] = event["new_member"]
                record[f"event{index}_direction"] = direction
    return record


def _aggregate_arm(frame: pd.DataFrame) -> dict:
    scored_days = int(len(frame)) * 1260
    result = {
        "tasks": int(len(frame)),
        "scored_days": scored_days,
        "zero_true_probability_days": int(frame["zero_true_probability_days"].sum()),
        "true_probability_below_0_01_days": int(
            frame["true_probability_below_0_01_days"].sum()
        ),
        "severe_negative_log_probability_days": int(
            frame["severe_negative_log_probability_days"].sum()
        ),
        "mean_true_negative_log_probability": float(
            frame["mean_true_negative_log_probability"].mean()
        ),
        "multiclass_brier": float(frame["multiclass_brier"].mean()),
    }
    for window in WINDOWS:
        events_total = int(len(frame)) * 6
        events_passed = int(frame[f"events_passed_w{window}"].sum())
        by_type: dict[str, dict] = {}
        for index in range(6):
            switch_day = int(frame[f"event{index}_switch_day"].iloc[0])
            direction = str(frame[f"event{index}_direction"].iloc[0])
            passed = int(frame[f"event{index}_w{window}_pass"].sum())
            starts = frame.loc[
                frame[f"event{index}_w{window}_pass"],
                f"event{index}_w{window}_start",
            ]
            by_type[f"switch_day_{switch_day}"] = {
                "direction": direction,
                "passed": passed,
                "total": int(len(frame)),
                "pass_rate": passed / len(frame),
                "median_response_start_days_when_passed": (
                    float(starts.median()) if len(starts) else None
                ),
            }
        increase_passed = sum(
            value["passed"] for value in by_type.values()
            if value["direction"] == "increase"
        )
        decrease_passed = sum(
            value["passed"] for value in by_type.values()
            if value["direction"] == "decrease"
        )
        result[f"window_{window}d"] = {
            "events_passed": events_passed,
            "events_total": events_total,
            "event_pass_rate": events_passed / events_total,
            "increase_pass_rate": increase_passed / (3 * len(frame)),
            "decrease_pass_rate": decrease_passed / (3 * len(frame)),
            "by_transition": by_type,
        }
    return result


def _gate_report(arm_summary: dict, gates: dict) -> dict:
    checks = {
        "zero_true_probability_days": (
            arm_summary["zero_true_probability_days"]
            <= gates["zero_true_probability_days_max"]
        ),
        "severe_negative_log_probability_days": (
            arm_summary["severe_negative_log_probability_days"]
            <= gates["severe_negative_log_probability_days_max"]
        ),
        "mean_true_negative_log_probability": (
            arm_summary["mean_true_negative_log_probability"]
            <= gates["mean_true_negative_log_probability_max"]
        ),
        "multiclass_brier": (
            arm_summary["multiclass_brier"] <= gates["multiclass_brier_max"]
        ),
    }
    for window in WINDOWS:
        tier = arm_summary[f"window_{window}d"]
        per_type_ok = all(
            value["pass_rate"] >= gates["per_transition_type_event_pass_rate_min"]
            for value in tier["by_transition"].values()
        )
        checks[f"per_transition_type_pass_rate_w{window}"] = per_type_ok
    checks["probability_quality_all"] = all(
        checks[name]
        for name in (
            "zero_true_probability_days",
            "severe_negative_log_probability_days",
            "mean_true_negative_log_probability",
            "multiclass_brier",
        )
    )
    return checks


def _paired_against_03b(
    frame: pd.DataFrame,
    frozen_root: Path,
) -> dict:
    counts = {
        "events_w30": {"improved": 0, "equal": 0, "worse": 0},
        "multiclass_brier": {"improved": 0, "equal": 0, "worse": 0},
        "mean_true_negative_log_probability": {"improved": 0, "equal": 0, "worse": 0},
        "zero_days_new_total": int(frame["zero_true_probability_days"].sum()),
        "zero_days_baseline_total": 0,
    }
    for record in frame.itertuples(index=False):
        baseline_path = (
            frozen_root / "arms" / record.arm_id / "probs"
            / f"{record.basin_id}_s{record.seed}.npz"
        )
        with np.load(baseline_path, allow_pickle=False) as archive:
            probs = archive["probabilities"]
            log_probs = archive["log_probabilities"]
            true_idx = archive["true_candidate_indices"].astype(np.int64)
            switch_days = archive["switch_days"].astype(np.int64)
            rotation = archive["rotation"].astype(np.int64)
        row = np.arange(len(probs))
        true_p = probs[row, true_idx]
        true_nll = -log_probs[row, true_idx]
        onehot = np.eye(3)[true_idx]
        baseline_brier = float(np.mean(np.sum((probs - onehot) ** 2, axis=1)))
        baseline_nll = float(np.mean(true_nll))
        counts["zero_days_baseline_total"] += int(np.sum(true_p == 0.0))
        baseline_events = sum(
            event["passed"]
            for event in _evaluate_events_window(
                probs,
                list(zip(switch_days.tolist(), rotation[1:].tolist())),
                30,
            )
        )
        for name, new_value, old_value, higher_is_better in (
            ("events_w30", record.events_passed_w30, baseline_events, True),
            ("multiclass_brier", record.multiclass_brier, baseline_brier, False),
            (
                "mean_true_negative_log_probability",
                record.mean_true_negative_log_probability,
                baseline_nll,
                False,
            ),
        ):
            if new_value == old_value:
                counts[name]["equal"] += 1
            elif (new_value > old_value) == higher_is_better:
                counts[name]["improved"] += 1
            else:
                counts[name]["worse"] += 1
    return counts


def summarize(config_path: Path, expected_config_sha256: str) -> dict:
    verified = propq.verify_parameter_path_design90_propq(
        _REPO_ROOT,
        config_path,
        expected_config_sha256,
        require_output_absent=False,
    )
    output_root = _REPO_ROOT / propq.OUTPUT_ROOT
    runner_summary_path = output_root / "runner_summary.json"
    runner_summary = json.loads(runner_summary_path.read_text(encoding="utf-8"))
    if runner_summary.get("execution_status") != "complete":
        raise ValueError("03C execution is not complete; refusing scientific summary")
    if runner_summary.get("config_sha256") != expected_config_sha256:
        raise ValueError("03C runner summary was produced under another configuration")
    registered_implementation = {
        role: entry["sha256"]
        for role, entry in verified.configuration["implementation"].items()
    }
    if runner_summary.get("implementation_hashes") != registered_implementation:
        raise ValueError(
            "the 360-task run did not execute under the frozen implementation"
        )
    frozen_root = _REPO_ROOT / FROZEN_03B_ROOT
    verification_dir = output_root / "verification"
    if verification_dir.exists():
        raise FileExistsError(f"verification already exists: {verification_dir}")

    expected_tasks = {
        (str(row.basin_id), int(row.seed), arm)
        for row in verified.task_table.itertuples(index=False)
        for arm in ("C", "P")
    }
    records = []
    for arm in ("C", "P"):
        for npz_path in sorted((output_root / "arms" / arm / "probs").glob("*.npz")):
            records.append(_task_record(npz_path, propq.EXPECTED_FILTER["q_mode"]))
    frame = pd.DataFrame(records)
    observed_tasks = {
        (row.basin_id, row.seed, row.arm_id)
        for row in frame.itertuples(index=False)
    }
    if observed_tasks != expected_tasks or len(frame) != 360:
        raise ValueError("03C outputs do not cover exactly the registered 360 tasks")

    gates = verified.configuration["decision_gates"]
    arm_summaries = {}
    gate_reports = {}
    paired = {}
    for arm in ("C", "P"):
        arm_frame = frame[frame["arm_id"] == arm].reset_index(drop=True)
        arm_summaries[arm] = _aggregate_arm(arm_frame)
        gate_reports[arm] = _gate_report(arm_summaries[arm], gates)
        paired[arm] = _paired_against_03b(arm_frame, frozen_root)

    summary = {
        "experiment_id": propq.EXPERIMENT_ID,
        "verification_status": "passed",
        "config_sha256": verified.config_sha256,
        "task_count": 360,
        "scored_days_per_arm": 180 * 1260,
        "run_executed_under_frozen_implementation": True,
        "post_execution_implementation_drift": {
            role: value
            for role, value in verified.implementation_hashes.items()
            if role.endswith("_registered") or role.endswith("_post_execution_amended")
        },
        "registered_decision_gates": gates,
        "arm_summary": arm_summaries,
        "gate_report": gate_reports,
        "paired_against_frozen_03b_fixed_q": paired,
        "frozen_03b_root": FROZEN_03B_ROOT.as_posix(),
        "claim_boundary": dict(verified.configuration["claim_boundary"]),
    }
    verification_dir.mkdir(exist_ok=False)
    frame.to_csv(verification_dir / "task_metrics.csv", index=False)
    with (verification_dir / "verification_summary.json").open(
        "x", encoding="utf-8", newline="\n"
    ) as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2, sort_keys=False)
        handle.write("\n")
    return summary


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(propq.CONFIGURATION))
    parser.add_argument("--expected-config-sha256", required=True)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        summary = summarize(Path(arguments.config), arguments.expected_config_sha256)
    except Exception as error:  # noqa: BLE001 - executable must stop cleanly
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
