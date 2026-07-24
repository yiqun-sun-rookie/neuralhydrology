"""Forecast-phase weight drift comparison (ID23 G3 follow-up, 2026-07-24).

Design freeze: ``docs/plans/2026-07-24-g3-forecast-weight-drift-design.md``.

In the frozen pipeline the model-probability vector is propagated through the
transition matrix on every forecast day, so over a seven-day horizon roughly
``1 - stay**7`` of the probability mass leaks to candidates the filter has
already identified as wrong. That propagation is Bayes-consistent with the
switching prior used during assimilation, but in this experiment the assumed
switching rate (2 percent per day) is about 3.6 times the true one (one switch
per 180 days). Phase 2 could only bound the cost of that mismatch; this module
measures it.

The measurement holds the *combination* weights at the final assimilation
posterior while leaving assimilation completely untouched:

    frozen_forecast[lead] = w_posterior . candidate_predictions[lead, :]

For the no-interaction method this is an exact ablation of the drift: without
state mixing each candidate propagates on its own, so ``candidate_predictions``
does not depend on the weights at all (anchored by test against independent
single-candidate runs). For the full-interaction method the candidate paths do
depend on the weights through state mixing, so freezing only the combination
weights is a partial ablation and is reported as such.
"""

from __future__ import annotations

from typing import Mapping, Sequence

import numpy as np

from .forecast import forecast_from_posterior
from .interaction_value_comparison import _block_bootstrap_ci, oracle_arm
from .methods import MethodCandidate, build_method_bank

_METHODS = ("none", "full")
_VARIANTS = ("drifting", "frozen")


def assimilate_family_forecast_paths(
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
) -> dict:
    """Assimilate then forecast, keeping the per-candidate forecast paths.

    Identical to the phase-2 ``assimilate_family_arm`` except that the candidate
    forecast paths and the per-forecast-day weights are returned alongside the
    combined forecast, so the combination can be redone with frozen weights.
    """
    candidates = tuple(candidates)
    active_forcing = np.asarray(active_forcing, dtype=np.float64)
    leads = np.asarray(tuple(int(value) for value in leads), dtype=np.int64)
    assimilation_days = int(assimilation_days)
    bank = build_method_bank(
        candidates=candidates,
        initial_states=initial_states,
        initial_covariance=initial_covariance,
        observation_standard_deviation=float(observation_standard_deviation),
        factor_transition_stay_probability=float(factor_transition_stay_probability),
        interaction_mode=interaction_mode,
    )
    probabilities = np.empty((assimilation_days, len(candidates)), dtype=np.float64)
    for day in range(assimilation_days):
        rain, potential_evaporation, temperature = active_forcing[day]
        for transition in bank.transitions:
            transition.set_forcing(rain, potential_evaporation, temperature)
        bank.estimator.step(observations[day])
        probabilities[day] = bank.estimator.probabilities
    final_posterior = np.asarray(bank.estimator.probabilities, dtype=np.float64).copy()
    future = active_forcing[assimilation_days : assimilation_days + int(leads[-1])]
    forecast = forecast_from_posterior(
        bank,
        future,
        lead_days=tuple(int(value) for value in leads),
        interaction_mode=interaction_mode,
    )
    return {
        "assimilation_probabilities": probabilities,
        "final_posterior_weights": final_posterior,
        "forecast_weights": np.asarray(forecast.probabilities, dtype=np.float64),
        "candidate_predictions": np.asarray(forecast.candidate_predictions, dtype=np.float64),
        "drifting_forecast": forecast.combined_predictions,
    }


def frozen_weight_forecast(candidate_predictions, weights) -> np.ndarray:
    """Combine per-candidate forecasts with weights held fixed across all leads."""
    predictions = np.asarray(candidate_predictions, dtype=np.float64)
    weight_vector = np.asarray(weights, dtype=np.float64)
    if predictions.ndim != 2 or not np.all(np.isfinite(predictions)):
        raise ValueError("candidate_predictions must be a finite (leads, candidates) array")
    if weight_vector.ndim != 1 or weight_vector.shape[0] != predictions.shape[1]:
        raise ValueError("weights must be one per candidate")
    if not np.all(np.isfinite(weight_vector)) or np.any(weight_vector < 0.0):
        raise ValueError("weights must be finite and non-negative")
    if abs(float(weight_vector.sum()) - 1.0) > 1e-12:
        raise ValueError("weights must sum to one within 1e-12")
    return predictions @ weight_vector


