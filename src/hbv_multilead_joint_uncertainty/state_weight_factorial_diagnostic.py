"""Pure forecast compositors for the state-path by final-weight diagnostic."""

from __future__ import annotations

import copy
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

import numpy as np

from .forecast import forecast_from_posterior
from .methods import MethodCandidate, build_method_bank


def _as_real_float_array(value: object, name: str) -> np.ndarray:
    """Convert a real-valued input while normalizing public validation errors."""
    try:
        untyped = np.asarray(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be convertible to a real float array") from error
    if np.iscomplexobj(untyped):
        raise ValueError(f"{name} must be real-valued")
    try:
        return np.asarray(value, dtype=np.float64)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be convertible to a real float array") from error


def combine_candidate_forecasts(
    candidate_forecasts: np.ndarray,
    final_probabilities: np.ndarray,
) -> np.ndarray:
    """Combine candidate forecasts using one fixed final probability vector."""
    forecasts = _as_real_float_array(candidate_forecasts, "candidate_forecasts")
    probabilities = _as_real_float_array(final_probabilities, "final_probabilities")
    if forecasts.ndim != 2 or not np.all(np.isfinite(forecasts)):
        raise ValueError("candidate_forecasts must be a finite (lead, candidate) array")
    if probabilities.ndim != 1 or probabilities.shape[0] != forecasts.shape[1]:
        raise ValueError("final_probabilities must contain one value per candidate")
    if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
        raise ValueError("final_probabilities must be finite and non-negative")
    if abs(float(probabilities.sum()) - 1.0) > 1e-12:
        raise ValueError("final_probabilities must sum to one within 1e-12")
    return forecasts @ probabilities


def state_weight_factorial_forecasts(
    full_candidate_forecasts: np.ndarray,
    none_candidate_forecasts: np.ndarray,
    full_final_probabilities: np.ndarray,
    none_final_probabilities: np.ndarray,
) -> dict[str, np.ndarray]:
    """Cross two candidate-forecast paths with two final probability vectors."""
    full_forecasts = _as_real_float_array(
        full_candidate_forecasts,
        "full_candidate_forecasts",
    )
    none_forecasts = _as_real_float_array(
        none_candidate_forecasts,
        "none_candidate_forecasts",
    )
    if full_forecasts.shape != none_forecasts.shape:
        raise ValueError("full and none candidate forecasts must have identical shapes")

    full_states_full_weights = combine_candidate_forecasts(
        full_forecasts,
        full_final_probabilities,
    )
    full_states_none_weights = combine_candidate_forecasts(
        full_forecasts,
        none_final_probabilities,
    )
    none_states_full_weights = combine_candidate_forecasts(
        none_forecasts,
        full_final_probabilities,
    )
    none_states_none_weights = combine_candidate_forecasts(
        none_forecasts,
        none_final_probabilities,
    )
    return {
        "full_states_full_weights": full_states_full_weights,
        "full_states_none_weights": full_states_none_weights,
        "none_states_full_weights": none_states_full_weights,
        "none_states_none_weights": none_states_none_weights,
        "prediction_nonadditivity": (
            full_states_full_weights
            - full_states_none_weights
            - none_states_full_weights
            + none_states_none_weights
        ),
    }


@dataclass(frozen=True)
class TerminalAssimilationForecast:
    """Terminal candidate posteriors and one frozen-probability forecast."""

    daily_probabilities: np.ndarray
    final_candidate_states: np.ndarray
    final_candidate_covariances: np.ndarray
    candidate_forecasts: np.ndarray
    combined_forecast: np.ndarray


def _validated_positive_integer(value: object, name: str) -> int:
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, (int, np.integer)):
        raise ValueError(f"{name} must be a positive integer")
    result = int(value)
    if result <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return result


