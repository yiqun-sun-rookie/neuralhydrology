"""Independently verify the frozen H17R final-reserve confirmation."""

from __future__ import annotations

import argparse
import csv
from dataclasses import replace
import hashlib
import json
import math
import os
import zipfile
from pathlib import Path
from typing import Any, Mapping, Sequence

import numpy as np
import torch

from hbv_history_conditioned_imm.causal_duration import CausalSemiMarkovTransitionModule
from hbv_history_conditioned_imm.long_history import (
    LongHistoryParameterSwitchBatch,
    ObservableAssimilationBatch,
    duration_dependent_switch_hazard,
)
from hbv_history_conditioned_imm.parameter_switch import _generate_one_truth
from hbv_history_conditioned_imm.scripts.run_h17_supervised_probability_upper_bound import (
    H17DataSplit,
    _base_transition,
    _causality_audit,
    _estimator,
    _parameter_candidates,
    _static_network,
)
from hbv_history_conditioned_imm.supervised_probability import (
    ActiveRowSupervision,
    ProbabilityRolloutResult,
    rollout_semi_markov_probability,
    rollout_static_probability,
)
from hbv_history_conditioned_imm.synthetic import BlockSeeds
from hbv_history_conditioned_imm.synthetic import _forcing
from hbv_multilead_joint_uncertainty.synthetic_truth import generate_reference_truth


