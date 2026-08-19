"""Independent verifier for the registered 90-basin C/P path design."""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

import numpy as np
import pandas as pd

from camels_switch_confirmation import run_parameter_path_design90 as runner
from camels_switch_confirmation import verify_parameter_path_mechanism as base


_REPO_ROOT = Path(__file__).resolve().parents[2]

DIRECTION_NAMES = {
    (0, 1): "center_to_half",
    (0, 2): "center_to_double",
    (1, 0): "half_to_center",
    (1, 2): "half_to_double",
    (2, 0): "double_to_center",
    (2, 1): "double_to_half",
}
EXPECTED_DIRECTION_NAMES = tuple(DIRECTION_NAMES.values())
EXPECTED_GATE_CONTRACT = {
    "task_count": 360,
    "source_task_count": 180,
    "events_per_arm": 1080,
    "events_per_direction_per_arm": 180,
    "baseline_c_events_passed": 706,
    "p_events_strictly_greater_than_c": True,
    "p_overall_event_pass_rate_min": 0.65,
    "p_direction_event_pass_rate_min": 0.50,
    "maximum_direction_passed_event_decline": 9,
    "p_multiclass_brier_max": 2.0 / 3.0,
    "p_mean_true_negative_log_probability_max": math.log(3.0),
    "p_true_probability_below_0_01_days_max": 1944,
    "p_severe_negative_log_probability_days_max": 0,
    "p_zero_true_probability_days_max": 0,
}


def _direction_rows_by_key(
    direction_summary: Sequence[Mapping],
) -> dict[tuple[str, str], dict]:
    rows: dict[tuple[str, str], dict] = {}
    for value in direction_summary:
        row = dict(value)
        key = (str(row.get("arm_id")), str(row.get("direction")))
        if key in rows:
            raise ValueError("direction summary contains duplicate arm-direction rows")
        rows[key] = row
    expected = {
        (arm_id, direction)
        for arm_id in ("C", "P")
        for direction in EXPECTED_DIRECTION_NAMES
    }
    if set(rows) != expected:
        raise ValueError("direction summary must contain all twelve registered rows")
    for key, row in rows.items():
        if int(row.get("events", -1)) != 180:
            raise ValueError(f"direction {key} must contain exactly 180 events")
        passed = int(row.get("passed", -1))
        if passed < 0 or passed > 180:
            raise ValueError(f"direction {key} has an invalid passed count")
    return rows


def evaluate_design90_gates(
    *,
    verification_passed: bool,
    task_count: int,
    arm_summary: Mapping[str, Mapping],
    direction_summary: Sequence[Mapping],
) -> dict:
    """Evaluate the ten immutable Design90 continuation conditions."""
    if set(arm_summary) != {"C", "P"}:
        raise ValueError("arm summary must contain exactly C and P")
    c = arm_summary["C"]
    p = arm_summary["P"]
    direction_rows = _direction_rows_by_key(direction_summary)
    technical = bool(
        verification_passed
        and int(task_count) == 360
        and int(c.get("task_count", -1)) == 180
        and int(p.get("task_count", -1)) == 180
        and int(c.get("event_count", -1)) == 1080
        and int(p.get("event_count", -1)) == 1080
    )
    c_events = int(c.get("events_passed", -1))
    p_events = int(p.get("events_passed", -1))
    p_event_rate = p_events / 1080.0
    direction_minimum = all(
        int(direction_rows[("P", direction)]["passed"]) / 180.0 >= 0.50
        for direction in EXPECTED_DIRECTION_NAMES
    )
    direction_decline = all(
        int(direction_rows[("P", direction)]["passed"])
        >= int(direction_rows[("C", direction)]["passed"]) - 9
        for direction in EXPECTED_DIRECTION_NAMES
    )
    conditions = {
        "all_360_tasks_and_independent_checks": technical,
        "p_events_strictly_above_reproduced_c_706": bool(
            c_events == 706 and p_events > c_events
        ),
        "p_overall_event_pass_rate_at_least_0_65": bool(p_event_rate >= 0.65),
        "all_p_direction_pass_rates_at_least_0_50": bool(direction_minimum),
        "no_direction_loses_more_than_9_events": bool(direction_decline),
        "p_brier_not_above_c_or_two_thirds": bool(
            float(p.get("multiclass_brier", math.inf))
            <= float(c.get("multiclass_brier", -math.inf))
            and float(p.get("multiclass_brier", math.inf)) <= 2.0 / 3.0
        ),
        "p_mean_negative_log_probability_not_above_c_or_log_three": bool(
            float(p.get("mean_true_negative_log_probability", math.inf))
            <= float(c.get("mean_true_negative_log_probability", -math.inf))
            and float(p.get("mean_true_negative_log_probability", math.inf))
            <= math.log(3.0)
        ),
        "p_true_probability_below_0_01_days_at_most_1944": bool(
            int(p.get("true_probability_below_0_01_days", 1945)) <= 1944
        ),
        "p_severe_negative_log_probability_days_zero": bool(
            int(p.get("severe_negative_log_probability_days", -1)) == 0
        ),
        "p_exact_zero_true_probability_days_zero": bool(
            int(p.get("zero_true_probability_days", -1)) == 0
        ),
    }
    return {
        "conditions": conditions,
        "overall_status": "GO" if all(conditions.values()) else "HOLD",
    }


