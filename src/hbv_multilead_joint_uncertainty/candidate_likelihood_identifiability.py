"""Observation-likelihood identifiability without candidate interaction or weights."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from .methods import MethodCandidate, build_method_bank, build_method_definitions
from .synthetic_truth import (
    advance_reference_state,
    generate_reference_truth,
    project_reference_state,
    reference_routed_discharge,
)
from .three_stage_switching_validation import (
    SUPPORTED_SCENARIOS,
    ThreeStageTruthSchedule,
    _initial_covariance,
    _integer_seeds,
    build_three_stage_truth_schedule,
)


@dataclass(frozen=True)
class CandidateLikelihoodIdentifiabilityResult:
    """Raw candidate likelihood evidence from independent candidate filters."""

    scenario: str
    schedule: ThreeStageTruthSchedule
    block_ids: tuple[str, ...]
    process_noise_seeds: np.ndarray
    observation_noise_seeds: np.ndarray
    forcing_blocks: np.ndarray
    warmup_days: int
    stage_lengths: np.ndarray
    adaptation_days: int
    assimilation_days: int
    candidate_ids: tuple[str, ...]
    candidate_parameter_indices: np.ndarray
    candidate_process_indices: np.ndarray
    truth_candidate_indices: np.ndarray
    parameter_ids: tuple[str, str, str]
    process_ids: tuple[str, str, str]
    initial_parameter_states: np.ndarray
    initial_covariances: np.ndarray
    process_standard_normals: np.ndarray
    observation_standard_normals: np.ndarray
    truth_deterministic_states: np.ndarray
    truth_process_perturbations: np.ndarray
    truth_projection_adjustments: np.ndarray
    truth_states: np.ndarray
    truth_discharge: np.ndarray
    observed_discharge: np.ndarray
    candidate_prior_observations: np.ndarray
    candidate_innovations: np.ndarray
    candidate_innovation_variances: np.ndarray
    candidate_daily_log_likelihoods: np.ndarray
    scored_daily_log_likelihoods: np.ndarray
    cumulative_log_likelihoods: np.ndarray
    true_candidate_daily_ranks: np.ndarray
    true_candidate_cumulative_ranks: np.ndarray
    true_candidate_daily_margins: np.ndarray
    true_candidate_cumulative_margins: np.ndarray
    first_cumulative_rank_one_day: np.ndarray
    first_stable_cumulative_rank_one_day: np.ndarray
    stable_cumulative_identifiable: np.ndarray

    @property
    def candidate_count(self) -> int:
        return len(self.candidate_ids)


@dataclass(frozen=True)
class CandidateLikelihoodScores:
    """Stage-reset likelihood sums and strict true-candidate ranks."""

    cumulative_log_likelihoods: np.ndarray
    true_candidate_daily_ranks: np.ndarray
    true_candidate_cumulative_ranks: np.ndarray
    true_candidate_daily_margins: np.ndarray
    true_candidate_cumulative_margins: np.ndarray
    first_cumulative_rank_one_day: np.ndarray
    first_stable_cumulative_rank_one_day: np.ndarray
    stable_cumulative_identifiable: np.ndarray


def candidates_for_likelihood_diagnostic(
    definitions: Mapping[str, Sequence[MethodCandidate]], scenario: str
) -> tuple[MethodCandidate, ...]:
    """Return only the candidate bank whose factor changes in one scenario."""

    mapping = {
        "parameter_switch": "parameter_only",
        "process_noise_switch": "noise_only",
        "parameter_process_noise_switch": "joint",
    }
    if scenario not in mapping:
        raise ValueError(f"scenario must be one of {SUPPORTED_SCENARIOS}")
    candidates = tuple(definitions[mapping[scenario]])
    expected = 9 if scenario == "parameter_process_noise_switch" else 3
    if len(candidates) != expected:
        raise ValueError(f"scenario candidate bank must contain {expected} candidates")
    return candidates


def _scoring_windows(
    daily_log_likelihoods: np.ndarray,
    stage_start_days: np.ndarray,
    stage_end_days: np.ndarray,
    adaptation_days: int,
) -> np.ndarray:
    windows = []
    for start, end in zip(stage_start_days, stage_end_days):
        windows.append(
            daily_log_likelihoods[
                ..., int(start) + int(adaptation_days) : int(end), :
            ]
        )
    lengths = {window.shape[-2] for window in windows}
    if len(lengths) != 1:
        raise ValueError("all stages must leave the same number of scoring days")
    return np.stack(windows, axis=-3)


def score_candidate_log_likelihoods(
    scored_daily_log_likelihoods,
    truth_candidate_indices,
    stable_final_days: int = 5,
) -> CandidateLikelihoodScores:
    """Accumulate within stages and rank ties against the true candidate."""

    daily = np.asarray(scored_daily_log_likelihoods, dtype=np.float64)
    truth = np.asarray(truth_candidate_indices, dtype=np.int64)
    if daily.ndim != 5 or not np.all(np.isfinite(daily)):
        raise ValueError(
            "scored_daily_log_likelihoods must be finite with shape "
            "(blocks, truths, stages, days, candidates)"
        )
    block_count, truth_count, stage_count, scoring_days, candidate_count = daily.shape
    if block_count == 0 or truth_count == 0 or stage_count == 0 or scoring_days == 0:
        raise ValueError("scored_daily_log_likelihoods dimensions must be nonempty")
    if candidate_count < 2:
        raise ValueError("scored_daily_log_likelihoods must contain competing candidates")
    if truth.shape != (truth_count, stage_count) or np.any(truth < 0) or np.any(
        truth >= candidate_count
    ):
        raise ValueError(
            "truth_candidate_indices must have one valid candidate per truth and stage"
        )
    stable_days = int(stable_final_days)
    if (
        isinstance(stable_final_days, bool)
        or stable_days != stable_final_days
        or stable_days <= 0
        or stable_days > scoring_days
    ):
        raise ValueError("stable_final_days must be within the scoring window")

    cumulative = np.cumsum(daily, axis=-2)
    expanded_truth = np.broadcast_to(
        truth[None, :, :, None], (block_count, truth_count, stage_count, scoring_days)
    )
    true_daily = np.take_along_axis(
        daily, expanded_truth[..., None], axis=-1
    )[..., 0]
    true_cumulative = np.take_along_axis(
        cumulative, expanded_truth[..., None], axis=-1
    )[..., 0]

    daily_ranks = np.sum(daily >= true_daily[..., None], axis=-1).astype(np.int64)
    cumulative_ranks = np.sum(
        cumulative >= true_cumulative[..., None], axis=-1
    ).astype(np.int64)
    candidate_indices = np.arange(candidate_count, dtype=np.int64)
    wrong_mask = candidate_indices != expanded_truth[..., None]
    best_wrong_daily = np.max(np.where(wrong_mask, daily, -np.inf), axis=-1)
    best_wrong_cumulative = np.max(
        np.where(wrong_mask, cumulative, -np.inf), axis=-1
    )
    daily_margins = true_daily - best_wrong_daily
    cumulative_margins = true_cumulative - best_wrong_cumulative

    rank_one = cumulative_ranks == 1
    ever_first = np.any(rank_one, axis=-1)
    first_day = np.where(ever_first, np.argmax(rank_one, axis=-1) + 1, -1).astype(
        np.int64
    )
    stable_from_day = np.flip(
        np.logical_and.accumulate(np.flip(rank_one, axis=-1), axis=-1), axis=-1
    )
    ever_stable = np.any(stable_from_day, axis=-1)
    first_stable_day = np.where(
        ever_stable, np.argmax(stable_from_day, axis=-1) + 1, -1
    ).astype(np.int64)
    latest_qualifying_day = scoring_days - stable_days + 1
    stable = (first_stable_day >= 1) & (
        first_stable_day <= latest_qualifying_day
    )
    stable &= cumulative_margins[..., -1] > 0.0
    return CandidateLikelihoodScores(
        cumulative_log_likelihoods=cumulative,
        true_candidate_daily_ranks=daily_ranks,
        true_candidate_cumulative_ranks=cumulative_ranks,
        true_candidate_daily_margins=daily_margins,
        true_candidate_cumulative_margins=cumulative_margins,
        first_cumulative_rank_one_day=first_day,
        first_stable_cumulative_rank_one_day=first_stable_day,
        stable_cumulative_identifiable=stable,
    )


def _bootstrap_block_mean_interval(
    block_values: np.ndarray, replicates: int, seed: int
) -> tuple[float, float]:
    values = np.asarray(block_values, dtype=np.float64)
    count = int(replicates)
    if values.ndim != 1 or len(values) == 0 or not np.all(np.isfinite(values)):
        raise ValueError("block_values must be one finite nonempty vector")
    if isinstance(replicates, bool) or count != replicates or count <= 0:
        raise ValueError("bootstrap_replicates must be a positive integer")
    rng = np.random.default_rng(int(seed))
    indices = rng.integers(0, len(values), size=(count, len(values)))
    statistics = np.mean(values[indices], axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def evaluate_candidate_likelihood_identifiability(
    result: CandidateLikelihoodIdentifiabilityResult,
    bootstrap_replicates: int,
    bootstrap_seed: int,
    stable_fraction_minimum: float,
    bootstrap_lower_minimum: float,
    median_final_margin_minimum: float,
) -> dict:
    """Summarize stage evidence; only stages after a switch decide the outcome."""

    stable = np.asarray(result.stable_cumulative_identifiable, dtype=bool)
    daily_ranks = np.asarray(result.true_candidate_daily_ranks, dtype=np.int64)
    cumulative_ranks = np.asarray(
        result.true_candidate_cumulative_ranks, dtype=np.int64
    )
    cumulative_margins = np.asarray(
        result.true_candidate_cumulative_margins, dtype=np.float64
    )
    first_stable = np.asarray(
        result.first_stable_cumulative_rank_one_day, dtype=np.int64
    )
    if stable.ndim != 3 or stable.shape[2] != 3:
        raise ValueError("stable_cumulative_identifiable must have three stages")
    expected_daily = (*stable.shape, daily_ranks.shape[-1])
    if (
        daily_ranks.ndim != 4
        or daily_ranks.shape != expected_daily
        or cumulative_ranks.shape != daily_ranks.shape
        or cumulative_margins.shape != daily_ranks.shape
        or first_stable.shape != stable.shape
    ):
        raise ValueError("likelihood score arrays have inconsistent shapes")
    if not np.all(np.isfinite(cumulative_margins)):
        raise ValueError("true candidate cumulative margins must be finite")
    blocks = tuple(str(value) for value in result.block_ids)
    if len(blocks) != stable.shape[0] or len(set(blocks)) != len(blocks):
        raise ValueError("block_ids must identify every bootstrap unit")
    stable_minimum = float(stable_fraction_minimum)
    lower_minimum = float(bootstrap_lower_minimum)
    margin_minimum = float(median_final_margin_minimum)
    if not np.all(
        np.isfinite([stable_minimum, lower_minimum, margin_minimum])
    ):
        raise ValueError("decision thresholds must be finite")

    stage_rows = []
    for stage_index in range(3):
        stable_stage = stable[:, :, stage_index]
        block_fractions = np.mean(stable_stage, axis=1)
        lower, upper = _bootstrap_block_mean_interval(
            block_fractions,
            bootstrap_replicates,
            int(bootstrap_seed) + stage_index,
        )
        stable_fraction = float(np.mean(stable_stage))
        final_margins = cumulative_margins[:, :, stage_index, -1]
        median_final_margin = float(np.median(final_margins))
        successful_days = first_stable[:, :, stage_index]
        successful_days = successful_days[successful_days >= 1]
        median_first_stable_day = (
            float(np.median(successful_days)) if successful_days.size else None
        )
        stage_passed = bool(
            stable_fraction >= stable_minimum
            and lower > lower_minimum
            and median_final_margin > margin_minimum
        )
        stage_rows.append(
            {
                "stage_number": stage_index + 1,
                "is_switching_stage": stage_index > 0,
                "block_count": stable.shape[0],
                "truth_trial_count_per_block": stable.shape[1],
                "scoring_day_count": daily_ranks.shape[-1],
                "daily_true_candidate_strict_rank_one_fraction": float(
                    np.mean(daily_ranks[:, :, stage_index] == 1)
                ),
                "final_cumulative_true_candidate_strict_rank_one_fraction": float(
                    np.mean(cumulative_ranks[:, :, stage_index, -1] == 1)
                ),
                "stable_identifiable_fraction": stable_fraction,
                "stable_fraction_block_bootstrap_lower": lower,
                "stable_fraction_block_bootstrap_upper": upper,
                "median_final_true_vs_best_wrong_cumulative_log_likelihood_margin": (
                    median_final_margin
                ),
                "median_first_stable_cumulative_rank_one_day_among_successes": (
                    median_first_stable_day
                ),
                "stage_passed": stage_passed,
            }
        )
    switching_stage_numbers = [2, 3]
    switching_passed = bool(
        all(stage_rows[index - 1]["stage_passed"] for index in switching_stage_numbers)
    )
    return {
        "scenario": result.scenario,
        "stage_results": stage_rows,
        "switching_stage_numbers": switching_stage_numbers,
        "switching_stages_passed": switching_passed,
        "scientific_status": "passed" if switching_passed else "not_passed",
        "decision_rules": {
            "stable_fraction_minimum": stable_minimum,
            "stable_fraction_block_bootstrap_lower_strict_minimum": lower_minimum,
            "median_final_margin_strict_minimum": margin_minimum,
            "bootstrap_unit": "synthetic_block",
            "bootstrap_replicates": int(bootstrap_replicates),
            "bootstrap_seed": int(bootstrap_seed),
            "stage_one_decides_scientific_status": False,
        },
    }


def run_candidate_likelihood_identifiability(
    forcing_blocks,
    block_ids: Sequence[str],
    parameter_vectors: Mapping[str, Mapping[str, float]],
    process_scales: Mapping[str, float],
    process_covariances: Mapping[str, np.ndarray],
    selected_process_id: str,
    scenario: str,
    process_noise_seeds: Sequence[int],
    observation_noise_seeds: Sequence[int],
    warmup_days: int,
    stage_lengths: Sequence[int],
    adaptation_days: int,
    initial_covariance_fraction: float,
    observation_standard_deviation: float,
) -> CandidateLikelihoodIdentifiabilityResult:
    """Compare independent candidate observation likelihoods on one truth schedule."""

    forcing_values = np.asarray(forcing_blocks, dtype=np.float64)
    if forcing_values.ndim != 3 or forcing_values.shape[2] != 3:
        raise ValueError("forcing_blocks must have shape (blocks, days, 3)")
    block_count, forcing_days, _ = forcing_values.shape
    if block_count == 0 or not np.all(np.isfinite(forcing_values)):
        raise ValueError("forcing_blocks must contain finite values")
    blocks = tuple(str(value) for value in block_ids)
    if (
        len(blocks) != block_count
        or len(set(blocks)) != block_count
        or any(not value for value in blocks)
    ):
        raise ValueError("block_ids must contain one unique nonempty identifier per block")
    process_seeds = _integer_seeds(
        process_noise_seeds, block_count, "process_noise_seeds"
    )
    observation_seeds = _integer_seeds(
        observation_noise_seeds, block_count, "observation_noise_seeds"
    )
    if isinstance(warmup_days, bool) or int(warmup_days) != warmup_days or int(warmup_days) <= 0:
        raise ValueError("warmup_days must be a positive integer")
    warmup = int(warmup_days)
    lengths = np.asarray(tuple(stage_lengths), dtype=np.int64)
    if lengths.shape != (3,) or np.any(lengths <= 0):
        raise ValueError("stage_lengths must contain exactly three positive values")
    adaptation = int(adaptation_days)
    if (
        isinstance(adaptation_days, bool)
        or adaptation != adaptation_days
        or adaptation < 0
        or np.any(lengths <= adaptation)
    ):
        raise ValueError("adaptation_days must leave at least one scoring day per stage")
    assimilation_days = int(np.sum(lengths))
    if forcing_days != warmup + assimilation_days:
        raise ValueError("forcing blocks must exactly cover warmup and three stages")
    covariance_fraction = float(initial_covariance_fraction)
    observation_std = float(observation_standard_deviation)
    if not np.isfinite(covariance_fraction) or covariance_fraction <= 0.0:
        raise ValueError("initial_covariance_fraction must be finite and positive")
    if not np.isfinite(observation_std) or observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be finite and positive")

    definitions = build_method_definitions(
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=selected_process_id,
    )
    schedule = build_three_stage_truth_schedule(
        definitions=definitions,
        scenario=scenario,
        selected_process_id=selected_process_id,
        stage_lengths=tuple(int(value) for value in lengths),
        forecast_days=1,
    )
    candidates = candidates_for_likelihood_diagnostic(definitions, scenario)
    joint_candidates = tuple(definitions["joint"])
    parameter_ids = tuple(
        dict.fromkeys(candidate.parameter_id for candidate in joint_candidates)
    )
    process_ids = tuple(
        dict.fromkeys(candidate.process_id for candidate in joint_candidates)
    )
    parameter_index = {value: index for index, value in enumerate(parameter_ids)}
    process_index = {value: index for index, value in enumerate(process_ids)}
    candidate_parameter_indices = np.asarray(
        [parameter_index[candidate.parameter_id] for candidate in candidates],
        dtype=np.int64,
    )
    candidate_process_indices = np.asarray(
        [process_index[candidate.process_id] for candidate in candidates], dtype=np.int64
    )
    truth_candidate_indices = schedule.primary_candidate_indices[:, :assimilation_days].copy()
    truth_count = truth_candidate_indices.shape[0]
    candidate_count = len(candidates)

    parameter_values = {
        str(key): {name: float(value) for name, value in values.items()}
        for key, values in parameter_vectors.items()
    }
    process_covariance_values = {
        str(key): np.asarray(value, dtype=np.float64)
        for key, value in process_covariances.items()
    }
    initial_parameter_states = np.empty(
        (block_count, len(parameter_ids), 15), dtype=np.float64
    )
    initial_covariances = np.empty((block_count, 15, 15), dtype=np.float64)
    process_normals = np.empty((block_count, assimilation_days, 15), dtype=np.float64)
    observation_normals = np.empty((block_count, assimilation_days), dtype=np.float64)
    truth_shape = (block_count, truth_count, assimilation_days, 15)
    truth_deterministic_states = np.empty(truth_shape, dtype=np.float64)
    truth_process_perturbations = np.empty(truth_shape, dtype=np.float64)
    truth_projection_adjustments = np.empty(truth_shape, dtype=np.float64)
    truth_states = np.empty(truth_shape, dtype=np.float64)
    truth_discharge = np.empty((block_count, truth_count, assimilation_days), dtype=np.float64)
    observed_discharge = np.empty_like(truth_discharge)
    likelihood_shape = (block_count, truth_count, assimilation_days, candidate_count)
    candidate_prior_observations = np.empty(likelihood_shape, dtype=np.float64)
    candidate_innovations = np.empty(likelihood_shape, dtype=np.float64)
    candidate_innovation_variances = np.empty(likelihood_shape, dtype=np.float64)
    candidate_daily_log_likelihoods = np.empty(likelihood_shape, dtype=np.float64)

    for block in range(block_count):
        forcing = forcing_values[block]
        warm_forcing = forcing[:warmup]
        active_forcing = forcing[warmup:]
        initial_states: dict[str, np.ndarray] = {}
        for parameter_id in parameter_ids:
            state = generate_reference_truth(
                warm_forcing, parameter_values[parameter_id]
            ).states[-1]
            initial_states[parameter_id] = state
            initial_parameter_states[block, parameter_index[parameter_id]] = state
        covariance = _initial_covariance(
            initial_states["trained_center"], covariance_fraction
        )
        initial_covariances[block] = covariance
        process_normals[block] = np.random.default_rng(
            int(process_seeds[block])
        ).standard_normal((assimilation_days, 15))
        observation_normals[block] = np.random.default_rng(
            int(observation_seeds[block])
        ).standard_normal(assimilation_days)

        for truth_index in range(truth_count):
            first_joint_index = int(schedule.joint_candidate_indices[truth_index, 0])
            truth_state = initial_states[
                joint_candidates[first_joint_index].parameter_id
            ].copy()
            for day in range(assimilation_days):
                joint_index = int(schedule.joint_candidate_indices[truth_index, day])
                truth_candidate = joint_candidates[joint_index]
                parameters = parameter_values[truth_candidate.parameter_id]
                covariance_value = process_covariance_values[truth_candidate.process_id]
                rain, potential_evaporation, temperature = active_forcing[day]
                deterministic_state = advance_reference_state(
                    truth_state,
                    rain,
                    potential_evaporation,
                    temperature,
                    parameters,
                )
                perturbation = process_normals[block, day] * np.sqrt(
                    np.diag(covariance_value)
                )
                unprojected = deterministic_state + perturbation
                projected = project_reference_state(unprojected, parameters)
                discharge = reference_routed_discharge(projected, parameters["lag_time"])
                truth_deterministic_states[block, truth_index, day] = deterministic_state
                truth_process_perturbations[block, truth_index, day] = perturbation
                truth_projection_adjustments[block, truth_index, day] = projected - unprojected
                truth_states[block, truth_index, day] = projected
                truth_discharge[block, truth_index, day] = discharge
                observed_discharge[block, truth_index, day] = (
                    discharge + observation_std * observation_normals[block, day]
                )
                truth_state = projected

            bank = build_method_bank(
                candidates=candidates,
                initial_states=initial_states,
                initial_covariance=covariance,
                observation_standard_deviation=observation_std,
                factor_transition_stay_probability=1.0,
                interaction_mode="none",
            )
            for day in range(assimilation_days):
                rain, potential_evaporation, temperature = active_forcing[day]
                for transition in bank.transitions:
                    transition.set_forcing(rain, potential_evaporation, temperature)
                for candidate_index, candidate_filter in enumerate(
                    bank.estimator.filters
                ):
                    step = candidate_filter.step(
                        observed_discharge[block, truth_index, day]
                    )
                    candidate_prior_observations[
                        block, truth_index, day, candidate_index
                    ] = float(step.prior_observation[0])
                    candidate_innovations[
                        block, truth_index, day, candidate_index
                    ] = float(step.innovation[0])
                    candidate_innovation_variances[
                        block, truth_index, day, candidate_index
                    ] = float(step.innovation_covariance[0, 0])
                    candidate_daily_log_likelihoods[
                        block, truth_index, day, candidate_index
                    ] = step.log_likelihood

    scored = _scoring_windows(
        candidate_daily_log_likelihoods,
        schedule.stage_start_days,
        schedule.stage_end_days,
        adaptation,
    )
    stage_truth_candidate_indices = np.stack(
        [
            truth_candidate_indices[:, int(start) + adaptation]
            for start in schedule.stage_start_days
        ],
        axis=1,
    )
    scores = score_candidate_log_likelihoods(
        scored,
        stage_truth_candidate_indices,
        stable_final_days=min(5, scored.shape[-2]),
    )
    return CandidateLikelihoodIdentifiabilityResult(
        scenario=scenario,
        schedule=schedule,
        block_ids=blocks,
        process_noise_seeds=process_seeds.copy(),
        observation_noise_seeds=observation_seeds.copy(),
        forcing_blocks=forcing_values.copy(),
        warmup_days=warmup,
        stage_lengths=lengths.copy(),
        adaptation_days=adaptation,
        assimilation_days=assimilation_days,
        candidate_ids=tuple(candidate.candidate_id for candidate in candidates),
        candidate_parameter_indices=candidate_parameter_indices,
        candidate_process_indices=candidate_process_indices,
        truth_candidate_indices=truth_candidate_indices,
        parameter_ids=parameter_ids,
        process_ids=process_ids,
        initial_parameter_states=initial_parameter_states,
        initial_covariances=initial_covariances,
        process_standard_normals=process_normals,
        observation_standard_normals=observation_normals,
        truth_deterministic_states=truth_deterministic_states,
        truth_process_perturbations=truth_process_perturbations,
        truth_projection_adjustments=truth_projection_adjustments,
        truth_states=truth_states,
        truth_discharge=truth_discharge,
        observed_discharge=observed_discharge,
        candidate_prior_observations=candidate_prior_observations,
        candidate_innovations=candidate_innovations,
        candidate_innovation_variances=candidate_innovation_variances,
        candidate_daily_log_likelihoods=candidate_daily_log_likelihoods,
        scored_daily_log_likelihoods=scored,
        cumulative_log_likelihoods=scores.cumulative_log_likelihoods,
        true_candidate_daily_ranks=scores.true_candidate_daily_ranks,
        true_candidate_cumulative_ranks=scores.true_candidate_cumulative_ranks,
        true_candidate_daily_margins=scores.true_candidate_daily_margins,
        true_candidate_cumulative_margins=scores.true_candidate_cumulative_margins,
        first_cumulative_rank_one_day=scores.first_cumulative_rank_one_day,
        first_stable_cumulative_rank_one_day=(
            scores.first_stable_cumulative_rank_one_day
        ),
        stable_cumulative_identifiable=scores.stable_cumulative_identifiable,
    )
