"""Matched causal propagation for synthetic HBV-lite truth-parameter switches."""

from __future__ import annotations

from collections.abc import Mapping, Sequence

import numpy as np

from .synthetic_truth import (
    HYDROLOGIC_STATE_NAMES,
    PARAMETER_NAMES,
    advance_reference_state,
    project_reference_state,
)


ROUTING_STATE_NAMES = tuple(f"qraw_t_minus_{offset}" for offset in range(10))
STATE_NAMES = HYDROLOGIC_STATE_NAMES + ROUTING_STATE_NAMES
BRANCH_NAMES = (
    "continue_old_true_parameters",
    "switch_to_new_true_parameters",
)
STATE_GROUP_NAMES = ("hydrologic_stores", "routing_memory")
STATE_GROUP_SLICES = (slice(0, 5), slice(5, 15))


def _validated_state(state, label: str) -> np.ndarray:
    values = np.asarray(state, dtype=np.float64)
    if values.shape != (len(STATE_NAMES),) or not np.all(np.isfinite(values)):
        raise ValueError(f"{label} must be one finite fifteen-element vector")
    return values


def _validated_forcing(forcing) -> np.ndarray:
    values = np.asarray(forcing, dtype=np.float64)
    if values.ndim != 2 or values.shape[1] != 3 or values.shape[0] == 0:
        raise ValueError("forcing must have shape (response_days, 3) with at least one day")
    if not np.all(np.isfinite(values)):
        raise ValueError("forcing must contain only finite values")
    return values


def _validated_process_perturbations(process_perturbations, response_days: int) -> np.ndarray:
    values = np.asarray(process_perturbations, dtype=np.float64)
    expected = (response_days, len(STATE_NAMES))
    if values.shape != expected or not np.all(np.isfinite(values)):
        raise ValueError(f"process_perturbations must be one finite array with shape {expected}")
    if np.any(values[:, len(HYDROLOGIC_STATE_NAMES):] != 0.0):
        raise ValueError("routing-memory process perturbations must be exactly zero")
    return values


def _validated_parameters(parameters: Mapping[str, float], label: str) -> dict[str, float]:
    if set(parameters) != set(PARAMETER_NAMES):
        raise ValueError(f"{label} must contain exactly the thirteen HBV-lite parameters")
    values = {name: float(parameters[name]) for name in PARAMETER_NAMES}
    if not np.all(np.isfinite(tuple(values.values()))):
        raise ValueError(f"{label} must contain only finite values")
    return values


def propagate_matched_parameter_branches(
    initial_state,
    forcing,
    process_perturbations,
    old_parameters: Mapping[str, float],
    new_parameters: Mapping[str, float],
) -> dict[str, np.ndarray | float]:
    """Propagate two truth branches whose only difference is the parameter vector.

    Both branches begin from an exact copy of the supplied pre-switch state and
    receive the same forcing and realized process perturbation on every day.
    The explicit pre-transition projection is retained because parameter-domain
    clipping is part of the authoritative synthetic-truth transition.
    """
    state0 = _validated_state(initial_state, "initial_state")
    forcing_values = _validated_forcing(forcing)
    perturbations = _validated_process_perturbations(process_perturbations, len(forcing_values))
    branch_parameters = (
        _validated_parameters(old_parameters, "old_parameters"),
        _validated_parameters(new_parameters, "new_parameters"),
    )

    response_days = len(forcing_values)
    shape = (len(BRANCH_NAMES), response_days, len(STATE_NAMES))
    branch_states = np.empty(shape, dtype=np.float64)
    pretransition_projected_states = np.empty(shape, dtype=np.float64)
    deterministic_states = np.empty(shape, dtype=np.float64)
    pretransition_projection_adjustments = np.empty(shape, dtype=np.float64)
    postperturbation_projection_adjustments = np.empty(shape, dtype=np.float64)
    routing_shift_maximum_absolute_error = 0.0

    for branch_index, parameters in enumerate(branch_parameters):
        state = state0.copy()
        for lead, (rain, potential_evaporation, temperature) in enumerate(forcing_values):
            pretransition = project_reference_state(state, parameters)
            deterministic = advance_reference_state(
                pretransition,
                rain,
                potential_evaporation,
                temperature,
                parameters,
            )
            unprojected = deterministic + perturbations[lead]
            projected = project_reference_state(unprojected, parameters)

            pretransition_projected_states[branch_index, lead] = pretransition
            pretransition_projection_adjustments[branch_index, lead] = pretransition - state
            deterministic_states[branch_index, lead] = deterministic
            postperturbation_projection_adjustments[branch_index, lead] = projected - unprojected
            branch_states[branch_index, lead] = projected

            routing_shift_error = np.max(np.abs(deterministic[6:] - pretransition[5:14]))
            routing_shift_maximum_absolute_error = max(
                routing_shift_maximum_absolute_error,
                float(routing_shift_error),
            )
            state = projected

    return {
        "branch_names": np.asarray(BRANCH_NAMES),
        "initial_states": np.stack((state0.copy(), state0.copy())),
        "shared_forcing": forcing_values.copy(),
        "shared_process_perturbations": perturbations.copy(),
        "pretransition_projected_states": pretransition_projected_states,
        "pretransition_projection_adjustments": pretransition_projection_adjustments,
        "deterministic_states": deterministic_states,
        "postperturbation_projection_adjustments": postperturbation_projection_adjustments,
        "branch_states": branch_states,
        "branch_state_difference": branch_states[1] - branch_states[0],
        "routing_shift_maximum_absolute_error": routing_shift_maximum_absolute_error,
    }