EXPECTED_EXPERIMENT_ID = (
    "h17r_monotone_piecewise_age_risk_learning_rate_0p075_"
    "fresh_reserved_confirmation_v01"
)
CONFIG_RELATIVE_PATH = (
    "src/hbv_history_conditioned_imm/configs/"
    "h17r_monotone_piecewise_age_risk_learning_rate_0p075_"
    "fresh_reserved_confirmation_v01.json"
)
PREREGISTRATION_RELATIVE_PATH = CONFIG_RELATIVE_PATH.replace(
    ".json", ".preregistered_manifest.json"
)
RESERVE_OPEN_TOMBSTONE_DIRECTORY = Path("src/hbv_history_conditioned_imm/configs")
SCHEDULE_FIELDS = (
    "mode_indices",
    "active_source_indices",
    "regime_age_before_transition",
    "oracle_active_row_probabilities",
    "transition_evaluation_mask",
    "switch_event_mask",
)
TENSOR_BATCH_FIELDS = (
    "forcing",
    "observations",
    "truth_states",
    "truth_discharge",
    "true_parameter_indices",
    "active_source_indices",
    "regime_age_before_transition",
    "oracle_active_row_probabilities",
    "transition_evaluation_mask",
    "switch_event_mask",
    "projection_adjustments",
    "process_perturbations",
    "initial_states",
    "initial_covariances",
)
METHODS = (
    "static",
    "history_seed_1710101",
    "history_seed_1710102",
    "history_seed_1710103",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _lexists(path: Path) -> bool:
    return os.path.lexists(os.fspath(path))


def _reserve_open_tombstone_path(
    project_root: str | Path, config: Mapping[str, Any]
) -> Path:
    root = Path(project_root).resolve()
    experiment_id = str(config["experiment_id"])
    if Path(experiment_id).name != experiment_id or experiment_id in {"", ".", ".."}:
        raise ValueError("the reserve-open tombstone experiment identifier is unsafe")
    directory = (root / RESERVE_OPEN_TOMBSTONE_DIRECTORY).resolve()
    directory.relative_to(root)
    derived = directory / f"{experiment_id}.reserve_opened.tombstone.json"
    configured = (
        root / str(config["one_read_contract"]["permanent_tombstone_relative_path"])
    ).resolve()
    configured.relative_to(root)
    if configured != derived:
        raise ValueError("the permanent reserve-open tombstone path changed")
    return configured


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _close(left: Any, right: Any, *, tolerance: float = 1e-12) -> bool:
    if isinstance(left, Mapping) and isinstance(right, Mapping):
        return set(left) == set(right) and all(
            _close(left[key], right[key], tolerance=tolerance) for key in left
        )
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(
            _close(a, b, tolerance=tolerance) for a, b in zip(left, right)
        )
    if isinstance(left, bool) or isinstance(right, bool):
        return left is right
    if left is None or right is None or isinstance(left, str) or isinstance(right, str):
        return left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return math.isfinite(float(left)) and math.isfinite(float(right)) and math.isclose(
            float(left), float(right), rel_tol=0.0, abs_tol=tolerance
        )
    return left == right


def _seed(config: Mapping[str, Any], *, layer: str, stream: str, ordinal: int) -> int:
    namespace = config["seed_namespace"]
    return (
        int(namespace["base"])
        + int(namespace["stage_codes"]["final_reserve"])
        * int(namespace["stage_multiplier"])
        + int(namespace["layer_codes"][layer]) * int(namespace["layer_multiplier"])
        + int(namespace["stream_codes"][stream])
        * int(namespace["stream_multiplier"])
        + int(ordinal)
    )


def _mapping_sha256(values: Mapping[str, Any]) -> str:
    payload = json.dumps(values, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )
    return hashlib.sha256(payload).hexdigest()


def _require_approved_preregistration_sha256(value: str) -> str:
    normalized = str(value).strip().lower()
    if len(normalized) != 64 or any(
        character not in "0123456789abcdef" for character in normalized
    ):
        raise ValueError("an exact externally approved preregistration SHA-256 is required")
    return normalized


def _registry_rows(project_root: Path) -> list[dict[str, str]]:
    path = project_root / "src/hbv_history_conditioned_imm/configs/experiment_registry.csv"
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def _immutable_registry_fields(row: Mapping[str, str]) -> dict[str, str]:
    return {
        str(name): str(value)
        for name, value in row.items()
        if name not in {"status", "notes"}
    }


def _anchored_context(
    result_config: Mapping[str, Any],
    project_root: Path,
    *,
    approved_preregistration_sha256: str,
) -> dict[str, Any]:
    manifest_path = project_root / PREREGISTRATION_RELATIVE_PATH
    live_config_path = project_root / CONFIG_RELATIVE_PATH
    if not manifest_path.is_file() or not live_config_path.is_file():
        raise FileNotFoundError("the external H17R preregistration anchor is missing")
    manifest = _read_json(manifest_path)
    live_config = _read_json(live_config_path)
    if (
        manifest.get("experiment_id") != EXPECTED_EXPERIMENT_ID
        or live_config.get("experiment_id") != EXPECTED_EXPERIMENT_ID
        or not _close(dict(result_config), live_config)
    ):
        raise ValueError("the result config differs from the anchored live H17R config")
    files = manifest.get("files")
    if not isinstance(files, Mapping):
        raise ValueError("the H17R preregistration file map is missing")
    expected_files = set(str(value) for value in live_config["source_snapshot"]["files"])
    expected_files.discard(PREREGISTRATION_RELATIVE_PATH)
    if set(str(value) for value in files) != expected_files:
        raise ValueError("the H17R preregistration file closure is incomplete")
    for relative, expected in files.items():
        source = project_root / str(relative)
        if not source.is_file() or _sha256(source) != str(expected):
            raise ValueError(f"a preregistered H17R file changed: {relative}")
    rows = _registry_rows(project_root)
    matches = [row for row in rows if row["exp_id"] == EXPECTED_EXPERIMENT_ID]
    if len(matches) != 1:
        raise ValueError("the live registry does not contain exactly one H17R row")
    live_row = matches[0]
    manifest_hash = _sha256(manifest_path)
    approved_hash = _require_approved_preregistration_sha256(
        approved_preregistration_sha256
    )
    if manifest_hash != approved_hash:
        raise ValueError(
            "the preregistration manifest does not match the externally approved SHA-256"
        )
    token = f"{live_config['preregistration_manifest']['registry_note_token']}{manifest_hash}"
    if token not in live_row["notes"]:
        raise ValueError("the live registry no longer anchors the preregistration manifest")
    immutable = _immutable_registry_fields(live_row)
    if immutable != manifest.get("registry_immutable_fields"):
        raise ValueError("an immutable H17R registry field changed after preregistration")
    return {
        "manifest": manifest,
        "manifest_sha256": manifest_hash,
        "externally_approved_sha256": approved_hash,
        "live_config": live_config,
        "live_config_sha256": _sha256(live_config_path),
        "live_registry_row": live_row,
        "live_registry_row_sha256": _mapping_sha256(live_row),
        "immutable_registry_fields_sha256": _mapping_sha256(immutable),
        "registry_note_token": token,
    }


def _related_result_paths(project_root: Path, prefix: str) -> list[Path]:
    parent = project_root / "results/23_hbv_multilead_joint_uncertainty"
    if not parent.exists():
        return []
    normalized = prefix.lower()
    return [
        path
        for path in parent.iterdir()
        if path.name.lstrip(".").lower().startswith(normalized)
    ]


def _reproduce_schedule(
    *, seed: int, total_days: int, hazard: Mapping[str, Any]
) -> dict[str, np.ndarray]:
    days = int(total_days)
    generator = np.random.default_rng(int(seed))
    modes = np.empty(days, dtype=np.int64)
    sources = np.full(days, -1, dtype=np.int64)
    ages = np.zeros(days, dtype=np.int64)
    oracle = np.zeros((days, 3), dtype=np.float64)
    evaluated = np.zeros(days, dtype=np.bool_)
    switched = np.zeros(days, dtype=np.bool_)
    modes[0] = int(generator.integers(0, 3))
    current_age = 1
    for day in range(1, days):
        source = int(modes[day - 1])
        switch_hazard = duration_dependent_switch_hazard(current_age, hazard)
        row = np.full(3, switch_hazard / 2.0, dtype=np.float64)
        row[source] = 1.0 - switch_hazard
        sources[day] = source
        ages[day] = current_age
        oracle[day] = row
        evaluated[day] = True
        if float(generator.random()) < switch_hazard:
            alternatives = tuple(value for value in range(3) if value != source)
            modes[day] = alternatives[int(generator.integers(0, 2))]
            switched[day] = True
            current_age = 1
        else:
            modes[day] = source
            current_age += 1
    return {
        "mode_indices": modes,
        "active_source_indices": sources,
        "regime_age_before_transition": ages,
        "oracle_active_row_probabilities": oracle,
        "transition_evaluation_mask": evaluated,
        "switch_event_mask": switched,
    }


def _expected_schedule_keys() -> set[str]:
    return {
        *(f"natural_core_{name}" for name in SCHEDULE_FIELDS),
        *(f"coverage_{name}" for name in SCHEDULE_FIELDS),
        *(f"coverage_candidate_trace_{name}" for name in SCHEDULE_FIELDS),
        "coverage_accepted_candidate_ordinals",
    }


def _schedule_schema_and_replay(
    config: Mapping[str, Any], arrays: Mapping[str, np.ndarray]
) -> dict[str, Any]:
    if set(arrays) != _expected_schedule_keys():
        raise ValueError("schedule_arrays.npz does not have the exact frozen schema")
    days = int(config["data"]["assimilation_days"])
    natural_count = int(config["data"]["natural_core_blocks"])
    accepted_ordinals = np.asarray(
        arrays["coverage_accepted_candidate_ordinals"], dtype=np.int64
    )
    if arrays["coverage_accepted_candidate_ordinals"].dtype != np.dtype("int64"):
        raise ValueError("coverage accepted ordinals have the wrong dtype")
    accepted_count = int(accepted_ordinals.size)
    inspected = int(arrays["coverage_candidate_trace_mode_indices"].shape[0])
    prefixes = {
        "natural_core": natural_count,
        "coverage": accepted_count,
        "coverage_candidate_trace": inspected,
    }
    for prefix, count in prefixes.items():
        for name in SCHEDULE_FIELDS:
            value = arrays[f"{prefix}_{name}"]
            expected_shape = (
                (count, days, 3)
                if name == "oracle_active_row_probabilities"
                else (count, days)
            )
            expected_dtype = (
                np.dtype("float64")
                if name == "oracle_active_row_probabilities"
                else np.dtype("bool")
                if name in {"transition_evaluation_mask", "switch_event_mask"}
                else np.dtype("int64")
            )
            if value.shape != expected_shape or value.dtype != expected_dtype:
                raise ValueError(f"{prefix}_{name} violates its frozen shape or dtype")
            if np.issubdtype(value.dtype, np.floating) and not np.isfinite(value).all():
                raise ValueError(f"{prefix}_{name} contains a nonfinite value")
    if (
        accepted_count > int(config["coverage_selection"]["maximum_accepted_coverage_blocks"])
        or inspected > int(config["coverage_selection"]["maximum_candidate_schedules"])
        or np.any(accepted_ordinals < 1)
        or np.any(accepted_ordinals > inspected)
        or len(set(int(value) for value in accepted_ordinals)) != accepted_count
    ):
        raise ValueError("coverage selection ordinals violate the frozen bounds")

    for ordinal in range(1, natural_count + 1):
        reproduced = _reproduce_schedule(
            seed=_seed(config, layer="natural_core", stream="schedule", ordinal=ordinal),
            total_days=days,
            hazard=config["duration_hazard"],
        )
        for name in SCHEDULE_FIELDS:
            if not np.array_equal(
                arrays[f"natural_core_{name}"][ordinal - 1], reproduced[name]
            ):
                raise ValueError(f"natural schedule {ordinal} did not independently replay")
    for ordinal in range(1, inspected + 1):
        reproduced = _reproduce_schedule(
            seed=_seed(config, layer="coverage", stream="schedule", ordinal=ordinal),
            total_days=days,
            hazard=config["duration_hazard"],
        )
        for name in SCHEDULE_FIELDS:
            if not np.array_equal(
                arrays[f"coverage_candidate_trace_{name}"][ordinal - 1],
                reproduced[name],
            ):
                raise ValueError(f"coverage schedule {ordinal} did not independently replay")
    for rank, ordinal in enumerate(accepted_ordinals.tolist()):
        for name in SCHEDULE_FIELDS:
            if not np.array_equal(
                arrays[f"coverage_{name}"][rank],
                arrays[f"coverage_candidate_trace_{name}"][int(ordinal) - 1],
            ):
                raise ValueError("an accepted coverage schedule differs from its trace row")
    selected, counts, selection_inspected = _independent_selection_from_trace(config, arrays)
    if selected != accepted_ordinals.tolist() or selection_inspected != inspected:
        raise ValueError("the saved coverage selection differs from independent selection")
    return {
        "accepted_ordinals": [int(value) for value in accepted_ordinals],
        "counts": counts,
        "inspected": inspected,
        "natural_schedule_count": natural_count,
        "postdecision_schedule_replay_event_count": 1,
    }


def _schedule_counts(schedule: Any) -> dict[str, np.ndarray]:
    sources = np.asarray(schedule.active_source_indices, dtype=np.int64)
    ages = np.asarray(schedule.regime_age_before_transition, dtype=np.int64)
    mask = np.asarray(schedule.transition_evaluation_mask, dtype=np.bool_)
    result = {
        name: np.zeros(3, dtype=np.int64)
        for name in (
            "days_40_to_49",
            "days_50_plus",
            "segments_reaching_50",
            "distinct_50_plus_blocks",
        )
    }
    for source in range(3):
        active = mask & (sources == source)
        result["days_40_to_49"][source] = np.count_nonzero(
            active & (ages >= 40) & (ages <= 49)
        )
        result["days_50_plus"][source] = np.count_nonzero(active & (ages >= 50))
        result["segments_reaching_50"][source] = np.count_nonzero(active & (ages == 50))
        result["distinct_50_plus_blocks"][source] = int(
            result["days_50_plus"][source] > 0
        )
    return result


def _thresholds(config: Mapping[str, Any]) -> dict[str, np.ndarray]:
    values = config["coverage_thresholds"]
    return {
        "days_40_to_49": np.full(
            3, int(values["minimum_40_to_49_days_per_source"]), dtype=np.int64
        ),
        "days_50_plus": np.full(
            3, int(values["minimum_50_plus_days_per_source"]), dtype=np.int64
        ),
        "segments_reaching_50": np.full(
            3, int(values["minimum_segments_reaching_50_per_source"]), dtype=np.int64
        ),
        "distinct_50_plus_blocks": np.full(
            3,
            int(values["minimum_distinct_50_plus_blocks_per_source"]),
            dtype=np.int64,
        ),
    }


def _complete(counts: Mapping[str, np.ndarray], thresholds: Mapping[str, np.ndarray]) -> bool:
    return all(np.all(counts[name] >= thresholds[name]) for name in thresholds)


def _reduces(
    candidate: Mapping[str, np.ndarray],
    counts: Mapping[str, np.ndarray],
    thresholds: Mapping[str, np.ndarray],
    names: Sequence[str],
) -> bool:
    return any(
        np.any((counts[name] < thresholds[name]) & (candidate[name] > 0))
        for name in names
    )


def _schedule_count_arrays(
    sources: np.ndarray, ages: np.ndarray, mask: np.ndarray
) -> dict[str, np.ndarray]:
    class Values:
        active_source_indices = sources
        regime_age_before_transition = ages
        transition_evaluation_mask = mask

    return _schedule_counts(Values())


def _independent_selection_from_trace(
    config: Mapping[str, Any], arrays: Mapping[str, np.ndarray]
) -> tuple[list[int], dict[str, np.ndarray], int]:
    thresholds = _thresholds(config)
    counts = {name: np.zeros(3, dtype=np.int64) for name in thresholds}
    accepted_indices: list[int] = []
    trace_sources = np.asarray(
        arrays["coverage_candidate_trace_active_source_indices"], dtype=np.int64
    )
    trace_ages = np.asarray(
        arrays["coverage_candidate_trace_regime_age_before_transition"],
        dtype=np.int64,
    )
    trace_masks = np.asarray(
        arrays["coverage_candidate_trace_transition_evaluation_mask"], dtype=np.bool_
    )
    inspected = int(trace_sources.shape[0])
    for offset in range(inspected):
        index = offset + 1
        if len(accepted_indices) >= int(
            config["coverage_selection"]["maximum_accepted_coverage_blocks"]
        ):
            break
        candidate = _schedule_count_arrays(
            trace_sources[offset], trace_ages[offset], trace_masks[offset]
        )
        accept = _reduces(
            candidate,
            counts,
            thresholds,
            ("days_50_plus", "segments_reaching_50", "distinct_50_plus_blocks"),
        ) or _reduces(candidate, counts, thresholds, ("days_40_to_49",))
        if accept:
            accepted_indices.append(index)
            for name in counts:
                counts[name] += candidate[name]
        if _complete(counts, thresholds):
            break
    return accepted_indices, counts, inspected


def _selected_metrics(
    matrices: np.ndarray,
    sources: np.ndarray,
    targets: np.ndarray,
    selected: np.ndarray,
) -> dict[str, int | float | None]:
    block, day = np.nonzero(selected)
    count = int(block.size)
    if count == 0:
        return {
            "count": 0,
            "oracle_brier": None,
            "switch_hazard_mean_absolute_error": None,
        }
    active_sources = sources[block, day]
    rows = matrices[block, day, active_sources]
    target_rows = targets[block, day]
    coordinate = np.arange(count)
    brier = float(np.mean(np.sum(np.square(rows - target_rows), axis=-1)))
    hazard_mae = float(
        np.mean(
            np.abs(
                (1.0 - rows[coordinate, active_sources])
                - (1.0 - target_rows[coordinate, active_sources])
            )
        )
    )
    return {
        "count": count,
        "oracle_brier": brier if math.isfinite(brier) else None,
        "switch_hazard_mean_absolute_error": (
            hazard_mae if math.isfinite(hazard_mae) else None
        ),
    }


def _independent_metrics(
    config: Mapping[str, Any], arrays: Mapping[str, np.ndarray]
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    natural_sources = np.asarray(arrays["natural_core_source_indices"], dtype=np.int64)
    natural_targets = np.asarray(arrays["natural_core_target_probabilities"], dtype=np.float64)
    natural_mask = np.asarray(arrays["natural_core_evaluation_mask"], dtype=np.bool_)
    natural_metrics = {}
    matrices_by_layer: dict[str, dict[str, np.ndarray]] = {"natural_core": {}, "coverage": {}}
    for method in METHODS:
        matrices = np.asarray(
            arrays[f"natural_core_{method}_transition_matrices"], dtype=np.float64
        )
        matrices_by_layer["natural_core"][method] = matrices
        natural_metrics[method] = _selected_metrics(
            matrices, natural_sources, natural_targets, natural_mask
        )

    coverage_sources = np.asarray(arrays["coverage_source_indices"], dtype=np.int64)
    coverage_targets = np.asarray(arrays["coverage_target_probabilities"], dtype=np.float64)
    coverage_mask = np.asarray(arrays["coverage_evaluation_mask"], dtype=np.bool_)
    coverage_ages = np.asarray(arrays["coverage_ages"], dtype=np.int64)
    age_masks = {
        "age_40_49": (coverage_ages >= 40) & (coverage_ages <= 49),
        "age_50_plus": coverage_ages >= 50,
    }
    coverage_metrics: dict[str, Any] = {}
    for method in METHODS:
        matrices = np.asarray(
            arrays[f"coverage_{method}_transition_matrices"], dtype=np.float64
        )
        matrices_by_layer["coverage"][method] = matrices
        coverage_metrics[method] = {
            age_name: {
                str(source): _selected_metrics(
                    matrices,
                    coverage_sources,
                    coverage_targets,
                    coverage_mask & age_mask & (coverage_sources == source),
                )
                for source in range(3)
            }
            for age_name, age_mask in age_masks.items()
        }

    threshold = float(config["evaluation_contract"]["minimum_relative_reduction"])
    records = []
    def gate_record(
        *, layer: str, method: str, cell: str, metric: str, baseline: Any, candidate: Any
    ) -> dict[str, Any]:
        baseline_value = float(baseline) if baseline is not None else math.nan
        candidate_value = float(candidate) if candidate is not None else math.nan
        valid = (
            math.isfinite(baseline_value)
            and baseline_value > 0.0
            and math.isfinite(candidate_value)
            and candidate_value >= 0.0
        )
        reduction = 1.0 - candidate_value / baseline_value if valid else None
        return {
            "layer": layer,
            "method": method,
            "cell": cell,
            "metric": metric,
            "static_error": baseline_value if math.isfinite(baseline_value) else None,
            "candidate_error": candidate_value if math.isfinite(candidate_value) else None,
            "denominator_valid": valid,
            "relative_reduction": reduction,
            "failure_reason": (
                None
                if valid
                else "invalid_or_zero_static_denominator_or_nonfinite_candidate"
            ),
            "passed": bool(valid and reduction is not None and reduction >= threshold),
        }

    for method in METHODS[1:]:
        for metric in ("oracle_brier", "switch_hazard_mean_absolute_error"):
            records.append(
                gate_record(
                    layer="natural_core",
                    method=method,
                    cell="all_scored_transitions",
                    metric=metric,
                    baseline=natural_metrics["static"][metric],
                    candidate=natural_metrics[method][metric],
                )
            )
    for method in METHODS[1:]:
        for age_name in age_masks:
            for source in range(3):
                for metric in ("oracle_brier", "switch_hazard_mean_absolute_error"):
                    records.append(
                        gate_record(
                            layer="rare_duration_coverage",
                            method=method,
                            cell=f"source_{source}_{age_name}",
                            metric=metric,
                            baseline=coverage_metrics["static"][age_name][str(source)][metric],
                            candidate=coverage_metrics[method][age_name][str(source)][metric],
                        )
                    )
    metrics = {
        "natural_core": natural_metrics,
        "minimum_relative_reduction": threshold,
        "gate_records": records,
        "natural_gate_count": 6,
        "coverage_gate_count": 36,
        "passed_gate_count": sum(bool(item["passed"]) for item in records),
        "failed_gate_count": sum(not bool(item["passed"]) for item in records),
        "all_42_performance_conditions_passed": all(
            bool(item["passed"]) for item in records
        ),
    }
    stratified = {
        "age_bins": ["age_40_49", "age_50_plus"],
        "source_ids": config["evaluation_contract"]["coverage_source_ids"],
        "methods": coverage_metrics,
    }
    legality_layers: dict[str, Any] = {}
    finite = True
    for layer, methods in matrices_by_layer.items():
        legality_layers[layer] = {}
        for method, matrices in methods.items():
            method_finite = bool(np.isfinite(matrices).all())
            finite = finite and method_finite
            legality_layers[layer][method] = {
                "maximum_transition_row_sum_error": (
                    float(np.max(np.abs(matrices.sum(axis=-1) - 1.0)))
                    if method_finite
                    else None
                ),
                "minimum_transition_probability": (
                    float(np.min(matrices)) if method_finite else None
                ),
                "all_values_finite": method_finite,
            }
    maximum_row_error = (
        max(
            float(np.max(np.abs(matrices.sum(axis=-1) - 1.0)))
            for layer in matrices_by_layer.values()
            for matrices in layer.values()
        )
        if finite
        else None
    )
    minimum_probability = (
        min(
            float(np.min(matrices))
            for layer in matrices_by_layer.values()
            for matrices in layer.values()
        )
        if finite
        else None
    )
    legality = {
        "layers": legality_layers,
        "maximum_transition_row_sum_error": maximum_row_error,
        "minimum_transition_probability": minimum_probability,
        "all_values_finite": finite,
        "passed": bool(
            finite
            and minimum_probability is not None
            and minimum_probability >= 0.0
            and maximum_row_error is not None
            and maximum_row_error <= 1e-12
        ),
    }
    return metrics, stratified, legality


def _expected_generation_keys() -> set[str]:
    result: set[str] = set()
    for layer in ("natural_core", "coverage"):
        result.update(f"{layer}_{name}" for name in TENSOR_BATCH_FIELDS)
        result.update(
            {
                f"{layer}_block_ids",
                f"{layer}_block_seed_matrix",
                f"{layer}_accepted_process_seeds",
                f"{layer}_rejected_process_seeds",
            }
        )
    return result


def _expected_reserve_keys() -> set[str]:
    result: set[str] = set()
    data_names = (
        "forcing",
        "observations",
        "initial_states",
        "initial_covariances",
        "source_indices",
        "target_probabilities",
        "evaluation_mask",
        "switch_event_mask",
        "ages",
    )
    for layer in ("natural_core", "coverage"):
        result.update(f"{layer}_{name}" for name in data_names)
        result.update(
            f"{layer}_{method}_transition_matrices" for method in METHODS
        )
    return result


def _block_seed(
    config: Mapping[str, Any], *, layer: str, rank: int, schedule_ordinal: int
) -> BlockSeeds:
    return BlockSeeds(
        block_id=f"final_reserve_{layer}_block_{rank:03d}",
        forcing_seed=_seed(config, layer=layer, stream="forcing", ordinal=rank),
        process_seed=_seed(config, layer=layer, stream="process", ordinal=rank),
        observation_seed=_seed(
            config, layer=layer, stream="observation", ordinal=rank
        ),
        schedule_seed=_seed(
            config, layer=layer, stream="schedule", ordinal=schedule_ordinal
        ),
    )


def _generation_schema(
    config: Mapping[str, Any],
    arrays: Mapping[str, np.ndarray],
    *,
    natural_count: int,
    coverage_count: int,
) -> None:
    if set(arrays) != _expected_generation_keys():
        raise ValueError("generation_arrays.npz does not have the exact frozen schema")
    total_days = int(config["data"]["assimilation_days"]) + int(
        config["data"]["maximum_forecast_lead"]
    )
    shapes = {
        "forcing": lambda count: (count, total_days, 3),
        "observations": lambda count: (count, total_days),
        "truth_states": lambda count: (count, total_days, 15),
        "truth_discharge": lambda count: (count, total_days),
        "true_parameter_indices": lambda count: (count, total_days),
        "active_source_indices": lambda count: (count, total_days),
        "regime_age_before_transition": lambda count: (count, total_days),
        "oracle_active_row_probabilities": lambda count: (count, total_days, 3),
        "transition_evaluation_mask": lambda count: (count, total_days),
        "switch_event_mask": lambda count: (count, total_days),
        "projection_adjustments": lambda count: (count, total_days, 15),
        "process_perturbations": lambda count: (count, total_days, 15),
        "initial_states": lambda count: (count, 15),
        "initial_covariances": lambda count: (count, 15, 15),
    }
    integer_names = {
        "true_parameter_indices",
        "active_source_indices",
        "regime_age_before_transition",
    }
    boolean_names = {"transition_evaluation_mask", "switch_event_mask"}
    for layer, count in (("natural_core", natural_count), ("coverage", coverage_count)):
        for name, shape in shapes.items():
            value = arrays[f"{layer}_{name}"]
            expected_dtype = (
                np.dtype("int64")
                if name in integer_names
                else np.dtype("bool")
                if name in boolean_names
                else np.dtype("float64")
            )
            if value.shape != shape(count) or value.dtype != expected_dtype:
                raise ValueError(f"{layer}_{name} violates its frozen shape or dtype")
            if np.issubdtype(value.dtype, np.floating) and not np.isfinite(value).all():
                raise ValueError(f"{layer}_{name} contains a nonfinite value")
        if arrays[f"{layer}_block_ids"].shape != (count,) or arrays[
            f"{layer}_block_ids"
        ].dtype.kind != "U":
            raise ValueError(f"{layer} block identifiers violate their frozen schema")
        if arrays[f"{layer}_block_seed_matrix"].shape != (count, 4) or arrays[
            f"{layer}_block_seed_matrix"
        ].dtype != np.dtype("int64"):
            raise ValueError(f"{layer} block seeds violate their frozen schema")
        if arrays[f"{layer}_accepted_process_seeds"].shape != (count,) or arrays[
            f"{layer}_accepted_process_seeds"
        ].dtype != np.dtype("int64"):
            raise ValueError(f"{layer} accepted seeds violate their frozen schema")
        rejected = arrays[f"{layer}_rejected_process_seeds"]
        if rejected.ndim != 1 or rejected.dtype != np.dtype("int64"):
            raise ValueError(f"{layer} rejected seeds violate their frozen schema")


def _reserve_schema(
    config: Mapping[str, Any],
    arrays: Mapping[str, np.ndarray],
    *,
    natural_count: int,
    coverage_count: int,
) -> None:
    if set(arrays) != _expected_reserve_keys():
        raise ValueError("reserve_arrays.npz does not have the exact frozen schema")
    days = int(config["data"]["assimilation_days"])
    shapes = {
        "forcing": lambda count: (count, days, 3),
        "observations": lambda count: (count, days),
        "initial_states": lambda count: (count, 15),
        "initial_covariances": lambda count: (count, 15, 15),
        "source_indices": lambda count: (count, days),
        "target_probabilities": lambda count: (count, days, 3),
        "evaluation_mask": lambda count: (count, days),
        "switch_event_mask": lambda count: (count, days),
        "ages": lambda count: (count, days),
    }
    integer_names = {"source_indices", "ages"}
    boolean_names = {"evaluation_mask", "switch_event_mask"}
    for layer, count in (("natural_core", natural_count), ("coverage", coverage_count)):
        for name, shape in shapes.items():
            value = arrays[f"{layer}_{name}"]
            expected_dtype = (
                np.dtype("int64")
                if name in integer_names
                else np.dtype("bool")
                if name in boolean_names
                else np.dtype("float64")
            )
            if value.shape != shape(count) or value.dtype != expected_dtype:
                raise ValueError(f"{layer}_{name} violates its frozen shape or dtype")
            if np.issubdtype(value.dtype, np.floating) and not np.isfinite(value).all():
                raise ValueError(f"{layer}_{name} contains a nonfinite value")
        for method in METHODS:
            value = arrays[f"{layer}_{method}_transition_matrices"]
            if value.shape != (count, days, 3, 3) or value.dtype != np.dtype(
                "float64"
            ):
                raise ValueError(
                    f"{layer}_{method}_transition_matrices has the wrong shape or dtype"
                )


def _attempt_record(
    config: Mapping[str, Any],
    *,
    layer: str,
    rank: int,
    schedule_ordinal: int,
    record: Mapping[str, Any],
) -> tuple[BlockSeeds, list[int], int]:
    requested = _block_seed(
        config, layer=layer, rank=rank, schedule_ordinal=schedule_ordinal
    )
    rejected = [int(value) for value in record["rejected_process_seeds"]]
    accepted = int(record["accepted_process_seed"])
    maximum_resamples = int(config["seed_namespace"]["maximum_process_resample_attempt"])
    sequence = [requested.process_seed] + [
        _seed(
            config,
            layer=layer,
            stream="process_resample",
            ordinal=rank * 1000 + attempt,
        )
        for attempt in range(1, maximum_resamples + 1)
    ]
    expected_rejected = sequence[: len(rejected)]
    if (
        record.get("block_id") != requested.block_id
        or int(record.get("requested_process_seed", -1)) != requested.process_seed
        or rejected != expected_rejected
        or len(rejected) >= len(sequence)
        or accepted != sequence[len(rejected)]
        or int(record.get("total_attempt_count", -1)) != len(rejected) + 1
        or len(rejected) + 1 > int(config["seed_namespace"]["maximum_total_process_attempts"])
    ):
        raise ValueError(f"the process attempt record changed for {requested.block_id}")
    return requested, rejected, accepted


def _validate_process_exhaustion_ledger(
    config: Mapping[str, Any],
    seed_audit: Mapping[str, Any],
    exhaustion_audit: Mapping[str, Any],
    *,
    accepted_coverage_ordinals: Sequence[int],
) -> list[dict[str, Any]]:
    failure_layer = str(exhaustion_audit["layer"])
    failure_rank = int(exhaustion_audit["failed_block_rank"])
    failure_ordinal = int(exhaustion_audit["schedule_ordinal"])
    layer_order = ("natural_core", "coverage")
    if failure_layer not in layer_order:
        raise ValueError("process-exhaustion ledger names an unknown layer")
    expected_layers = layer_order[: layer_order.index(failure_layer) + 1]
    if set(seed_audit.get("layers", {})) != set(expected_layers):
        raise ValueError("process-exhaustion ledger has incomplete layer coverage")
    ordinals_by_layer = {
        "natural_core": list(
            range(1, int(config["data"]["natural_core_blocks"]) + 1)
        ),
        "coverage": [int(value) for value in accepted_coverage_ordinals],
    }
    if (
        failure_rank < 1
        or failure_rank > len(ordinals_by_layer[failure_layer])
        or failure_ordinal != ordinals_by_layer[failure_layer][failure_rank - 1]
    ):
        raise ValueError("process-exhaustion ledger has a changed failure location")
    maximum_resamples = int(
        config["seed_namespace"]["maximum_process_resample_attempt"]
    )
    maximum_attempts = int(config["seed_namespace"]["maximum_total_process_attempts"])
    all_records: list[dict[str, Any]] = []
    for layer in expected_layers:
        values = seed_audit["layers"][layer]
        records = [dict(value) for value in values["process_attempts"]]
        expected_count = (
            failure_rank if layer == failure_layer else len(ordinals_by_layer[layer])
        )
        if len(records) != expected_count:
            raise ValueError("process-exhaustion ledger has an incomplete block prefix")
        accepted_values: list[int] = []
        rejected_values: list[int] = []
        for rank, record in enumerate(records, start=1):
            schedule_ordinal = ordinals_by_layer[layer][rank - 1]
            requested = _block_seed(
                config,
                layer=layer,
                rank=rank,
                schedule_ordinal=schedule_ordinal,
            )
            sequence = [requested.process_seed] + [
                _seed(
                    config,
                    layer=layer,
                    stream="process_resample",
                    ordinal=rank * 1000 + attempt,
                )
                for attempt in range(1, maximum_resamples + 1)
            ]
            rejected = [int(value) for value in record["rejected_process_seeds"]]
            attempted = [int(value) for value in record["attempted_process_seeds"]]
            is_failed_record = layer == failure_layer and rank == failure_rank
            common_matches = (
                record.get("layer") == layer
                and int(record.get("block_rank", -1)) == rank
                and int(record.get("schedule_ordinal", -1)) == schedule_ordinal
                and record.get("block_id") == requested.block_id
                and record.get("requested_block_seeds") == list(requested.all_seeds)
                and int(record.get("total_attempt_count", -1)) == len(attempted)
                and 1 <= len(attempted) <= maximum_attempts
            )
            if is_failed_record:
                record_matches = (
                    common_matches
                    and record.get("outcome") == "exhausted"
                    and record.get("accepted_process_seed") is None
                    and attempted == sequence
                    and rejected == sequence
                )
            else:
                accepted = int(record.get("accepted_process_seed", -1))
                record_matches = (
                    common_matches
                    and record.get("outcome") == "accepted"
                    and len(rejected) < len(sequence)
                    and rejected == sequence[: len(rejected)]
                    and accepted == sequence[len(rejected)]
                    and attempted == [*rejected, accepted]
                )
                if record_matches:
                    accepted_values.append(accepted)
            if not record_matches:
                raise ValueError("process-exhaustion ledger contains a changed block attempt")
            rejected_values.extend(rejected)
            all_records.append(record)
        expected_failed_count = int(layer == failure_layer)
        if (
            int(values.get("attempted_block_count", -1)) != len(records)
            or int(values.get("completed_block_count", -1))
            != len(records) - expected_failed_count
            or int(values.get("failed_block_count", -1)) != expected_failed_count
            or values.get("schedule_ordinals")
            != [int(record["schedule_ordinal"]) for record in records]
            or values.get("accepted_process_seeds") != accepted_values
            or values.get("rejected_process_seeds") != rejected_values
            or int(values.get("rejected_process_seed_count", -1))
            != len(rejected_values)
        ):
            raise ValueError("process-exhaustion ledger aggregates do not match its blocks")
    failed_record = all_records[-1]
    completed_records = [
        record for record in all_records if record["outcome"] == "accepted"
    ]
    expected_failure = {
        "layer": failure_layer,
        "failed_block_rank": failure_rank,
        "schedule_ordinal": failure_ordinal,
        "block_id": failed_record["block_id"],
    }
    expected_actual_count = (
        len(seed_audit["schedule_seeds"]["natural_core"])
        + len(seed_audit["schedule_seeds"]["coverage_candidates"])
        + sum(3 + len(record["attempted_process_seeds"]) for record in all_records)
    )
    expected_committed_count = (
        len(seed_audit["schedule_seeds"]["natural_core"])
        + len(seed_audit["schedule_seeds"]["coverage_candidates"])
        + len(all_records) * (3 + maximum_resamples)
    )
    audit_matches = (
        seed_audit.get("stage") == "final_reserve"
        and seed_audit.get("outcome_scope") == "physical_process_exhaustion"
        and seed_audit.get("physical_generation_started") is True
        and seed_audit.get("process_exhaustion") == expected_failure
        and int(seed_audit.get("actual_seed_count", -1)) == expected_actual_count
        and int(seed_audit.get("committed_seed_count", -1))
        == expected_committed_count
        and seed_audit.get("committed_seed_unique") is True
        and seed_audit.get("all_actual_seeds_are_committed") is True
        and seed_audit.get("actual_seeds_disjoint_from_h16_and_h17p") is True
        and seed_audit.get("legacy_process_seed_arithmetic_used") is False
        and seed_audit.get("explicit_process_resample_stream_used") is True
        and int(seed_audit.get("all_generation_calls_maximum_process_resamples", -1))
        == 1
        and int(seed_audit.get("maximum_total_process_attempts_observed", -1))
        == max(int(record["total_attempt_count"]) for record in all_records)
        and seed_audit.get("all_process_attempt_counts_within_frozen_limit") is True
        and exhaustion_audit.get("physical_generation_started") is True
        and exhaustion_audit.get("block_id") == failed_record["block_id"]
        and exhaustion_audit.get("requested_block_seeds")
        == failed_record["requested_block_seeds"]
        and exhaustion_audit.get("attempted_process_seeds")
        == failed_record["attempted_process_seeds"]
        and int(exhaustion_audit.get("attempt_count", -1))
        == int(failed_record["total_attempt_count"])
        and int(exhaustion_audit.get("maximum_total_process_attempts", -1))
        == maximum_attempts
        and int(
            exhaustion_audit.get("all_generation_calls_maximum_process_resamples", -1)
        )
        == 1
        and int(exhaustion_audit.get("completed_block_count_before_failure", -1))
        == len(completed_records)
        and int(exhaustion_audit.get("attempted_block_count", -1))
        == len(all_records)
        and exhaustion_audit.get("completed_block_attempt_records")
        == completed_records
        and exhaustion_audit.get("failed_block_attempt_record") == failed_record
        and exhaustion_audit.get("all_layer_process_attempts")
        == {
            layer: seed_audit["layers"][layer]["process_attempts"]
            for layer in expected_layers
        }
        and exhaustion_audit.get("seed_ledger_sha256")
        == _mapping_sha256(seed_audit)
        and int(exhaustion_audit.get("checkpoint_load_count", -1)) == 0
    )
    if not audit_matches:
        raise ValueError("process-exhaustion ledger does not match its terminal audit")
    return all_records


def _replay_process_exhaustion_record(
    config: Mapping[str, Any],
    h17_config: Mapping[str, Any],
    record: Mapping[str, Any],
) -> dict[str, int | bool]:
    candidates = _parameter_candidates(h17_config)
    requested = _block_seed(
        config,
        layer=str(record["layer"]),
        rank=int(record["block_rank"]),
        schedule_ordinal=int(record["schedule_ordinal"]),
    )
    warmup_days = int(config["data"]["warmup_days"])
    total_days = int(config["data"]["assimilation_days"]) + int(
        config["data"]["maximum_forecast_lead"]
    )
    complete_forcing = _forcing(requested.forcing_seed, warmup_days + total_days)
    warmup_truth = generate_reference_truth(
        complete_forcing[:warmup_days],
        candidates[str(config["data"]["warmup_parameter_id"])],
    )
    schedule = _reproduce_schedule(
        seed=requested.schedule_seed,
        total_days=total_days,
        hazard=config["duration_hazard"],
    )
    attempted = [int(value) for value in record["attempted_process_seeds"]]
    accepted_count = 0
    rejected_count = 0
    for attempt_index, process_seed in enumerate(attempted):
        should_succeed = (
            record["outcome"] == "accepted" and attempt_index == len(attempted) - 1
        )
        try:
            _generate_one_truth(
                forcing=complete_forcing[warmup_days:],
                initial_state=warmup_truth.states[-1].copy(),
                schedule_indices=schedule["mode_indices"],
                parameter_ids=tuple(candidates),
                parameter_candidates=candidates,
                process_normals=np.random.default_rng(process_seed).standard_normal(
                    total_days
                ),
                process_standard_deviation=float(
                    config["data"]["fixed_process_standard_deviation"]
                ),
                process_state_index=int(config["data"]["fixed_process_state_index"]),
                require_zero_projection=bool(config["data"]["require_zero_projection"]),
            )
        except ValueError as error:
            if "projection" not in str(error) or should_succeed:
                raise
            rejected_count += 1
        else:
            if not should_succeed:
                raise ValueError(
                    "a process-exhaustion ledger seed has a changed physical outcome"
                )
            accepted_count += 1
    return {
        "attempt_count": len(attempted),
        "accepted_attempt_count": accepted_count,
        "rejected_attempt_count": rejected_count,
        "outcome_exactly_replayed": bool(
            accepted_count == int(record["outcome"] == "accepted")
            and rejected_count
            == len(attempted) - int(record["outcome"] == "accepted")
        ),
    }


def _replay_physical_layer(
    config: Mapping[str, Any],
    h17_config: Mapping[str, Any],
    *,
    layer: str,
    schedule_ordinals: Sequence[int],
    generation: Mapping[str, np.ndarray],
    seed_audit: Mapping[str, Any],
) -> dict[str, Any]:
    records = seed_audit["layers"][layer]["process_attempts"]
    if len(records) != len(schedule_ordinals):
        raise ValueError(f"{layer} process-attempt record count changed")
    candidates = _parameter_candidates(h17_config)
    parameter_ids = tuple(candidates)
    warmup_id = str(config["data"]["warmup_parameter_id"])
    warmup_parameters = candidates[warmup_id]
    warmup_days = int(config["data"]["warmup_days"])
    total_days = int(config["data"]["assimilation_days"]) + int(
        config["data"]["maximum_forecast_lead"]
    )
    process_sd = float(config["data"]["fixed_process_standard_deviation"])
    process_state_index = int(config["data"]["fixed_process_state_index"])
    observation_sd = float(config["data"]["observation_standard_deviation"])
    covariance_fraction = float(config["data"]["initial_covariance_fraction"])
    flattened_rejected: list[int] = []
    accepted_values: list[int] = []
    maximum_difference = 0.0
    for rank, (schedule_ordinal, record) in enumerate(
        zip(schedule_ordinals, records), start=1
    ):
        requested, rejected, accepted = _attempt_record(
            config,
            layer=layer,
            rank=rank,
            schedule_ordinal=int(schedule_ordinal),
            record=record,
        )
        flattened_rejected.extend(rejected)
        accepted_values.append(accepted)
        expected_id = requested.block_id
        if str(generation[f"{layer}_block_ids"][rank - 1]) != expected_id:
            raise ValueError(f"{layer} block identifier changed at rank {rank}")
        if not np.array_equal(
            generation[f"{layer}_block_seed_matrix"][rank - 1],
            np.asarray(requested.all_seeds, dtype=np.int64),
        ):
            raise ValueError(f"{layer} block seed matrix changed at rank {rank}")

        complete_forcing = _forcing(
            requested.forcing_seed, warmup_days + total_days
        )
        warmup_truth = generate_reference_truth(
            complete_forcing[:warmup_days], warmup_parameters
        )
        initial_state = warmup_truth.states[-1].copy()
        active_forcing = complete_forcing[warmup_days:]
        schedule = _reproduce_schedule(
            seed=requested.schedule_seed,
            total_days=total_days,
            hazard=config["duration_hazard"],
        )
        for rejected_seed in rejected:
            try:
                _generate_one_truth(
                    forcing=active_forcing,
                    initial_state=initial_state,
                    schedule_indices=schedule["mode_indices"],
                    parameter_ids=parameter_ids,
                    parameter_candidates=candidates,
                    process_normals=np.random.default_rng(rejected_seed).standard_normal(
                        total_days
                    ),
                    process_standard_deviation=process_sd,
                    process_state_index=process_state_index,
                    require_zero_projection=bool(config["data"]["require_zero_projection"]),
                )
            except ValueError as error:
                if "projection" not in str(error):
                    raise
            else:
                raise ValueError(
                    f"a recorded rejected process seed now succeeds for {expected_id}"
                )
        truth = _generate_one_truth(
            forcing=active_forcing,
            initial_state=initial_state,
            schedule_indices=schedule["mode_indices"],
            parameter_ids=parameter_ids,
            parameter_candidates=candidates,
            process_normals=np.random.default_rng(accepted).standard_normal(total_days),
            process_standard_deviation=process_sd,
            process_state_index=process_state_index,
            require_zero_projection=bool(config["data"]["require_zero_projection"]),
        )
        observations = truth["discharge"] + observation_sd * np.random.default_rng(
            requested.observation_seed
        ).standard_normal(total_days)
        scales = np.maximum(np.abs(initial_state), 1.0)
        covariance = np.diag(np.square(covariance_fraction * scales))
        expected = {
            "forcing": active_forcing,
            "observations": observations,
            "truth_states": truth["states"],
            "truth_discharge": truth["discharge"],
            "true_parameter_indices": schedule["mode_indices"],
            "active_source_indices": schedule["active_source_indices"],
            "regime_age_before_transition": schedule[
                "regime_age_before_transition"
            ],
            "oracle_active_row_probabilities": schedule[
                "oracle_active_row_probabilities"
            ],
            "transition_evaluation_mask": schedule["transition_evaluation_mask"],
            "switch_event_mask": schedule["switch_event_mask"],
            "projection_adjustments": truth["projection_adjustments"],
            "process_perturbations": truth["process_perturbations"],
            "initial_states": initial_state,
            "initial_covariances": covariance,
        }
        for name, expected_value in expected.items():
            observed = generation[f"{layer}_{name}"][rank - 1]
            if not np.array_equal(observed, np.asarray(expected_value)):
                raise ValueError(
                    f"independent physical replay differs for {layer} rank {rank}: {name}"
                )
            if np.issubdtype(observed.dtype, np.floating) and observed.size:
                maximum_difference = max(
                    maximum_difference,
                    float(np.max(np.abs(observed - np.asarray(expected_value)))),
                )
    if not np.array_equal(
        generation[f"{layer}_accepted_process_seeds"],
        np.asarray(accepted_values, dtype=np.int64),
    ) or not np.array_equal(
        generation[f"{layer}_rejected_process_seeds"],
        np.asarray(flattened_rejected, dtype=np.int64),
    ):
        raise ValueError(f"{layer} flattened process seed evidence changed")
    return {
        "block_count": len(schedule_ordinals),
        "rejected_process_seed_count": len(flattened_rejected),
        "maximum_absolute_replay_difference": maximum_difference,
        "all_physical_arrays_exactly_replayed": True,
    }


def _bindings_match(
    schedule: Mapping[str, np.ndarray],
    generation: Mapping[str, np.ndarray],
    reserve: Mapping[str, np.ndarray],
    *,
    natural_count: int,
    coverage_count: int,
) -> bool:
    mapping = {
        "mode_indices": "true_parameter_indices",
        "active_source_indices": "active_source_indices",
        "regime_age_before_transition": "regime_age_before_transition",
        "oracle_active_row_probabilities": "oracle_active_row_probabilities",
        "transition_evaluation_mask": "transition_evaluation_mask",
        "switch_event_mask": "switch_event_mask",
    }
    reserve_mapping = {
        "forcing": "forcing",
        "observations": "observations",
        "initial_states": "initial_states",
        "initial_covariances": "initial_covariances",
        "source_indices": "active_source_indices",
        "target_probabilities": "oracle_active_row_probabilities",
        "evaluation_mask": "transition_evaluation_mask",
        "switch_event_mask": "switch_event_mask",
        "ages": "regime_age_before_transition",
    }
    for layer, count in (("natural_core", natural_count), ("coverage", coverage_count)):
        if any(
            not np.array_equal(
                schedule[f"{layer}_{schedule_name}"],
                generation[f"{layer}_{generation_name}"][:, : schedule[f"{layer}_{schedule_name}"].shape[1]],
            )
            for schedule_name, generation_name in mapping.items()
        ):
            return False
        for reserve_name, generation_name in reserve_mapping.items():
            left = reserve[f"{layer}_{reserve_name}"]
            right = generation[f"{layer}_{generation_name}"]
            if right.ndim >= 2 and right.shape[1] >= 300 and reserve_name not in {
                "initial_states",
                "initial_covariances",
            }:
                right = right[:, :300]
            if not np.array_equal(left, right):
                return False
        if reserve[f"{layer}_forcing"].shape[0] != count:
            return False
    return True


def _split_from_reserve(
    arrays: Mapping[str, np.ndarray], *, layer: str, days: int
) -> H17DataSplit:
    def tensor(name: str) -> torch.Tensor:
        return torch.from_numpy(np.asarray(arrays[f"{layer}_{name}"]).copy())

    return H17DataSplit(
        name=f"{layer}_independent_replay",
        observable=ObservableAssimilationBatch(
            forcing=tensor("forcing"),
            observations=tensor("observations"),
            initial_states=tensor("initial_states"),
            initial_covariances=tensor("initial_covariances"),
            assimilation_days=days,
        ),
        supervision=ActiveRowSupervision(
            source_indices=tensor("source_indices"),
            target_probabilities=tensor("target_probabilities"),
            evaluation_mask=tensor("evaluation_mask"),
            switch_event_mask=tensor("switch_event_mask"),
            regime_age_before_transition=tensor("ages"),
        ),
    )


def _duration_network(
    h17_config: Mapping[str, Any], base_transition: torch.Tensor
) -> CausalSemiMarkovTransitionModule:
    contract = h17_config["duration_contract"]
    return CausalSemiMarkovTransitionModule(
        base_transition=base_transition,
        maximum_age=int(contract["maximum_age"]),
        hazard_hidden_size=int(contract["hazard_hidden_size"]),
        maximum_logit_correction=float(contract["maximum_logit_correction"]),
        minimum_differentiable_mode_probability=float(
            contract["minimum_differentiable_mode_probability"]
        ),
        age_risk_representation=str(contract["age_risk_representation"]),
        piecewise_knot_count=int(contract["piecewise_knot_count"]),
    )


def _load_replay_models(
    config: Mapping[str, Any], h17_config: Mapping[str, Any], root: Path
) -> tuple[Any, dict[str, CausalSemiMarkovTransitionModule], dict[str, Any]]:
    base = _base_transition(h17_config)
    static_path = root / "static_reference_checkpoint.pt"
    if _sha256(static_path) != str(config["static_reference"]["checkpoint_sha256"]):
        raise ValueError("the copied static checkpoint hash changed")
    static_payload = torch.load(static_path, map_location="cpu", weights_only=False)
    if (
        static_payload.get("experiment_id")
        != "h17_supervised_active_row_probability_upper_bound_v01"
        or static_payload.get("method") != "learned_history_free_static_matrix"
        or int(static_payload.get("test_reads_before_selection", -1)) != 0
    ):
        raise ValueError("the copied static checkpoint metadata changed")
    static = _static_network(h17_config, base)
    static.load_state_dict(static_payload["network_state_dict"], strict=True)
    static.eval()
    histories: dict[str, CausalSemiMarkovTransitionModule] = {}
    audit: dict[str, Any] = {"static": {"sha256": _sha256(static_path)}, "histories": {}}
    for specification in config["source_h17f"]["checkpoints"]:
        seed = int(specification["initialization_seed"])
        path = root / f"history_seed_{seed}_checkpoint.pt"
        if _sha256(path) != str(specification["sha256"]):
            raise ValueError(f"the copied history checkpoint hash changed for {seed}")
        payload = torch.load(path, map_location="cpu", weights_only=False)
        if (
            payload.get("experiment_id") != config["source_h17f"]["experiment_id"]
            or int(payload.get("initialization_seed", -1)) != seed
            or int(payload.get("best_epoch", -1)) != int(specification["selected_epoch"])
            or payload.get("transition_architecture") != "explicit_causal_duration"
            or int(payload.get("test_reads_before_selection", -1)) != 0
            or bool(payload.get("warm_started"))
        ):
            raise ValueError(f"the copied history checkpoint metadata changed for {seed}")
        network = _duration_network(h17_config, base)
        network.load_state_dict(payload["network_state_dict"], strict=True)
        network.eval()
        histories[str(seed)] = network
        audit["histories"][str(seed)] = {
            "sha256": _sha256(path),
            "best_epoch": int(payload["best_epoch"]),
        }
    audit["semantic_replay_checkpoint_load_count"] = 4
    return static, histories, audit


def _evaluate_replay(
    split: H17DataSplit,
    *,
    h17_config: Mapping[str, Any],
    static: Any,
    histories: Mapping[str, CausalSemiMarkovTransitionModule],
) -> dict[str, ProbabilityRolloutResult]:
    candidates = _parameter_candidates(h17_config)
    with torch.no_grad():
        results: dict[str, ProbabilityRolloutResult] = {
            "static": rollout_static_probability(
                split.supervision,
                static,
                dtype=split.observable.forcing.dtype,
                device=split.observable.forcing.device,
            )
        }
        for seed, network in histories.items():
            results[f"history_seed_{seed}"] = rollout_semi_markov_probability(
                split.observable,
                split.supervision,
                network,
                _estimator(h17_config, candidates),
            )
    return results


def _slice_split(split: H17DataSplit, count: int) -> H17DataSplit:
    return H17DataSplit(
        name=f"{split.name}_audit",
        observable=replace(
            split.observable,
            forcing=split.observable.forcing[:count].clone(),
            observations=split.observable.observations[:count].clone(),
            initial_states=split.observable.initial_states[:count].clone(),
            initial_covariances=split.observable.initial_covariances[:count].clone(),
        ),
        supervision=replace(
            split.supervision,
            source_indices=split.supervision.source_indices[:count].clone(),
            target_probabilities=split.supervision.target_probabilities[:count].clone(),
            evaluation_mask=split.supervision.evaluation_mask[:count].clone(),
            switch_event_mask=split.supervision.switch_event_mask[:count].clone(),
            regime_age_before_transition=split.supervision.regime_age_before_transition[
                :count
            ].clone(),
        ),
    )


def _independent_causality(
    config: Mapping[str, Any],
    h17_config: Mapping[str, Any],
    split: H17DataSplit,
    histories: Mapping[str, CausalSemiMarkovTransitionModule],
    baseline_results: Mapping[str, ProbabilityRolloutResult],
) -> dict[str, Any]:
    audit_split = _slice_split(
        split, int(config["evaluation_contract"]["causality_audit_natural_blocks"])
    )
    day = 3
    per_seed: dict[str, Any] = {}
    candidates = _parameter_candidates(h17_config)
    with torch.no_grad():
        for seed, network in histories.items():
            baseline = baseline_results[f"history_seed_{seed}"].transition_matrices[
                : audit_split.observable.forcing.shape[0]
            ]
            current_observations = audit_split.observable.observations.clone()
            current_observations[:, day] += 5.0
            current = rollout_semi_markov_probability(
                replace(audit_split.observable, observations=current_observations),
                audit_split.supervision,
                network,
                _estimator(h17_config, candidates),
            ).transition_matrices
            future_observations = audit_split.observable.observations.clone()
            future_observations[:, day + 1] += 5.0
            future = rollout_semi_markov_probability(
                replace(audit_split.observable, observations=future_observations),
                audit_split.supervision,
                network,
                _estimator(h17_config, candidates),
            ).transition_matrices
            per_seed[seed] = {
                "current_observation_effect_on_same_day_transition": float(
                    torch.max(torch.abs(baseline[:, day] - current[:, day]))
                ),
                "future_observation_effect_on_earlier_transition": float(
                    torch.max(torch.abs(baseline[:, day] - future[:, day]))
                ),
            }
    current_maximum = max(
        value["current_observation_effect_on_same_day_transition"]
        for value in per_seed.values()
    )
    future_maximum = max(
        value["future_observation_effect_on_earlier_transition"]
        for value in per_seed.values()
    )
    return {
        "per_seed": per_seed,
        "maximum_current_observation_effect_on_same_day_transition": current_maximum,
        "maximum_future_observation_effect_on_earlier_transition": future_maximum,
        "forbidden_training_input_count": 0,
        "passed": bool(
            current_maximum
            <= float(config["evaluation_contract"]["maximum_same_day_observation_effect"])
            and future_maximum
            <= float(config["evaluation_contract"]["maximum_future_observation_effect"])
        ),
    }


def _replay_checkpoints(
    config: Mapping[str, Any],
    h17_config: Mapping[str, Any],
    root: Path,
    reserve: Mapping[str, np.ndarray],
    saved_causality: Mapping[str, Any],
) -> dict[str, Any]:
    days = int(config["data"]["assimilation_days"])
    static, histories, checkpoint_audit = _load_replay_models(
        config, h17_config, root
    )
    splits = {
        layer: _split_from_reserve(reserve, layer=layer, days=days)
        for layer in ("natural_core", "coverage")
    }
    results = {
        layer: _evaluate_replay(
            split,
            h17_config=h17_config,
            static=static,
            histories=histories,
        )
        for layer, split in splits.items()
    }
    replay_arrays = dict(reserve)
    maximum_differences: dict[str, float] = {}
    for layer, layer_results in results.items():
        for method, result in layer_results.items():
            replayed = result.transition_matrices.detach().cpu().numpy()
            saved = reserve[f"{layer}_{method}_transition_matrices"]
            difference = float(np.max(np.abs(replayed - saved))) if saved.size else 0.0
            maximum_differences[f"{layer}_{method}"] = difference
            if not np.allclose(replayed, saved, rtol=0.0, atol=1e-10):
                raise ValueError(
                    f"the saved transition matrices do not match checkpoint replay: {layer} {method}"
                )
            replay_arrays[f"{layer}_{method}_transition_matrices"] = replayed
    metrics, stratified, legality = _independent_metrics(config, replay_arrays)
    independent_causality = _independent_causality(
        config,
        h17_config,
        splits["natural_core"],
        histories,
        results["natural_core"],
    )
    causality_matches = (
        _close(
            saved_causality.get(
                "maximum_current_observation_effect_on_same_day_transition"
            ),
            independent_causality[
                "maximum_current_observation_effect_on_same_day_transition"
            ],
        )
        and _close(
            saved_causality.get(
                "maximum_future_observation_effect_on_earlier_transition"
            ),
            independent_causality[
                "maximum_future_observation_effect_on_earlier_transition"
            ],
        )
        and int(saved_causality.get("forbidden_training_input_count", -1)) == 0
        and independent_causality["passed"] is True
    )
    return {
        "metrics": metrics,
        "stratified_metrics": stratified,
        "legality": legality,
        "causality": independent_causality,
        "causality_matches": causality_matches,
        "checkpoint_audit": checkpoint_audit,
        "maximum_transition_matrix_replay_differences": maximum_differences,
        "all_transition_matrices_match": all(
            value <= 1e-10 for value in maximum_differences.values()
        ),
    }


def _source_snapshot_matches(root: Path, project_root: Path) -> bool:
    manifest = _read_json(root / "source_manifest.json")
    entries = manifest["entries"]
    expected_names = [entry["path"] for entry in entries]
    with zipfile.ZipFile(root / "source_snapshot.zip", "r") as archive:
        if archive.namelist() != expected_names:
            return False
        for entry in entries:
            data = archive.read(entry["path"])
            if len(data) != int(entry["size_bytes"]):
                return False
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                return False
            live = project_root / entry["path"]
            if not live.is_file() or _sha256(live) != entry["sha256"]:
                return False
    return True


def _registry_check(
    config: Mapping[str, Any], project_root: Path, decision: Mapping[str, Any], *, terminal: bool
) -> tuple[bool, int]:
    path = project_root / "src/hbv_history_conditioned_imm/configs/experiment_registry.csv"
    with path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    matches = [row for row in rows if row["exp_id"] == config["experiment_id"]]
    h18_count = sum(row["exp_id"].lower().startswith("h18") for row in rows)
    expected_status = (
        decision["registry_completion_status"]
        if terminal
        else config["registry_contract"]["eligible_status"]
    )
    return (
        len(matches) == 1
        and matches[0]["status"] == expected_status
        and matches[0]["run_dir"] == config["result_relative_path"]
        and matches[0]["metrics_path"] == config["registry_contract"]["metrics_relative_path"],
        h18_count,
    )


def _legacy_incomplete_verify_h17r_result(
    result_directory: str | Path,
    *,
    project_root: str | Path,
    verify_checksums: bool = True,
    verify_live_registry: bool = True,
) -> dict[str, Any]:
    raise RuntimeError("the incomplete legacy H17R verifier is permanently disabled")
    root = Path(result_directory).resolve()
    project = Path(project_root).resolve()
    config = _read_json(root / "config_snapshot.json")
    if config.get("experiment_id") != EXPECTED_EXPERIMENT_ID:
        raise ValueError("unexpected H17R result identity")
    required = set(str(value) for value in config["required_result_files"])
    found = {path.name for path in root.iterdir() if path.is_file()}
    expected_found = required if verify_checksums else required - {
        "independent_verification.json",
        "checksums.json",
    }
    exact_files = found == expected_found
    checksum_coverage = True
    checksums_match = True
    if verify_checksums:
        checksums = _read_json(root / "checksums.json")
        checksum_coverage = set(checksums) == required - {"checksums.json"}
        checksums_match = checksum_coverage and all(
            (root / name).is_file() and _sha256(root / name) == digest
            for name, digest in checksums.items()
        )

    open_audit = _read_json(root / "reserve_open_audit.json")
    execution = _read_json(root / "execution_audit.json")
    coverage_report = _read_json(root / "coverage_report.json")
    generation = _read_json(root / "generation_audit.json")
    checkpoint = _read_json(root / "checkpoint_integrity_audit.json")
    saved_metrics = _read_json(root / "metrics.json")
    saved_stratified = _read_json(root / "stratified_metrics.json")
    saved_legality = _read_json(root / "probability_legality_audit.json")
    causality = _read_json(root / "causality_audit.json")
    decision = _read_json(root / "decision.json")
    seed_audit = _read_json(root / "seed_namespace_audit.json")

    natural_schedules, accepted, coverage_schedules, counts, inspected = (
        _independent_schedules(config)
    )
    with np.load(root / "schedule_arrays.npz", allow_pickle=False) as source:
        schedule_arrays = {name: source[name] for name in source.files}
    schedules_match = (
        _schedule_arrays_match(schedule_arrays, "natural_core", natural_schedules)
        and _schedule_arrays_match(schedule_arrays, "coverage", coverage_schedules)
        and np.array_equal(
            schedule_arrays["coverage_accepted_candidate_ordinals"],
            np.asarray(accepted, dtype=np.int64),
        )
    )
    coverage_matches = (
        bool(coverage_report["coverage_passed"])
        and accepted == coverage_report["accepted_candidate_ordinals"]
        and len(accepted) == int(coverage_report["accepted_coverage_block_count"])
        and inspected == int(coverage_report["candidate_schedules_inspected"])
        and all(
            np.array_equal(counts[name], np.asarray(coverage_report["counts"][name]))
            for name in counts
        )
        and _complete(counts, _thresholds(config))
    )

    with np.load(root / "reserve_arrays.npz", allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    independent_metrics, independent_stratified, independent_legality = (
        _independent_metrics(config, arrays)
    )
    metrics_match = _close(saved_metrics, independent_metrics)
    stratified_match = _close(saved_stratified, independent_stratified)
    legality_match = all(
        _close(saved_legality[key], independent_legality[key])
        for key in (
            "maximum_transition_row_sum_error",
            "minimum_transition_probability",
            "all_values_finite",
            "passed",
        )
    )
    causality_passed = (
        float(causality["maximum_current_observation_effect_on_same_day_transition"])
        == 0.0
        and float(causality["maximum_future_observation_effect_on_earlier_transition"])
        == 0.0
        and int(causality["forbidden_training_input_count"]) == 0
    )
    expected_pass = bool(
        coverage_matches
        and independent_metrics["all_42_performance_conditions_passed"]
        and independent_legality["passed"]
        and causality_passed
    )
    expected_decision = (
        config["decision_contract"]["pass_decision"]
        if expected_pass
        else config["decision_contract"]["hold_decision"]
    )
    expected_status = (
        config["registry_contract"]["completion_status_pass"]
        if expected_pass
        else config["registry_contract"]["completion_status_hold"]
    )
    decision_matches = (
        decision["passed"] is expected_pass
        and decision["decision"] == expected_decision
        and decision["registry_completion_status"] == expected_status
        and decision["h18_authorized"] is False
    )
    registry_matches, h18_rows = _registry_check(
        config, project, decision, terminal=verify_live_registry
    )
    h18_results = list(
        (project / "results/23_hbv_multilead_joint_uncertainty").glob("h18*")
    )
    checkpoint_hashes = (
        _sha256(root / "static_reference_checkpoint.pt")
        == config["static_reference"]["checkpoint_sha256"]
        and all(
            _sha256(root / f"history_seed_{int(item['initialization_seed'])}_checkpoint.pt")
            == item["sha256"]
            for item in config["source_h17f"]["checkpoints"]
        )
        and checkpoint["checkpoint_load_count_before_coverage_pass"] == 0
        and checkpoint["checkpoint_selection_performed"] is False
    )
    source_hashes = all(
        _sha256(project / relative) == expected
        for relative, expected in config["source_dependency_contract"].items()
    )
    related_h17r_paths = _related_result_paths(project, "h17r")
    related_h17r_paths_match = all(
        path.resolve() == root for path in related_h17r_paths
    ) and len(related_h17r_paths) <= 1
    execution_matches = (
        int(open_audit["open_event_count"]) == 1
        and open_audit["resume_allowed"] is False
        and open_audit["retry_allowed"] is False
        and int(execution["reserve_open_event_count"]) == 1
        and int(execution["decision_bearing_evaluation_events"]) == 1
        and execution["training_started"] is False
        and execution["optimizer_created"] is False
        and execution["checkpoint_selection_performed"] is False
        and execution["same_identifier_resume_or_retry_allowed"] is False
    )
    generation_matches = (
        int(generation["natural_core_block_count"]) == 120
        and int(generation["coverage_block_count"]) == len(accepted)
        and float(generation["maximum_absolute_projection_adjustment"]) == 0.0
        and generation["all_physical_values_finite"] is True
        and seed_audit["actual_seeds_disjoint_from_h16_and_h17p"] is True
        and seed_audit["committed_seed_unique"] is True
        and seed_audit["legacy_process_seed_arithmetic_used"] is False
        and seed_audit["all_generation_calls_maximum_process_resamples"] == 1
    )
    natural_count = int(np.count_nonzero(arrays["natural_core_evaluation_mask"]))
    shape_contract = (
        arrays["natural_core_forcing"].shape == (120, 300, 3)
        and natural_count == 35880
        and arrays["coverage_forcing"].shape == (len(accepted), 300, 3)
    )
    checks = {
        "exact_required_file_set": exact_files,
        "checksum_coverage": checksum_coverage,
        "checksums_match": checksums_match,
        "source_snapshot_matches_manifest_and_live_sources": _source_snapshot_matches(
            root, project
        ),
        "runtime_source_hashes_match": source_hashes,
        "single_nonresumable_reserve_open": execution_matches,
        "final_schedules_independently_reproduce": schedules_match,
        "coverage_selection_and_thresholds_independently_match": coverage_matches,
        "physical_generation_and_seed_contract_match": generation_matches,
        "checkpoint_hashes_and_no_selection_match": checkpoint_hashes,
        "reserve_array_shapes_and_natural_count_match": shape_contract,
        "natural_and_coverage_metrics_independently_match": metrics_match,
        "rare_source_by_age_metrics_independently_match": stratified_match,
        "probability_legality_independently_matches": legality_match,
        "causality_and_forbidden_input_gates_pass": causality_passed,
        "all_42_gate_decision_matches": decision_matches,
        "live_registry_status_matches": registry_matches,
        "h18_registry_and_result_counts_are_zero": h18_rows == 0 and not h18_results,
    }
    return {
        "experiment_id": config["experiment_id"],
        "verify_checksums_requested": verify_checksums,
        "verify_live_registry_requested": verify_live_registry,
        "checks": checks,
        "independent_values": {
            "accepted_coverage_block_count": len(accepted),
            "candidate_schedules_inspected": inspected,
            "natural_scored_transition_count": natural_count,
            "passed_performance_condition_count": int(
                independent_metrics["passed_gate_count"]
            ),
            "failed_performance_condition_count": int(
                independent_metrics["failed_gate_count"]
            ),
            "decision": expected_decision,
        },
        "verified": all(checks.values()),
    }


def _source_snapshot_matches_v2(
    root: Path, project_root: Path, config: Mapping[str, Any]
) -> bool:
    manifest = _read_json(root / "source_manifest.json")
    expected_names = sorted(str(value) for value in config["source_snapshot"]["files"])
    entries = manifest.get("entries", [])
    if (
        manifest.get("format") != config["source_snapshot"]["format"]
        or manifest.get("fixed_zip_timestamp")
        != config["source_snapshot"]["fixed_zip_timestamp"]
        or int(manifest.get("source_file_count", -1)) != len(expected_names)
        or [entry.get("path") for entry in entries] != expected_names
    ):
        return False
    with zipfile.ZipFile(root / "source_snapshot.zip", "r") as archive:
        if archive.namelist() != expected_names:
            return False
        for information, entry in zip(archive.infolist(), entries):
            if (
                tuple(information.date_time) != (1980, 1, 1, 0, 0, 0)
                or information.filename != entry["path"]
                or information.compress_type != zipfile.ZIP_DEFLATED
            ):
                return False
            data = archive.read(entry["path"])
            if (
                len(data) != int(entry["size_bytes"])
                or hashlib.sha256(data).hexdigest() != entry["sha256"]
            ):
                return False
            live = project_root / entry["path"]
            if not live.is_file() or _sha256(live) != entry["sha256"]:
                return False
    return True


def _checksum_manifest_valid_v2(directory: Path) -> bool:
    manifest = _read_json(directory / "checksums.json")
    found = {
        path.name
        for path in directory.iterdir()
        if path.is_file() and path.name != "checksums.json"
    }
    return set(manifest) == found and all(
        _sha256(directory / name) == str(digest) for name, digest in manifest.items()
    )


def _upstream_hashes_match_v2(config: Mapping[str, Any], project: Path) -> bool:
    specifications = {
        project / str(config["source_h16"]["declaration"]["path"]): config[
            "source_h16"
        ]["declaration"]["sha256"],
        project / str(config["source_h17p"]["declaration"]["path"]): config[
            "source_h17p"
        ]["declaration"]["sha256"],
        project / str(config["source_h17f"]["declaration"]["path"]): config[
            "source_h17f"
        ]["declaration"]["sha256"],
        project
        / str(config["source_h16"]["result_directory"])
        / "config_snapshot.json": config["source_h16"]["config_snapshot_sha256"],
        project
        / str(config["source_h16"]["result_directory"])
        / "independent_verification.json": config["source_h16"][
            "independent_verification_sha256"
        ],
        project
        / str(config["source_h17p"]["result_directory"])
        / "independent_verification.json": config["source_h17p"][
            "independent_verification_sha256"
        ],
        project
        / str(config["source_h17f"]["result_directory"])
        / "config_snapshot.json": config["source_h17f"]["config_snapshot_sha256"],
        project
        / str(config["source_h17f"]["result_directory"])
        / "independent_verification.json": config["source_h17f"][
            "independent_verification_sha256"
        ],
        project / str(config["static_reference"]["checkpoint_path"]): config[
            "static_reference"
        ]["checkpoint_sha256"],
        (
            project / str(config["static_reference"]["checkpoint_path"])
        ).parent
        / "checksums.json": config["static_reference"]["checksums_sha256"],
    }
    for checkpoint in config["source_h17f"]["checkpoints"]:
        specifications[project / str(checkpoint["path"])] = checkpoint["sha256"]
    if not all(
        path.is_file() and _sha256(path) == str(digest)
        for path, digest in specifications.items()
    ):
        return False
    for source_name in ("source_h16", "source_h17p", "source_h17f"):
        result = project / str(config[source_name]["result_directory"])
        if not _checksum_manifest_valid_v2(result):
            return False
    static_root = (
        project / str(config["static_reference"]["checkpoint_path"])
    ).parent
    if not _checksum_manifest_valid_v2(static_root):
        return False
    h17f_metrics = _read_json(
        project / str(config["source_h17f"]["result_directory"]) / "metrics.json"
    )
    if h17f_metrics.get("decision") != config["eligibility_contract"][
        "h17f_required_decision"
    ]:
        return False
    return all(
        _read_json(
            project
            / str(config[source]["result_directory"])
            / "independent_verification.json"
        ).get("verified")
        is True
        for source in ("source_h16", "source_h17p", "source_h17f")
    )


def _registry_check_v2(
    config: Mapping[str, Any],
    project_root: Path,
    decision: Mapping[str, Any],
    anchored: Mapping[str, Any],
    saved_row: Mapping[str, str],
    *,
    terminal: bool,
) -> tuple[bool, int]:
    rows = _registry_rows(project_root)
    matches = [row for row in rows if row["exp_id"] == config["experiment_id"]]
    h18_count = sum(row["exp_id"].lower().startswith("h18") for row in rows)
    expected_live_status = (
        decision["registry_completion_status"]
        if terminal
        else config["registry_contract"]["eligible_status"]
    )
    saved_terminal = (
        saved_row.get("status") == decision["registry_completion_status"]
        and anchored["registry_note_token"] in saved_row.get("notes", "")
        and _immutable_registry_fields(saved_row)
        == anchored["manifest"]["registry_immutable_fields"]
    )
    live_valid = (
        len(matches) == 1
        and matches[0]["status"] == expected_live_status
        and anchored["registry_note_token"] in matches[0]["notes"]
        and _immutable_registry_fields(matches[0])
        == anchored["manifest"]["registry_immutable_fields"]
    )
    return bool(saved_terminal and live_valid), h18_count


def _load_npz(path: Path) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as source:
        return {name: source[name].copy() for name in source.files}


def _base_verification_v2(
    result_directory: str | Path,
    *,
    project_root: str | Path,
    verify_checksums: bool,
    verify_live_registry: bool,
    approved_preregistration_sha256: str,
) -> dict[str, Any]:
    root = Path(result_directory).resolve()
    project = Path(project_root).resolve()
    config = _read_json(root / "config_snapshot.json")
    if config.get("experiment_id") != EXPECTED_EXPERIMENT_ID:
        raise ValueError("unexpected H17R result identity")
    anchored = _anchored_context(
        config,
        project,
        approved_preregistration_sha256=approved_preregistration_sha256,
    )
    decision = _read_json(root / "decision.json")
    outcome = str(decision.get("outcome", ""))
    terminal_metrics = _read_json(root / "metrics.json")
    if outcome == "complete_evaluation":
        required = set(str(value) for value in config["required_result_files"])
    elif outcome == "coverage_hold":
        required = set(str(value) for value in config["coverage_hold_result_files"])
    elif outcome == "process_exhaustion_hold":
        required = set(
            str(value) for value in config["process_exhaustion_hold_result_files"]
        )
        partial = _read_json(root / "partial_artifact_manifest.json")
        if (
            set(partial)
            != {"outcome", "files", "all_listed_files_must_be_checksummed"}
            or partial.get("outcome") != "process_exhaustion_hold"
            or partial.get("all_listed_files_must_be_checksummed") is not True
            or set(str(value) for value in partial["files"])
            != required - {
                "partial_artifact_manifest.json",
                "checksums.json",
            }
        ):
            raise ValueError("the process-exhaustion partial manifest changed")
    elif outcome == "execution_hold":
        partial = _read_json(root / "partial_artifact_manifest.json")
        required = set(str(value) for value in partial["files"])
        required.update({"partial_artifact_manifest.json", "checksums.json"})
    else:
        raise ValueError("the H17R result has an unknown terminal outcome")
    found = {path.name for path in root.iterdir() if path.is_file()}
    if any(name.endswith(".tmp") for name in found):
        raise ValueError("the H17R result contains a temporary file")
    expected_found = (
        required
        if verify_checksums
        else required - {"independent_verification.json", "checksums.json"}
    )
    exact_files = found == expected_found
    checksum_coverage = True
    checksums_match = True
    saved_independent_verified = True
    if verify_checksums:
        checksums = _read_json(root / "checksums.json")
        checksum_coverage = set(checksums) == required - {"checksums.json"}
        checksums_match = checksum_coverage and all(
            (root / name).is_file() and _sha256(root / name) == str(digest)
            for name, digest in checksums.items()
        )
        independent = _read_json(root / "independent_verification.json")
        saved_independent_verified = (
            independent.get("verified") is True
            and independent.get("semantic_replay_requested") is True
        )

    open_audit = _read_json(root / "reserve_open_audit.json")
    execution = _read_json(root / "execution_audit.json")
    eligibility = _read_json(root / "eligibility_audit.json")
    saved_row = _read_json(root / "registry_entry.json")
    registry_open_entry = _read_json(root / "registry_open_entry.json")
    registry_open_snapshot_path = root / "registry_open_snapshot.csv"
    expected_tombstone_bindings = {
        "preregistration_manifest_sha256": anchored["manifest_sha256"],
        "live_config_sha256": anchored["live_config_sha256"],
        "eligible_registry_row_sha256": eligibility[
            "eligible_registry_row_sha256"
        ],
        "eligible_registry_file_sha256": eligibility[
            "eligible_registry_file_sha256"
        ],
        "immutable_registry_fields_sha256": anchored[
            "immutable_registry_fields_sha256"
        ],
        "source_manifest_sha256": _sha256(root / "source_manifest.json"),
        "source_snapshot_sha256": _sha256(root / "source_snapshot.zip"),
        "h17p_independent_verification_sha256": config["source_h17p"][
            "independent_verification_sha256"
        ],
        "h17f_independent_verification_sha256": config["source_h17f"][
            "independent_verification_sha256"
        ],
        "static_reference_checkpoint_sha256": config["static_reference"][
            "checkpoint_sha256"
        ],
        "staged_config_snapshot_sha256": _sha256(root / "config_snapshot.json"),
        "staged_eligibility_audit_sha256": _sha256(root / "eligibility_audit.json"),
        "staged_generator_contract_sha256": _sha256(root / "generator_contract.json"),
        "staged_registry_open_entry_sha256": _sha256(
            root / "registry_open_entry.json"
        ),
        "staged_registry_open_snapshot_sha256": _sha256(
            registry_open_snapshot_path
        ),
        "staged_environment_sha256": _sha256(root / "environment.json"),
        "externally_approved_preregistration_sha256": anchored[
            "externally_approved_sha256"
        ],
    }
    canonical_final = (project / str(config["result_relative_path"])).resolve()
    canonical_staging = canonical_final.parent / f".{config['experiment_id']}.staging-sealed"
    tombstone_path = _reserve_open_tombstone_path(project, config)
    tombstone_matches = False
    permanent_tombstone_sha256 = None
    if _lexists(tombstone_path) and tombstone_path.is_file() and not tombstone_path.is_symlink():
        tombstone = _read_json(tombstone_path)
        permanent_tombstone_sha256 = _sha256(tombstone_path)
        tombstone_matches = (
            tombstone.get("schema") == "permanent_single_reserve_open_tombstone_v1"
            and tombstone.get("experiment_id") == config["experiment_id"]
            and tombstone.get("open_event_id")
            == f"{config['experiment_id']}:final_reserve:1"
            and int(tombstone.get("open_event_count", -1)) == 1
            and tombstone.get("stage") == "final_reserve"
            and tombstone.get("result_relative_path") == config["result_relative_path"]
            and tombstone.get("canonical_final_path") == str(canonical_final)
            and tombstone.get("canonical_staging_path") == str(canonical_staging.resolve())
            and tombstone.get("canonical_tombstone_path") == str(tombstone_path.resolve())
            and tombstone.get("replacement_or_deletion_allowed") is False
            and tombstone.get("same_identifier_reopen_allowed") is False
            and tombstone.get("resume_allowed") is False
            and tombstone.get("retry_allowed") is False
            and tombstone.get("training_allowed") is False
            and tombstone.get("h18_authorized") is False
            and int(tombstone.get("pre_open_schedule_read_count", -1)) == 0
            and int(tombstone.get("pre_open_target_read_count", -1)) == 0
            and int(tombstone.get("pre_open_score_read_count", -1)) == 0
            and tombstone.get("bindings") == expected_tombstone_bindings
        )
    expected_bindings = {
        **expected_tombstone_bindings,
        "permanent_tombstone_sha256": permanent_tombstone_sha256,
    }
    marker_matches = (
        open_audit.get("schema") == "single_decision_bearing_reserve_open_v1"
        and open_audit.get("experiment_id") == config["experiment_id"]
        and open_audit.get("open_event_id")
        == f"{config['experiment_id']}:final_reserve:1"
        and int(open_audit.get("open_event_count", -1)) == 1
        and open_audit.get("stage") == "final_reserve"
        and open_audit.get("resume_allowed") is False
        and open_audit.get("retry_allowed") is False
        and open_audit.get("training_allowed") is False
        and int(open_audit.get("pre_open_schedule_read_count", -1)) == 0
        and int(open_audit.get("pre_open_target_read_count", -1)) == 0
        and int(open_audit.get("pre_open_score_read_count", -1)) == 0
        and open_audit.get("permanent_tombstone_sha256")
        == permanent_tombstone_sha256
        and open_audit.get("bindings") == expected_bindings
    )
    execution_common = (
        int(execution.get("reserve_open_event_count", -1)) == 1
        and execution.get("training_started") is False
        and execution.get("optimizer_created") is False
        and execution.get("checkpoint_selection_performed") is False
        and execution.get("architecture_or_hyperparameter_selection_performed")
        is False
        and execution.get("human_intermediate_target_or_score_inspection") is False
        and execution.get("same_identifier_resume_or_retry_allowed") is False
        and execution.get("h18_registered_or_run") is False
    )
    registry_matches, h18_rows = _registry_check_v2(
        config,
        project,
        decision,
        anchored,
        saved_row,
        terminal=verify_live_registry,
    )
    with registry_open_snapshot_path.open("r", encoding="utf-8", newline="") as handle:
        open_rows = list(csv.DictReader(handle))
    matching_open_rows = [
        row for row in open_rows if row.get("exp_id") == config["experiment_id"]
    ]
    registry_open_matches = (
        _sha256(registry_open_snapshot_path)
        == eligibility["eligible_registry_file_sha256"]
        and len(matching_open_rows) == 1
        and matching_open_rows[0] == registry_open_entry
        and registry_open_entry.get("status")
        == config["registry_contract"]["eligible_status"]
        and _mapping_sha256(registry_open_entry)
        == eligibility["eligible_registry_row_sha256"]
        and anchored["registry_note_token"] in registry_open_entry.get("notes", "")
        and _immutable_registry_fields(registry_open_entry)
        == anchored["manifest"]["registry_immutable_fields"]
    )
    source_hashes = all(
        (project / relative).is_file()
        and _sha256(project / relative) == str(expected)
        for relative, expected in config["source_dependency_contract"].items()
    )
    related_h17r_paths = _related_result_paths(project, "h17r")
    related_h17r_paths_match = all(
        path.resolve() == root for path in related_h17r_paths
    ) and len(related_h17r_paths) <= 1
    expected_metrics_relative_path = f"{config['result_relative_path']}/metrics.json"
    metrics_link_matches = (
        config["registry_contract"]["metrics_relative_path"]
        == expected_metrics_relative_path
        and registry_open_entry.get("metrics_path") == expected_metrics_relative_path
        and saved_row.get("metrics_path") == expected_metrics_relative_path
        and (root / "metrics.json").is_file()
        and (
            outcome == "complete_evaluation"
            or (
                set(terminal_metrics)
                == {
                    "schema",
                    "outcome",
                    "evaluation_performed",
                    "all_42_performance_conditions_passed",
                    "passed_gate_count",
                    "failed_gate_count",
                    "reason",
                }
                and
                terminal_metrics.get("schema") == "h17r_terminal_metrics_v1"
                and terminal_metrics.get("outcome") == outcome
                and terminal_metrics.get("evaluation_performed") is False
                and terminal_metrics.get("all_42_performance_conditions_passed")
                is False
                and terminal_metrics.get("passed_gate_count") is None
                and terminal_metrics.get("failed_gate_count") is None
                and isinstance(terminal_metrics.get("reason"), str)
                and bool(terminal_metrics.get("reason"))
            )
        )
    )
    checks = {
        "exact_required_file_set": exact_files,
        "checksum_coverage": checksum_coverage,
        "checksums_match": checksums_match,
        "saved_semantic_verification_passes": saved_independent_verified,
        "external_preregistration_anchor_matches": True,
        "externally_approved_preregistration_hash_matches": (
            anchored["manifest_sha256"]
            == anchored["externally_approved_sha256"]
        ),
        "eligible_registry_open_snapshot_matches": registry_open_matches,
        "registry_metrics_path_resolves_for_terminal_outcome": metrics_link_matches,
        "no_other_visible_or_hidden_h17r_result_path_exists": related_h17r_paths_match,
        "source_snapshot_matches_manifest_and_live_sources": _source_snapshot_matches_v2(
            root, project, config
        ),
        "runtime_source_hashes_match": source_hashes,
        "upstream_frozen_evidence_matches": _upstream_hashes_match_v2(config, project),
        "single_nonresumable_reserve_open_and_bindings_match": marker_matches,
        "permanent_reserve_open_tombstone_matches": tombstone_matches,
        "execution_prohibitions_match": execution_common,
        "saved_and_live_registry_rows_match_contract": registry_matches,
        "h18_registry_and_visible_or_hidden_result_counts_are_zero": (
            h18_rows == 0 and not _related_result_paths(project, "h18")
        ),
    }
    return {
        "root": root,
        "project": project,
        "config": config,
        "anchored": anchored,
        "decision": decision,
        "outcome": outcome,
        "execution": execution,
        "checks": checks,
        "independent_values": {"outcome": outcome, "decision": decision.get("decision")},
    }


def _semantic_schedule_v2(context: dict[str, Any]) -> dict[str, Any]:
    root = context["root"]
    config = context["config"]
    schedule_arrays = _load_npz(root / "schedule_arrays.npz")
    evidence = _schedule_schema_and_replay(config, schedule_arrays)
    accepted = evidence["accepted_ordinals"]
    counts = evidence["counts"]
    thresholds = _thresholds(config)
    coverage_complete = _complete(counts, thresholds)
    coverage_report = _read_json(root / "coverage_report.json")
    coverage_matches = (
        bool(coverage_report["coverage_passed"]) is coverage_complete
        and coverage_report["accepted_candidate_ordinals"] == accepted
        and int(coverage_report["candidate_schedules_inspected"])
        == evidence["inspected"]
        and int(coverage_report["accepted_coverage_block_count"]) == len(accepted)
        and all(
            coverage_report["counts"][name] == counts[name].tolist()
            and coverage_report["thresholds"][name] == thresholds[name].tolist()
            for name in thresholds
        )
        and int(coverage_report["checkpoint_load_count_before_coverage_pass"]) == 0
        and int(coverage_report["physical_generation_count_before_coverage_pass"]) == 0
    )
    seed_audit = _read_json(root / "seed_namespace_audit.json")
    expected_natural = [
        _seed(config, layer="natural_core", stream="schedule", ordinal=value)
        for value in range(1, int(config["data"]["natural_core_blocks"]) + 1)
    ]
    expected_coverage = [
        _seed(config, layer="coverage", stream="schedule", ordinal=value)
        for value in range(1, evidence["inspected"] + 1)
    ]
    schedule_seed_audit_matches = (
        seed_audit["schedule_seeds"]["natural_core"] == expected_natural
        and seed_audit["schedule_seeds"]["coverage_candidates"] == expected_coverage
        and seed_audit["schedule_selection_used_only_frozen_fields"] is True
    )
    context["checks"].update(
        {
            "final_schedules_independently_replay": True,
            "coverage_selection_and_thresholds_independently_match": coverage_matches,
            "all_decision_schedule_seeds_are_audited": schedule_seed_audit_matches,
        }
    )
    context["independent_values"].update(
        {
            "accepted_coverage_block_count": len(accepted),
            "candidate_schedules_inspected": evidence["inspected"],
        }
    )
    return {
        "arrays": schedule_arrays,
        "accepted": accepted,
        "counts": counts,
        "coverage_complete": coverage_complete,
        "seed_audit": seed_audit,
    }


def _semantic_coverage_hold_v2(
    context: dict[str, Any], schedule: Mapping[str, Any]
) -> None:
    config = context["config"]
    decision = context["decision"]
    execution = context["execution"]
    matches = (
        schedule["coverage_complete"] is False
        and decision.get("passed") is False
        and decision.get("outcome") == "coverage_hold"
        and decision.get("decision") == config["decision_contract"]["hold_decision"]
        and decision.get("registry_completion_status")
        == config["registry_contract"]["completion_status_hold"]
        and decision.get("coverage_passed") is False
        and decision.get("all_42_performance_conditions_passed") is False
        and decision.get("probability_legality_passed") is None
        and decision.get("causality_passed") is None
        and decision.get("same_identifier_rerun_allowed") is False
        and decision.get("threshold_change_allowed") is False
        and decision.get("additional_sampling_allowed") is False
        and decision.get("h18_authorized") is False
        and int(execution.get("reserve_open_event_count", -1)) == 1
        and int(execution.get("decision_bearing_schedule_generation_events", -1)) == 1
        and int(execution.get("postdecision_independent_schedule_replay_events", -1))
        == 1
        and int(execution.get("decision_bearing_physical_generation_events", -1)) == 0
        and int(execution.get("postdecision_independent_physical_replay_events", -1))
        == 0
        and int(execution.get("decision_bearing_evaluation_events", -1)) == 0
        and int(execution.get("production_checkpoint_load_count", -1)) == 0
        and int(execution.get("postdecision_semantic_checkpoint_load_count", -1)) == 0
        and int(execution.get("checksum_only_verification_events", -1)) == 2
    )
    context["checks"][
        "coverage_hold_decision_and_zero_physical_or_checkpoint_use_match"
    ] = matches


def _complete_decision_contract_matches(
    config: Mapping[str, Any],
    decision: Mapping[str, Any],
    *,
    expected_pass: bool,
    performance_passed: bool,
    legality_passed: bool,
    causality_passed: bool,
) -> bool:
    expected_decision = (
        config["decision_contract"]["pass_decision"]
        if expected_pass
        else config["decision_contract"]["hold_decision"]
    )
    expected_status = (
        config["registry_contract"]["completion_status_pass"]
        if expected_pass
        else config["registry_contract"]["completion_status_hold"]
    )
    return bool(
        decision.get("passed") is expected_pass
        and decision.get("outcome") == "complete_evaluation"
        and decision.get("decision") == expected_decision
        and decision.get("registry_completion_status") == expected_status
        and decision.get("coverage_passed") is True
        and decision.get("all_42_performance_conditions_passed")
        is performance_passed
        and decision.get("probability_legality_passed") is legality_passed
        and decision.get("causality_passed") is causality_passed
        and decision.get("same_identifier_rerun_allowed") is False
        and decision.get("threshold_change_allowed") is False
        and decision.get("additional_sampling_allowed") is False
        and decision.get("h18_authorized") is False
    )


def _semantic_complete_v2(
    context: dict[str, Any], schedule: Mapping[str, Any]
) -> None:
    root = context["root"]
    project = context["project"]
    config = context["config"]
    decision = context["decision"]
    execution = context["execution"]
    if schedule["coverage_complete"] is not True:
        raise ValueError("a complete-evaluation result lacks frozen coverage")
    accepted = schedule["accepted"]
    seed_audit = schedule["seed_audit"]
    generation_arrays = _load_npz(root / "generation_arrays.npz")
    reserve_arrays = _load_npz(root / "reserve_arrays.npz")
    natural_count = int(config["data"]["natural_core_blocks"])
    coverage_count = len(accepted)
    _generation_schema(
        config,
        generation_arrays,
        natural_count=natural_count,
        coverage_count=coverage_count,
    )
    _reserve_schema(
        config,
        reserve_arrays,
        natural_count=natural_count,
        coverage_count=coverage_count,
    )
    bindings_match = _bindings_match(
        schedule["arrays"],
        generation_arrays,
        reserve_arrays,
        natural_count=natural_count,
        coverage_count=coverage_count,
    )
    h17f_root = project / str(config["source_h17f"]["result_directory"])
    h17_config_path = h17f_root / "config_snapshot.json"
    if _sha256(h17_config_path) != config["source_h17f"]["config_snapshot_sha256"]:
        raise ValueError("the H17F config snapshot changed before replay")
    h17_config = _read_json(h17_config_path)
    if (
        config["base_parameters"] != h17_config["base_parameters"]
        or config["parameter_candidates"] != h17_config["parameter_candidates"]
        or float(config["data"]["fixed_process_standard_deviation"])
        != float(h17_config["filter"]["common_process_standard_deviation"])
        or float(config["data"]["observation_standard_deviation"])
        != float(h17_config["filter"]["observation_standard_deviation"])
        or str(config["data"]["fixed_process_state_name"])
        != str(h17_config["filter"]["process_state_name"])
    ):
        raise ValueError("H17R physical/model factors differ from frozen H17F")
    physical = {
        "natural_core": _replay_physical_layer(
            config,
            h17_config,
            layer="natural_core",
            schedule_ordinals=list(range(1, natural_count + 1)),
            generation=generation_arrays,
            seed_audit=seed_audit,
        ),
        "coverage": _replay_physical_layer(
            config,
            h17_config,
            layer="coverage",
            schedule_ordinals=accepted,
            generation=generation_arrays,
            seed_audit=seed_audit,
        ),
    }
    saved_causality = _read_json(root / "causality_audit.json")
    replay = _replay_checkpoints(
        config, h17_config, root, reserve_arrays, saved_causality
    )
    saved_metrics = _read_json(root / "metrics.json")
    saved_stratified = _read_json(root / "stratified_metrics.json")
    saved_legality = _read_json(root / "probability_legality_audit.json")
    metrics_match = _close(saved_metrics, replay["metrics"], tolerance=1e-10)
    stratified_match = _close(
        saved_stratified, replay["stratified_metrics"], tolerance=1e-10
    )
    legality_match = _close(saved_legality, replay["legality"], tolerance=1e-12)
    natural_scored = int(
        np.count_nonzero(reserve_arrays["natural_core_evaluation_mask"])
    )
    expected_pass = bool(
        replay["metrics"]["all_42_performance_conditions_passed"]
        and replay["legality"]["passed"]
        and replay["causality"]["passed"]
    )
    expected_decision = (
        config["decision_contract"]["pass_decision"]
        if expected_pass
        else config["decision_contract"]["hold_decision"]
    )
    expected_status = (
        config["registry_contract"]["completion_status_pass"]
        if expected_pass
        else config["registry_contract"]["completion_status_hold"]
    )
    decision_matches = _complete_decision_contract_matches(
        config,
        decision,
        expected_pass=expected_pass,
        performance_passed=bool(
            replay["metrics"]["all_42_performance_conditions_passed"]
        ),
        legality_passed=bool(replay["legality"]["passed"]),
        causality_passed=bool(replay["causality"]["passed"]),
    )
    generation_report = _read_json(root / "generation_audit.json")
    checkpoint_report = _read_json(root / "checkpoint_integrity_audit.json")
    physical_contract = (
        int(generation_report["natural_core_block_count"]) == natural_count
        and int(generation_report["coverage_block_count"]) == coverage_count
        and float(generation_report["maximum_absolute_projection_adjustment"]) == 0.0
        and generation_report["all_physical_values_finite"] is True
        and seed_audit["actual_seeds_disjoint_from_h16_and_h17p"] is True
        and seed_audit["committed_seed_unique"] is True
        and seed_audit["legacy_process_seed_arithmetic_used"] is False
        and seed_audit["all_generation_calls_maximum_process_resamples"] == 1
        and seed_audit["all_process_attempt_counts_within_frozen_limit"] is True
        and all(
            item["all_physical_arrays_exactly_replayed"] for item in physical.values()
        )
    )
    checkpoint_contract = (
        int(checkpoint_report["checkpoint_load_count_before_coverage_pass"]) == 0
        and int(checkpoint_report["production_checkpoint_load_count"]) == 4
        and checkpoint_report["checkpoint_selection_performed"] is False
        and checkpoint_report["all_hashes_verified"] is True
        and replay["all_transition_matrices_match"] is True
    )
    execution_complete = (
        int(execution.get("decision_bearing_schedule_generation_events", -1)) == 1
        and int(execution.get("postdecision_independent_schedule_replay_events", -1))
        == 1
        and int(execution.get("decision_bearing_physical_generation_events", -1)) == 1
        and int(execution.get("postdecision_independent_physical_replay_events", -1))
        == 1
        and int(execution.get("decision_bearing_evaluation_events", -1)) == 1
        and int(execution.get("production_checkpoint_load_count", -1)) == 4
        and int(execution.get("postdecision_semantic_checkpoint_load_count", -1)) == 4
        and int(execution.get("checksum_only_verification_events", -1)) == 2
        and int(execution.get("checkpoint_load_count_before_coverage_pass", -1)) == 0
    )
    context["checks"].update(
        {
            "schedule_generation_and_evaluation_arrays_are_bound": bindings_match,
            "physical_generation_and_seed_contract_independently_replay": physical_contract,
            "four_frozen_checkpoints_independently_replay_all_matrices": checkpoint_contract,
            "natural_and_coverage_metrics_independently_match": metrics_match,
            "rare_source_by_age_metrics_independently_match": stratified_match,
            "probability_legality_independently_matches": legality_match,
            "causality_is_independently_recomputed_and_matches": replay[
                "causality_matches"
            ],
            "natural_scored_transition_count_matches": natural_scored
            == int(config["data"]["natural_core_scored_transition_count"]),
            "all_42_gate_decision_matches": decision_matches,
            "execution_event_counts_match_one_decision_and_one_audit_replay": execution_complete,
        }
    )
    context["independent_values"].update(
        {
            "natural_scored_transition_count": natural_scored,
            "passed_performance_condition_count": int(
                replay["metrics"]["passed_gate_count"]
            ),
            "failed_performance_condition_count": int(
                replay["metrics"]["failed_gate_count"]
            ),
            "expected_decision": expected_decision,
            "physical_replay": physical,
            "maximum_transition_matrix_replay_differences": replay[
                "maximum_transition_matrix_replay_differences"
            ],
            "semantic_replay_checkpoint_load_count": replay["checkpoint_audit"][
                "semantic_replay_checkpoint_load_count"
            ],
        }
    )


def _semantic_process_exhaustion_v2(
    context: dict[str, Any], schedule: Mapping[str, Any]
) -> None:
    root = context["root"]
    project = context["project"]
    config = context["config"]
    decision = context["decision"]
    execution = context["execution"]
    audit = _read_json(root / "process_exhaustion_audit.json")
    failure = _read_json(root / "failure_report.json")
    seed_audit = schedule["seed_audit"]
    records = _validate_process_exhaustion_ledger(
        config,
        seed_audit,
        audit,
        accepted_coverage_ordinals=schedule["accepted"],
    )
    h17_config_path = (
        project
        / str(config["source_h17f"]["result_directory"])
        / "config_snapshot.json"
    )
    if _sha256(h17_config_path) != config["source_h17f"]["config_snapshot_sha256"]:
        raise ValueError("the H17F config changed before process-exhaustion replay")
    h17_config = _read_json(h17_config_path)
    if (
        config["base_parameters"] != h17_config["base_parameters"]
        or config["parameter_candidates"] != h17_config["parameter_candidates"]
        or float(config["data"]["fixed_process_standard_deviation"])
        != float(h17_config["filter"]["common_process_standard_deviation"])
        or float(config["data"]["observation_standard_deviation"])
        != float(h17_config["filter"]["observation_standard_deviation"])
        or str(config["data"]["fixed_process_state_name"])
        != str(h17_config["filter"]["process_state_name"])
    ):
        raise ValueError("H17R physical factors changed before process-exhaustion replay")
    replayed = [
        _replay_process_exhaustion_record(config, h17_config, record)
        for record in records
    ]
    all_outcomes_replayed = all(
        item["outcome_exactly_replayed"] is True for item in replayed
    )
    layer = str(audit["layer"])
    rank = int(audit["failed_block_rank"])
    decision_matches = (
        schedule["coverage_complete"] is True
        and decision.get("passed") is False
        and decision.get("outcome") == "process_exhaustion_hold"
        and decision.get("decision") == config["decision_contract"]["hold_decision"]
        and decision.get("registry_completion_status")
        == config["registry_contract"]["completion_status_hold"]
        and decision.get("coverage_passed") is True
        and decision.get("all_42_performance_conditions_passed") is False
        and decision.get("probability_legality_passed") is None
        and decision.get("causality_passed") is None
        and decision.get("same_identifier_rerun_allowed") is False
        and decision.get("threshold_change_allowed") is False
        and decision.get("additional_sampling_allowed") is False
        and decision.get("h18_authorized") is False
        and failure.get("experiment_id") == config["experiment_id"]
        and failure.get("decision")
        == "PROCESS_SEED_EXHAUSTION_HOLD_RESERVE_BURNED"
        and failure.get("exception_type") == "ProcessLayerExhaustion"
        and isinstance(failure.get("exception_message"), str)
        and bool(failure.get("exception_message"))
        and failure.get("same_identifier_rerun_allowed") is False
        and failure.get("h18_authorized") is False
        and audit.get("physical_generation_started") is True
        and audit.get("same_identifier_rerun_allowed") is False
        and int(audit.get("checkpoint_load_count", -1)) == 0
        and int(execution.get("reserve_open_event_count", -1)) == 1
        and int(execution.get("decision_bearing_schedule_generation_events", -1))
        == 1
        and int(execution.get("postdecision_independent_schedule_replay_events", -1))
        == 1
        and int(execution.get("decision_bearing_physical_generation_events", -1))
        == 1
        and int(execution.get("postdecision_independent_physical_replay_events", -1))
        == 1
        and int(execution.get("decision_bearing_evaluation_events", -1)) == 0
        and int(execution.get("production_checkpoint_load_count", -1)) == 0
        and int(execution.get("postdecision_semantic_checkpoint_load_count", -1)) == 0
        and int(execution.get("checksum_only_verification_events", -1)) == 2
    )
    context["checks"].update(
        {
            "process_exhaustion_full_seed_ledger_matches": True,
            "all_completed_and_failed_process_attempts_independently_replay": (
                all_outcomes_replayed
            ),
            "process_exhaustion_decision_and_zero_checkpoint_use_match": decision_matches,
        }
    )
    context["independent_values"].update(
        {
            "process_exhaustion_layer": layer,
            "process_exhaustion_block_rank": rank,
            "independently_replayed_process_block_count": len(records),
            "independently_replayed_process_attempt_count": sum(
                int(item["attempt_count"]) for item in replayed
            ),
        }
    )


def _execution_hold_contract_matches(
    config: Mapping[str, Any],
    decision: Mapping[str, Any],
    failure: Mapping[str, Any],
    partial: Mapping[str, Any],
    execution: Mapping[str, Any],
) -> bool:
    unknown_counts_are_explicitly_null = all(
        execution.get(name) is None
        for name in (
            "decision_bearing_schedule_generation_events",
            "decision_bearing_physical_generation_events",
            "decision_bearing_evaluation_events",
            "production_checkpoint_load_count",
        )
    )
    return bool(
        decision.get("passed") is False
        and decision.get("outcome") == "execution_hold"
        and decision.get("decision") == "EXECUTION_HOLD_RESERVE_BURNED"
        and decision.get("registry_completion_status")
        == config["registry_contract"]["completion_status_hold"]
        and decision.get("h18_authorized") is False
        and failure.get("experiment_id") == config["experiment_id"]
        and failure.get("decision") == "EXECUTION_HOLD_RESERVE_BURNED"
        and isinstance(failure.get("exception_type"), str)
        and bool(failure.get("exception_type"))
        and isinstance(failure.get("exception_message"), str)
        and failure.get("same_identifier_rerun_allowed") is False
        and failure.get("h18_authorized") is False
        and partial.get("outcome") == "execution_hold"
        and partial.get("all_listed_files_must_be_checksummed") is True
        and unknown_counts_are_explicitly_null
        and int(execution.get("postdecision_independent_schedule_replay_events", -1))
        == 0
        and int(execution.get("postdecision_independent_physical_replay_events", -1))
        == 0
        and int(execution.get("postdecision_semantic_checkpoint_load_count", -1)) == 0
    )


def verify_h17r_result(
    result_directory: str | Path,
    *,
    project_root: str | Path,
    verify_checksums: bool = True,
    verify_live_registry: bool = True,
    semantic_replay: bool = False,
    approved_preregistration_sha256: str,
) -> dict[str, Any]:
    context = _base_verification_v2(
        result_directory,
        project_root=project_root,
        verify_checksums=verify_checksums,
        verify_live_registry=verify_live_registry,
        approved_preregistration_sha256=approved_preregistration_sha256,
    )
    outcome = context["outcome"]
    if semantic_replay and outcome in {
        "complete_evaluation",
        "coverage_hold",
        "process_exhaustion_hold",
    }:
        schedule = _semantic_schedule_v2(context)
        if outcome == "coverage_hold":
            _semantic_coverage_hold_v2(context, schedule)
        elif outcome == "complete_evaluation":
            _semantic_complete_v2(context, schedule)
        else:
            _semantic_process_exhaustion_v2(context, schedule)
    elif semantic_replay and outcome in {
        "execution_hold",
    }:
        root = context["root"]
        decision = context["decision"]
        config = context["config"]
        failure = _read_json(root / "failure_report.json")
        partial = _read_json(root / "partial_artifact_manifest.json")
        execution = context["execution"]
        context["checks"]["execution_hold_is_nonclaiming_and_nonresumable"] = (
            _execution_hold_contract_matches(
                config, decision, failure, partial, execution
            )
        )
        context["independent_values"][
            "execution_hold_scientific_semantic_replay_performed"
        ] = False
    elif not semantic_replay:
        context["checks"][
            "semantic_evidence_is_frozen_in_saved_independent_verification"
        ] = context["checks"]["saved_semantic_verification_passes"]
    return {
        "experiment_id": context["config"]["experiment_id"],
        "outcome": outcome,
        "verify_checksums_requested": verify_checksums,
        "verify_live_registry_requested": verify_live_registry,
        "semantic_replay_requested": semantic_replay,
        "checks": context["checks"],
        "independent_values": context["independent_values"],
        "scientific_semantic_result_verified": bool(
            outcome != "execution_hold" and all(context["checks"].values())
        ),
        "terminal_package_integrity_verified": all(context["checks"].values()),
        "verified": all(context["checks"].values()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("result_directory")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--skip-checksums", action="store_true")
    parser.add_argument("--skip-live-registry", action="store_true")
    parser.add_argument("--semantic-replay", action="store_true")
    parser.add_argument("--approved-prereg-sha256", required=True)
    args = parser.parse_args()
    values = verify_h17r_result(
        args.result_directory,
        project_root=args.project_root,
        verify_checksums=not args.skip_checksums,
        verify_live_registry=not args.skip_live_registry,
        semantic_replay=args.semantic_replay,
        approved_preregistration_sha256=args.approved_prereg_sha256,
    )
    print(json.dumps(values, indent=2, sort_keys=True))
    if values["verified"] is not True:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
