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


# --------------------------------------------------------------------------- #
# Driver: run all four arms on the SAME truths from a frozen switching result
# --------------------------------------------------------------------------- #

_ARMS = ("full", "none", "static", "oracle")


def compare_interaction_arms(
    result,
    definitions: Mapping[str, Sequence[MethodCandidate]],
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
) -> dict:
    """Run full/none/static/oracle on the primary family of a switching result.

    ``result`` is a ``ThreeStageSwitchingValidationResult`` (the full IMM run whose
    truths, observations, forcing and initial states are reused bit-for-bit). The
    ``full`` arm reuses the result's stored per-family outputs (already proven
    bit-identical to ``assimilate_family_arm``); none/static/oracle are computed on
    the same reconstructed inputs. Returns forecasts, squared errors against the
    noise-free forecast target, and per-arm identification probabilities.
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
        arm: np.empty((block_count, truth_count, lead_count), dtype=np.float64)
        for arm in _ARMS
    }
    probabilities = {
        arm: np.empty(
            (block_count, truth_count, assimilation_days, candidate_count),
            dtype=np.float64,
        )
        for arm in ("full", "none")
    }
    truth_forecasts = np.asarray(result.truth_forecast_discharge, dtype=np.float64)

    for block in range(block_count):
        initial_states = {
            pid: result.initial_parameter_states[block, index]
            for index, pid in enumerate(result.parameter_ids)
        }
        active_forcing = result.forcing_blocks[block][int(result.warmup_days) :]
        covariance = result.initial_covariances[block]
        for truth in range(truth_count):
            observations = result.observed_discharge[block, truth]
            forecasts["full"][block, truth] = result.method_predictions[
                block, truth, primary_index
            ]
            probabilities["full"][block, truth] = result.method_assimilation_probabilities[
                block, truth, primary_index, :, :candidate_count
            ]
            probs_none, forecast_none = assimilate_family_arm(
                candidates, initial_states, covariance, active_forcing, observations,
                assimilation_days, leads, obs_std, stay, "none",
            )
            forecasts["none"][block, truth] = forecast_none
            probabilities["none"][block, truth] = probs_none
            _, forecast_static = static_mixing_arm(
                candidates, initial_states, covariance, active_forcing, observations,
                assimilation_days, leads, obs_std, stay,
            )
            forecasts["static"][block, truth] = forecast_static
            stage_true = [int(labels[truth, start]) for start, _ in stage_boundaries]
            forecasts["oracle"][block, truth] = oracle_arm(
                candidates, stage_true, stage_boundaries, initial_states, covariance,
                active_forcing, observations, leads, obs_std, stay,
            )

    squared_errors = {
        arm: (forecasts[arm] - truth_forecasts) ** 2 for arm in _ARMS
    }
    return {
        "arms": _ARMS,
        "leads": leads,
        "block_ids": block_ids,
        "truth_count": truth_count,
        "assimilation_days": assimilation_days,
        "stage_boundaries": stage_boundaries,
        "primary_method_name": primary,
        "candidate_count": candidate_count,
        "forecasts": forecasts,
        "truth_forecasts": truth_forecasts,
        "squared_errors": squared_errors,
        "probabilities": probabilities,
        "true_candidate_labels": labels,
    }


# --------------------------------------------------------------------------- #
# Summarizer: RMSE, paired block-bootstrap, identification, H1/H2/H3
# --------------------------------------------------------------------------- #


def paired_block_difference(driver_output: dict, arm_a: str, arm_b: str) -> np.ndarray:
    """Per-block mean-over-truths squared-error difference (arm_a - arm_b), shape [B, L]."""
    difference = driver_output["squared_errors"][arm_a] - driver_output["squared_errors"][arm_b]
    return difference.mean(axis=1)


def _block_bootstrap_ci(per_block: np.ndarray, replicates: int, seed: int):
    """Paired block bootstrap: resample blocks (rows), keep all leads together."""
    per_block = np.asarray(per_block, dtype=np.float64)
    block_count = per_block.shape[0]
    rng = np.random.default_rng(int(seed))
    indices = rng.integers(0, block_count, size=(int(replicates), block_count))
    statistics = per_block[indices].mean(axis=1)
    low = np.quantile(statistics, 0.025, axis=0)
    high = np.quantile(statistics, 0.975, axis=0)
    return per_block.mean(axis=0), low, high


def _stage_median_true_probability(
    probabilities: np.ndarray, labels: np.ndarray, stage_boundaries, adaptation_days: int
):
    adaptation = int(adaptation_days)
    truth_count = probabilities.shape[1]
    medians = []
    for start, end in stage_boundaries:
        evaluated_start = int(start) + adaptation
        evaluated_end = int(end)
        collected = []
        for truth in range(truth_count):
            for day in range(evaluated_start, evaluated_end):
                candidate = int(labels[truth, day])
                collected.append(probabilities[:, truth, day, candidate])
        medians.append(float(np.median(np.concatenate(collected))))
    return medians


def summarize_interaction_value(
    driver_output: dict,
    bootstrap_replicates: int,
    bootstrap_seed: int,
    adaptation_days: int,
) -> dict:
    """RMSE, paired block-bootstrap CIs, identification medians and H1/H2/H3 verdicts.

    H1 (interaction adds identification) uses the PRIMARY identification metric,
    posterior probability mass (median true-candidate probability) per the gate
    criterion lesson. H2 (full <= none <= static forecast RMSE) uses paired block
    bootstrap. H3 measures the gap to oracle.
    """
    arms = driver_output["arms"]
    squared_errors = driver_output["squared_errors"]
    rmse = {arm: np.sqrt(squared_errors[arm].mean(axis=(0, 1))) for arm in arms}

    full_minus_none = paired_block_difference(driver_output, "full", "none")
    none_minus_static = paired_block_difference(driver_output, "none", "static")
    fn_mean, fn_low, fn_high = _block_bootstrap_ci(
        full_minus_none, bootstrap_replicates, bootstrap_seed
    )
    ns_mean, ns_low, ns_high = _block_bootstrap_ci(
        none_minus_static, bootstrap_replicates, bootstrap_seed
    )

    oracle_ratio = {arm: rmse[arm] / rmse["oracle"] for arm in arms}

    full_medians = _stage_median_true_probability(
        driver_output["probabilities"]["full"],
        driver_output["true_candidate_labels"],
        driver_output["stage_boundaries"],
        adaptation_days,
    )
    none_medians = _stage_median_true_probability(
        driver_output["probabilities"]["none"],
        driver_output["true_candidate_labels"],
        driver_output["stage_boundaries"],
        adaptation_days,
    )
    h1 = bool(all(f >= n for f, n in zip(full_medians, none_medians)))
    h2 = bool(np.all(fn_high < 0.0) and np.all(ns_high < 0.0))
    h3 = bool(
        np.all(
            np.abs(rmse["full"] - rmse["oracle"]) < np.abs(rmse["static"] - rmse["oracle"])
        )
    )

    return {
        "rmse": rmse,
        "paired_full_minus_none": {"mean": fn_mean, "ci_low": fn_low, "ci_high": fn_high},
        "paired_none_minus_static": {"mean": ns_mean, "ci_low": ns_low, "ci_high": ns_high},
        "oracle_ratio": oracle_ratio,
        "identification": {
            "full_stage_median_true_probability": full_medians,
            "none_stage_median_true_probability": none_medians,
            "h1_full_ge_none_all_stages": h1,
        },
        "h2_full_le_none_le_static": h2,
        "h3_full_closer_to_oracle_than_static": h3,
    }
