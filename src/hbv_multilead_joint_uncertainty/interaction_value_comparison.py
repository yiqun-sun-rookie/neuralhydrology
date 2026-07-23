"""Phase-2 interaction-value comparison arms (ID23 G3 phase 2).

Compares four mixing/interaction strategies on ONE candidate family and the SAME
truths: full IMM, no-interaction likelihood (``none``), static mixing (frozen uniform
weights, no likelihood update), and oracle (single known-true candidate, parameters
switched at stage boundaries with state carried). See design freeze
``docs/plans/2026-07-23-g3-phase2-interaction-value-comparison-design.md``.

Correctness is anchored on the frozen three-stage runner: ``assimilate_family_arm``
with ``interaction_mode="full"`` reproduces the runner's per-family assimilation and
forecast bit-for-bit; ``static_mixing_arm`` reuses the frozen single-candidate path
directly and averages with fixed uniform weights; ``oracle_arm`` reuses single-
candidate banks (mode ``full``, so a single stage equals the frozen path) and carries
the posterior state across parameter switches.
"""

from __future__ import annotations

from typing import Mapping, Sequence

import numpy as np

from .forecast import forecast_from_posterior
from .methods import MethodCandidate, build_method_bank
from .three_stage_switching_validation import _assimilate_record_then_forecast


def assimilate_family_arm(
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
) -> tuple[np.ndarray, np.ndarray]:
    """Assimilate a candidate family under ``interaction_mode`` then forecast.

    Returns ``(daily_probabilities[days, n], combined_forecast[n_leads])``. With
    ``interaction_mode="full"`` this is bit-identical to the frozen runner's
    ``_assimilate_record_then_forecast`` for the same family.
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
    future = active_forcing[assimilation_days : assimilation_days + int(leads[-1])]
    forecast = forecast_from_posterior(
        bank,
        future,
        lead_days=tuple(int(value) for value in leads),
        interaction_mode=interaction_mode,
    )
    return probabilities, forecast.combined_predictions


def static_mixing_arm(
    candidates: Sequence[MethodCandidate],
    initial_states: Mapping[str, np.ndarray],
    initial_covariance: np.ndarray,
    active_forcing: np.ndarray,
    observations: np.ndarray,
    assimilation_days: int,
    leads: Sequence[int],
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
) -> tuple[np.ndarray, np.ndarray]:
    """Static mixing: independent single-candidate filters, frozen uniform weights.

    Each candidate is assimilated independently (frozen single-candidate path) and the
    combined forecast is the uniform (1/n) average of the candidate forecasts. Weights
    never update, so the reported per-day probabilities are uniform.
    """
    candidates = tuple(candidates)
    assimilation_days = int(assimilation_days)
    candidate_count = len(candidates)
    per_candidate = []
    for candidate in candidates:
        _, _, _, forecast = _assimilate_record_then_forecast(
            candidates=(candidate,),
            initial_states=initial_states,
            covariance=initial_covariance,
            active_forcing=active_forcing,
            observations=observations,
            assimilation_days=assimilation_days,
            leads=np.asarray(tuple(int(value) for value in leads), dtype=np.int64),
            observation_standard_deviation=float(observation_standard_deviation),
            factor_transition_stay_probability=float(factor_transition_stay_probability),
        )
        per_candidate.append(forecast.combined_predictions)
    combined_forecast = np.mean(per_candidate, axis=0)
    frozen_probabilities = np.full(
        (assimilation_days, candidate_count), 1.0 / candidate_count, dtype=np.float64
    )
    return frozen_probabilities, combined_forecast


def oracle_arm(
    candidates: Sequence[MethodCandidate],
    true_candidate_index_per_stage: Sequence[int],
    stage_boundaries: Sequence[tuple[int, int]],
    initial_states: Mapping[str, np.ndarray],
    initial_covariance: np.ndarray,
    active_forcing: np.ndarray,
    observations: np.ndarray,
    leads: Sequence[int],
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
) -> np.ndarray:
    """Oracle: the known-true candidate at every stage, state carried across switches.

    A single-candidate filter assimilates each stage with that stage's true candidate
    parameters; at a stage boundary the posterior state and covariance are carried into
    a filter rebuilt with the next stage's true parameters (parameter switch). The
    forecast is issued from the final posterior. A single stage reduces exactly to the
    frozen single-candidate assimilation.
    """
    candidates = tuple(candidates)
    active_forcing = np.asarray(active_forcing, dtype=np.float64)
    leads = np.asarray(tuple(int(value) for value in leads), dtype=np.int64)
    boundaries = [(int(start), int(end)) for start, end in stage_boundaries]
    stage_indices = [int(index) for index in true_candidate_index_per_stage]
    if len(stage_indices) != len(boundaries) or not boundaries:
        raise ValueError("one true candidate index per stage boundary is required")
    assimilation_days = boundaries[-1][1]

    carried_state = None
    carried_covariance = None
    bank = None
    for (start, end), candidate_index in zip(boundaries, stage_indices):
        candidate = candidates[candidate_index]
        if carried_state is None:
            stage_initial_states = initial_states
            stage_covariance = initial_covariance
        else:
            stage_initial_states = {candidate.parameter_id: carried_state}
            stage_covariance = carried_covariance
        bank = build_method_bank(
            candidates=(candidate,),
            initial_states=stage_initial_states,
            initial_covariance=stage_covariance,
            observation_standard_deviation=float(observation_standard_deviation),
            factor_transition_stay_probability=float(factor_transition_stay_probability),
            interaction_mode="full",
        )
        for day in range(start, end):
            rain, potential_evaporation, temperature = active_forcing[day]
            for transition in bank.transitions:
                transition.set_forcing(rain, potential_evaporation, temperature)
            bank.estimator.step(observations[day])
        carried_state = bank.estimator.state.copy()
        carried_covariance = bank.estimator.covariance.copy()

    future = active_forcing[assimilation_days : assimilation_days + int(leads[-1])]
    forecast = forecast_from_posterior(
        bank,
        future,
        lead_days=tuple(int(value) for value in leads),
        interaction_mode="full",
    )
    return forecast.combined_predictions
