"""Filter-free synthetic truth with scheduled HBV-lite parameter regimes."""

from __future__ import annotations

from dataclasses import dataclass
from itertools import combinations
from typing import Mapping, Sequence

import numpy as np
import torch

from hbv_multilead_joint_uncertainty.synthetic_truth import (
    PARAMETER_NAMES,
    advance_reference_state,
    generate_reference_truth,
    project_reference_state,
    reference_routed_discharge,
)

from .hbv import HBV15Model, forecast_global_state
from .synthetic import BlockSeeds, _forcing, _random_schedule


PARAMETER_IDS = (
    "slow_recession",
    "calibrated_recession",
    "fast_recession",
)


@dataclass(frozen=True)
class ParameterSwitchBatch:
    """One continuous truth per block plus all reproducibility metadata."""

    forcing: torch.Tensor
    observations: torch.Tensor
    truth_states: torch.Tensor
    truth_discharge: torch.Tensor
    true_parameter_indices: torch.Tensor
    projection_adjustments: torch.Tensor
    process_perturbations: torch.Tensor
    initial_states: torch.Tensor
    initial_covariances: torch.Tensor
    switch_days: torch.Tensor
    block_ids: tuple[str, ...]
    block_seeds: tuple[BlockSeeds, ...]
    accepted_process_seeds: tuple[int, ...]
    rejected_process_seeds: tuple[int, ...]
    parameter_ids: tuple[str, str, str]
    assimilation_days: int

    @property
    def true_process_indices(self) -> torch.Tensor:
        """Compatibility name for the generic three-mode probability audit."""

        return self.true_parameter_indices


def _validated_parameters(parameters: Mapping[str, float]) -> dict[str, float]:
    if set(parameters) != set(PARAMETER_NAMES):
        raise ValueError("parameters must contain exactly thirteen HBV-lite values")
    result = {name: float(parameters[name]) for name in PARAMETER_NAMES}
    if not np.all(np.isfinite(tuple(result.values()))):
        raise ValueError("parameters must be finite")
    return result


def build_parameter_candidates(
    base_parameters: Mapping[str, float],
    recession_coefficients: Sequence[float],
) -> dict[str, dict[str, float]]:
    """Create three candidates whose only difference is upper-zone recession."""

    base = _validated_parameters(base_parameters)
    coefficients = tuple(float(value) for value in recession_coefficients)
    if (
        len(coefficients) != 3
        or len(set(coefficients)) != 3
        or not np.all(np.isfinite(coefficients))
        or any(value <= 0.0 or value >= 1.0 for value in coefficients)
        or not coefficients[0] < coefficients[1] < coefficients[2]
    ):
        raise ValueError(
            "three unique increasing recession coefficients between zero and one are required"
        )
    return {
        identifier: {**base, "parK1": coefficient}
        for identifier, coefficient in zip(PARAMETER_IDS, coefficients)
    }


def _generate_one_truth(
    *,
    forcing: np.ndarray,
    initial_state: np.ndarray,
    schedule_indices: np.ndarray,
    parameter_ids: tuple[str, str, str],
    parameter_candidates: Mapping[str, Mapping[str, float]],
    process_normals: np.ndarray,
    process_standard_deviation: float,
    process_state_index: int,
    require_zero_projection: bool,
) -> dict[str, np.ndarray]:
    day_count = len(forcing)
    state = np.asarray(initial_state, dtype=np.float64).copy()
    states = np.empty((day_count, 15), dtype=np.float64)
    discharge = np.empty(day_count, dtype=np.float64)
    perturbations = np.zeros((day_count, 15), dtype=np.float64)
    adjustments = np.zeros((day_count, 15), dtype=np.float64)

    for day, (rain, potential_evaporation, temperature) in enumerate(forcing):
        identifier = parameter_ids[int(schedule_indices[day])]
        parameters = parameter_candidates[identifier]
        projected_previous = project_reference_state(state, parameters)
        if np.any(projected_previous != state):
            raise ValueError(
                "parameter-switch truth would require pre-transition projection"
            )
        deterministic = advance_reference_state(
            state,
            float(rain),
            float(potential_evaporation),
            float(temperature),
            parameters,
        )
        perturbation = np.zeros(15, dtype=np.float64)
        perturbation[int(process_state_index)] = (
            float(process_standard_deviation) * float(process_normals[day])
        )
        unprojected = deterministic + perturbation
        projected = project_reference_state(unprojected, parameters)
        adjustment = projected - unprojected
        if require_zero_projection and np.any(adjustment != 0.0):
            raise ValueError(
                "parameter-switch truth would require post-noise projection"
            )
        state = projected
        states[day] = state
        perturbations[day] = perturbation
        adjustments[day] = adjustment
        discharge[day] = reference_routed_discharge(
            state, float(parameters["lag_time"])
        )
    return {
        "states": states,
        "discharge": discharge,
        "process_perturbations": perturbations,
        "projection_adjustments": adjustments,
    }


