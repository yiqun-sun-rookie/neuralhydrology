"""Historical uncertainty-propagating readouts and ensemble controls.

Historical result keys are retained for reproducibility.  Despite their
``unique`` names, these readouts instantiate one unscented filter and propagate
its covariance and sigma points.  They are not a direct deterministic model
trajectory from one state.  The corrected deterministic contract lives in
``deterministic_unique_state_forecast.py``.  Propagating every candidate state
separately and weighting discharge remains an ensemble forecast control.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES
from hbv_joint_uncertainty.preflight import CandidateBank
from hbv_multilead_joint_uncertainty.forecast import (
    PosteriorForecast,
    forecast_from_posterior,
)
from hbv_multilead_joint_uncertainty.methods import (
    MethodCandidate,
    build_method_bank,
)


HISTORICAL_COVARIANCE_READOUT = (
    "posterior_unique_complete_covariance_weighted_parameters"
)
# Both strings below are archived result keys, not declarations of the
# standard method's final state or of a current primary forecast method.
ENSEMBLE_FORECAST_CONTROL = "current_multiple_states"

READOUT_METHODS = (
    "current_multiple_states",
    HISTORICAL_COVARIANCE_READOUT,
    "posterior_unique_within_covariance_weighted_parameters",
    "posterior_unique_complete_covariance_maximum_parameters",
    "maximum_posterior_candidate",
    "uniform_unique_complete_covariance_uniform_parameters",
)

_TIME_STRATA = (
    ("days_000_006", 0, 6),
    ("days_007_029", 7, 29),
    ("days_030_089", 30, 89),
    ("days_090_179", 90, 179),
)


@dataclass(frozen=True)
class PosteriorMoments:
    """First two moments of a finite state mixture."""

    mean_state: np.ndarray
    within_covariance: np.ndarray
    between_covariance: np.ndarray
    complete_covariance: np.ndarray


@dataclass(frozen=True)
class ForecastReadoutResult:
    """Archived forecast controls derived from one global posterior update.

    ``current_forecast`` retains model-conditioned trajectories only for the
    historical ensemble control.  ``global_posterior_state`` is the standard
    fully interacting method's unique final state estimate at the origin.
    """

    lead_days: np.ndarray
    predictions: dict[str, np.ndarray]
    current_forecast: PosteriorForecast
    maximum_posterior_index: int
    global_posterior_state: np.ndarray
    posterior_within_covariance: np.ndarray
    posterior_between_covariance: np.ndarray
    posterior_complete_covariance: np.ndarray
    uniform_mean_state: np.ndarray
    uniform_within_covariance: np.ndarray
    uniform_between_covariance: np.ndarray
    uniform_complete_covariance: np.ndarray
    posterior_weighted_parameters: dict[str, float]
    uniform_parameters: dict[str, float]
    maximum_parameters: dict[str, float]
    unique_projected_states: dict[str, np.ndarray]
    projection_displacements: dict[str, float]

    @property
    def historical_covariance_prediction(self) -> np.ndarray:
        """Return the archived one-filter covariance-propagating readout."""

        return self.predictions[HISTORICAL_COVARIANCE_READOUT].copy()

    @property
    def ensemble_control_prediction(self) -> np.ndarray:
        """Return the legacy multi-trajectory probability-weighted control."""

        return self.predictions[ENSEMBLE_FORECAST_CONTROL].copy()


def _validated_weights(weights, count: int) -> np.ndarray:
    values = np.asarray(weights, dtype=np.float64)
    if values.shape != (count,):
        raise ValueError(f"weights must have shape ({count},)")
    if not np.all(np.isfinite(values)) or np.any(values < 0.0):
        raise ValueError("weights must be finite and nonnegative")
    if not np.isclose(np.sum(values), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("weights must sum to one within 1e-12")
    return values / np.sum(values)


def _validated_covariance(
    covariance,
    state_count: int,
    label: str,
) -> np.ndarray:
    values = np.asarray(covariance, dtype=np.float64)
    if values.shape != (state_count, state_count):
        raise ValueError(
            f"{label} must have shape ({state_count}, {state_count})"
        )
    if not np.all(np.isfinite(values)):
        raise ValueError(f"{label} must be finite")
    if not np.allclose(values, values.T, rtol=0.0, atol=1e-12):
        raise ValueError(f"{label} must be symmetric")
    symmetric = 0.5 * (values + values.T)
    eigenvalues = np.linalg.eigvalsh(symmetric)
    scale = max(float(np.max(np.abs(eigenvalues))), 1.0)
    tolerance = max(
        1e-12,
        np.finfo(np.float64).eps * state_count * scale * 100.0,
    )
    if float(np.min(eigenvalues)) < -tolerance:
        raise ValueError(f"{label} must be positive semidefinite")
    return symmetric


def posterior_moments(
    candidate_states,
    candidate_covariances,
    weights,
) -> PosteriorMoments:
    """Return within-, between-, and complete covariance for a state mixture."""

    states = np.asarray(candidate_states, dtype=np.float64)
    covariances = np.asarray(candidate_covariances, dtype=np.float64)
    if states.ndim != 2 or states.shape[0] == 0:
        raise ValueError("candidate states must be a nonempty matrix")
    if not np.all(np.isfinite(states)):
        raise ValueError("candidate states must be finite")
    candidate_count, state_count = states.shape
    if covariances.shape != (
        candidate_count,
        state_count,
        state_count,
    ):
        raise ValueError(
            "candidate covariances must match candidate states"
        )
    checked_covariances = np.asarray(
        [
            _validated_covariance(
                covariance,
                state_count,
                f"candidate covariance {index}",
            )
            for index, covariance in enumerate(covariances)
        ]
    )
    probabilities = _validated_weights(weights, candidate_count)
    mean_state = probabilities @ states
    within = np.einsum(
        "i,ijk->jk",
        probabilities,
        checked_covariances,
    )
    deviations = states - mean_state
    between = np.einsum(
        "i,ij,ik->jk",
        probabilities,
        deviations,
        deviations,
    )
    within = 0.5 * (within + within.T)
    between = 0.5 * (between + between.T)
    within = _validated_covariance(
        within, state_count, "within covariance"
    )
    between = _validated_covariance(
        between, state_count, "between covariance"
    )
    complete = _validated_covariance(
        within + between,
        state_count,
        "complete covariance",
    )
    return PosteriorMoments(
        mean_state=mean_state.copy(),
        within_covariance=within.copy(),
        between_covariance=between.copy(),
        complete_covariance=complete.copy(),
    )


def weighted_parameters(
    candidates: Sequence[MethodCandidate],
    weights,
) -> dict[str, float]:
    """Average the thirteen candidate parameters under explicit weights."""

    definitions = tuple(candidates)
    if not definitions:
        raise ValueError("candidates must be nonempty")
    probabilities = _validated_weights(weights, len(definitions))
    for candidate in definitions:
        if set(candidate.parameters) != set(PARAMETER_NAMES):
            raise ValueError(
                "each candidate must define the thirteen HBV parameters"
            )
    matrix = np.asarray(
        [
            [candidate.parameters[name] for name in PARAMETER_NAMES]
            for candidate in definitions
        ],
        dtype=np.float64,
    )
    if not np.all(np.isfinite(matrix)):
        raise ValueError("candidate parameters must be finite")
    values = probabilities @ matrix
    return {
        name: float(value)
        for name, value in zip(PARAMETER_NAMES, values)
    }


def _single_candidate_bank(
    source_candidates: Sequence[MethodCandidate],
    parameters: Mapping[str, float],
    state,
    covariance,
    observation_standard_deviation: float,
    identifier: str,
) -> tuple[CandidateBank, np.ndarray]:
    definitions = tuple(source_candidates)
    if not definitions:
        raise ValueError("source candidates must be nonempty")
    reference = definitions[0]
    for candidate in definitions[1:]:
        if (
            candidate.process_id != reference.process_id
            or candidate.process_scale != reference.process_scale
            or not np.array_equal(
                candidate.process_covariance,
                reference.process_covariance,
            )
        ):
            raise ValueError(
                "unique parameter readout requires one shared process contract"
            )
    unique = MethodCandidate(
        candidate_id=str(identifier),
        parameter_id=str(identifier),
        process_id=reference.process_id,
        process_scale=reference.process_scale,
        parameters={name: float(parameters[name]) for name in PARAMETER_NAMES},
        process_covariance=reference.process_covariance.copy(),
    )
    state_values = np.asarray(state, dtype=np.float64)
    covariance_values = _validated_covariance(
        covariance,
        len(state_values),
        "unique covariance",
    )
    bank = build_method_bank(
        (unique,),
        {unique.parameter_id: state_values},
        covariance_values,
        float(observation_standard_deviation),
        factor_transition_stay_probability=1.0,
        interaction_mode="none",
    )
    projected = bank.estimator.filters[0].state.copy()
    bank.estimator.global_posterior_state = projected
    bank.estimator.global_posterior_covariance = covariance_values
    bank.estimator.filters[0].covariance = covariance_values.copy()
    return bank, projected


def _forecast_unique(
    source_candidates: Sequence[MethodCandidate],
    parameters: Mapping[str, float],
    state: np.ndarray,
    covariance: np.ndarray,
    observation_standard_deviation: float,
    identifier: str,
    future_forcing,
    lead_days,
) -> tuple[np.ndarray, np.ndarray]:
    bank, projected = _single_candidate_bank(
        source_candidates,
        parameters,
        state,
        covariance,
        observation_standard_deviation,
        identifier,
    )
    forecast = forecast_from_posterior(
        bank,
        future_forcing,
        lead_days=lead_days,
        interaction_mode="none",
    )
    return forecast.combined_predictions.copy(), projected


def forecast_readout_variants(
    bank: CandidateBank,
    method_candidates: Sequence[MethodCandidate],
    future_forcing,
    *,
    lead_days: Sequence[int] = tuple(range(1, 8)),
) -> ForecastReadoutResult:
    """Issue frozen historical uncertainty-propagating readouts and controls."""

    candidates = tuple(method_candidates)
    filters = tuple(bank.estimator.filters)
    if len(candidates) != len(filters) or len(filters) == 0:
        raise ValueError(
            "method candidates must match the nonempty posterior bank"
        )
    probabilities = _validated_weights(
        bank.estimator.probabilities,
        len(filters),
    )
    states = np.asarray([candidate.state for candidate in filters])
    covariances = np.asarray(
        [candidate.covariance for candidate in filters]
    )
    posterior = posterior_moments(
        states,
        covariances,
        probabilities,
    )
    if not np.allclose(
        bank.estimator.global_posterior_state,
        posterior.mean_state,
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError(
            "estimator global posterior differs from the probability-weighted "
            "model-conditioned posterior states"
        )
    uniform_weights = np.full(
        len(filters),
        1.0 / len(filters),
        dtype=np.float64,
    )
    uniform = posterior_moments(
        states,
        covariances,
        uniform_weights,
    )
    posterior_parameters = weighted_parameters(candidates, probabilities)
    uniform_parameters = weighted_parameters(candidates, uniform_weights)
    maximum_index = int(np.argmax(probabilities))
    maximum_parameters = candidates[maximum_index].parameters.copy()
    observation_covariance = np.asarray(
        filters[0].observation_covariance,
        dtype=np.float64,
    )
    if observation_covariance.shape != (1, 1):
        raise ValueError(
            "forecast readout comparison requires scalar observation noise"
        )
    observation_standard_deviation = float(
        np.sqrt(observation_covariance[0, 0])
    )

    current = forecast_from_posterior(
        bank,
        future_forcing,
        lead_days=lead_days,
        interaction_mode="full",
    )
    predictions: dict[str, np.ndarray] = {
        ENSEMBLE_FORECAST_CONTROL: current.combined_predictions.copy(),
    }
    projected_states: dict[str, np.ndarray] = {}

    unique_contracts = (
        (
            HISTORICAL_COVARIANCE_READOUT,
            posterior_parameters,
            posterior.mean_state,
            posterior.complete_covariance,
        ),
        (
            "posterior_unique_within_covariance_weighted_parameters",
            posterior_parameters,
            posterior.mean_state,
            posterior.within_covariance,
        ),
        (
            "posterior_unique_complete_covariance_maximum_parameters",
            maximum_parameters,
            posterior.mean_state,
            posterior.complete_covariance,
        ),
        (
            "uniform_unique_complete_covariance_uniform_parameters",
            uniform_parameters,
            uniform.mean_state,
            uniform.complete_covariance,
        ),
    )
    for method, parameters, state, covariance in unique_contracts:
        prediction, projected = _forecast_unique(
            candidates,
            parameters,
            state,
            covariance,
            observation_standard_deviation,
            method,
            future_forcing,
            lead_days,
        )
        predictions[method] = prediction
        projected_states[method] = projected
    predictions["maximum_posterior_candidate"] = (
        current.candidate_predictions[:, maximum_index].copy()
    )
    ordered_predictions = {
        method: predictions[method]
        for method in READOUT_METHODS
    }
    projection_displacements = {
        method: float(
            np.max(
                np.abs(
                    projected
                    - (
                        uniform.mean_state
                        if method.startswith("uniform_")
                        else posterior.mean_state
                    )
                )
            )
        )
        for method, projected in projected_states.items()
    }
    return ForecastReadoutResult(
        lead_days=current.lead_days.copy(),
        predictions=ordered_predictions,
        current_forecast=current,
        maximum_posterior_index=maximum_index,
        global_posterior_state=posterior.mean_state.copy(),
        posterior_within_covariance=posterior.within_covariance.copy(),
        posterior_between_covariance=posterior.between_covariance.copy(),
        posterior_complete_covariance=posterior.complete_covariance.copy(),
        uniform_mean_state=uniform.mean_state.copy(),
        uniform_within_covariance=uniform.within_covariance.copy(),
        uniform_between_covariance=uniform.between_covariance.copy(),
        uniform_complete_covariance=uniform.complete_covariance.copy(),
        posterior_weighted_parameters=posterior_parameters.copy(),
        uniform_parameters=uniform_parameters.copy(),
        maximum_parameters=maximum_parameters.copy(),
        unique_projected_states={
            key: value.copy()
            for key, value in projected_states.items()
        },
        projection_displacements=projection_displacements,
    )


def _masked_rmse(
    squared_error: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    lead_count = squared_error.shape[-1]
    result = np.empty(lead_count, dtype=np.float64)
    for lead in range(lead_count):
        selected = squared_error[:, :, mask[:, lead], lead]
        if selected.size == 0:
            raise ValueError("each lead requires at least one selected origin")
        result[lead] = np.sqrt(np.mean(selected))
    return result


def _block_mse(
    squared_error: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    block_count = squared_error.shape[0]
    lead_count = squared_error.shape[-1]
    result = np.empty((block_count, lead_count), dtype=np.float64)
    for lead in range(lead_count):
        selected = squared_error[:, :, mask[:, lead], lead]
        if selected.shape[2] == 0:
            raise ValueError("each lead requires at least one selected origin")
        result[:, lead] = np.mean(selected, axis=(1, 2))
    return result


def _validate_forecast_arrays(
    forecasts: Mapping[str, np.ndarray],
    truth,
    same_stage_mask,
    days_since_switch,
    bootstrap_indices,
) -> tuple[
    dict[str, np.ndarray],
    np.ndarray,
    np.ndarray,
    np.ndarray,
    np.ndarray,
]:
    if not forecasts:
        raise ValueError("forecasts must be nonempty")
    truth_values = np.asarray(truth, dtype=np.float64)
    if truth_values.ndim != 4 or not np.all(np.isfinite(truth_values)):
        raise ValueError(
            "truth must be finite [blocks, truths, origins, leads]"
        )
    forecast_values = {}
    for method, values in forecasts.items():
        array = np.asarray(values, dtype=np.float64)
        if array.shape != truth_values.shape or not np.all(np.isfinite(array)):
            raise ValueError(
                f"forecast {method} must be finite and match truth"
            )
        forecast_values[str(method)] = array
    mask = np.asarray(same_stage_mask, dtype=bool)
    expected_mask = truth_values.shape[2:]
    if mask.shape != expected_mask:
        raise ValueError(
            f"same-stage mask must have shape {expected_mask}"
        )
    offsets = np.asarray(days_since_switch)
    if (
        offsets.shape != (truth_values.shape[2],)
        or not np.issubdtype(offsets.dtype, np.integer)
    ):
        raise ValueError(
            "days since switch must be one integer per origin"
        )
    bootstrap = np.asarray(bootstrap_indices)
    if (
        bootstrap.ndim != 2
        or bootstrap.shape[1] != truth_values.shape[0]
        or not np.issubdtype(bootstrap.dtype, np.integer)
        or np.any(bootstrap < 0)
        or np.any(bootstrap >= truth_values.shape[0])
    ):
        raise ValueError(
            "bootstrap indices must select matched blocks"
        )
    return (
        forecast_values,
        truth_values,
        mask,
        offsets.astype(np.int64, copy=False),
        bootstrap.astype(np.int64, copy=False),
    )


def summarize_readout_forecasts(
    forecasts: Mapping[str, np.ndarray],
    truth,
    same_stage_mask,
    *,
    days_since_switch,
    bootstrap_indices,
    minimum_meaningful_rmse_fraction: float,
    replacement_baseline: str,
    general_repair_baseline: str,
) -> dict[str, object]:
    """Summarize forecast readouts with matched-block paired inference."""

    (
        forecast_values,
        truth_values,
        mask,
        offsets,
        bootstrap,
    ) = _validate_forecast_arrays(
        forecasts,
        truth,
        same_stage_mask,
        days_since_switch,
        bootstrap_indices,
    )
    fraction = float(minimum_meaningful_rmse_fraction)
    if not np.isfinite(fraction) or not 0.0 < fraction < 1.0:
        raise ValueError(
            "minimum meaningful RMSE fraction must be between zero and one"
        )
    baselines = (
        str(replacement_baseline),
        str(general_repair_baseline),
    )
    if any(baseline not in forecast_values for baseline in baselines):
        raise ValueError("comparison baseline is missing from forecasts")
    squared_errors = {
        method: np.square(values - truth_values)
        for method, values in forecast_values.items()
    }
    rmse = {
        method: _masked_rmse(values, mask)
        for method, values in squared_errors.items()
    }
    block_mse = {
        method: _block_mse(values, mask)
        for method, values in squared_errors.items()
    }
    alternatives = tuple(
        method for method in forecast_values if method not in set(baselines)
    )
    comparisons: dict[str, dict[str, dict[str, object]]] = {}
    decisions: dict[str, dict[str, bool]] = {}
    for method in alternatives:
        comparisons[method] = {}
        for baseline in baselines:
            block_difference = block_mse[method] - block_mse[baseline]
            bootstrap_difference = np.mean(
                block_difference[bootstrap],
                axis=1,
            )
            baseline_mse = np.mean(block_mse[baseline], axis=0)
            boundary = baseline_mse * (
                (1.0 - fraction) ** 2 - 1.0
            )
            relative = rmse[method] / rmse[baseline] - 1.0
            point_passes = relative <= -fraction
            ci_low = np.percentile(
                bootstrap_difference, 2.5, axis=0
            )
            ci_high = np.percentile(
                bootstrap_difference, 97.5, axis=0
            )
            interval_passes = ci_high < boundary
            key = f"minus_{baseline}"
            comparisons[method][key] = {
                "block_mean_mse_difference": block_difference,
                "mean_mse_difference": np.mean(
                    block_difference, axis=0
                ),
                "ci_low": ci_low,
                "ci_high": ci_high,
                "baseline_mse": baseline_mse,
                "meaningful_improvement_boundary": boundary,
                "relative_rmse_fraction": relative,
                "point_estimate_passes": point_passes,
                "interval_passes": interval_passes,
                "all_leads_pass": bool(
                    np.all(point_passes) and np.all(interval_passes)
                ),
            }
        decisions[method] = {
            "replace_current_multiple_states": bool(
                comparisons[method][
                    f"minus_{baselines[0]}"
                ]["all_leads_pass"]
            ),
            "repair_general_degradation": bool(
                comparisons[method][
                    f"minus_{baselines[1]}"
                ]["all_leads_pass"]
            ),
        }
    time_strata = {}
    for name, minimum, maximum in _TIME_STRATA:
        stratum_mask = mask & (
            (offsets >= minimum) & (offsets <= maximum)
        )[:, None]
        if np.any(np.sum(stratum_mask, axis=0) == 0):
            continue
        time_strata[name] = {
            "minimum_offset": minimum,
            "maximum_offset": maximum,
            "sample_count_per_block_truth": np.sum(
                stratum_mask, axis=0
            ),
            "rmse": {
                method: _masked_rmse(values, stratum_mask)
                for method, values in squared_errors.items()
            },
        }
    return {
        "methods": tuple(forecast_values),
        "same_stage_sample_count_per_block_truth": np.sum(mask, axis=0),
        "squared_errors": squared_errors,
        "rmse": rmse,
        "block_mse": block_mse,
        "comparisons": comparisons,
        "decisions": decisions,
        "time_strata": time_strata,
    }