def _verify_task_records(
    output_root: Path,
    expected_keys: set[tuple[str, int]],
) -> None:
    for arm_id in ("C", "P"):
        path = output_root / "arms" / arm_id / "tasks.csv"
        if not path.is_file():
            raise FileNotFoundError(f"arm {arm_id} task records are missing")
        records = pd.read_csv(path, dtype={"basin_id": str}, keep_default_na=False)
        required = {"basin_id", "seed", "arm_id", "run_status", "truth_clip_count"}
        if not required.issubset(records.columns) or len(records) != 180:
            raise ValueError(f"arm {arm_id} task records are incomplete")
        records["basin_id"] = [
            base._normalize_basin_id(value) for value in records["basin_id"]
        ]
        keys = set(zip(records["basin_id"], records["seed"].astype(int)))
        if (
            keys != expected_keys
            or not (records["arm_id"] == arm_id).all()
            or not (records["run_status"] == "success").all()
            or not (records["truth_clip_count"].astype(int) == 0).all()
        ):
            raise ValueError(f"arm {arm_id} task records are invalid")
        probability_files = {
            value.stem
            for value in (output_root / "arms" / arm_id / "probs").glob("*.npz")
        }
        expected_files = {f"{basin_id}_s{seed}" for basin_id, seed in expected_keys}
        if probability_files != expected_files:
            raise ValueError(f"arm {arm_id} probability file set is incomplete")


def _extended_probability_metrics(
    arrays: Mapping[str, np.ndarray],
) -> tuple[dict, list[dict]]:
    metrics, events = base._probability_metrics(arrays)
    probabilities = np.asarray(arrays["probabilities"], dtype=np.float64)
    logs = np.asarray(arrays["log_probabilities"], dtype=np.float64)
    truth = np.asarray(arrays["true_candidate_indices"], dtype=np.int64)
    indices = np.arange(base.SCORING_START, base.SCORING_STOP)
    scored_truth = truth[indices]
    true_probabilities = probabilities[indices, scored_truth]
    true_negative_logs = -logs[indices, scored_truth]
    metrics.update(
        {
            "true_probability_below_0_01_days": int(
                np.sum(true_probabilities < 0.01)
            ),
            "median_true_negative_log_probability": float(
                np.median(true_negative_logs)
            ),
            "p99_true_negative_log_probability": float(
                np.quantile(true_negative_logs, 0.99)
            ),
            "p999_true_negative_log_probability": float(
                np.quantile(true_negative_logs, 0.999)
            ),
            "maximum_true_negative_log_probability": float(
                np.max(true_negative_logs)
            ),
            "_true_probabilities": true_probabilities,
            "_true_negative_logs": true_negative_logs,
        }
    )
    return metrics, events