def _validated_lead_days(leads: Sequence[int]) -> tuple[int, ...]:
    try:
        values = tuple(leads)
    except TypeError as error:
        raise ValueError("leads must be a nonempty sequence of integers") from error
    if not values or any(
        isinstance(value, (bool, np.bool_))
        or not isinstance(value, (int, np.integer))
        for value in values
    ):
        raise ValueError("leads must be a nonempty sequence of integers")
    result = tuple(int(value) for value in values)
    if any(value <= 0 for value in result) or any(
        current <= previous for previous, current in zip(result, result[1:])
    ):
        raise ValueError("leads must be positive, unique, and strictly increasing")
    return result


def _validated_scalar(value: object, name: str) -> float:
    if isinstance(value, (bool, np.bool_)):
        raise ValueError(f"{name} must be a finite scalar")
    try:
        untyped = np.asarray(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be a finite scalar") from error
    if untyped.ndim != 0 or np.iscomplexobj(untyped):
        raise ValueError(f"{name} must be a finite scalar")
    try:
        result = float(untyped)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be a finite scalar") from error
    if not np.isfinite(result):
        raise ValueError(f"{name} must be a finite scalar")
    return result


def _validated_probability_vector(value: object, candidate_count: int) -> np.ndarray:
    probabilities = _as_real_float_array(value, "candidate probabilities").copy()
    if probabilities.shape != (candidate_count,):
        raise ValueError("candidate probabilities must contain one value per candidate")
    if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
        raise ValueError("candidate probabilities must be finite and non-negative")
    if abs(float(probabilities.sum()) - 1.0) > 1e-12:
        raise ValueError("candidate probabilities must sum to one within 1e-12")
    return probabilities


def _readonly_copy(value: np.ndarray) -> np.ndarray:
    result = np.asarray(value, dtype=np.float64).copy()
    result.setflags(write=False)
    return result


def assimilate_terminal_forecast(
    candidates: Sequence[MethodCandidate],
    initial_states: Mapping[str, np.ndarray],
    initial_covariance: np.ndarray,
    active_forcing: np.ndarray,
    observations: np.ndarray,
    assimilation_days: int,
    leads: Sequence[int],
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
    interaction_mode: str,
) -> TerminalAssimilationForecast:
    """Assimilate one path and capture every terminal candidate before forecasting."""
    if interaction_mode not in {"full", "none"}:
        raise ValueError("interaction_mode must be full or none")
    days = _validated_positive_integer(assimilation_days, "assimilation_days")
    lead_days = _validated_lead_days(leads)

    try:
        definitions = tuple(copy.deepcopy(tuple(candidates)))
    except TypeError as error:
        raise ValueError("candidates must be a nonempty sequence") from error
    if not definitions:
        raise ValueError("candidates must be a nonempty sequence")
    if any(not hasattr(candidate, "parameter_id") for candidate in definitions):
        raise ValueError("each candidate must define parameter_id")
    candidate_count = len(definitions)

    if not isinstance(initial_states, Mapping) or not initial_states:
        raise ValueError("initial_states must be a nonempty mapping")
    copied_states = {}
    for parameter_id, state in initial_states.items():
        state_array = _as_real_float_array(state, "initial state").copy()
        if state_array.shape != (15,) or not np.all(np.isfinite(state_array)):
            raise ValueError("every initial state must be a finite 15-vector")
        copied_states[parameter_id] = state_array
    missing = {
        candidate.parameter_id
        for candidate in definitions
        if candidate.parameter_id not in copied_states
    }
    if missing:
        raise ValueError("initial_states is missing at least one candidate parameter_id")

    covariance = _as_real_float_array(initial_covariance, "initial_covariance").copy()
    if covariance.shape != (15, 15) or not np.all(np.isfinite(covariance)):
        raise ValueError("initial_covariance must be a finite 15 by 15 matrix")
    if not np.allclose(covariance, covariance.T, rtol=0.0, atol=1e-12):
        raise ValueError("initial_covariance must be symmetric")

    forcing = _as_real_float_array(active_forcing, "active_forcing").copy()
    if forcing.ndim != 2 or forcing.shape[1] != 3 or not np.all(np.isfinite(forcing)):
        raise ValueError("active_forcing must be a finite array with shape (days, 3)")
    required_days = days + lead_days[-1]
    if len(forcing) < required_days:
        raise ValueError("active_forcing does not cover assimilation plus maximum lead")

    observed = _as_real_float_array(observations, "observations").copy()
    if observed.ndim != 1 or len(observed) < days:
        raise ValueError("observations must be a vector covering every assimilation day")
    if not np.all(np.isfinite(observed[:days])):
        raise ValueError("observations must be finite on every assimilation day")

    observation_std = _validated_scalar(
        observation_standard_deviation, "observation_standard_deviation"
    )
    if observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be positive")
    stay_probability = _validated_scalar(
        factor_transition_stay_probability,
        "factor_transition_stay_probability",
    )
    if stay_probability < 0.0 or stay_probability > 1.0:
        raise ValueError("factor_transition_stay_probability must be between zero and one")

    bank = build_method_bank(
        candidates=definitions,
        initial_states=copied_states,
        initial_covariance=covariance,
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=stay_probability,
        interaction_mode=interaction_mode,
    )
    filters = tuple(bank.estimator.filters)
    transitions = tuple(bank.transitions)
    if len(filters) != candidate_count or len(transitions) != candidate_count:
        raise ValueError("candidate bank components must match the candidate count")

    daily_probabilities = np.empty((days, candidate_count), dtype=np.float64)
    for day in range(days):
        rain, potential_evaporation, temperature = forcing[day]
        for transition in transitions:
            transition.set_forcing(rain, potential_evaporation, temperature)
        bank.estimator.step(observed[day])
        daily_probabilities[day] = _validated_probability_vector(
            bank.estimator.probabilities, candidate_count
        )

    terminal_states = np.empty((candidate_count, 15), dtype=np.float64)
    terminal_covariances = np.empty((candidate_count, 15, 15), dtype=np.float64)
    for candidate_index, candidate_filter in enumerate(filters):
        state = _as_real_float_array(candidate_filter.state, "terminal candidate state")
        covariance_at_terminal = _as_real_float_array(
            candidate_filter.covariance, "terminal candidate covariance"
        )
        if state.shape != (15,) or not np.all(np.isfinite(state)):
            raise ValueError("every terminal candidate state must be a finite 15-vector")
        if covariance_at_terminal.shape != (15, 15) or not np.all(
            np.isfinite(covariance_at_terminal)
        ):
            raise ValueError(
                "every terminal candidate covariance must be a finite 15 by 15 matrix"
            )
        terminal_states[candidate_index] = state.copy()
        terminal_covariances[candidate_index] = covariance_at_terminal.copy()

    future = forcing[days:required_days].copy()
    forecast = forecast_from_posterior(
        bank,
        future,
        lead_days=lead_days,
        interaction_mode=interaction_mode,
    )
    forecast_probabilities = _as_real_float_array(
        forecast.probabilities, "forecast probabilities"
    ).copy()
    candidate_forecasts = _as_real_float_array(
        forecast.candidate_predictions, "candidate forecasts"
    ).copy()
    combined_forecast = _as_real_float_array(
        forecast.combined_predictions, "combined forecast"
    ).copy()
    lead_count = len(lead_days)
    if forecast_probabilities.shape != (lead_count, candidate_count):
        raise ValueError("forecast probabilities have an invalid shape")
    if candidate_forecasts.shape != (lead_count, candidate_count):
        raise ValueError("candidate forecasts have an invalid shape")
    if combined_forecast.shape != (lead_count,):
        raise ValueError("combined forecast has an invalid shape")
    if not all(
        np.all(np.isfinite(values))
        for values in (forecast_probabilities, candidate_forecasts, combined_forecast)
    ):
        raise ValueError("forecast outputs must be finite")

    frozen_probabilities = np.broadcast_to(
        daily_probabilities[-1], forecast_probabilities.shape
    )
    if not np.array_equal(forecast_probabilities, frozen_probabilities):
        raise RuntimeError("forecast probabilities must equal the final posterior")
    expected_combined = candidate_forecasts @ daily_probabilities[-1]
    maximum_combination_error = float(
        np.max(np.abs(combined_forecast - expected_combined))
    )
    if maximum_combination_error > 1e-12:
        raise RuntimeError(
            "combined forecast must use the final posterior probabilities; "
            f"maximum absolute error={maximum_combination_error}"
        )

    return TerminalAssimilationForecast(
        daily_probabilities=_readonly_copy(daily_probabilities),
        final_candidate_states=_readonly_copy(terminal_states),
        final_candidate_covariances=_readonly_copy(terminal_covariances),
        candidate_forecasts=_readonly_copy(candidate_forecasts),
        combined_forecast=_readonly_copy(combined_forecast),
    )


_SEALED_DRIVER_FIELDS = (
    "block_ids",
    "forcing_blocks",
    "warmup_days",
    "assimilation_days",
    "forecast_lead_days",
    "initial_parameter_states",
    "initial_covariances",
    "observed_discharge",
    "truth_forecast_discharge",
    "truth_primary_candidate_indices",
    "parameter_ids",
    "candidate_ids",
)


def _validated_nonnegative_integer(value: object, name: str) -> int:
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, (int, np.integer)):
        raise ValueError(f"{name} must be a non-negative integer")
    result = int(value)
    if result < 0:
        raise ValueError(f"{name} must be a non-negative integer")
    return result


