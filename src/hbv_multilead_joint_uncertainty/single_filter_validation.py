"""Closed-truth validation of one modified unscented state filter."""

from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import advance_state, routed_discharge
from hbv_joint_uncertainty.preflight import ForcingTransition, RoutedDischargeObservation, project_hbv_state
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter


@dataclass(frozen=True)
class SingleFilterStateValidationResult:
    start_days: np.ndarray
    forcing_realization_ids: np.ndarray
    perturbation_signs: np.ndarray
    process_covariance: np.ndarray
    truth_states: np.ndarray
    open_loop_states: np.ndarray
    no_observation_filter_states: np.ndarray
    filtered_states: np.ndarray
    truth_one_day_discharge: np.ndarray
    open_loop_one_day_predictions: np.ndarray
    no_observation_filter_one_day_predictions: np.ndarray
    filtered_one_day_predictions: np.ndarray
    open_loop_state_normalized_root_mean_square_error: np.ndarray
    no_observation_filter_state_normalized_root_mean_square_error: np.ndarray
    filtered_state_normalized_root_mean_square_error: np.ndarray
    open_loop_one_day_root_mean_square_error: np.ndarray
    no_observation_filter_one_day_root_mean_square_error: np.ndarray
    filtered_one_day_root_mean_square_error: np.ndarray


def _root_mean_square(values: np.ndarray, axis=None) -> np.ndarray:
    return np.sqrt(np.mean(np.square(values), axis=axis))