# --------------------------------------------------------------------------- #
# Driver: both methods, both variants, on the SAME truths
# --------------------------------------------------------------------------- #


def compare_forecast_weight_drift(
    result,
    definitions: Mapping[str, Sequence[MethodCandidate]],
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
) -> dict:
    """Run drifting and frozen forecast combinations for both methods.

    ``result`` is the reproduced ``ThreeStageSwitchingValidationResult`` whose truths,
    observations, forcing and initial states are reused bit-for-bit. The oracle is
    recomputed with the phase-2 routine purely as a reference point for the reported
    gap; it is unaffected by the weight treatment (single candidate, weight always 1).
    """
    primary = result.schedule.primary_method_name
    candidates = tuple(definitions[primary])
    candidate_count = len(candidates)
    primary_index = list(result.method_names).index(primary)
    block_ids = tuple(result.block_ids)
    block_count = len(block_ids)
    truth_count = int(result.method_assimilation_probabilities.shape[1])
    assimilation_days = int(result.assimilation_days)
    leads = np.asarray(result.forecast_lead_days, dtype=np.int64)
    lead_count = len(leads)
    obs_std = float(observation_standard_deviation)
    stay = float(factor_transition_stay_probability)
    stage_boundaries = [
        (int(start), int(end))
        for start, end in zip(
            result.schedule.stage_start_days, result.schedule.stage_end_days
        )
    ]
    labels = np.asarray(result.schedule.primary_candidate_indices)[:, :assimilation_days]

    forecasts = {
        (method, variant): np.empty((block_count, truth_count, lead_count), dtype=np.float64)
        for method in _METHODS
        for variant in _VARIANTS
    }
    forecast_weights = {
        method: np.empty(
            (block_count, truth_count, lead_count, candidate_count), dtype=np.float64
        )
        for method in _METHODS
    }
    final_posterior_weights = {
        method: np.empty((block_count, truth_count, candidate_count), dtype=np.float64)
        for method in _METHODS
    }
    oracle_forecasts = np.empty((block_count, truth_count, lead_count), dtype=np.float64)
    truth_forecasts = np.asarray(result.truth_forecast_discharge, dtype=np.float64)
    full_matches_runner = True

    for block in range(block_count):
        initial_states = {
            pid: result.initial_parameter_states[block, index]
            for index, pid in enumerate(result.parameter_ids)
        }
        active_forcing = result.forcing_blocks[block][int(result.warmup_days) :]
        covariance = result.initial_covariances[block]
        for truth in range(truth_count):
            observations = result.observed_discharge[block, truth]
            for method in _METHODS:
                paths = assimilate_family_forecast_paths(
                    candidates, initial_states, covariance, active_forcing, observations,
                    assimilation_days, leads, obs_std, stay, method,
                )
                forecasts[(method, "drifting")][block, truth] = paths["drifting_forecast"]
                forecasts[(method, "frozen")][block, truth] = frozen_weight_forecast(
                    paths["candidate_predictions"], paths["final_posterior_weights"]
                )
                forecast_weights[method][block, truth] = paths["forecast_weights"]
                final_posterior_weights[method][block, truth] = paths["final_posterior_weights"]
                if method == "full" and not np.array_equal(
                    paths["drifting_forecast"],
                    result.method_predictions[block, truth, primary_index],
                ):
                    full_matches_runner = False
            stage_true = [int(labels[truth, start]) for start, _ in stage_boundaries]
            oracle_forecasts[block, truth] = oracle_arm(
                candidates, stage_true, stage_boundaries, initial_states, covariance,
                active_forcing, observations, leads, obs_std, stay,
            )

    squared_errors = {
        key: (value - truth_forecasts) ** 2 for key, value in forecasts.items()
    }
    return {
        "methods": _METHODS,
        "variants": _VARIANTS,
        "leads": leads,
        "block_ids": block_ids,
        "truth_count": truth_count,
        "assimilation_days": assimilation_days,
        "stage_boundaries": stage_boundaries,
        "primary_method_name": primary,
        "candidate_count": candidate_count,
        "forecasts": forecasts,
        "squared_errors": squared_errors,
        "oracle_forecasts": oracle_forecasts,
        "oracle_squared_errors": (oracle_forecasts - truth_forecasts) ** 2,
        "truth_forecasts": truth_forecasts,
        "forecast_weights": forecast_weights,
        "final_posterior_weights": final_posterior_weights,
        "true_candidate_labels": labels,
        "full_drifting_matches_frozen_runner": bool(full_matches_runner),
    }