def _complete_arm_summary(task_rows: list[dict]) -> dict[str, dict]:
    summary = base._aggregate_task_metrics(task_rows)
    for arm_id in ("C", "P"):
        rows = [row for row in task_rows if row["arm_id"] == arm_id]
        probabilities = np.concatenate([row["_true_probabilities"] for row in rows])
        negative_logs = np.concatenate([row["_true_negative_logs"] for row in rows])
        if len(probabilities) != 194400 or len(negative_logs) != 194400:
            raise ValueError(f"arm {arm_id} must contain 194400 scoring days")
        summary[arm_id].update(
            {
                "true_probability_below_0_01_days": int(
                    np.sum(probabilities < 0.01)
                ),
                "median_true_negative_log_probability": float(
                    np.median(negative_logs)
                ),
                "p99_true_negative_log_probability": float(
                    np.quantile(negative_logs, 0.99)
                ),
                "p999_true_negative_log_probability": float(
                    np.quantile(negative_logs, 0.999)
                ),
                "maximum_true_negative_log_probability": float(
                    np.max(negative_logs)
                ),
            }
        )
    return summary


def _direction_summary(event_rows: list[dict]) -> list[dict]:
    frame = pd.DataFrame(event_rows)
    rows = []
    for arm_id in ("C", "P"):
        for direction in EXPECTED_DIRECTION_NAMES:
            selected = frame[
                (frame["arm_id"] == arm_id) & (frame["direction"] == direction)
            ]
            if len(selected) != 180:
                raise ValueError(
                    f"arm {arm_id} direction {direction} must contain 180 events"
                )
            passed = int(selected["passed"].astype(bool).sum())
            rows.append(
                {
                    "arm_id": arm_id,
                    "direction": direction,
                    "events": 180,
                    "passed": passed,
                    "pass_rate": passed / 180.0,
                }
            )
    return rows


def _paired_task_summary(task_rows: list[dict]) -> list[dict]:
    lookup = {
        (row["arm_id"], row["basin_id"], int(row["seed"])): row
        for row in task_rows
    }
    result = []
    comparisons = (
        ("events_passed", 1.0),
        ("multiclass_brier", -1.0),
        ("mean_true_negative_log_probability", -1.0),
    )
    keys = sorted({(row["basin_id"], int(row["seed"])) for row in task_rows})
    if len(keys) != 180:
        raise ValueError("paired task summary requires 180 task identities")
    for metric, improvement_sign in comparisons:
        differences = np.asarray(
            [
                float(lookup[("P", *key)][metric])
                - float(lookup[("C", *key)][metric])
                for key in keys
            ],
            dtype=np.float64,
        )
        signed = improvement_sign * differences
        result.append(
            {
                "metric": metric,
                "improved": int(np.sum(signed > 0.0)),
                "equal": int(np.sum(signed == 0.0)),
                "worse": int(np.sum(signed < 0.0)),
                "median_p_minus_c": float(np.median(differences)),
            }
        )
    return result