def run_single_filter_state_validation(
    forcing,
    truth_states,
    truth_discharge,
    parameters: Mapping[str, float],
    start_days: Sequence[int],
    duration_days: int,
    perturbation_scales: Sequence[float],
    perturbation_seed: int,
    observation_standard_deviation: float,
) -> SingleFilterStateValidationResult:
    """Compare one state filter with an uncorrected trajectory under known truth."""
    forcing_values = np.asarray(forcing, dtype=np.float64)
    state_values = np.asarray(truth_states, dtype=np.float64)
    discharge_values = np.asarray(truth_discharge, dtype=np.float64)
    if forcing_values.ndim != 2 or forcing_values.shape[1] != 3:
        raise ValueError("forcing must have shape (days, 3)")
    if state_values.shape != (len(forcing_values), 15):
        raise ValueError("truth_states must have shape (days, 15)")
    if discharge_values.shape != (len(forcing_values),):
        raise ValueError("truth_discharge must have shape (days,)")
    if not np.all(np.isfinite(forcing_values)) or not np.all(np.isfinite(state_values)):
        raise ValueError("forcing and truth_states must be finite")
    if not np.all(np.isfinite(discharge_values)):
        raise ValueError("truth_discharge must be finite")

    starts = np.asarray(tuple(start_days), dtype=np.int64)
    if starts.ndim != 1 or len(starts) == 0 or np.any(starts <= 0) or len(set(starts.tolist())) != len(starts):
        raise ValueError("start_days must contain unique positive integers")
    duration = int(duration_days)
    if isinstance(duration_days, bool) or duration != duration_days or duration <= 0:
        raise ValueError("duration_days must be a positive integer")
    if int(np.max(starts)) + duration >= len(forcing_values):
        raise ValueError("each trial must leave one target day after its final assimilation day")
    scales = np.asarray(tuple(perturbation_scales), dtype=np.float64)
    if scales.shape != (5,) or not np.all(np.isfinite(scales)) or np.any(scales <= 0.0):
        raise ValueError("perturbation_scales must contain five finite positive values")
    observation_std = float(observation_standard_deviation)
    if not np.isfinite(observation_std) or observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be finite and positive")
    parameter_values = {name: float(value) for name, value in parameters.items()}

    trial_count = len(starts)
    shape = (trial_count, duration, 15)
    saved_truth_states = np.empty(shape, dtype=np.float64)
    open_loop_states = np.empty(shape, dtype=np.float64)
    no_observation_filter_states = np.empty(shape, dtype=np.float64)
    filtered_states = np.empty(shape, dtype=np.float64)
    truth_one_day_discharge = np.empty((trial_count, duration), dtype=np.float64)
    open_loop_predictions = np.empty((trial_count, duration), dtype=np.float64)
    no_observation_filter_predictions = np.empty((trial_count, duration), dtype=np.float64)
    filtered_predictions = np.empty((trial_count, duration), dtype=np.float64)
    rng = np.random.default_rng(int(perturbation_seed))
    signs = rng.choice(np.asarray([-1.0, 1.0]), size=(trial_count, 5))

    initial_covariance = np.zeros((15, 15), dtype=np.float64)
    initial_covariance[:5, :5] = np.diag(np.square(scales))
    process_covariance = np.zeros((15, 15), dtype=np.float64)
    observation_covariance = np.asarray([[observation_std**2]], dtype=np.float64)
    for trial, start in enumerate(starts):
        initial_state = state_values[start - 1].copy()
        initial_state[:5] += signs[trial] * scales
        initial_state = project_hbv_state(initial_state, parameter_values)
        open_state = initial_state.copy()
        transition = ForcingTransition(parameter_values)
        observation = RoutedDischargeObservation(parameter_values)
        projector = lambda values, p=parameter_values: project_hbv_state(values, p)
        estimator = ModifiedUnscentedFilter(
            state=initial_state,
            covariance=initial_covariance.copy(),
            transition=transition,
            observation=observation,
            process_covariance=process_covariance.copy(),
            observation_covariance=observation_covariance.copy(),
            state_projector=projector,
            alpha=0.6874,
            beta=2.0,
            kappa=-2.0,
        )
        no_observation_filter = copy.deepcopy(estimator)
        for offset, day in enumerate(range(int(start), int(start) + duration)):
            rain, potential_evaporation, temperature = forcing_values[day]
            open_state = project_hbv_state(
                advance_state(
                    open_state,
                    rain,
                    potential_evaporation,
                    temperature,
                    parameter_values,
                ),
                parameter_values,
            )
            transition.set_forcing(rain, potential_evaporation, temperature)
            posterior = estimator.step(discharge_values[day])
            no_observation_filter.transition.set_forcing(
                rain, potential_evaporation, temperature
            )
            no_observation_state, _ = no_observation_filter.predict_without_observation()
            saved_truth_states[trial, offset] = state_values[day]
            open_loop_states[trial, offset] = open_state
            no_observation_filter_states[trial, offset] = no_observation_state
            filtered_states[trial, offset] = posterior.posterior_state

            next_rain, next_evaporation, next_temperature = forcing_values[day + 1]
            open_future = project_hbv_state(
                advance_state(
                    open_state,
                    next_rain,
                    next_evaporation,
                    next_temperature,
                    parameter_values,
                ),
                parameter_values,
            )
            open_loop_predictions[trial, offset] = routed_discharge(
                open_future, parameter_values["lag_time"]
            )
            no_observation_forecast = copy.deepcopy(no_observation_filter)
            no_observation_forecast.transition.set_forcing(
                next_rain, next_evaporation, next_temperature
            )
            no_observation_forecast_state, _ = no_observation_forecast.predict()
            no_observation_filter_predictions[trial, offset] = (
                no_observation_forecast.observation(no_observation_forecast_state)[0]
            )
            forecast_filter = copy.deepcopy(estimator)
            forecast_filter.transition.set_forcing(next_rain, next_evaporation, next_temperature)
            forecast_state, _ = forecast_filter.predict()
            filtered_predictions[trial, offset] = forecast_filter.observation(forecast_state)[0]
            truth_one_day_discharge[trial, offset] = discharge_values[day + 1]

    state_scale = scales[None, None, :]
    open_state_error = (open_loop_states[:, :, :5] - saved_truth_states[:, :, :5]) / state_scale
    filtered_state_error = (filtered_states[:, :, :5] - saved_truth_states[:, :, :5]) / state_scale
    no_observation_state_error = (
        no_observation_filter_states[:, :, :5] - saved_truth_states[:, :, :5]
    ) / state_scale
    open_state_metric = _root_mean_square(open_state_error, axis=(1, 2))
    no_observation_state_metric = _root_mean_square(no_observation_state_error, axis=(1, 2))
    filtered_state_metric = _root_mean_square(filtered_state_error, axis=(1, 2))
    open_flow_metric = _root_mean_square(open_loop_predictions - truth_one_day_discharge, axis=1)
    no_observation_flow_metric = _root_mean_square(
        no_observation_filter_predictions - truth_one_day_discharge, axis=1
    )
    filtered_flow_metric = _root_mean_square(filtered_predictions - truth_one_day_discharge, axis=1)
    return SingleFilterStateValidationResult(
        start_days=starts.copy(),
        forcing_realization_ids=np.arange(trial_count, dtype=np.int64),
        perturbation_signs=signs,
        process_covariance=process_covariance.copy(),
        truth_states=saved_truth_states,
        open_loop_states=open_loop_states,
        no_observation_filter_states=no_observation_filter_states,
        filtered_states=filtered_states,
        truth_one_day_discharge=truth_one_day_discharge,
        open_loop_one_day_predictions=open_loop_predictions,
        no_observation_filter_one_day_predictions=no_observation_filter_predictions,
        filtered_one_day_predictions=filtered_predictions,
        open_loop_state_normalized_root_mean_square_error=open_state_metric,
        no_observation_filter_state_normalized_root_mean_square_error=(
            no_observation_state_metric
        ),
        filtered_state_normalized_root_mean_square_error=filtered_state_metric,
        open_loop_one_day_root_mean_square_error=open_flow_metric,
        no_observation_filter_one_day_root_mean_square_error=no_observation_flow_metric,
        filtered_one_day_root_mean_square_error=filtered_flow_metric,
    )