def _parameter_map(vector) -> dict[str, float]:
    values = np.asarray(vector, dtype=np.float64)
    if values.shape != (len(PARAMETER_NAMES),) or not np.all(np.isfinite(values)):
        raise ValueError("each parameter vector must contain thirteen finite values")
    return {name: float(value) for name, value in zip(PARAMETER_NAMES, values)}


def build_switch_events(
    *,
    forcing_blocks,
    warmup_days: int,
    truth_states,
    truth_process_perturbations,
    truth_parameter_indices,
    parameter_ids,
    parameter_vectors,
    switch_boundaries: Sequence[int],
    response_days: int,
) -> dict[str, np.ndarray | float]:
    """Assemble all matched block, truth-trial, and switch-boundary events."""
    forcing_values = np.asarray(forcing_blocks, dtype=np.float64)
    truth_values = np.asarray(truth_states, dtype=np.float64)
    perturbation_values = np.asarray(truth_process_perturbations, dtype=np.float64)
    schedule = np.asarray(truth_parameter_indices, dtype=np.int64)
    identifiers = np.asarray(parameter_ids).astype(str)
    parameter_values = np.asarray(parameter_vectors, dtype=np.float64)
    boundaries = np.asarray(switch_boundaries, dtype=np.int64)
    warmup = int(warmup_days)
    window = int(response_days)

    if forcing_values.ndim != 3 or forcing_values.shape[2] != 3 or not np.all(np.isfinite(forcing_values)):
        raise ValueError("forcing_blocks must have shape (blocks, days, 3) and be finite")
    if truth_values.ndim != 4 or truth_values.shape[0] != forcing_values.shape[0] or truth_values.shape[3] != 15:
        raise ValueError("truth_states must have shape (blocks, truth_trials, days, 15)")
    if perturbation_values.shape != truth_values.shape or not np.all(np.isfinite(perturbation_values)):
        raise ValueError("truth_process_perturbations must match truth_states and be finite")
    if not np.all(np.isfinite(truth_values)):
        raise ValueError("truth_states must contain only finite values")
    if schedule.shape != truth_values.shape[1:3]:
        raise ValueError("truth_parameter_indices must have shape (truth_trials, days)")
    if identifiers.ndim != 1 or parameter_values.shape != (len(identifiers), len(PARAMETER_NAMES)):
        raise ValueError("parameter identifiers and vectors have incompatible shapes")
    if not np.all(np.isfinite(parameter_values)):
        raise ValueError("parameter_vectors must contain only finite values")
    if np.any(schedule < 0) or np.any(schedule >= len(identifiers)):
        raise ValueError("truth_parameter_indices contains an invalid parameter index")
    if boundaries.ndim != 1 or len(boundaries) == 0 or np.any(boundaries <= 0):
        raise ValueError("switch_boundaries must contain positive zero-based indices")
    if window <= 0 or warmup < 0:
        raise ValueError("response_days must be positive and warmup_days nonnegative")
    if np.max(boundaries) + window > truth_values.shape[2]:
        raise ValueError("truth-state response window exceeds the saved truth horizon")
    if warmup + np.max(boundaries) + window > forcing_values.shape[1]:
        raise ValueError("forcing response window exceeds the saved forcing horizon")

    records: list[dict[str, np.ndarray | float | int | str]] = []
    for block_index in range(forcing_values.shape[0]):
        for truth_index in range(truth_values.shape[1]):
            for boundary in boundaries:
                boundary_value = int(boundary)
                old_index = int(schedule[truth_index, boundary_value - 1])
                new_index = int(schedule[truth_index, boundary_value])
                if old_index == new_index:
                    raise ValueError("configured boundary is not a true-parameter switch")
                if not np.all(schedule[truth_index, boundary_value:boundary_value + window] == new_index):
                    raise ValueError("new true parameter is not fixed throughout the response window")

                event_forcing = forcing_values[
                    block_index,
                    warmup + boundary_value:warmup + boundary_value + window,
                ]
                event_perturbations = perturbation_values[
                    block_index,
                    truth_index,
                    boundary_value:boundary_value + window,
                ]
                initial_state = truth_values[block_index, truth_index, boundary_value - 1]
                propagation = propagate_matched_parameter_branches(
                    initial_state,
                    event_forcing,
                    event_perturbations,
                    _parameter_map(parameter_values[old_index]),
                    _parameter_map(parameter_values[new_index]),
                )
                saved_truth = truth_values[
                    block_index,
                    truth_index,
                    boundary_value:boundary_value + window,
                ]
                reconstruction_error = float(np.max(np.abs(propagation["branch_states"][1] - saved_truth)))
                records.append(
                    {
                        "block_index": block_index,
                        "truth_index": truth_index,
                        "boundary": boundary_value,
                        "old_parameter_index": old_index,
                        "new_parameter_index": new_index,
                        "transition_label": f"{identifiers[old_index]}_to_{identifiers[new_index]}",
                        "initial_state": initial_state.copy(),
                        "forcing": event_forcing.copy(),
                        "perturbations": event_perturbations.copy(),
                        "branch_parameters": np.stack((parameter_values[old_index], parameter_values[new_index])),
                        "saved_truth": saved_truth.copy(),
                        "reconstruction_error": reconstruction_error,
                        **propagation,
                    }
                )

    if not records:
        raise ValueError("no switch events were assembled")

    array_fields = (
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
    result: dict[str, np.ndarray | float] = {
        "event_indices": np.arange(len(records), dtype=np.int64),
        "block_indices": np.asarray([record["block_index"] for record in records], dtype=np.int64),
        "truth_indices": np.asarray([record["truth_index"] for record in records], dtype=np.int64),
        "switch_boundaries": np.asarray([record["boundary"] for record in records], dtype=np.int64),
        "old_parameter_indices": np.asarray(
            [record["old_parameter_index"] for record in records], dtype=np.int64
        ),
        "new_parameter_indices": np.asarray(
            [record["new_parameter_index"] for record in records], dtype=np.int64
        ),
        "transition_labels": np.asarray([record["transition_label"] for record in records]),
        "branch_names": np.asarray(BRANCH_NAMES),
        "parameter_names": np.asarray(PARAMETER_NAMES),
        "parameter_ids": identifiers.copy(),
        "parameter_vectors": parameter_values.copy(),
        "warmup_days": np.asarray(warmup, dtype=np.int64),
        "response_days": np.asarray(window, dtype=np.int64),
    }
    for field in array_fields:
        result[field] = np.stack([np.asarray(record[field]) for record in records])
    reconstruction_errors = np.asarray([record["reconstruction_error"] for record in records], dtype=np.float64)
    result["new_branch_truth_reconstruction_maximum_absolute_error_by_event"] = reconstruction_errors
    result["new_branch_truth_reconstruction_maximum_absolute_error"] = float(np.max(reconstruction_errors))
    result["routing_shift_maximum_absolute_error"] = float(
        max(float(record["routing_shift_maximum_absolute_error"]) for record in records)
    )
    return result


def evaluate_physical_checks(events: Mapping[str, np.ndarray | float], *, tolerance: float) -> dict[str, float | bool]:
    """Evaluate every fail-closed physical and matched-design condition."""
    threshold = float(tolerance)
    if not np.isfinite(threshold) or threshold < 0.0:
        raise ValueError("tolerance must be one finite nonnegative value")
    states = np.asarray(events["branch_states"], dtype=np.float64)
    parameters = np.asarray(events["branch_parameters"], dtype=np.float64)
    perturbations = np.asarray(events["shared_process_perturbations"], dtype=np.float64)
    initial_states = np.asarray(events["initial_states"], dtype=np.float64)
    if states.ndim != 4 or states.shape[1:] != (2, int(np.asarray(events["response_days"]).item()), 15):
        raise ValueError("event branch states have an invalid shape")
    if parameters.shape != (states.shape[0], 2, len(PARAMETER_NAMES)):
        raise ValueError("event branch parameters have an invalid shape")

    field_capacity = parameters[:, :, PARAMETER_NAMES.index("parFC")][:, :, None]
    holding_fraction = parameters[:, :, PARAMETER_NAMES.index("parCWH")][:, :, None]
    soil_excess = states[..., 2] - field_capacity
    meltwater_excess = states[..., 1] - holding_fraction * states[..., 0]
    minimum_state = float(np.min(states))
    maximum_soil_excess = float(np.max(soil_excess))
    maximum_meltwater_excess = float(np.max(meltwater_excess))
    routing_perturbation_maximum = float(np.max(np.abs(perturbations[..., 5:])))
    initial_state_branch_maximum_difference = float(np.max(np.abs(initial_states[:, 1] - initial_states[:, 0])))
    routing_shift_maximum = float(events["routing_shift_maximum_absolute_error"])
    truth_reconstruction_maximum = float(events["new_branch_truth_reconstruction_maximum_absolute_error"])

    checks = {
        "all_states_finite": bool(np.all(np.isfinite(states))),
        "all_states_nonnegative_with_tolerance": minimum_state >= -threshold,
        "soil_moisture_not_above_active_field_capacity": maximum_soil_excess <= threshold,
        "meltwater_not_above_active_holding_fraction_times_snowpack": maximum_meltwater_excess <= threshold,
        "routing_memory_process_perturbations_exactly_zero": routing_perturbation_maximum == 0.0,
        "routing_memory_shift_exact_within_tolerance": routing_shift_maximum <= threshold,
        "initial_states_identical_between_branches": initial_state_branch_maximum_difference == 0.0,
        "new_branch_reconstructs_sealed_truth_within_tolerance": truth_reconstruction_maximum <= threshold,
    }
    return {
        **checks,
        "minimum_state": minimum_state,
        "maximum_soil_moisture_excess": maximum_soil_excess,
        "maximum_meltwater_holding_excess": maximum_meltwater_excess,
        "routing_memory_process_perturbation_maximum_absolute_value": routing_perturbation_maximum,
        "routing_memory_shift_maximum_absolute_error": routing_shift_maximum,
        "initial_state_branch_maximum_absolute_difference": initial_state_branch_maximum_difference,
        "new_branch_truth_reconstruction_maximum_absolute_error": truth_reconstruction_maximum,
        "passed": all(checks.values()),
    }


def _root_mean_square(values: np.ndarray, axis) -> np.ndarray:
    return np.sqrt(np.mean(np.square(values), axis=axis))


def summarize_state_response(
    branch_state_differences,
    state_scales,
    transition_labels: Sequence[str],
    initial_new_parameter_domain_projection_adjustments,
    *,
    tolerance: float,
) -> dict[str, np.ndarray | int | str]:
    """Summarize all-state response curves without collapsing routing memory."""
    differences = np.asarray(branch_state_differences, dtype=np.float64)
    if differences.ndim != 3 or differences.shape[2] != len(STATE_NAMES) or differences.shape[1] == 0:
        raise ValueError("branch_state_differences must have shape (events, response_days, 15)")
    if differences.shape[0] == 0 or not np.all(np.isfinite(differences)):
        raise ValueError("branch_state_differences must contain finite values and at least one event")

    scales = np.asarray(state_scales, dtype=np.float64)
    if scales.shape != (len(STATE_NAMES),) or not np.all(np.isfinite(scales)) or np.any(scales <= 0.0):
        raise ValueError("state_scales must contain fifteen finite positive values")
    labels = np.asarray(transition_labels).astype(str)
    if labels.shape != (differences.shape[0],):
        raise ValueError("transition_labels must contain one label per event")
    projection = np.asarray(initial_new_parameter_domain_projection_adjustments, dtype=np.float64)
    if projection.shape != (differences.shape[0], len(STATE_NAMES)) or not np.all(np.isfinite(projection)):
        raise ValueError("initial projection adjustments must have shape (events, 15) and be finite")
    threshold = float(tolerance)
    if not np.isfinite(threshold) or threshold < 0.0:
        raise ValueError("tolerance must be one finite nonnegative value")

    standardized = differences / scales[None, None, :]
    pooled_state_response = _root_mean_square(standardized, axis=0)
    pooled_state_raw_response = _root_mean_square(differences, axis=0)
    group_response = np.column_stack(
        [_root_mean_square(standardized[:, :, group_slice], axis=(0, 2)) for group_slice in STATE_GROUP_SLICES]
    )

    unique_labels = tuple(dict.fromkeys(labels.tolist()))
    transition_state_response = np.stack(
        [_root_mean_square(standardized[labels == label], axis=0) for label in unique_labels]
    )
    transition_state_raw_response = np.stack(
        [_root_mean_square(differences[labels == label], axis=0) for label in unique_labels]
    )
    transition_group_response = np.stack(
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
    transition_event_count = np.asarray([np.count_nonzero(labels == label) for label in unique_labels], dtype=np.int64)

    absolute_projection_exceeds_tolerance = np.abs(projection) > threshold
    projection_event_count = int(np.count_nonzero(np.any(absolute_projection_exceeds_tolerance, axis=1)))
    decision = (
        "requires_separate_fixed_parameter_state_jump_recovery_experiment"
        if projection_event_count > 0
        else "suitable_as_clean_parameter_switch_truth_condition_for_state_accuracy"
    )

    return {
        "state_names": np.asarray(STATE_NAMES),
        "state_group_names": np.asarray(STATE_GROUP_NAMES),
        "transition_labels": np.asarray(unique_labels),
        "transition_event_count": transition_event_count,
        "standardized_response": standardized,
        "pooled_state_root_mean_square_raw_response": pooled_state_raw_response,
        "pooled_state_root_mean_square_standardized_response": pooled_state_response,
        "transition_state_root_mean_square_raw_response": transition_state_raw_response,
        "transition_state_root_mean_square_standardized_response": transition_state_response,
        "group_root_mean_square_standardized_response": group_response,
        "transition_group_root_mean_square_standardized_response": transition_group_response,
        "per_state_day_1_root_mean_square_raw_response": pooled_state_raw_response[0],
        "per_state_day_1_root_mean_square_standardized_response": pooled_state_response[0],
        "per_state_peak_root_mean_square_raw_response": np.max(pooled_state_raw_response, axis=0),
        "per_state_peak_root_mean_square_standardized_response": np.max(pooled_state_response, axis=0),
        "per_state_peak_lead": np.argmax(pooled_state_response, axis=0).astype(np.int64) + 1,
        "per_group_day_1_root_mean_square_standardized_response": group_response[0],
        "per_group_peak_root_mean_square_standardized_response": np.max(group_response, axis=0),
        "per_group_peak_lead": np.argmax(group_response, axis=0).astype(np.int64) + 1,
        "initial_new_parameter_domain_projection_adjustments": projection,
        "initial_new_parameter_domain_projection_event_count": projection_event_count,
        "initial_new_parameter_domain_projection_state_event_count": np.count_nonzero(
            absolute_projection_exceeds_tolerance,
            axis=0,
        ).astype(np.int64),
        "decision": decision,
    }