def verify_parameter_path_design90(
    config_path: str | Path,
    expected_config_sha256: str,
) -> dict:
    """Verify a complete 360-task run and atomically write all reports."""
    root = _REPO_ROOT.resolve()
    configuration = Path(config_path)
    if not configuration.is_absolute():
        configuration = root / configuration
    configuration = configuration.resolve()
    if not configuration.is_file():
        raise FileNotFoundError(f"configuration is missing: {configuration}")
    try:
        configuration.relative_to(root)
    except ValueError as error:
        raise ValueError("configuration path must be inside the repository root") from error
    observed_config_sha256 = base.sha256_file(configuration)
    if observed_config_sha256 != str(expected_config_sha256):
        raise ValueError("configuration SHA-256 changed")
    config = json.loads(configuration.read_text(encoding="utf-8"))
    if not isinstance(config, Mapping):
        raise ValueError("configuration root must be an object")
    if config.get("configuration_status") != runner.CONFIGURATION_STATUS:
        raise ValueError("configuration_status changed")
    if tuple(config.get("arms", ())) != base.EXPECTED_ARMS:
        raise ValueError("Design90 arms must be exactly C and P")
    if config.get("decision_gates") != EXPECTED_GATE_CONTRACT:
        raise ValueError("registered Design90 decision gates changed")
    runtime_contract = base._verify_runtime_contract(config)
    inputs = config.get("inputs")
    outputs = config.get("outputs")
    if not isinstance(inputs, Mapping) or not isinstance(outputs, Mapping):
        raise ValueError("configuration inputs and outputs must be mappings")
    implementation_hashes, registered_input_hashes = base._verify_registered_files(
        root, config
    )
    parent_hashes = runner._verify_parent_mechanism(root, config)
    basin_ids, _, basin_list_hash = runner._load_basin_list(root, config)
    registered_input_hashes.update(parent_hashes)
    registered_input_hashes["basin_list_sha256"] = basin_list_hash
    output_root = base._repository_path(root, outputs.get("root"), "output root").resolve()
    if not output_root.is_dir():
        raise FileNotFoundError(f"completed output root is missing: {output_root}")
    verification_root = output_root / "verification"
    temporary_root = output_root / "verification.tmp"
    if verification_root.exists() or temporary_root.exists():
        raise FileExistsError("verification output or temporary directory already exists")
    task_path = base._repository_path(root, inputs.get("task_table"), "task table")
    task_hash = base.sha256_file(task_path)
    if task_hash != str(inputs.get("task_table_sha256")):
        raise ValueError("task table SHA-256 changed")
    tasks = runner.validate_design90_task_frame(
        pd.read_csv(
            task_path,
            dtype={"basin_id": str, "arm_id": str},
            keep_default_na=False,
        ),
        basin_ids,
    )
    expected_keys = set(zip(tasks["basin_id"], tasks["seed"]))
    initial_moments = base._load_initial_moment_manifest(root, inputs, expected_keys)
    runner_summary_path = output_root / "runner_summary.json"
    if not runner_summary_path.is_file():
        raise FileNotFoundError("runner summary is missing")
    runner_summary = json.loads(runner_summary_path.read_text(encoding="utf-8"))
    if (
        runner_summary.get("execution_status") != "complete"
        or runner_summary.get("scientific_aggregation_status")
        != "ready_for_independent_design90_verification"
        or runner_summary.get("experiment_id") != config.get("experiment_id")
        or runner_summary.get("config_sha256") != observed_config_sha256
        or runner_summary.get("n_source_tasks") != 180
        or runner_summary.get("n_arms") != 2
        or runner_summary.get("n_tasks_planned") != 360
        or runner_summary.get("n_submitted") != 360
        or runner_summary.get("run_status_counts") != {"success": 360}
        or runner_summary.get("arms") != config.get("arms")
        or runner_summary.get("runtime") != runtime_contract
        or runner_summary.get("implementation_hashes") != implementation_hashes
        or runner_summary.get("registered_input_hashes") != registered_input_hashes
    ):
        raise ValueError("runner summary is incomplete or mismatched")
    _verify_task_records(output_root, expected_keys)

    task_rows: list[dict] = []
    event_rows: list[dict] = []
    maximum_source_probability_difference = 0.0
    maximum_source_log_probability_difference = 0.0
    path_maxima: dict[str, float] = {}
    for task in tasks.itertuples(index=False):
        key = (str(task.basin_id), int(task.seed))
        source_path = base._repository_path(
            root, task.source_probability_path, f"source task {key}"
        )
        if (
            not source_path.is_file()
            or source_path.stat().st_size != int(task.source_probability_bytes)
            or base.sha256_file(source_path) != str(task.source_probability_sha256)
        ):
            raise ValueError(f"registered source probability file changed for {key}")
        source_arrays = base._load_npz(source_path)
        arm_arrays = {
            arm_id: base._load_npz(
                output_root
                / "arms"
                / arm_id
                / "probs"
                / f"{task.basin_id}_s{task.seed}.npz"
            )
            for arm_id in ("C", "P")
        }
        base._require_fields(source_arrays, base.SOURCE_EXACT_FIELDS, "source")
        base._verify_probability_arrays(source_arrays, "source")
        for arm_id, arrays in arm_arrays.items():
            base._require_fields(arrays, base.SOURCE_EXACT_FIELDS, f"arm {arm_id}")
            base._require_fields(arrays, ("truth_parfc",), f"arm {arm_id}")
            base._verify_probability_arrays(arrays, f"arm {arm_id}")
            if (
                base._normalize_basin_id(base._scalar(arrays, "basin_id")) != key[0]
                or int(base._scalar(arrays, "seed")) != key[1]
                or int(base._scalar(arrays, "truth_clip_count")) != 0
            ):
                raise ValueError(f"arm {arm_id} identity or truth clipping changed")
        expected_metadata = {
            "C": ("full", "conservative_parfc"),
            "P": ("pairwise_path_postcollapse", "conservative_parfc"),
        }
        for arm_id, (interaction, mapping) in expected_metadata.items():
            if (
                base._scalar(arm_arrays[arm_id], "arm_id") != arm_id
                or base._scalar(arm_arrays[arm_id], "state_interaction_mode")
                != interaction
                or base._scalar(arm_arrays[arm_id], "parameter_state_mapping")
                != mapping
            ):
                raise ValueError(f"arm {arm_id} method metadata changed")
        for name in base.SOURCE_EXACT_FIELDS:
            if not np.array_equal(source_arrays[name], arm_arrays["C"][name]):
                raise ValueError(f"arm C source shared field {name} differs")
        source_probability_difference = base._maximum_absolute_difference(
            source_arrays["probabilities"], arm_arrays["C"]["probabilities"]
        )
        source_log_difference = base._assert_log_arrays_close(
            source_arrays["log_probabilities"],
            arm_arrays["C"]["log_probabilities"],
            tolerance=base.PROBABILITY_TOLERANCE,
            label="arm C source stable log probabilities",
        )
        if source_probability_difference > base.PROBABILITY_TOLERANCE:
            raise ValueError("arm C source ordinary probabilities differ")
        maximum_source_probability_difference = max(
            maximum_source_probability_difference, source_probability_difference
        )
        maximum_source_log_probability_difference = max(
            maximum_source_log_probability_difference, source_log_difference
        )
        if base.evaluate_events_independently(
            source_arrays["probabilities"],
            source_arrays["switch_days"],
            source_arrays["true_candidate_indices"],
        ) != base.evaluate_events_independently(
            arm_arrays["C"]["probabilities"],
            arm_arrays["C"]["switch_days"],
            arm_arrays["C"]["true_candidate_indices"],
        ):
            raise ValueError("arm C source event decisions differ")
        for name in base.CROSS_ARM_EXACT_FIELDS:
            if not np.array_equal(arm_arrays["C"][name], arm_arrays["P"][name]):
                raise ValueError(f"cross-arm shared field {name} differs")
        derived_truth = base._derive_true_candidate_indices(
            arm_arrays["C"]["candidate_parameter_names"],
            arm_arrays["C"]["candidate_parameter_vectors"],
            arm_arrays["C"]["truth_parfc"],
            stage_days=int(base._scalar(arm_arrays["C"], "stage_days")),
        )
        for arm_id in ("C", "P"):
            base._require_bitwise_equal(
                arm_arrays[arm_id]["true_candidate_indices"],
                derived_truth,
                f"arm {arm_id} independently derived truth labels",
            )
            if not np.array_equal(
                np.asarray(arm_arrays[arm_id]["switch_days"], dtype=np.int64),
                np.arange(180, 1260, 180, dtype=np.int64),
            ):
                raise ValueError(f"arm {arm_id} switch days changed")
            if not np.array_equal(
                np.asarray(arm_arrays[arm_id]["rotation"], dtype=np.int64),
                base.TRUTH_STAGE_SEQUENCE,
            ):
                raise ValueError(f"arm {arm_id} rotation changed")
        task_path_maxima = base._verify_path_arrays(
            arm_arrays["P"], initial_moments[key]
        )
        for name, value in task_path_maxima.items():
            path_maxima[name] = max(path_maxima.get(name, 0.0), float(value))
        for arm_id in ("C", "P"):
            metrics, events = _extended_probability_metrics(arm_arrays[arm_id])
            task_rows.append(
                {"arm_id": arm_id, "basin_id": key[0], "seed": key[1], **metrics}
            )
            for event in events:
                direction_key = (int(event["old_member"]), int(event["new_member"]))
                if direction_key not in DIRECTION_NAMES:
                    raise ValueError("event direction is outside the registered six")
                event_rows.append(
                    {
                        "arm_id": arm_id,
                        "basin_id": key[0],
                        "seed": key[1],
                        "switch_day": int(event["switch_day"]),
                        "direction": DIRECTION_NAMES[direction_key],
                        "passed": bool(event["passed"]),
                        "response_start": int(event["response_start"]),
                    }
                )
    if len(task_rows) != 360 or len(event_rows) != 2160:
        raise ValueError("verified metric rows must contain 360 tasks and 2160 events")
    arm_summary = _complete_arm_summary(task_rows)
    directions = _direction_summary(event_rows)
    pairs = _paired_task_summary(task_rows)
    decision = evaluate_design90_gates(
        verification_passed=True,
        task_count=len(task_rows),
        arm_summary=arm_summary,
        direction_summary=directions,
    )
    report = {
        "experiment_id": config.get("experiment_id"),
        "configuration_status": config.get("configuration_status"),
        "config_sha256": observed_config_sha256,
        "task_table_sha256": task_hash,
        "implementation_hashes": implementation_hashes,
        "runtime": runtime_contract,
        "registered_input_hashes": registered_input_hashes,
        "verification_status": "passed",
        "task_count": 360,
        "source_task_count": 180,
        "scoring_slice": {
            "start_index_inclusive": 180,
            "stop_index_exclusive": 1260,
            "days_per_task": 1080,
            "days_per_arm": 194400,
        },
        "maximum_source_probability_absolute_difference": (
            maximum_source_probability_difference
        ),
        "maximum_source_log_probability_absolute_difference": (
            maximum_source_log_probability_difference
        ),
        "path_reconstruction_diagnostics": path_maxima,
        "arm_summary": arm_summary,
        "direction_summary": directions,
        "paired_task_summary": pairs,
        "decision_gate": decision,
        "claim_scope": "reused_design90_basins_and_design_seeds_only_not_validation",
    }
    public_task_rows = [
        {key: value for key, value in row.items() if not key.startswith("_")}
        for row in task_rows
    ]
    temporary_root.mkdir(exist_ok=False)
    try:
        pd.DataFrame(public_task_rows).to_csv(
            temporary_root / "task_metrics.csv", index=False
        )
        pd.DataFrame(event_rows).to_csv(
            temporary_root / "event_metrics.csv", index=False
        )
        pd.DataFrame(directions).to_csv(
            temporary_root / "direction_summary.csv", index=False
        )
        pd.DataFrame(pairs).to_csv(
            temporary_root / "paired_task_summary.csv", index=False
        )
        with (temporary_root / "verification_summary.json").open(
            "x", encoding="utf-8"
        ) as handle:
            json.dump(report, handle, indent=2, sort_keys=True)
            handle.write("\n")
        temporary_root.rename(verification_root)
    except Exception:
        raise
    return report


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--expected-config-sha256", required=True)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        report = verify_parameter_path_design90(
            arguments.config,
            arguments.expected_config_sha256,
        )
    except Exception as error:  # noqa: BLE001 - executable must stop cleanly
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