def run_independent_single_filter_state_validation(
    forcing_realizations,
    truth_state_realizations,
    truth_discharge_realizations,
    forcing_realization_ids: Sequence[int],
    parameters: Mapping[str, float],
    start_day: int,
    duration_days: int,
    perturbation_scales: Sequence[float],
    perturbation_seed: int,
    observation_standard_deviation: float,
) -> SingleFilterStateValidationResult:
    """Use one independently generated forcing sequence as each statistical trial."""
    forcing_values = np.asarray(forcing_realizations, dtype=np.float64)
    state_values = np.asarray(truth_state_realizations, dtype=np.float64)
    discharge_values = np.asarray(truth_discharge_realizations, dtype=np.float64)
    identifiers = np.asarray(tuple(forcing_realization_ids), dtype=np.int64)
    if forcing_values.ndim != 3 or forcing_values.shape[2] != 3:
        raise ValueError("forcing_realizations must have shape (trials, days, 3)")
    trial_count, day_count, _ = forcing_values.shape
    if state_values.shape != (trial_count, day_count, 15):
        raise ValueError("truth_state_realizations must have shape (trials, days, 15)")
    if discharge_values.shape != (trial_count, day_count):
        raise ValueError("truth_discharge_realizations must have shape (trials, days)")
    if identifiers.shape != (trial_count,) or len(set(identifiers.tolist())) != trial_count:
        raise ValueError("forcing_realization_ids must contain one unique value per trial")
    if trial_count < 2:
        raise ValueError("at least two independent forcing realizations are required")

    results = []
    for trial in range(trial_count):
        results.append(
            run_single_filter_state_validation(
                forcing=forcing_values[trial],
                truth_states=state_values[trial],
                truth_discharge=discharge_values[trial],
                parameters=parameters,
                start_days=(start_day,),
                duration_days=duration_days,
                perturbation_scales=perturbation_scales,
                perturbation_seed=int(perturbation_seed) + trial,
                observation_standard_deviation=observation_standard_deviation,
            )
        )

    def concatenate(name: str) -> np.ndarray:
        return np.concatenate([getattr(result, name) for result in results], axis=0)

    return SingleFilterStateValidationResult(
        start_days=concatenate("start_days"),
        forcing_realization_ids=identifiers.copy(),
        perturbation_signs=concatenate("perturbation_signs"),
        process_covariance=results[0].process_covariance.copy(),
        truth_states=concatenate("truth_states"),
        open_loop_states=concatenate("open_loop_states"),
        no_observation_filter_states=concatenate("no_observation_filter_states"),
        filtered_states=concatenate("filtered_states"),
        truth_one_day_discharge=concatenate("truth_one_day_discharge"),
        open_loop_one_day_predictions=concatenate("open_loop_one_day_predictions"),
        no_observation_filter_one_day_predictions=concatenate(
            "no_observation_filter_one_day_predictions"
        ),
        filtered_one_day_predictions=concatenate("filtered_one_day_predictions"),
        open_loop_state_normalized_root_mean_square_error=concatenate(
            "open_loop_state_normalized_root_mean_square_error"
        ),
        filtered_state_normalized_root_mean_square_error=concatenate(
            "filtered_state_normalized_root_mean_square_error"
        ),
        no_observation_filter_state_normalized_root_mean_square_error=concatenate(
            "no_observation_filter_state_normalized_root_mean_square_error"
        ),
        open_loop_one_day_root_mean_square_error=concatenate(
            "open_loop_one_day_root_mean_square_error"
        ),
        no_observation_filter_one_day_root_mean_square_error=concatenate(
            "no_observation_filter_one_day_root_mean_square_error"
        ),
        filtered_one_day_root_mean_square_error=concatenate(
            "filtered_one_day_root_mean_square_error"
        ),
    )
