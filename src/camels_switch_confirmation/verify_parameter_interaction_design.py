"""Independent verifier for the registered three-arm parFC design diagnostic."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd


SHARED_ARRAY_NAMES = (
    "truth_q",
    "observations",
    "switch_days",
    "true_candidate_indices",
    "candidate_parameter_names",
    "candidate_parameter_vectors",
    "truth_slz_lognormal_sigma",
    "observation_sigma",
    "truth_clip_count",
    "rain",
    "pet",
    "temperature",
    "rotation",
    "stage_days",
    "basin_id",
    "seed",
    "filter_process_variance_scale",
    "filter_process_covariance_structure",
    "filter_q_mode",
    "filter_q_state_multiplier",
    "filter_observation_variance_multiplier",
    "filter_process_lower_groundwater_variance",
)


@dataclass(frozen=True)
class ExpectedDesignCounts:
    """Configuration-derived task and event counts for one paired design."""

    basin_count: int
    seed_count: int
    arm_count: int
    events_per_task: int
    tasks_per_arm: int
    total_tasks: int
    events_per_arm: int
    total_events: int
    events_per_direction_per_arm: int


def expected_design_counts(
    *,
    basin_count: int,
    seed_count: int,
    arm_count: int,
    events_per_task: int,
) -> ExpectedDesignCounts:
    """Return the exact registered counts, rejecting non-positive inputs."""
    values = {
        "basin_count": basin_count,
        "seed_count": seed_count,
        "arm_count": arm_count,
        "events_per_task": events_per_task,
    }
    for label, value in values.items():
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ValueError(f"{label} must be a positive integer")
    tasks_per_arm = basin_count * seed_count
    events_per_arm = tasks_per_arm * events_per_task
    return ExpectedDesignCounts(
        basin_count=basin_count,
        seed_count=seed_count,
        arm_count=arm_count,
        events_per_task=events_per_task,
        tasks_per_arm=tasks_per_arm,
        total_tasks=tasks_per_arm * arm_count,
        events_per_arm=events_per_arm,
        total_events=events_per_arm * arm_count,
        events_per_direction_per_arm=tasks_per_arm,
    )


def evaluate_registered_decision_gates(
    arm_summary: pd.DataFrame,
    direction_summary: pd.DataFrame,
    gate_config: Mapping | None,
) -> dict:
    """Evaluate relative replication and optional absolute freeze-review gates."""
    required_arm_columns = {
        "arm_id",
        "events_passed",
        "multiclass_brier",
        "true_negative_log_probability",
    }
    required_direction_columns = {"arm_id", "events", "passed", "pass_rate"}
    if not required_arm_columns.issubset(arm_summary.columns):
        raise ValueError("arm summary lacks decision-gate columns")
    if not required_direction_columns.issubset(direction_summary.columns):
        raise ValueError("direction summary lacks decision-gate columns")
    arm_lookup = arm_summary.set_index("arm_id")
    if not {"A", "B", "C"}.issubset(arm_lookup.index):
        raise ValueError("decision gates require arms A, B, and C")
    c_directions = direction_summary[direction_summary["arm_id"] == "C"]
    if len(c_directions) != 6:
        raise ValueError("decision gates require six arm-C directions")
    c_event_total = int(c_directions["events"].sum())
    if c_event_total <= 0:
        raise ValueError("arm-C event count must be positive")
    c_event_passed = int(arm_lookup.loc["C", "events_passed"])
    c_overall_rate = float(c_event_passed / c_event_total)
    c_minimum_direction_rate = float(c_directions["pass_rate"].min())
    scale_replication = bool(
        arm_lookup.loc["C", "events_passed"]
        > arm_lookup.loc["A", "events_passed"]
        and arm_lookup.loc["C", "multiclass_brier"]
        <= arm_lookup.loc["A", "multiclass_brier"]
        and arm_lookup.loc["C", "true_negative_log_probability"]
        <= arm_lookup.loc["A", "true_negative_log_probability"]
    )
    result = {
        "scale_replication_gate_passed": scale_replication,
        "c_overall_event_pass_rate": c_overall_rate,
        "c_minimum_direction_pass_rate": c_minimum_direction_rate,
        "c_multiclass_brier": float(arm_lookup.loc["C", "multiclass_brier"]),
        "c_true_negative_log_probability": float(
            arm_lookup.loc["C", "true_negative_log_probability"]
        ),
        "validation_freeze_eligibility_gate_registered": False,
        "validation_freeze_eligibility_gate_passed": None,
    }
    registered = dict(gate_config or {}).get("validation_freeze_eligibility")
    if registered is None:
        return result
    if not isinstance(registered, Mapping):
        raise ValueError("validation freeze eligibility gate must be a mapping")
    thresholds = {
        "c_overall_event_pass_rate_min": float(
            registered["c_overall_event_pass_rate_min"]
        ),
        "c_minimum_direction_pass_rate_min": float(
            registered["c_minimum_direction_pass_rate_min"]
        ),
        "c_multiclass_brier_max": float(
            registered["c_multiclass_brier_max"]
        ),
        "c_true_negative_log_probability_max": float(
            registered["c_true_negative_log_probability_max"]
        ),
    }
    requires_scale = bool(registered.get("requires_scale_replication", True))
    freeze_eligible = bool(
        (scale_replication or not requires_scale)
        and c_overall_rate >= thresholds["c_overall_event_pass_rate_min"]
        and c_minimum_direction_rate
        >= thresholds["c_minimum_direction_pass_rate_min"]
        and float(arm_lookup.loc["C", "multiclass_brier"])
        <= thresholds["c_multiclass_brier_max"]
        and float(arm_lookup.loc["C", "true_negative_log_probability"])
        <= thresholds["c_true_negative_log_probability_max"]
    )
    result.update(
        {
            "validation_freeze_eligibility_gate_registered": True,
            "validation_freeze_eligibility_gate_passed": freeze_eligible,
            "validation_freeze_eligibility_thresholds": thresholds,
        }
    )
    return result


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def compute_probability_metrics(
    probabilities: np.ndarray,
    true_candidate_indices: np.ndarray,
    stable_start: int = 180,
    log_probabilities: np.ndarray | None = None,
) -> dict:
    """Compute multiclass Brier and true-candidate log scores."""
    values = np.asarray(probabilities, dtype=np.float64)
    truth = np.asarray(true_candidate_indices, dtype=np.int64)
    if values.ndim != 2 or values.shape[1] != 3 or truth.shape != (len(values),):
        raise ValueError("probabilities and true-candidate indices have invalid shapes")
    if not np.all(np.isfinite(values)):
        raise ValueError("probabilities contain non-finite values")
    if np.max(np.abs(values.sum(axis=1) - 1.0)) > 1e-12:
        raise ValueError("probabilities do not sum to one")
    if np.any(values < 0.0) or np.any(values > 1.0):
        raise ValueError("probabilities fall outside [0,1]")
    if np.any((truth < 0) | (truth >= 3)):
        raise ValueError("true-candidate indices fall outside the candidate bank")
    scoring = slice(int(stable_start), len(values))
    scored_probabilities = values[scoring]
    scored_truth = truth[scoring]
    if len(scored_probabilities) == 0:
        raise ValueError("stable scoring interval is empty")
    target = np.eye(3, dtype=np.float64)[scored_truth]
    brier = float(np.mean(np.sum((scored_probabilities - target) ** 2, axis=1)))
    true_probability = scored_probabilities[
        np.arange(len(scored_probabilities)), scored_truth
    ]
    if log_probabilities is None:
        true_log_probability = np.log(
            np.maximum(true_probability, np.finfo(np.float64).tiny)
        )
    else:
        logs = np.asarray(log_probabilities, dtype=np.float64)
        if logs.shape != values.shape or not np.all(np.isfinite(logs)):
            raise ValueError("log probabilities have invalid shape or values")
        if np.max(np.abs(np.logaddexp.reduce(logs, axis=1))) > 1e-12:
            raise ValueError("log probabilities are not normalized")
        if np.max(np.abs(np.exp(logs) - values)) > 1e-12:
            raise ValueError("probabilities and log probabilities are inconsistent")
        scored_logs = logs[scoring]
        true_log_probability = scored_logs[
            np.arange(len(scored_logs)), scored_truth
        ]
    negative_log_probability = float(np.mean(-true_log_probability))
    return {
        "multiclass_brier": brier,
        "true_negative_log_probability": negative_log_probability,
    }


def evaluate_events_independently(
    probabilities: np.ndarray,
    switch_days: np.ndarray,
    true_candidate_indices: np.ndarray,
    response_window_days: int = 30,
    consecutive_days: int = 5,
) -> list[dict]:
    """Recompute the six registered event decisions without runner helpers."""
    values = np.asarray(probabilities, dtype=np.float64)
    switches = np.asarray(switch_days, dtype=np.int64)
    truth = np.asarray(true_candidate_indices, dtype=np.int64)
    if truth.shape != (len(values),):
        raise ValueError("true-candidate indices do not match probability days")
    events = []
    for switch_day in switches:
        day = int(switch_day)
        if day < 0 or day >= len(values):
            raise ValueError("switch day falls outside probability days")
        new_index = int(truth[day])
        old_index = int(truth[day - 1]) if day else new_index
        passed = False
        response_start = -1
        final_start = min(day + response_window_days, len(values)) - consecutive_days
        for start in range(day, final_start + 1):
            block = values[start : start + consecutive_days]
            other = np.delete(block, new_index, axis=1)
            if np.all(block[:, new_index] > 0.5) and np.all(
                block[:, new_index, None] - other >= 0.1
            ):
                passed = True
                response_start = start - day
                break
        events.append(
            {
                "switch_day": day,
                "old_member": old_index,
                "new_member": new_index,
                "direction": f"{old_index}->{new_index}",
                "passed": passed,
                "response_start": response_start,
            }
        )
    return events


def verify_cross_arm_arrays(arms: Mapping[str, Mapping[str, np.ndarray]]) -> None:
    """Require the truth, observations, candidates, and noise to be exact."""
    if tuple(arms) != ("A", "B", "C"):
        raise ValueError("cross-arm task must contain arms A, B, and C in order")
    reference = arms["A"]
    for name in SHARED_ARRAY_NAMES:
        if name not in reference:
            raise ValueError(f"arm A lacks required array {name}")
        for arm_id in ("B", "C"):
            if name not in arms[arm_id]:
                raise ValueError(f"arm {arm_id} lacks required array {name}")
            if not np.array_equal(reference[name], arms[arm_id][name]):
                raise ValueError(f"{name} differs across arms")
    expected_metadata = {
        "A": ("parameter_grouped", "legacy_projection"),
        "B": ("full", "legacy_projection"),
        "C": ("full", "conservative_parfc"),
    }
    for arm_id, (interaction_mode, mapping_mode) in expected_metadata.items():
        arrays = arms[arm_id]
        if str(arrays.get("arm_id", np.array("")).item()) != arm_id:
            raise ValueError(f"arm {arm_id} identity metadata changed")
        if str(arrays.get("state_interaction_mode", np.array("")).item()) != interaction_mode:
            raise ValueError(f"arm {arm_id} state interaction metadata changed")
        if str(arrays.get("parameter_state_mapping", np.array("")).item()) != mapping_mode:
            raise ValueError(f"arm {arm_id} parameter mapping metadata changed")


def _load_npz(path: Path) -> dict[str, np.ndarray]:
    if not path.is_file():
        raise FileNotFoundError(f"task probability file is missing: {path}")
    with np.load(path, allow_pickle=False) as arrays:
        return {name: arrays[name].copy() for name in arrays.files}


def _verify_registered_files(repo_root: Path, config: Mapping) -> dict:
    """Independently rehash all registered input and implementation artifacts."""
    observed = {}
    inputs = config["inputs"]
    selection = config["design_selection"]
    pairs = (
        (inputs["parameter_table"], inputs["parameter_table_sha256"], "parameter_table"),
        (inputs["g1_precheck_table"], inputs["g1_precheck_table_sha256"], "g1_precheck_table"),
        (inputs["forcing_coverage_table"], inputs["forcing_coverage_table_sha256"], "forcing_coverage_table"),
        (inputs["raw_input_manifest"], inputs["raw_input_manifest_sha256"], "raw_input_manifest"),
        (selection["basin_list"], selection["basin_list_sha256"], "basin_list"),
    )
    for relative, expected, label in pairs:
        path = repo_root / relative
        digest = sha256_file(path)
        if digest != expected:
            raise ValueError(f"registered {label} SHA-256 changed")
        observed[f"{label}_sha256"] = digest
    manifest = pd.read_csv(repo_root / inputs["raw_input_manifest"], keep_default_na=False)
    for row in manifest.itertuples(index=False):
        path = repo_root / row.relative_path
        if path.stat().st_size != int(row.bytes) or sha256_file(path) != str(row.sha256):
            raise ValueError(f"registered raw input changed: {row.relative_path}")
    for label, entry in config["implementation"].items():
        digest = sha256_file(repo_root / entry["path"])
        if digest != entry["sha256"]:
            raise ValueError(f"registered implementation changed: {label}")
        observed[f"implementation:{label}"] = digest
    return observed


def verify_design(
    output_root: str | Path,
    config_path: str | Path,
    expected_config_sha256: str,
) -> dict:
    """Verify one complete registered diagnostic and write a new report directory."""
    configuration = Path(config_path).resolve()
    repo_root = configuration.parents[3]
    if sha256_file(configuration) != expected_config_sha256:
        raise ValueError("configuration SHA-256 changed")
    config = json.loads(configuration.read_text(encoding="utf-8"))
    registered_hashes = _verify_registered_files(repo_root, config)
    basin_frame = pd.read_csv(
        repo_root / config["design_selection"]["basin_list"],
        dtype={"basin_id": str},
    )
    basin_ids = basin_frame["basin_id"].str.zfill(8).tolist()
    seeds = [int(value) for value in config["seeds"]["design"]]
    registered_basin_count = int(config["design_selection"]["basin_count"])
    arm_ids = [str(arm["arm_id"]) for arm in config["arms"]]
    rotation = [int(value) for value in config["truth"]["rotation"]]
    registered_directions = [
        f"{old}->{new}" for old, new in zip(rotation[:-1], rotation[1:])
    ]
    if (
        len(basin_ids) != registered_basin_count
        or len(set(basin_ids)) != registered_basin_count
        or seeds != [0, 1]
    ):
        raise ValueError(
            "registered design basin count, unique basins, or seeds [0,1] changed"
        )
    if arm_ids != ["A", "B", "C"]:
        raise ValueError("registered design arms must be exactly A, B, and C")
    if len(registered_directions) != 6 or len(set(registered_directions)) != 6:
        raise ValueError(
            "registered rotation must contain exactly six distinct directed switches"
        )
    counts = expected_design_counts(
        basin_count=registered_basin_count,
        seed_count=len(seeds),
        arm_count=len(arm_ids),
        events_per_task=len(registered_directions),
    )
    output = Path(output_root).resolve()
    expected_output = (repo_root / config["outputs"]["root"]).resolve()
    if output != expected_output or not output.is_dir():
        raise ValueError("completed output root differs from configuration")
    root_summary = json.loads((output / "runner_summary.json").read_text(encoding="utf-8"))
    if root_summary.get("execution_status") != "complete":
        raise ValueError("runner did not complete every registered arm")
    if (
        root_summary.get("experiment_id") != config["experiment_id"]
        or root_summary.get("config_sha256") != expected_config_sha256
        or root_summary.get("n_arms_started") != counts.arm_count
        or root_summary.get("n_tasks_planned") != counts.total_tasks
    ):
        raise ValueError("runner root summary identity or counts changed")
    expected_task_keys = {(basin_id, seed) for basin_id in basin_ids for seed in seeds}
    for arm in config["arms"]:
        arm_id = arm["arm_id"]
        arm_root = output / "arms" / arm_id
        arm_summary = json.loads(
            (arm_root / "g2_summary.json").read_text(encoding="utf-8")
        )
        if (
            arm_summary.get("execution_status") != "complete"
            or arm_summary.get("config_sha256") != expected_config_sha256
            or arm_summary.get("arm_id") != arm_id
            or arm_summary.get("n_tasks") != counts.tasks_per_arm
            or arm_summary.get("n_success") != counts.tasks_per_arm
            or arm_summary.get("n_failed") != 0
            or arm_summary.get("state_interaction_mode") != arm["interaction_mode"]
            or arm_summary.get("parameter_state_mapping")
            != arm["parameter_state_mapping"]
        ):
            raise ValueError(f"arm {arm_id} summary is incomplete or mismatched")
        runner_records = pd.read_csv(
            arm_root / "g2_events.csv",
            dtype={"basin_id": str},
            keep_default_na=False,
        )
        runner_records["basin_id"] = runner_records["basin_id"].str.zfill(8)
        observed_keys = set(
            zip(runner_records["basin_id"], runner_records["seed"].astype(int))
        )
        if (
            len(runner_records) != counts.tasks_per_arm
            or observed_keys != expected_task_keys
            or not (runner_records["run_status"] == "success").all()
            or not (runner_records["truth_clip_count"].astype(int) == 0).all()
        ):
            raise ValueError(f"arm {arm_id} task records are incomplete or invalid")
    reference_config = config["legacy_reference"]
    reference_manifest_path = repo_root / reference_config["manifest"]
    if sha256_file(reference_manifest_path) != reference_config["manifest_sha256"]:
        raise ValueError("legacy reference manifest SHA-256 changed")
    reference_manifest = pd.read_csv(
        reference_manifest_path,
        dtype={"basin_id": str},
    )
    reference_manifest["basin_id"] = reference_manifest["basin_id"].str.zfill(8)
    reference_lookup = {
        (row.basin_id, int(row.seed)): row
        for row in reference_manifest.itertuples(index=False)
    }
    if (
        len(reference_lookup) != counts.tasks_per_arm
        or set(reference_lookup) != expected_task_keys
    ):
        raise ValueError("legacy reference manifest task keys changed")

    task_rows = []
    event_rows = []
    maximum_probability_sum_error = 0.0
    maximum_legacy_probability_difference = 0.0
    for basin_id in basin_ids:
        for seed in seeds:
            arm_arrays = {
                arm_id: _load_npz(
                    output / "arms" / arm_id / "probs" / f"{basin_id}_s{seed}.npz"
                )
                for arm_id in ("A", "B", "C")
            }
            verify_cross_arm_arrays(arm_arrays)
            expected_truth = np.repeat(
                np.asarray(config["truth"]["rotation"], dtype=np.int64),
                int(config["truth"]["stage_days"]),
            )
            for arm_id, arrays in arm_arrays.items():
                if not np.array_equal(arrays["true_candidate_indices"], expected_truth):
                    raise ValueError("true-candidate indices differ from registered rotation")
                if not np.array_equal(
                    arrays["rotation"], np.asarray(config["truth"]["rotation"])
                ) or int(arrays["stage_days"].item()) != int(
                    config["truth"]["stage_days"]
                ):
                    raise ValueError("task stage metadata differs from registered rotation")
                if str(arrays["basin_id"].item()).zfill(8) != basin_id or int(
                    arrays["seed"].item()
                ) != seed:
                    raise ValueError("task basin or seed metadata changed")
                if int(arrays["truth_clip_count"].item()) != 0:
                    raise ValueError("truth clipping occurred")
            for arm_id, arrays in arm_arrays.items():
                probabilities = np.asarray(arrays["probabilities"], dtype=np.float64)
                truth = np.asarray(arrays["true_candidate_indices"], dtype=np.int64)
                if probabilities.shape != (1260, 3):
                    raise ValueError("registered task probability shape changed")
                probability_error = float(
                    np.max(np.abs(probabilities.sum(axis=1) - 1.0))
                )
                maximum_probability_sum_error = max(
                    maximum_probability_sum_error, probability_error
                )
                if "log_probabilities" not in arrays:
                    raise ValueError("registered task lacks stable log probabilities")
                metrics = compute_probability_metrics(
                    probabilities,
                    truth,
                    log_probabilities=arrays["log_probabilities"],
                )
                events = evaluate_events_independently(
                    probabilities,
                    arrays["switch_days"],
                    truth,
                )
                task_rows.append(
                    {
                        "arm_id": arm_id,
                        "basin_id": basin_id,
                        "seed": seed,
                        "events_passed": sum(event["passed"] for event in events),
                        **metrics,
                    }
                )
                for event_index, event in enumerate(events):
                    event_rows.append(
                        {
                            "arm_id": arm_id,
                            "basin_id": basin_id,
                            "seed": seed,
                            "event_index": event_index,
                            **event,
                        }
                    )

            reference_row = reference_lookup[(basin_id, seed)]
            reference_path = repo_root / reference_row.relative_path
            if reference_path.stat().st_size != int(reference_row.bytes) or \
               sha256_file(reference_path) != str(reference_row.sha256):
                raise ValueError("legacy task reference changed")
            reference_arrays = _load_npz(reference_path)
            for name in ("truth_q", "observations", "switch_days"):
                if not np.array_equal(arm_arrays["A"][name], reference_arrays[name]):
                    raise ValueError(f"arm A {name} differs from legacy reference")
            probability_difference = float(
                np.max(np.abs(
                    arm_arrays["A"]["probabilities"] - reference_arrays["probabilities"]
                ))
            )
            maximum_legacy_probability_difference = max(
                maximum_legacy_probability_difference, probability_difference
            )
            if probability_difference > float(reference_config["probability_absolute_tolerance"]):
                raise ValueError("arm A probabilities differ from legacy reference")
            reference_truth = np.repeat(
                np.asarray(config["truth"]["rotation"], dtype=np.int64),
                int(config["truth"]["stage_days"]),
            )
            reference_events = evaluate_events_independently(
                reference_arrays["probabilities"],
                reference_arrays["switch_days"],
                reference_truth,
            )
            arm_a_events = evaluate_events_independently(
                arm_arrays["A"]["probabilities"],
                arm_arrays["A"]["switch_days"],
                arm_arrays["A"]["true_candidate_indices"],
            )
            if [
                (event["passed"], event["response_start"])
                for event in arm_a_events
            ] != [
                (event["passed"], event["response_start"])
                for event in reference_events
            ]:
                raise ValueError("arm A event decisions differ from legacy reference")

    tasks = pd.DataFrame(task_rows)
    events = pd.DataFrame(event_rows)
    if len(tasks) != counts.total_tasks or len(events) != counts.total_events:
        raise ValueError(
            "verified task or event count differs from the registered design"
        )
    task_counts = tasks.groupby("arm_id").size().to_dict()
    event_counts = events.groupby("arm_id").size().to_dict()
    expected_task_counts = {
        arm_id: counts.tasks_per_arm for arm_id in arm_ids
    }
    expected_event_counts = {
        arm_id: counts.events_per_arm for arm_id in arm_ids
    }
    if (
        task_counts != expected_task_counts
        or event_counts != expected_event_counts
    ):
        raise ValueError("per-arm task or event counts changed")
    arm_summary = tasks.groupby("arm_id", sort=True).agg(
        task_count=("basin_id", "size"),
        events_passed=("events_passed", "sum"),
        multiclass_brier=("multiclass_brier", "mean"),
        true_negative_log_probability=("true_negative_log_probability", "mean"),
    ).reset_index()
    direction_summary = events.groupby(["arm_id", "direction"], sort=True).agg(
        events=("passed", "size"),
        passed=("passed", "sum"),
    ).reset_index()
    direction_summary["pass_rate"] = (
        direction_summary["passed"] / direction_summary["events"]
    )
    expected_directions = set(registered_directions)
    for arm_id in arm_ids:
        arm_directions = direction_summary[direction_summary["arm_id"] == arm_id]
        if (
            set(arm_directions["direction"]) != expected_directions
            or not (
                arm_directions["events"]
                == counts.events_per_direction_per_arm
            ).all()
        ):
            raise ValueError(f"arm {arm_id} direction counts changed")
    arm_lookup = arm_summary.set_index("arm_id")
    comparisons = {}
    for left, right in (("A", "B"), ("B", "C"), ("A", "C")):
        comparisons[f"{left}_to_{right}"] = {
            "events_passed_change": int(
                arm_lookup.loc[right, "events_passed"]
                - arm_lookup.loc[left, "events_passed"]
            ),
            "multiclass_brier_change": float(
                arm_lookup.loc[right, "multiclass_brier"]
                - arm_lookup.loc[left, "multiclass_brier"]
            ),
            "true_negative_log_probability_change": float(
                arm_lookup.loc[right, "true_negative_log_probability"]
                - arm_lookup.loc[left, "true_negative_log_probability"]
            ),
        }
    gate_results = evaluate_registered_decision_gates(
        arm_summary,
        direction_summary,
        config.get("decision_gates"),
    )
    report = {
        "experiment_id": config["experiment_id"],
        "configuration_status": config["configuration_status"],
        "config_sha256": expected_config_sha256,
        "verification_status": "passed",
        "registered_basin_count": registered_basin_count,
        "task_count": int(len(tasks)),
        "event_count": int(len(events)),
        "probability_sum_maximum_absolute_error": maximum_probability_sum_error,
        "legacy_probability_maximum_absolute_difference": (
            maximum_legacy_probability_difference
        ),
        "arm_summary": arm_summary.to_dict("records"),
        "comparisons": comparisons,
        "continuation_gate_passed": gate_results[
            "scale_replication_gate_passed"
        ],
        "continuation_gate_scope": config.get("continuation_gate", {}).get(
            "scope", "exploratory_comparison_only_not_validation"
        ),
        "decision_gates": gate_results,
        "registered_hashes": registered_hashes,
    }
    verification = output / "verification"
    temporary_verification = output / "verification.tmp"
    if verification.exists() or temporary_verification.exists():
        raise FileExistsError("verification output or temporary output already exists")
    temporary_verification.mkdir(exist_ok=False)
    tasks.to_csv(temporary_verification / "task_metrics.csv", index=False)
    events.to_csv(temporary_verification / "event_metrics.csv", index=False)
    arm_summary.to_csv(temporary_verification / "arm_metrics.csv", index=False)
    direction_summary.to_csv(
        temporary_verification / "direction_metrics.csv", index=False
    )
    with (temporary_verification / "comparison_summary.json").open(
        "x", encoding="utf-8"
    ) as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write("\n")
    temporary_verification.rename(verification)
    return report


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--config-sha256", required=True)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        report = verify_design(
            arguments.output_root,
            arguments.config,
            arguments.config_sha256,
        )
    except Exception as error:  # noqa: BLE001 - verifier must stop on any mismatch
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