def _sealed_driver_value(sealed_inputs: Mapping[str, object], name: str) -> object:
    if not isinstance(sealed_inputs, Mapping):
        raise ValueError("sealed_inputs must be a mapping")
    if name not in sealed_inputs:
        raise ValueError(f"sealed_inputs is missing {name}")
    return sealed_inputs[name]


def _validated_identifier_vector(value: object, name: str) -> np.ndarray:
    raw = np.asarray(value)
    if raw.ndim != 1 or raw.size == 0:
        raise ValueError(f"{name} must be a nonempty identifier vector")
    identifiers = np.asarray([str(item) for item in raw], dtype=str)
    if any(not item for item in identifiers) or len(set(identifiers)) != len(identifiers):
        raise ValueError(f"{name} must contain unique nonempty identifiers")
    return identifiers


def _validated_terminal_result(
    result: TerminalAssimilationForecast,
    assimilation_days: int,
    lead_count: int,
    candidate_count: int,
    interaction_mode: str,
) -> dict[str, np.ndarray]:
    expected_shapes = {
        "daily_probabilities": (assimilation_days, candidate_count),
        "final_candidate_states": (candidate_count, 15),
        "final_candidate_covariances": (candidate_count, 15, 15),
        "candidate_forecasts": (lead_count, candidate_count),
        "combined_forecast": (lead_count,),
    }
    arrays = {}
    for field_name, expected_shape in expected_shapes.items():
        if not hasattr(result, field_name):
            raise ValueError(
                f"{interaction_mode} terminal forecast is missing {field_name}"
            )
        values = _as_real_float_array(
            getattr(result, field_name),
            f"{interaction_mode} {field_name}",
        ).copy()
        if values.shape != expected_shape or not np.all(np.isfinite(values)):
            raise ValueError(
                f"{interaction_mode} {field_name} must be finite with shape "
                f"{expected_shape}"
            )
        arrays[field_name] = values
    probabilities = arrays["daily_probabilities"]
    if np.any(probabilities < 0.0) or not np.allclose(
        probabilities.sum(axis=1),
        1.0,
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError(
            f"{interaction_mode} daily probabilities must be non-negative and sum to one"
        )
    return arrays


def compare_state_weight_factorial(
    sealed_inputs: Mapping[str, object],
    candidates: Sequence[MethodCandidate],
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
) -> dict[str, object]:
    """Cross final weights over candidate forecast distributions from two paths."""
    for field_name in _SEALED_DRIVER_FIELDS:
        _sealed_driver_value(sealed_inputs, field_name)
    observation_std = _validated_scalar(
        observation_standard_deviation,
        "observation_standard_deviation",
    )
    if observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be positive")
    stay_probability = _validated_scalar(
        factor_transition_stay_probability,
        "factor_transition_stay_probability",
    )
    if stay_probability < 0.0 or stay_probability > 1.0:
        raise ValueError(
            "factor_transition_stay_probability must be between zero and one"
        )


    block_ids = _validated_identifier_vector(
        _sealed_driver_value(sealed_inputs, "block_ids"),
        "block_ids",
    )
    parameter_ids = _validated_identifier_vector(
        _sealed_driver_value(sealed_inputs, "parameter_ids"),
        "parameter_ids",
    )
    candidate_ids = _validated_identifier_vector(
        _sealed_driver_value(sealed_inputs, "candidate_ids"),
        "candidate_ids",
    )
    block_count = len(block_ids)
    candidate_count = len(candidate_ids)
    if len(parameter_ids) != candidate_count:
        raise ValueError("parameter_ids and candidate_ids must have equal length")

    try:
        definitions = tuple(candidates)
    except TypeError as error:
        raise ValueError("candidates must be a nonempty sequence") from error
    if len(definitions) != candidate_count:
        raise ValueError("candidates must contain one definition per candidate_id")
    if any(
        not hasattr(candidate, "candidate_id")
        or not hasattr(candidate, "parameter_id")
        for candidate in definitions
    ):
        raise ValueError("each candidate must define candidate_id and parameter_id")
    definition_candidate_ids = tuple(str(candidate.candidate_id) for candidate in definitions)
    definition_parameter_ids = tuple(str(candidate.parameter_id) for candidate in definitions)
    if definition_candidate_ids != tuple(candidate_ids):
        raise ValueError("candidate order must exactly match sealed candidate_ids")
    if len(set(definition_candidate_ids)) != candidate_count:
        raise ValueError("candidate candidate_ids must be unique")
    if len(set(definition_parameter_ids)) != candidate_count:
        raise ValueError("each parameter_id must map to exactly one candidate")
    if set(definition_parameter_ids) != set(parameter_ids):
        raise ValueError("candidate parameter_ids must exactly match sealed parameter_ids")

    warmup_raw = np.asarray(_sealed_driver_value(sealed_inputs, "warmup_days"))
    assimilation_raw = np.asarray(
        _sealed_driver_value(sealed_inputs, "assimilation_days")
    )
    if warmup_raw.ndim != 0 or assimilation_raw.ndim != 0:
        raise ValueError("warmup_days and assimilation_days must be scalars")
    warmup_days = _validated_nonnegative_integer(warmup_raw.item(), "warmup_days")
    assimilation_days = _validated_positive_integer(
        assimilation_raw.item(), "assimilation_days"
    )
    lead_days = _validated_lead_days(
        _sealed_driver_value(sealed_inputs, "forecast_lead_days")
    )
    lead_count = len(lead_days)
    active_end = warmup_days + assimilation_days + lead_days[-1]

    forcing_blocks = _as_real_float_array(
        _sealed_driver_value(sealed_inputs, "forcing_blocks"),
        "forcing_blocks",
    )
    if (
        forcing_blocks.ndim != 3
        or forcing_blocks.shape[0] != block_count
        or forcing_blocks.shape[2] != 3
        or forcing_blocks.shape[1] < active_end
    ):
        raise ValueError(
            "forcing_blocks must cover warmup, assimilation, and forecast"
        )
    consumed_forcing = forcing_blocks[:, warmup_days:active_end]
    if not np.all(np.isfinite(consumed_forcing)):
        raise ValueError("consumed forcing values must be finite")
    initial_parameter_states = _as_real_float_array(
        _sealed_driver_value(sealed_inputs, "initial_parameter_states"),
        "initial_parameter_states",
    )
    if initial_parameter_states.shape != (block_count, candidate_count, 15) or not np.all(
        np.isfinite(initial_parameter_states)
    ):
        raise ValueError(
            "initial_parameter_states must be finite with shape (block, parameter, 15)"
        )
    initial_covariances = _as_real_float_array(
        _sealed_driver_value(sealed_inputs, "initial_covariances"),
        "initial_covariances",
    )
    if initial_covariances.shape != (block_count, 15, 15) or not np.all(
        np.isfinite(initial_covariances)
    ):
        raise ValueError(
            "initial_covariances must be finite with shape (block, 15, 15)"
        )
    if not np.allclose(
        initial_covariances,
        np.swapaxes(initial_covariances, -1, -2),
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError("initial_covariances must be symmetric")

    truth_labels_raw = np.asarray(
        _sealed_driver_value(sealed_inputs, "truth_primary_candidate_indices")
    )
    if truth_labels_raw.ndim != 2 or truth_labels_raw.shape[1] < assimilation_days:
        raise ValueError(
            "truth_primary_candidate_indices must cover every assimilation day"
        )
    truth_count = truth_labels_raw.shape[0]
    if truth_count == 0:
        raise ValueError("truth_primary_candidate_indices must contain a truth trial")
    final_truth_labels_float = _as_real_float_array(
        truth_labels_raw[:, assimilation_days - 1],
        "final truth candidate indices",
    )
    if (
        not np.all(np.isfinite(final_truth_labels_float))
        or np.any(final_truth_labels_float != np.trunc(final_truth_labels_float))
        or np.any(final_truth_labels_float < 0)
        or np.any(final_truth_labels_float >= candidate_count)
    ):
        raise ValueError("final truth candidate indices must be valid integers")
    final_truth_labels = np.asarray(final_truth_labels_float, dtype=np.int64)

    observations = _as_real_float_array(
        _sealed_driver_value(sealed_inputs, "observed_discharge"),
        "observed_discharge",
    )
    if (
        observations.ndim != 3
        or observations.shape[:2] != (block_count, truth_count)
        or observations.shape[2] < assimilation_days
    ):
        raise ValueError(
            "observed_discharge must cover each block, truth, and assimilation day"
        )
    consumed_observations = observations[:, :, :assimilation_days]
    if not np.all(np.isfinite(consumed_observations)):
        raise ValueError("consumed observed discharge must be finite")
    truth_forecasts = _as_real_float_array(
        _sealed_driver_value(sealed_inputs, "truth_forecast_discharge"),
        "truth_forecast_discharge",
    ).copy()
    if truth_forecasts.shape != (block_count, truth_count, lead_count) or not np.all(
        np.isfinite(truth_forecasts)
    ):
        raise ValueError(
            "truth_forecast_discharge must be finite with shape (block, truth, lead)"
        )

    parameter_axis = {
        parameter_id: index for index, parameter_id in enumerate(parameter_ids)
    }
    candidate_axis = {
        parameter_id: index
        for index, parameter_id in enumerate(definition_parameter_ids)
    }
    final_truth_parameter_ids = tuple(
        str(parameter_ids[label]) for label in final_truth_labels
    )
    final_true_candidate_indices = np.asarray(
        [candidate_axis[parameter_id] for parameter_id in final_truth_parameter_ids],
        dtype=np.int64,
    )
    final_true_candidate_ids = candidate_ids[final_true_candidate_indices].copy()

    path_arrays = {
        "probabilities_full": np.empty(
            (block_count, truth_count, assimilation_days, candidate_count)
        ),
        "probabilities_none": np.empty(
            (block_count, truth_count, assimilation_days, candidate_count)
        ),
        "final_candidate_states_full": np.empty(
            (block_count, truth_count, candidate_count, 15)
        ),
        "final_candidate_states_none": np.empty(
            (block_count, truth_count, candidate_count, 15)
        ),
        "final_candidate_covariances_full": np.empty(
            (block_count, truth_count, candidate_count, 15, 15)
        ),
        "final_candidate_covariances_none": np.empty(
            (block_count, truth_count, candidate_count, 15, 15)
        ),
        "candidate_forecasts_full": np.empty(
            (block_count, truth_count, lead_count, candidate_count)
        ),
        "candidate_forecasts_none": np.empty(
            (block_count, truth_count, lead_count, candidate_count)
        ),
    }
    combination_names = (
        "full_states_full_weights",
        "full_states_none_weights",
        "none_states_full_weights",
        "none_states_none_weights",
        "prediction_nonadditivity",
    )
    combination_arrays = {
        name: np.empty((block_count, truth_count, lead_count))
        for name in combination_names
    }

    for block in range(block_count):
        initial_state_template = {
            parameter_id: initial_parameter_states[
                block, parameter_axis[parameter_id]
            ].copy()
            for parameter_id in definition_parameter_ids
        }
        forcing_slice = forcing_blocks[block, warmup_days:active_end].copy()
        for truth in range(truth_count):
            terminal = {}
            for mode in ("full", "none"):
                raw_result = assimilate_terminal_forecast(
                    candidates=copy.deepcopy(definitions),
                    initial_states={
                        parameter_id: state.copy()
                        for parameter_id, state in initial_state_template.items()
                    },
                    initial_covariance=initial_covariances[block].copy(),
                    active_forcing=forcing_slice.copy(),
                    observations=observations[block, truth, :assimilation_days].copy(),
                    assimilation_days=assimilation_days,
                    leads=lead_days,
                    observation_standard_deviation=observation_std,
                    factor_transition_stay_probability=stay_probability,
                    interaction_mode=mode,
                )
                terminal[mode] = _validated_terminal_result(
                    raw_result,
                    assimilation_days,
                    lead_count,
                    candidate_count,
                    mode,
                )
                path_arrays[f"probabilities_{mode}"][block, truth] = terminal[mode][
                    "daily_probabilities"
                ]
                path_arrays[f"final_candidate_states_{mode}"][block, truth] = terminal[
                    mode
                ]["final_candidate_states"]
                path_arrays[f"final_candidate_covariances_{mode}"][block, truth] = terminal[
                    mode
                ]["final_candidate_covariances"]
                path_arrays[f"candidate_forecasts_{mode}"][block, truth] = terminal[mode][
                    "candidate_forecasts"
                ]

            combinations = state_weight_factorial_forecasts(
                terminal["full"]["candidate_forecasts"],
                terminal["none"]["candidate_forecasts"],
                terminal["full"]["daily_probabilities"][-1],
                terminal["none"]["daily_probabilities"][-1],
            )
            if set(combinations) != set(combination_names):
                raise ValueError("factorial compositor returned unexpected fields")
            for name in combination_names:
                values = _as_real_float_array(combinations[name], name)
                if values.shape != (lead_count,) or not np.all(np.isfinite(values)):
                    raise ValueError(f"{name} must be a finite lead vector")
                combination_arrays[name][block, truth] = values
            if not np.allclose(
                terminal["full"]["combined_forecast"],
                combinations["full_states_full_weights"],
                rtol=0.0,
                atol=1e-12,
            ):
                raise RuntimeError("full path combined forecast violates the diagonal contract")
            if not np.allclose(
                terminal["none"]["combined_forecast"],
                combinations["none_states_none_weights"],
                rtol=0.0,
                atol=1e-12,
            ):
                raise RuntimeError("none path combined forecast violates the diagonal contract")

    return {
        **path_arrays,
        **combination_arrays,
        "truth_forecasts": truth_forecasts,
        "final_true_candidate_indices": final_true_candidate_indices,
        "final_true_candidate_ids": final_true_candidate_ids,
        "candidate_ids": candidate_ids.copy(),
        "parameter_ids": parameter_ids.copy(),
        "block_ids": block_ids.copy(),
        "forecast_lead_days": np.asarray(lead_days, dtype=np.int64),
        "assimilation_days": assimilation_days,
    }
