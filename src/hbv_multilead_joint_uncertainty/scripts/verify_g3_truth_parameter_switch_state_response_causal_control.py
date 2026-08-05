"""Independently verify the synthetic true-parameter switch state response."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from pathlib import Path

import matplotlib
import matplotlib.image as matplotlib_image
import numpy as np

matplotlib.use("Agg")


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_joint_uncertainty.hbv_adapter import (  # noqa: E402
    HYDRO_STATE_NAMES,
    PARAMETER_NAMES,
    STATE_NAMES,
    advance_state,
)
from hbv_joint_uncertainty.preflight import project_hbv_state  # noqa: E402


EXPERIMENT_ID = "g3_truth_parameter_switch_state_response_causal_control_v01"
DEFAULT_RESULT = PROJECT_ROOT / "results/23_hbv_multilead_joint_uncertainty" / EXPERIMENT_ID
BRANCH_NAMES = ("continue_old_true_parameters", "switch_to_new_true_parameters")
STATE_GROUP_NAMES = ("hydrologic_stores", "routing_memory")
STATE_GROUP_SLICES = (slice(0, 5), slice(5, 15))
TRUTH_ARRAY_NAMES = (
    "forcing_blocks",
    "warmup_days",
    "truth_states",
    "truth_process_perturbations",
    "truth_parameter_indices",
    "parameter_ids",
    "parameter_vectors",
)
SCALE_ARRAY_NAMES = ("truth_standard_deviation", "state_names")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _maximum_difference(left, right) -> float:
    left_values = np.asarray(left)
    right_values = np.asarray(right)
    if left_values.shape != right_values.shape:
        return float("inf")
    if left_values.dtype.kind in "OUS" or right_values.dtype.kind in "OUS":
        return 0.0 if np.array_equal(left_values.astype(str), right_values.astype(str)) else float("inf")
    if left_values.dtype.kind == "b" or right_values.dtype.kind == "b":
        return 0.0 if np.array_equal(left_values, right_values) else float("inf")
    if not np.all(np.isfinite(left_values)) or not np.all(np.isfinite(right_values)):
        return float("inf")
    if left_values.size == 0:
        return 0.0
    return float(np.max(np.abs(left_values.astype(np.float64) - right_values.astype(np.float64))))


def _load_named_arrays(path: Path, names: tuple[str, ...], requested: list[str]) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as archive:
        missing = [name for name in names if name not in archive.files]
        if missing:
            raise KeyError(f"independent verification source is missing arrays: {missing}")
        values = {}
        for name in names:
            requested.append(name)
            values[name] = np.asarray(archive[name]).copy()
    return values


def _parameter_map(vector) -> dict[str, float]:
    values = np.asarray(vector, dtype=np.float64)
    if values.shape != (len(PARAMETER_NAMES),) or not np.all(np.isfinite(values)):
        raise ValueError("independent parameter vector is invalid")
    return {name: float(value) for name, value in zip(PARAMETER_NAMES, values)}


def _recompute_events(config: dict, truth: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    forcing_blocks = np.asarray(truth["forcing_blocks"], dtype=np.float64)
    warmup = int(np.asarray(truth["warmup_days"]).item())
    truth_states = np.asarray(truth["truth_states"], dtype=np.float64)
    process_perturbations = np.asarray(truth["truth_process_perturbations"], dtype=np.float64)
    schedule = np.asarray(truth["truth_parameter_indices"], dtype=np.int64)
    parameter_ids = np.asarray(truth["parameter_ids"]).astype(str)
    parameter_vectors = np.asarray(truth["parameter_vectors"], dtype=np.float64)
    boundaries = tuple(int(value) for value in config["switch_boundaries_zero_based"])
    response_days = int(config["response_days"])

    records = []
    for block_index in range(forcing_blocks.shape[0]):
        for truth_index in range(truth_states.shape[1]):
            for boundary in boundaries:
                old_parameter_index = int(schedule[truth_index, boundary - 1])
                new_parameter_index = int(schedule[truth_index, boundary])
                if old_parameter_index == new_parameter_index:
                    raise ValueError("independent verifier found no parameter switch at a frozen boundary")
                if not np.all(schedule[truth_index, boundary:boundary + response_days] == new_parameter_index):
                    raise ValueError("independent verifier found another switch inside a response window")
                initial_state = truth_states[block_index, truth_index, boundary - 1].copy()
                forcing = forcing_blocks[
                    block_index,
                    warmup + boundary:warmup + boundary + response_days,
                ].copy()
                perturbations = process_perturbations[
                    block_index,
                    truth_index,
                    boundary:boundary + response_days,
                ].copy()
                if np.any(perturbations[:, len(HYDRO_STATE_NAMES):] != 0.0):
                    raise ValueError("independent verifier found routing-memory process perturbations")
                branch_parameter_vectors = np.stack(
                    (parameter_vectors[old_parameter_index], parameter_vectors[new_parameter_index])
                )
                branch_states = np.empty((2, response_days, len(STATE_NAMES)), dtype=np.float64)
                pretransition_states = np.empty_like(branch_states)
                pretransition_adjustments = np.empty_like(branch_states)
                deterministic_states = np.empty_like(branch_states)
                postperturbation_adjustments = np.empty_like(branch_states)
                routing_shift_maximum = 0.0
                for branch_index, vector in enumerate(branch_parameter_vectors):
                    parameters = _parameter_map(vector)
                    state = initial_state.copy()
                    for lead in range(response_days):
                        physical_before = project_hbv_state(state, parameters)
                        deterministic = advance_state(physical_before, *forcing[lead], parameters)
                        unprojected = deterministic + perturbations[lead]
                        projected = project_hbv_state(unprojected, parameters)
                        pretransition_states[branch_index, lead] = physical_before
                        pretransition_adjustments[branch_index, lead] = physical_before - state
                        deterministic_states[branch_index, lead] = deterministic
                        postperturbation_adjustments[branch_index, lead] = projected - unprojected
                        branch_states[branch_index, lead] = projected
                        routing_shift_maximum = max(
                            routing_shift_maximum,
                            float(np.max(np.abs(deterministic[6:] - physical_before[5:14]))),
                        )
                        state = projected
                saved_truth = truth_states[
                    block_index,
                    truth_index,
                    boundary:boundary + response_days,
                ].copy()
                records.append(
                    {
                        "block_index": block_index,
                        "truth_index": truth_index,
                        "switch_boundary": boundary,
                        "old_parameter_index": old_parameter_index,
                        "new_parameter_index": new_parameter_index,
                        "transition_label": (
                            f"{parameter_ids[old_parameter_index]}_to_{parameter_ids[new_parameter_index]}"
                        ),
                        "initial_state": initial_state,
                        "forcing": forcing,
                        "perturbations": perturbations,
                        "branch_parameters": branch_parameter_vectors,
                        "saved_truth": saved_truth,
                        "initial_states": np.stack((initial_state, initial_state)),
                        "shared_forcing": forcing,
                        "shared_process_perturbations": perturbations,
                        "pretransition_projected_states": pretransition_states,
                        "pretransition_projection_adjustments": pretransition_adjustments,
                        "deterministic_states": deterministic_states,
                        "postperturbation_projection_adjustments": postperturbation_adjustments,
                        "branch_states": branch_states,
                        "branch_state_difference": branch_states[1] - branch_states[0],
                        "reconstruction_error": float(np.max(np.abs(branch_states[1] - saved_truth))),
                        "routing_shift_error": routing_shift_maximum,
                    }
                )

    def stacked(name: str) -> np.ndarray:
        return np.stack([np.asarray(record[name]) for record in records])

    reconstruction = np.asarray([record["reconstruction_error"] for record in records], dtype=np.float64)
    return {
        "event_indices": np.arange(len(records), dtype=np.int64),
        "block_indices": np.asarray([record["block_index"] for record in records], dtype=np.int64),
        "truth_indices": np.asarray([record["truth_index"] for record in records], dtype=np.int64),
        "switch_boundaries": np.asarray([record["switch_boundary"] for record in records], dtype=np.int64),
        "old_parameter_indices": np.asarray(
            [record["old_parameter_index"] for record in records], dtype=np.int64
        ),
        "new_parameter_indices": np.asarray(
            [record["new_parameter_index"] for record in records], dtype=np.int64
        ),
        "event_transition_labels": np.asarray([record["transition_label"] for record in records]),
        "branch_names": np.asarray(BRANCH_NAMES),
        "parameter_names": np.asarray(PARAMETER_NAMES),
        "parameter_ids": parameter_ids,
        "parameter_vectors": parameter_vectors,
        "warmup_days": np.asarray(warmup, dtype=np.int64),
        "response_days": np.asarray(response_days, dtype=np.int64),
        **{
            name: stacked(name)
            for name in (
                "initial_state",
                "forcing",
                "perturbations",
                "branch_parameters",
                "saved_truth",
                "initial_states",
                "shared_forcing",
                "shared_process_perturbations",
                "pretransition_projected_states",
                "pretransition_projection_adjustments",
                "deterministic_states",
                "postperturbation_projection_adjustments",
                "branch_states",
                "branch_state_difference",
            )
        },
        "new_branch_truth_reconstruction_maximum_absolute_error_by_event": reconstruction,
        "new_branch_truth_reconstruction_maximum_absolute_error": np.asarray(
            np.max(reconstruction), dtype=np.float64
        ),
        "routing_shift_maximum_absolute_error": np.asarray(
            max(float(record["routing_shift_error"]) for record in records), dtype=np.float64
        ),
    }


def _root_mean_square(values: np.ndarray, axis) -> np.ndarray:
    return np.sqrt(np.mean(np.square(values), axis=axis))


def _recompute_summary(events: dict[str, np.ndarray], scales: np.ndarray, tolerance: float) -> dict[str, np.ndarray]:
    differences = np.asarray(events["branch_state_difference"], dtype=np.float64)
    labels = np.asarray(events["event_transition_labels"]).astype(str)
    unique_labels = tuple(dict.fromkeys(labels.tolist()))
    standardized = differences / scales[None, None, :]
    pooled_raw = _root_mean_square(differences, axis=0)
    pooled_standardized = _root_mean_square(standardized, axis=0)
    transition_raw = np.stack([_root_mean_square(differences[labels == label], axis=0) for label in unique_labels])
    transition_standardized = np.stack(
        [_root_mean_square(standardized[labels == label], axis=0) for label in unique_labels]
    )
    group_standardized = np.column_stack(
        [_root_mean_square(standardized[:, :, group_slice], axis=(0, 2)) for group_slice in STATE_GROUP_SLICES]
    )
    transition_groups = np.stack(
        [
            np.column_stack(
                [
                    _root_mean_square(standardized[labels == label, :, group_slice], axis=(0, 2))
                    for group_slice in STATE_GROUP_SLICES
                ]
            )
            for label in unique_labels
        ]
    )
    projection = np.asarray(events["pretransition_projection_adjustments"], dtype=np.float64)[:, 1, 0]
    projection_mask = np.abs(projection) > tolerance
    projection_count = int(np.count_nonzero(np.any(projection_mask, axis=1)))
    decision = (
        "requires_separate_fixed_parameter_state_jump_recovery_experiment"
        if projection_count > 0
        else "suitable_as_clean_parameter_switch_truth_condition_for_state_accuracy"
    )
    return {
        "state_names": np.asarray(STATE_NAMES),
        "state_group_names": np.asarray(STATE_GROUP_NAMES),
        "unique_transition_labels": np.asarray(unique_labels),
        "transition_event_count": np.asarray(
            [np.count_nonzero(labels == label) for label in unique_labels], dtype=np.int64
        ),
        "standardized_response": standardized,
        "pooled_state_root_mean_square_raw_response": pooled_raw,
        "pooled_state_root_mean_square_standardized_response": pooled_standardized,
        "transition_state_root_mean_square_raw_response": transition_raw,
        "transition_state_root_mean_square_standardized_response": transition_standardized,
        "group_root_mean_square_standardized_response": group_standardized,
        "transition_group_root_mean_square_standardized_response": transition_groups,
        "per_state_day_1_root_mean_square_raw_response": pooled_raw[0],
        "per_state_day_1_root_mean_square_standardized_response": pooled_standardized[0],
        "per_state_peak_root_mean_square_raw_response": np.max(pooled_raw, axis=0),
        "per_state_peak_root_mean_square_standardized_response": np.max(pooled_standardized, axis=0),
        "per_state_peak_lead": np.argmax(pooled_standardized, axis=0).astype(np.int64) + 1,
        "per_group_day_1_root_mean_square_standardized_response": group_standardized[0],
        "per_group_peak_root_mean_square_standardized_response": np.max(group_standardized, axis=0),
        "per_group_peak_lead": np.argmax(group_standardized, axis=0).astype(np.int64) + 1,
        "initial_new_parameter_domain_projection_adjustments": projection,
        "initial_new_parameter_domain_projection_standardized_adjustments": projection / scales[None, :],
        "initial_new_parameter_domain_projection_event_count": np.asarray(projection_count, dtype=np.int64),
        "initial_new_parameter_domain_projection_state_event_count": np.count_nonzero(
            projection_mask, axis=0
        ).astype(np.int64),
        "decision": np.asarray(decision),
        "state_scales": scales,
        "lead_days": np.arange(1, differences.shape[1] + 1, dtype=np.int64),
    }


def _recompute_physical(events: dict[str, np.ndarray], tolerance: float) -> tuple[dict, dict[str, np.ndarray]]:
    states = np.asarray(events["branch_states"], dtype=np.float64)
    parameters = np.asarray(events["branch_parameters"], dtype=np.float64)
    perturbations = np.asarray(events["shared_process_perturbations"], dtype=np.float64)
    initial_states = np.asarray(events["initial_states"], dtype=np.float64)
    field_capacity = parameters[:, :, PARAMETER_NAMES.index("parFC")][:, :, None]
    holding_fraction = parameters[:, :, PARAMETER_NAMES.index("parCWH")][:, :, None]
    values = {
        "minimum_state": float(np.min(states)),
        "maximum_soil_moisture_excess": float(np.max(states[..., 2] - field_capacity)),
        "maximum_meltwater_holding_excess": float(
            np.max(states[..., 1] - holding_fraction * states[..., 0])
        ),
        "routing_memory_process_perturbation_maximum_absolute_value": float(
            np.max(np.abs(perturbations[..., 5:]))
        ),
        "routing_memory_shift_maximum_absolute_error": float(
            events["routing_shift_maximum_absolute_error"]
        ),
        "initial_state_branch_maximum_absolute_difference": float(
            np.max(np.abs(initial_states[:, 1] - initial_states[:, 0]))
        ),
        "new_branch_truth_reconstruction_maximum_absolute_error": float(
            events["new_branch_truth_reconstruction_maximum_absolute_error"]
        ),
    }
    checks = {
        "all_states_finite": bool(np.all(np.isfinite(states))),
        "all_states_nonnegative_with_tolerance": values["minimum_state"] >= -tolerance,
        "soil_moisture_not_above_active_field_capacity": values["maximum_soil_moisture_excess"] <= tolerance,
        "meltwater_not_above_active_holding_fraction_times_snowpack": (
            values["maximum_meltwater_holding_excess"] <= tolerance
        ),
        "routing_memory_process_perturbations_exactly_zero": (
            values["routing_memory_process_perturbation_maximum_absolute_value"] == 0.0
        ),
        "routing_memory_shift_exact_within_tolerance": (
            values["routing_memory_shift_maximum_absolute_error"] <= tolerance
        ),
        "initial_states_identical_between_branches": (
            values["initial_state_branch_maximum_absolute_difference"] == 0.0
        ),
        "new_branch_reconstructs_sealed_truth_within_tolerance": (
            values["new_branch_truth_reconstruction_maximum_absolute_error"] <= tolerance
        ),
    }
    complete = {**checks, **values, "passed": all(checks.values())}
    evidence = {
        "physical_check_names": np.asarray(tuple(checks)),
        "physical_check_passed": np.asarray(tuple(checks.values()), dtype=bool),
        "physical_value_names": np.asarray(tuple(values)),
        "physical_values": np.asarray(tuple(values.values()), dtype=np.float64),
        "physical_checks_passed": np.asarray(complete["passed"], dtype=bool),
    }
    return complete, evidence


def _verify_csv_files(result_dir: Path, expected: dict[str, np.ndarray], tolerance: float) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    with (result_dir / "per_state_summary.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    checks["per_state_row_count"] = len(rows) == len(STATE_NAMES)
    checks["per_state_values"] = checks["per_state_row_count"]
    for row in rows:
        index = int(row["state_index"])
        numeric = {
            "frozen_state_standard_deviation": expected["state_scales"][index],
            "day_1_root_mean_square_raw_response": expected[
                "per_state_day_1_root_mean_square_raw_response"
            ][index],
            "day_1_root_mean_square_standardized_response": expected[
                "per_state_day_1_root_mean_square_standardized_response"
            ][index],
            "peak_root_mean_square_raw_response": expected["per_state_peak_root_mean_square_raw_response"][
                index
            ],
            "peak_root_mean_square_standardized_response": expected[
                "per_state_peak_root_mean_square_standardized_response"
            ][index],
        }
        checks["per_state_values"] &= (
            row["state_name"] == STATE_NAMES[index]
            and row["state_group"] == STATE_GROUP_NAMES[0 if index < 5 else 1]
            and int(row["peak_lead_day"]) == int(expected["per_state_peak_lead"][index])
            and int(row["initial_new_domain_projection_event_count"])
            == int(expected["initial_new_parameter_domain_projection_state_event_count"][index])
            and all(abs(float(row[name]) - float(value)) <= tolerance for name, value in numeric.items())
        )

    with (result_dir / "transition_state_summary.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    labels = tuple(expected["unique_transition_labels"].astype(str))
    checks["transition_state_row_count"] = len(rows) == len(labels) * len(STATE_NAMES)
    checks["transition_state_values"] = checks["transition_state_row_count"]
    for row in rows:
        transition_index = labels.index(row["transition_label"])
        state_index = int(row["state_index"])
        raw = expected["transition_state_root_mean_square_raw_response"][transition_index, :, state_index]
        standardized = expected["transition_state_root_mean_square_standardized_response"][
            transition_index, :, state_index
        ]
        raw_peak = int(np.argmax(raw))
        standardized_peak = int(np.argmax(standardized))
        checks["transition_state_values"] &= (
            row["state_name"] == STATE_NAMES[state_index]
            and int(row["event_count"]) == int(expected["transition_event_count"][transition_index])
            and abs(float(row["day_1_root_mean_square_raw_response"]) - float(raw[0])) <= tolerance
            and abs(float(row["day_1_root_mean_square_standardized_response"]) - float(standardized[0]))
            <= tolerance
            and abs(float(row["peak_root_mean_square_raw_response"]) - float(raw[raw_peak])) <= tolerance
            and int(row["raw_peak_lead_day"]) == raw_peak + 1
            and abs(
                float(row["peak_root_mean_square_standardized_response"])
                - float(standardized[standardized_peak])
            )
            <= tolerance
            and int(row["standardized_peak_lead_day"]) == standardized_peak + 1
        )

    with (result_dir / "response_curves.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    expected_count = len(expected["lead_days"]) * (1 + len(labels)) * (len(STATE_NAMES) + len(STATE_GROUP_NAMES))
    checks["response_curve_row_count"] = len(rows) == expected_count
    checks["response_curve_values"] = checks["response_curve_row_count"]
    for row in rows:
        lead = int(row["lead_day"]) - 1
        is_pooled = row["aggregation"] == "pooled"
        transition_index = None if is_pooled else labels.index(row["transition_label"])
        if row["object_type"] == "state":
            state_index = STATE_NAMES.index(row["object_name"])
            raw = (
                expected["pooled_state_root_mean_square_raw_response"][lead, state_index]
                if is_pooled
                else expected["transition_state_root_mean_square_raw_response"][
                    transition_index, lead, state_index
                ]
            )
            standardized = (
                expected["pooled_state_root_mean_square_standardized_response"][lead, state_index]
                if is_pooled
                else expected["transition_state_root_mean_square_standardized_response"][
                    transition_index, lead, state_index
                ]
            )
            checks["response_curve_values"] &= (
                abs(float(row["root_mean_square_raw_response"]) - float(raw)) <= tolerance
                and abs(float(row["root_mean_square_standardized_response"]) - float(standardized)) <= tolerance
            )
        else:
            group_index = STATE_GROUP_NAMES.index(row["object_name"])
            standardized = (
                expected["group_root_mean_square_standardized_response"][lead, group_index]
                if is_pooled
                else expected["transition_group_root_mean_square_standardized_response"][
                    transition_index, lead, group_index
                ]
            )
            checks["response_curve_values"] &= (
                row["root_mean_square_raw_response"] == ""
                and abs(float(row["root_mean_square_standardized_response"]) - float(standardized)) <= tolerance
            )
    return checks


def _verify_summary(summary: dict, expected: dict[str, np.ndarray], physical: dict, tolerance: float) -> dict[str, bool]:
    labels = tuple(expected["unique_transition_labels"].astype(str))
    event_labels = expected["event_transition_labels"].astype(str)
    projection = expected["initial_new_parameter_domain_projection_adjustments"]
    projection_by_transition = {
        label: int(np.count_nonzero(np.any(np.abs(projection[event_labels == label]) > tolerance, axis=1)))
        for label in labels
    }
    saved_physical = summary.get("physical_checks", {})
    physical_match = set(saved_physical) == set(physical)
    if physical_match:
        for name, expected_value in physical.items():
            saved_value = saved_physical[name]
            if isinstance(expected_value, bool):
                physical_match &= saved_value is expected_value
            else:
                physical_match &= abs(float(saved_value) - float(expected_value)) <= tolerance
    checks = {
        "status_pending_verification": summary.get("status") == "complete_pending_independent_verification",
        "conclusion_withheld": summary.get("scientific_conclusion_withheld_until_independent_verification") is True,
        "decision": summary.get("decision") == str(expected["decision"].item()),
        "event_count": summary.get("event_count") == len(event_labels),
        "response_days": summary.get("response_days") == len(expected["lead_days"]),
        "state_count": summary.get("state_count") == len(STATE_NAMES),
        "transition_counts": summary.get("directed_transition_event_counts")
        == {label: int(count) for label, count in zip(labels, expected["transition_event_count"])},
        "projection_event_count": summary.get("initial_new_parameter_domain_projection_event_count")
        == int(expected["initial_new_parameter_domain_projection_event_count"]),
        "projection_by_transition": summary.get("initial_new_parameter_domain_projection_events_by_transition")
        == projection_by_transition,
        "projection_by_state": summary.get("initial_new_parameter_domain_projection_state_event_count")
        == {
            name: int(count)
            for name, count in zip(
                STATE_NAMES,
                expected["initial_new_parameter_domain_projection_state_event_count"],
            )
        },
        "truth_reconstruction": abs(
            float(summary.get("new_branch_truth_reconstruction_maximum_absolute_error", np.inf))
            - float(expected["new_branch_truth_reconstruction_maximum_absolute_error"])
        )
        <= tolerance,
        "forbidden_scope": summary.get("forbidden_scope_checks")
        == {
            "observed_discharge_read": False,
            "forecast_executed": False,
            "assimilation_executed": False,
            "state_reset_at_switch": False,
        },
        "source_array_scope": set(summary.get("requested_source_arrays", ()))
        == set(TRUTH_ARRAY_NAMES + SCALE_ARRAY_NAMES),
        "physical_checks": physical_match,
    }
    state_rows = summary.get("per_state_summary", [])
    checks["per_state_summary"] = len(state_rows) == len(STATE_NAMES)
    for state_index, row in enumerate(state_rows):
        checks["per_state_summary"] &= (
            row.get("state_name") == STATE_NAMES[state_index]
            and abs(
                float(row.get("day_1_root_mean_square_standardized_response", np.inf))
                - float(expected["per_state_day_1_root_mean_square_standardized_response"][state_index])
            )
            <= tolerance
            and abs(
                float(row.get("peak_root_mean_square_standardized_response", np.inf))
                - float(expected["per_state_peak_root_mean_square_standardized_response"][state_index])
            )
            <= tolerance
            and int(row.get("peak_lead_day", -1)) == int(expected["per_state_peak_lead"][state_index])
        )
    group_rows = summary.get("state_group_summary", [])
    checks["state_group_summary"] = len(group_rows) == len(STATE_GROUP_NAMES)
    for group_index, row in enumerate(group_rows):
        checks["state_group_summary"] &= (
            row.get("state_group") == STATE_GROUP_NAMES[group_index]
            and abs(
                float(row.get("day_1_root_mean_square_standardized_response", np.inf))
                - float(expected["per_group_day_1_root_mean_square_standardized_response"][group_index])
            )
            <= tolerance
            and abs(
                float(row.get("peak_root_mean_square_standardized_response", np.inf))
                - float(expected["per_group_peak_root_mean_square_standardized_response"][group_index])
            )
            <= tolerance
            and int(row.get("peak_lead_day", -1)) == int(expected["per_group_peak_lead"][group_index])
        )
    return checks


def verify(result_dir: Path) -> dict:
    result_dir = result_dir.resolve()
    report_path = result_dir / "independent_verification.json"
    if report_path.exists():
        raise FileExistsError(f"independent verification report already exists: {report_path}")
    config = json.loads((result_dir / "config_snapshot.json").read_text(encoding="utf-8"))
    frozen_config_path = (
        PROJECT_ROOT
        / "src/hbv_multilead_joint_uncertainty/configs"
        / f"{EXPERIMENT_ID}.json"
    )
    frozen_config = json.loads(frozen_config_path.read_text(encoding="utf-8"))
    config_matches_frozen = config == frozen_config
    if config.get("experiment_id") != EXPERIMENT_ID:
        raise ValueError("result experiment identifier is not the frozen control")
    tolerance = float(config["numerical_tolerance"])

    truth_path = (PROJECT_ROOT / config["sealed_truth_evidence"]["path"]).resolve()
    scale_path = (PROJECT_ROOT / config["frozen_state_scale_evidence"]["path"]).resolve()
    source_hashes = {
        "sealed_truth_evidence": _sha256(truth_path),
        "frozen_state_scale_evidence": _sha256(scale_path),
    }
    source_hash_checks = {
        "sealed_truth_evidence": source_hashes["sealed_truth_evidence"]
        == config["sealed_truth_evidence"]["sha256"],
        "frozen_state_scale_evidence": source_hashes["frozen_state_scale_evidence"]
        == config["frozen_state_scale_evidence"]["sha256"],
    }
    for group_name, sources in config["frozen_model_sources"].items():
        for relative_path, expected_hash in sources.items():
            key = f"{group_name}:{relative_path}"
            actual_hash = _sha256(PROJECT_ROOT / relative_path)
            source_hashes[key] = actual_hash
            source_hash_checks[key] = actual_hash == expected_hash

    requested_arrays: list[str] = []
    truth = _load_named_arrays(truth_path, TRUTH_ARRAY_NAMES, requested_arrays)
    scale = _load_named_arrays(scale_path, SCALE_ARRAY_NAMES, requested_arrays)
    if tuple(scale["state_names"].astype(str)) != STATE_NAMES:
        raise ValueError("independent verifier found a state-name mismatch")
    scales = np.asarray(scale["truth_standard_deviation"], dtype=np.float64)
    events = _recompute_events(config, truth)
    summary_arrays = _recompute_summary(events, scales, tolerance)
    physical, physical_evidence = _recompute_physical(events, tolerance)
    expected = {
        **events,
        **summary_arrays,
        **physical_evidence,
        "observed_discharge_read": np.asarray(False, dtype=bool),
        "forecast_executed": np.asarray(False, dtype=bool),
        "assimilation_executed": np.asarray(False, dtype=bool),
        "state_reset_at_switch": np.asarray(False, dtype=bool),
    }

    with np.load(result_dir / "evidence.npz", allow_pickle=False) as saved:
        missing_keys = sorted(set(expected) - set(saved.files))
        unexpected_keys = sorted(set(saved.files) - set(expected))
        differences = {
            name: _maximum_difference(saved[name], expected[name])
            for name in expected
            if name in saved.files
        }
    maximum_difference = max(differences.values()) if differences else float("inf")

    csv_checks = _verify_csv_files(result_dir, expected, tolerance)
    saved_summary = json.loads((result_dir / "summary.json").read_text(encoding="utf-8"))
    summary_checks = _verify_summary(saved_summary, expected, physical, tolerance)
    checksum_manifest = json.loads((result_dir / "checksums.json").read_text(encoding="utf-8"))
    expected_checksum_names = set(config["output_files"]) - {"checksums.json"}
    checksum_checks = {
        "manifest_file_set": set(checksum_manifest) == expected_checksum_names,
        "file_hashes": all(
            (result_dir / name).is_file() and _sha256(result_dir / name) == digest
            for name, digest in checksum_manifest.items()
        ),
    }
    figure_checks = {}
    for figure_name in (
        "per_state_standardized_response.png",
        "state_group_standardized_response.png",
        "initial_new_parameter_domain_projection.png",
    ):
        try:
            image = matplotlib_image.imread(result_dir / figure_name)
            figure_checks[figure_name] = bool(image.size > 0 and image.ndim in (2, 3) and np.all(np.isfinite(image)))
        except Exception:
            figure_checks[figure_name] = False

    passed = (
        config_matches_frozen
        and all(source_hash_checks.values())
        and set(requested_arrays) == set(TRUTH_ARRAY_NAMES + SCALE_ARRAY_NAMES)
        and "observed_discharge" not in requested_arrays
        and "truth_discharge" not in requested_arrays
        and not missing_keys
        and not unexpected_keys
        and maximum_difference <= tolerance
        and physical["passed"]
        and all(csv_checks.values())
        and all(summary_checks.values())
        and all(checksum_checks.values())
        and all(figure_checks.values())
    )
    report = {
        "status": "passed" if passed else "failed",
        "independent_equation_path": "hbv_joint_uncertainty.hbv_adapter.advance_state",
        "independent_projection_path": "hbv_joint_uncertainty.preflight.project_hbv_state",
        "production_causal_control_module_imported": False,
        "production_runner_imported": False,
        "forecast_module_imported": False,
        "config_matches_frozen": config_matches_frozen,
        "tolerance": tolerance,
        "maximum_absolute_difference_overall": maximum_difference,
        "maximum_absolute_differences": differences,
        "missing_evidence_keys": missing_keys,
        "unexpected_evidence_keys": unexpected_keys,
        "source_hash_checks": source_hash_checks,
        "requested_source_arrays": requested_arrays,
        "observed_discharge_read": False,
        "truth_discharge_read": False,
        "forecast_executed": False,
        "assimilation_executed": False,
        "physical_checks": physical,
        "csv_checks": csv_checks,
        "summary_checks": summary_checks,
        "checksum_checks": checksum_checks,
        "figure_decode_checks": figure_checks,
        "independently_recomputed_decision": str(expected["decision"].item()),
        "independently_recomputed_initial_projection_event_count": int(
            expected["initial_new_parameter_domain_projection_event_count"]
        ),
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not passed:
        raise SystemExit(1)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    report = verify(args.result_dir)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