# --------------------------------------------------------------------------- #
# Summarizer
# --------------------------------------------------------------------------- #


def _verdicts(low: np.ndarray, high: np.ndarray) -> list:
    verdicts = []
    for lead_low, lead_high in zip(np.atleast_1d(low), np.atleast_1d(high)):
        if float(lead_high) < 0.0:
            verdicts.append("drift_harmful")
        elif float(lead_low) > 0.0:
            verdicts.append("drift_helpful")
        else:
            verdicts.append("not_significant")
    return verdicts


def _true_candidate_weight_medians(driver_output: dict, method: str) -> dict:
    labels = np.asarray(driver_output["true_candidate_labels"], dtype=np.int64)
    final_day = labels.shape[1] - 1
    posterior = np.asarray(driver_output["final_posterior_weights"][method], dtype=np.float64)
    forecast = np.asarray(driver_output["forecast_weights"][method], dtype=np.float64)
    truth_count = posterior.shape[1]
    lead_count = forecast.shape[2]
    final_values = []
    lead_values = [[] for _ in range(lead_count)]
    for truth in range(truth_count):
        candidate = int(labels[truth, final_day])
        final_values.append(posterior[:, truth, candidate])
        for lead in range(lead_count):
            lead_values[lead].append(forecast[:, truth, lead, candidate])
    return {
        "final_assimilation_day": float(np.median(np.concatenate(final_values))),
        "per_lead": [float(np.median(np.concatenate(values))) for values in lead_values],
    }


def summarize_forecast_weight_drift(
    driver_output: dict,
    bootstrap_replicates: int,
    bootstrap_seed: int,
) -> dict:
    """Paired block-bootstrap verdicts on (frozen minus drifting) squared error."""
    methods = tuple(driver_output["methods"])
    squared_errors = driver_output["squared_errors"]
    rmse = {
        key: np.sqrt(np.asarray(value, dtype=np.float64).mean(axis=(0, 1)))
        for key, value in squared_errors.items()
    }
    oracle_rmse = np.sqrt(
        np.asarray(driver_output["oracle_squared_errors"], dtype=np.float64).mean(axis=(0, 1))
    )

    paired = {}
    verdict = {}
    for method in methods:
        difference = (
            np.asarray(squared_errors[(method, "frozen")], dtype=np.float64)
            - np.asarray(squared_errors[(method, "drifting")], dtype=np.float64)
        ).mean(axis=1)
        mean, low, high = _block_bootstrap_ci(difference, bootstrap_replicates, bootstrap_seed)
        paired[method] = {"mean": mean, "ci_low": low, "ci_high": high}
        verdict[method] = _verdicts(low, high)

    return {
        "rmse": rmse,
        "oracle_rmse": oracle_rmse,
        "paired_frozen_minus_drifting": paired,
        "verdict": verdict,
        "frozen_minus_oracle_rmse": {
            method: rmse[(method, "frozen")] - oracle_rmse for method in methods
        },
        "drifting_minus_oracle_rmse": {
            method: rmse[(method, "drifting")] - oracle_rmse for method in methods
        },
        "true_candidate_weight_medians": {
            method: _true_candidate_weight_medians(driver_output, method)
            for method in methods
        },
    }