def generate_parameter_switch_batch(
    *,
    block_seeds: Sequence[BlockSeeds],
    parameter_candidates: Mapping[str, Mapping[str, float]],
    assimilation_days: int,
    maximum_forecast_lead: int,
    warmup_days: int,
    minimum_duration: int,
    maximum_duration: int,
    process_standard_deviation: float,
    observation_standard_deviation: float,
    process_state_index: int = 4,
    require_zero_projection: bool = True,
    initial_covariance_fraction: float = 0.001,
    maximum_process_resamples: int = 100,
) -> ParameterSwitchBatch:
    """Generate parameter-switch blocks without invoking any filter."""

    specifications = tuple(block_seeds)
    identifiers = tuple(str(value) for value in parameter_candidates)
    if identifiers != PARAMETER_IDS:
        raise ValueError(f"parameter candidates must use ordered identifiers {PARAMETER_IDS}")
    candidates = {
        identifier: _validated_parameters(parameter_candidates[identifier])
        for identifier in identifiers
    }
    if not specifications or len({block.block_id for block in specifications}) != len(
        specifications
    ):
        raise ValueError("block specifications must be nonempty and unique")
    if (
        assimilation_days <= 0
        or maximum_forecast_lead <= 0
        or warmup_days <= 0
        or process_standard_deviation <= 0.0
        or observation_standard_deviation <= 0.0
        or initial_covariance_fraction <= 0.0
        or maximum_process_resamples <= 0
    ):
        raise ValueError("generation lengths, deviations, and covariance must be positive")
    if int(process_state_index) not in (3, 4):
        raise ValueError("process state index must identify SUZ 3 or SLZ 4")

    total_days = int(assimilation_days) + int(maximum_forecast_lead)
    forcing_values: list[np.ndarray] = []
    observation_values: list[np.ndarray] = []
    state_values: list[np.ndarray] = []
    discharge_values: list[np.ndarray] = []
    parameter_indices: list[np.ndarray] = []
    adjustment_values: list[np.ndarray] = []
    perturbation_values: list[np.ndarray] = []
    initial_states: list[np.ndarray] = []
    initial_covariances: list[np.ndarray] = []
    switch_values: list[np.ndarray] = []
    accepted_seeds: list[int] = []
    rejected_seeds: list[int] = []

    for specification in specifications:
        complete_forcing = _forcing(
            specification.forcing_seed, int(warmup_days) + total_days
        )
        schedule, switches = _random_schedule(
            seed=specification.schedule_seed,
            assimilation_days=int(assimilation_days),
            total_days=total_days,
            minimum_duration=int(minimum_duration),
            maximum_duration=int(maximum_duration),
        )
        first_parameters = candidates[identifiers[int(schedule[0])]]
        warmup_truth = generate_reference_truth(
            complete_forcing[:warmup_days], first_parameters
        )
        initial_state = warmup_truth.states[-1].copy()
        active_forcing = complete_forcing[warmup_days:]

        truth = None
        accepted_seed = None
        for attempt in range(int(maximum_process_resamples)):
            candidate_seed = specification.process_seed + attempt * 1_000_000
            process_normals = np.random.default_rng(candidate_seed).standard_normal(
                total_days
            )
            try:
                truth = _generate_one_truth(
                    forcing=active_forcing,
                    initial_state=initial_state,
                    schedule_indices=schedule,
                    parameter_ids=identifiers,
                    parameter_candidates=candidates,
                    process_normals=process_normals,
                    process_standard_deviation=float(process_standard_deviation),
                    process_state_index=int(process_state_index),
                    require_zero_projection=bool(require_zero_projection),
                )
            except ValueError as error:
                if "projection" not in str(error):
                    raise
                rejected_seeds.append(candidate_seed)
                continue
            accepted_seed = candidate_seed
            break
        if truth is None or accepted_seed is None:
            raise RuntimeError(
                f"no zero-projection parameter truth found for {specification.block_id}"
            )

        observation_normals = np.random.default_rng(
            specification.observation_seed
        ).standard_normal(total_days)
        observations = truth["discharge"] + (
            float(observation_standard_deviation) * observation_normals
        )
        scales = np.maximum(np.abs(initial_state), 1.0)
        initial_covariance = np.diag(
            np.square(float(initial_covariance_fraction) * scales)
        )

        forcing_values.append(active_forcing)
        observation_values.append(observations)
        state_values.append(truth["states"])
        discharge_values.append(truth["discharge"])
        parameter_indices.append(schedule)
        adjustment_values.append(truth["projection_adjustments"])
        perturbation_values.append(truth["process_perturbations"])
        initial_states.append(initial_state)
        initial_covariances.append(initial_covariance)
        switch_values.append(switches)
        accepted_seeds.append(accepted_seed)

    def tensor(values: Sequence[np.ndarray], *, dtype: torch.dtype) -> torch.Tensor:
        return torch.as_tensor(np.stack(values), dtype=dtype).clone()

    return ParameterSwitchBatch(
        forcing=tensor(forcing_values, dtype=torch.float64),
        observations=tensor(observation_values, dtype=torch.float64),
        truth_states=tensor(state_values, dtype=torch.float64),
        truth_discharge=tensor(discharge_values, dtype=torch.float64),
        true_parameter_indices=tensor(parameter_indices, dtype=torch.int64),
        projection_adjustments=tensor(adjustment_values, dtype=torch.float64),
        process_perturbations=tensor(perturbation_values, dtype=torch.float64),
        initial_states=tensor(initial_states, dtype=torch.float64),
        initial_covariances=tensor(initial_covariances, dtype=torch.float64),
        switch_days=tensor(switch_values, dtype=torch.int64),
        block_ids=tuple(block.block_id for block in specifications),
        block_seeds=specifications,
        accepted_process_seeds=tuple(accepted_seeds),
        rejected_process_seeds=tuple(rejected_seeds),
        parameter_ids=identifiers,
        assimilation_days=int(assimilation_days),
    )


