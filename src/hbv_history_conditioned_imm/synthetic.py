"""Independent randomized synthetic data for the history-conditioned experiment."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np
import torch

from hbv_multilead_joint_uncertainty.state_domain_consistent_process_noise_switch import (
    generate_state_domain_consistent_truth,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import generate_reference_truth


@dataclass(frozen=True)
class BlockSeeds:
    block_id: str
    forcing_seed: int
    process_seed: int
    observation_seed: int
    schedule_seed: int

    @property
    def all_seeds(self) -> tuple[int, int, int, int]:
        return (
            self.forcing_seed,
            self.process_seed,
            self.observation_seed,
            self.schedule_seed,
        )


@dataclass(frozen=True)
class SyntheticBatch:
    forcing: torch.Tensor
    observations: torch.Tensor
    truth_states: torch.Tensor
    truth_discharge: torch.Tensor
    true_process_indices: torch.Tensor
    projection_adjustments: torch.Tensor
    initial_states: torch.Tensor
    initial_covariances: torch.Tensor
    switch_days: torch.Tensor
    block_ids: tuple[str, ...]
    block_seeds: tuple[BlockSeeds, ...]
    accepted_process_seeds: tuple[int, ...]
    rejected_process_seeds: tuple[int, ...]
    assimilation_days: int

    @property
    def seed_set(self) -> frozenset[int]:
        requested = {
            seed for block in self.block_seeds for seed in block.all_seeds
        }
        return frozenset(
            requested
            | set(self.accepted_process_seeds)
            | set(self.rejected_process_seeds)
        )


def make_block_seeds(
    *,
    split: str,
    count: int,
    forcing_prefix: int,
    process_prefix: int,
    observation_prefix: int,
    schedule_prefix: int,
    split_offset: int,
) -> tuple[BlockSeeds, ...]:
    """Create auditable, non-overlapping block identifiers and seed tuples."""
    if not split or count <= 0 or split_offset < 0:
        raise ValueError("split, count, and split_offset are invalid")
    prefixes = (
        int(forcing_prefix),
        int(process_prefix),
        int(observation_prefix),
        int(schedule_prefix),
    )
    if len(set(prefixes)) != 4 or any(value <= 0 for value in prefixes):
        raise ValueError("the four positive seed prefixes must be distinct")
    result = []
    for index in range(1, int(count) + 1):
        suffix = int(split_offset) * 100 + index
        result.append(
            BlockSeeds(
                block_id=f"{split}_block_{index:02d}",
                forcing_seed=prefixes[0] * 1000 + suffix,
                process_seed=prefixes[1] * 1000 + suffix,
                observation_seed=prefixes[2] * 1000 + suffix,
                schedule_seed=prefixes[3] * 1000 + suffix,
            )
        )
    return tuple(result)


def _random_schedule(
    *,
    seed: int,
    assimilation_days: int,
    total_days: int,
    minimum_duration: int,
    maximum_duration: int,
) -> tuple[np.ndarray, np.ndarray]:
    if minimum_duration <= 0 or maximum_duration < minimum_duration:
        raise ValueError("duration bounds are invalid")
    if assimilation_days < 3 * minimum_duration or total_days < assimilation_days:
        raise ValueError("sequence is too short for two switches and three regimes")
    generator = np.random.default_rng(int(seed))
    while True:
        first_duration = int(
            generator.integers(minimum_duration, maximum_duration + 1)
        )
        second_duration = int(
            generator.integers(minimum_duration, maximum_duration + 1)
        )
        if assimilation_days - first_duration - second_duration >= minimum_duration:
            break
    first_mode = int(generator.integers(0, 3))
    second_mode = int(generator.choice([value for value in range(3) if value != first_mode]))
    third_mode = int(generator.choice([value for value in range(3) if value != second_mode]))
    switches = np.asarray(
        [first_duration, first_duration + second_duration], dtype=np.int64
    )
    schedule = np.full(total_days, third_mode, dtype=np.int64)
    schedule[: switches[0]] = first_mode
    schedule[switches[0] : switches[1]] = second_mode
    return schedule, switches


def _forcing(seed: int, days: int) -> np.ndarray:
    generator = np.random.default_rng(int(seed))
    rain = 5.0 + generator.gamma(shape=0.8, scale=4.0, size=days)
    potential_evaporation = np.full(days, 2.0, dtype=np.float64)
    temperature = np.full(days, 10.0, dtype=np.float64)
    return np.column_stack((rain, potential_evaporation, temperature))


def generate_synthetic_batch(
    *,
    block_seeds: Sequence[BlockSeeds],
    parameters: Mapping[str, float],
    process_standard_deviations: Sequence[float],
    assimilation_days: int,
    maximum_forecast_lead: int,
    warmup_days: int,
    minimum_duration: int,
    maximum_duration: int,
    observation_standard_deviation: float,
    initial_covariance_fraction: float = 0.001,
    maximum_process_resamples: int = 100,
) -> SyntheticBatch:
    """Generate a batch, rejecting every process draw that needs projection."""
    specifications = tuple(block_seeds)
    deviations = tuple(float(value) for value in process_standard_deviations)
    if not specifications or len({block.block_id for block in specifications}) != len(specifications):
        raise ValueError("block specifications must be nonempty with unique identifiers")
    if len(deviations) != 3 or any(not np.isfinite(value) or value <= 0.0 for value in deviations):
        raise ValueError("three positive finite process standard deviations are required")
    if warmup_days <= 0 or maximum_forecast_lead <= 0 or assimilation_days <= 0:
        raise ValueError("warmup, assimilation, and forecast lengths must be positive")
    if observation_standard_deviation <= 0.0 or initial_covariance_fraction <= 0.0:
        raise ValueError("observation deviation and covariance fraction must be positive")
    if maximum_process_resamples <= 0:
        raise ValueError("maximum_process_resamples must be positive")

    total_days = int(assimilation_days) + int(maximum_forecast_lead)
    identifiers = ("low", "medium", "high")
    standard_deviations = dict(zip(identifiers, deviations))
    forcing_values = []
    observation_values = []
    state_values = []
    discharge_values = []
    process_indices = []
    adjustment_values = []
    initial_states = []
    initial_covariances = []
    switch_values = []
    accepted_seeds = []
    rejected_seeds = []

    for specification in specifications:
        complete_forcing = _forcing(
            specification.forcing_seed, int(warmup_days) + total_days
        )
        warmup_truth = generate_reference_truth(
            complete_forcing[:warmup_days], parameters
        )
        initial_state = warmup_truth.states[-1].copy()
        active_forcing = complete_forcing[warmup_days:]
        schedule_index, switches = _random_schedule(
            seed=specification.schedule_seed,
            assimilation_days=int(assimilation_days),
            total_days=total_days,
            minimum_duration=int(minimum_duration),
            maximum_duration=int(maximum_duration),
        )
        schedule = np.asarray(
            [identifiers[index] for index in schedule_index], dtype=np.str_
        )

        truth = None
        accepted_seed = None
        for attempt in range(int(maximum_process_resamples)):
            candidate_seed = specification.process_seed + attempt * 1_000_000
            process_normals = np.random.default_rng(candidate_seed).standard_normal(
                total_days
            )
            try:
                truth = generate_state_domain_consistent_truth(
                    active_forcing,
                    parameters,
                    initial_state,
                    schedule,
                    standard_deviations,
                    process_normals,
                )
            except ValueError as error:
                if "would require projection" not in str(error):
                    raise
                rejected_seeds.append(candidate_seed)
                continue
            accepted_seed = candidate_seed
            break
        if truth is None or accepted_seed is None:
            raise RuntimeError(
                f"no zero-projection process draw found for {specification.block_id}"
            )

        observation_normals = np.random.default_rng(
            specification.observation_seed
        ).standard_normal(total_days)
        observations = truth["discharge"] + float(
            observation_standard_deviation
        ) * observation_normals
        scales = np.maximum(np.abs(initial_state), 1.0)
        covariance = np.diag(
            np.square(float(initial_covariance_fraction) * scales)
        )

        forcing_values.append(active_forcing)
        observation_values.append(observations)
        state_values.append(truth["states"])
        discharge_values.append(truth["discharge"])
        process_indices.append(schedule_index)
        adjustment_values.append(truth["projection_adjustments"])
        initial_states.append(initial_state)
        initial_covariances.append(covariance)
        switch_values.append(switches)
        accepted_seeds.append(accepted_seed)

    def tensor(values: Sequence[np.ndarray], *, dtype: torch.dtype) -> torch.Tensor:
        return torch.as_tensor(np.stack(values), dtype=dtype).clone()

    return SyntheticBatch(
        forcing=tensor(forcing_values, dtype=torch.float64),
        observations=tensor(observation_values, dtype=torch.float64),
        truth_states=tensor(state_values, dtype=torch.float64),
        truth_discharge=tensor(discharge_values, dtype=torch.float64),
        true_process_indices=tensor(process_indices, dtype=torch.int64),
        projection_adjustments=tensor(adjustment_values, dtype=torch.float64),
        initial_states=tensor(initial_states, dtype=torch.float64),
        initial_covariances=tensor(initial_covariances, dtype=torch.float64),
        switch_days=tensor(switch_values, dtype=torch.int64),
        block_ids=tuple(block.block_id for block in specifications),
        block_seeds=specifications,
        accepted_process_seeds=tuple(accepted_seeds),
        rejected_process_seeds=tuple(rejected_seeds),
        assimilation_days=int(assimilation_days),
    )