def audit_parameter_signal(
    batch: ParameterSwitchBatch,
    candidate_parameters: Mapping[str, Mapping[str, float]],
    observation_standard_deviation: float,
    leads: Sequence[int],
) -> dict[str, object]:
    """Measure filter-free deterministic separation from matched truth origins."""

    requested = tuple(int(value) for value in leads)
    if (
        not requested
        or min(requested) <= 0
        or len(set(requested)) != len(requested)
        or observation_standard_deviation <= 0.0
    ):
        raise ValueError("leads and observation deviation are invalid")
    if tuple(candidate_parameters) != batch.parameter_ids:
        raise ValueError("candidate order differs from the truth batch")
    maximum_lead = max(requested)
    origins: list[tuple[int, int]] = []
    for block in range(len(batch.block_ids)):
        for day in range(batch.assimilation_days):
            stop = day + maximum_lead
            if stop >= batch.forcing.shape[1]:
                continue
            mode_window = batch.true_parameter_indices[block, day : stop + 1]
            if torch.all(mode_window == mode_window[0]):
                origins.append((block, day))
    if not origins:
        raise ValueError("no within-regime forecast origins are available")

    states = torch.stack([batch.truth_states[block, day] for block, day in origins])
    future_forcing = torch.stack(
        [
            batch.forcing[block, day + 1 : day + 1 + maximum_lead]
            for block, day in origins
        ]
    )
    forecasts: dict[str, dict[int, torch.Tensor]] = {}
    for identifier in batch.parameter_ids:
        forecasts[identifier] = forecast_global_state(
            states,
            future_forcing,
            HBV15Model(candidate_parameters[identifier]),
            requested,
        )

    pairwise: dict[str, dict[str, float]] = {}
    all_values: list[float] = []
    for first, second in combinations(batch.parameter_ids, 2):
        values: dict[str, float] = {}
        for lead in requested:
            difference = forecasts[first][lead] - forecasts[second][lead]
            rmse = float(torch.sqrt(torch.mean(difference.square())))
            values[str(lead)] = rmse
            all_values.append(rmse)
        pairwise[f"{first}__vs__{second}"] = values
    minimum = min(all_values)
    return {
        "uses_filter": False,
        "evaluated_origin_count": len(origins),
        "forecast_leads_days": list(requested),
        "pairwise_rmse_by_lead": pairwise,
        "minimum_pairwise_rmse": minimum,
        "observation_standard_deviation": float(observation_standard_deviation),
        "minimum_pairwise_rmse_to_observation_sd_ratio": minimum
        / float(observation_standard_deviation),
    }
