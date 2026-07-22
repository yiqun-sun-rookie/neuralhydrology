"""Calibration-only selection of parameter and effective noise contracts."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from itertools import combinations

import numpy as np
from scipy.stats import qmc

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, V1_PARAMETER_BOUNDS
from hbv_joint_uncertainty.preflight import build_process_covariance


def _validated_center(center: Mapping[str, float]) -> dict[str, float]:
    if set(center) != set(PARAMETER_NAMES):
        raise ValueError("center must contain exactly the thirteen HBV-lite parameters")
    result = {name: float(center[name]) for name in PARAMETER_NAMES}
    if not np.all(np.isfinite(list(result.values()))):
        raise ValueError("center parameters must be finite")
    for name, value in result.items():
        lower, upper = V1_PARAMETER_BOUNDS[name]
        if value < lower or value > upper:
            raise ValueError(f"center parameter {name} is outside the frozen bounds")
    return result


def generate_local_parameter_pool(
    center: Mapping[str, float],
    count: int = 256,
    fraction: float = 0.1,
    seed: int = 1,
) -> list[dict[str, float]]:
    """Generate a deterministic Sobol pool inside the former ten-percent stress envelope."""
    values = _validated_center(center)
    if isinstance(count, bool) or count <= 0 or count & (count - 1):
        raise ValueError("count must be a positive power of two")
    local_fraction = float(fraction)
    if not np.isfinite(local_fraction) or local_fraction <= 0.0 or local_fraction >= 1.0:
        raise ValueError("fraction must be finite and between zero and one")
    lower = []
    upper = []
    for name in PARAMETER_NAMES:
        bound_lower, bound_upper = V1_PARAMETER_BOUNDS[name]
        lower.append(values[name] - local_fraction * (values[name] - bound_lower))
        upper.append(values[name] + local_fraction * (bound_upper - values[name]))
    sampler = qmc.Sobol(d=len(PARAMETER_NAMES), scramble=True, seed=int(seed))
    unit = sampler.random_base2(m=int(np.log2(count)))
    samples = qmc.scale(unit, np.asarray(lower), np.asarray(upper))
    return [
        {name: float(sample[index]) for index, name in enumerate(PARAMETER_NAMES)}
        for sample in samples
    ]


def generate_multiscale_parameter_pool(
    center: Mapping[str, float],
    fractions: Sequence[float] = (0.1, 0.05, 0.025, 0.0125),
    count_per_scale: int = 256,
    seed: int = 1,
) -> tuple[list[dict[str, float]], list[dict]]:
    """Concatenate auditable Sobol pools at fixed nested envelope scales."""
    local_fractions = tuple(float(value) for value in fractions)
    if (
        not local_fractions
        or not np.all(np.isfinite(local_fractions))
        or any(value <= 0.0 or value >= 1.0 for value in local_fractions)
        or any(
            local_fractions[index] <= local_fractions[index + 1]
            for index in range(len(local_fractions) - 1)
        )
    ):
        raise ValueError("fractions must be a strictly descending finite sequence between zero and one")
    if (
        isinstance(count_per_scale, bool)
        or count_per_scale <= 0
        or count_per_scale & (count_per_scale - 1)
    ):
        raise ValueError("count_per_scale must be a positive power of two")
    pool = []
    audit = []
    for scale_index, fraction in enumerate(local_fractions):
        scale_pool = generate_local_parameter_pool(
            center,
            count=int(count_per_scale),
            fraction=fraction,
            seed=int(seed),
        )
        start = len(pool)
        pool.extend(scale_pool)
        audit.extend(
            {
                "candidate_index": start + scale_candidate_index,
                "scale_index": scale_index,
                "local_fraction": fraction,
                "scale_candidate_index": scale_candidate_index,
            }
            for scale_candidate_index in range(len(scale_pool))
        )
    return pool, audit


def select_equifinal_parameters(
    center: Mapping[str, float],
    candidates: Sequence[Mapping[str, float]],
    center_nse: float,
    center_mean_discharge: float,
    candidate_nse,
    candidate_mean_discharge,
    maximum_nse_drop: float = 0.03,
) -> dict[str, dict]:
    """Select the globally most separated calibration-equivalent parameter pair."""
    center_values = _validated_center(center)
    candidate_values = [_validated_center(row) for row in candidates]
    scores = np.asarray(candidate_nse, dtype=np.float64)
    means = np.asarray(candidate_mean_discharge, dtype=np.float64)
    if scores.shape != (len(candidate_values),) or means.shape != scores.shape:
        raise ValueError("candidate metrics must contain one value per candidate")
    if not np.all(np.isfinite(scores)) or not np.all(np.isfinite(means)):
        raise ValueError("candidate metrics must be finite")
    center_score = float(center_nse)
    center_mean = float(center_mean_discharge)
    allowed_drop = float(maximum_nse_drop)
    if (
        not np.isfinite(center_score)
        or not np.isfinite(center_mean)
        or not np.isfinite(allowed_drop)
        or allowed_drop < 0.0
    ):
        raise ValueError("center metrics and maximum_nse_drop must be finite")
    eligible = np.flatnonzero(scores >= center_score - allowed_drop)
    unique = []
    seen = set()
    for index in eligible:
        key = tuple(candidate_values[int(index)][name] for name in PARAMETER_NAMES)
        if key not in seen and key != tuple(center_values[name] for name in PARAMETER_NAMES):
            seen.add(key)
            unique.append(int(index))
    if len(unique) < 2:
        raise ValueError("parameter pool must contain two distinct eligible candidates")
    spans = np.asarray(
        [V1_PARAMETER_BOUNDS[name][1] - V1_PARAMETER_BOUNDS[name][0] for name in PARAMETER_NAMES],
        dtype=np.float64,
    )
    center_array = np.asarray([center_values[name] for name in PARAMETER_NAMES], dtype=np.float64)
    normalized = {
        index: (
            np.asarray([candidate_values[index][name] for name in PARAMETER_NAMES], dtype=np.float64)
            - center_array
        )
        / spans
        for index in unique
    }
    center_distances = {
        index: float(np.linalg.norm(values)) for index, values in normalized.items()
    }
    best_pair = None
    best_objective = -np.inf
    best_pair_distance = None
    for first_index, second_index in combinations(unique, 2):
        pair_distance = float(
            np.linalg.norm(normalized[first_index] - normalized[second_index])
        )
        objective = min(
            center_distances[first_index],
            center_distances[second_index],
            pair_distance,
        )
        # ``unique`` and ``combinations`` are in candidate-index order. Keeping the
        # first exact maximizer therefore implements the frozen lexicographic tie rule.
        if objective > best_objective:
            best_pair = (first_index, second_index)
            best_objective = objective
            best_pair_distance = pair_distance
    if best_pair is None or best_pair_distance is None or not np.isfinite(best_objective):
        raise ValueError("parameter diversity objective could not be evaluated")

    first_index, second_index = best_pair

    def selected_row(index: int) -> dict:
        return {
            "candidate_index": int(index),
            "parameters": candidate_values[index],
            "development_nse": float(scores[index]),
            "development_mean_discharge": float(means[index]),
            "normalized_distance_to_center": center_distances[index],
            "selected_pair_distance": best_pair_distance,
            "selected_pair_minimum_distance": float(best_objective),
            "selection_reason": (
                "member of the eligible pair maximizing the minimum normalized parameter-space "
                "distance to the trained center and to each other"
            ),
        }

    return {
        "equifinal_diverse_1": selected_row(first_index),
        "trained_center": {
            "candidate_index": None,
            "parameters": center_values,
            "development_nse": center_score,
            "development_mean_discharge": center_mean,
            "selection_reason": "frozen trained center",
        },
        "equifinal_diverse_2": selected_row(second_index),
    }


def robust_residual_scale(residuals, minimum: float = 0.05) -> float:
    values = np.asarray(residuals, dtype=np.float64)
    floor = float(minimum)
    if values.ndim != 1 or len(values) == 0 or not np.all(np.isfinite(values)):
        raise ValueError("residuals must be a nonempty finite vector")
    if not np.isfinite(floor) or floor <= 0.0:
        raise ValueError("minimum must be finite and positive")
    median = float(np.median(values))
    median_absolute_deviation = float(np.median(np.abs(values - median)))
    return max(1.4826 * median_absolute_deviation, floor)


def observation_standard_deviation_grid(
    residuals,
    multipliers: Sequence[float] = (0.25, 0.5, 1.0),
    minimum: float = 0.05,
) -> np.ndarray:
    factors = np.asarray(tuple(multipliers), dtype=np.float64)
    if factors.ndim != 1 or len(factors) == 0 or not np.all(np.isfinite(factors)) or np.any(factors <= 0.0):
        raise ValueError("multipliers must be a nonempty positive finite vector")
    return robust_residual_scale(residuals, minimum=minimum) * factors


def select_noise_grid(process_scales, observation_standard_deviations, mean_log_likelihoods) -> dict:
    process = np.asarray(process_scales, dtype=np.float64)
    observation = np.asarray(observation_standard_deviations, dtype=np.float64)
    scores = np.asarray(mean_log_likelihoods, dtype=np.float64)
    if process.ndim != 1 or len(process) < 3 or np.any(process <= 0.0) or not np.all(np.isfinite(process)):
        raise ValueError("process scales must contain at least three positive finite values")
    if np.any(np.diff(process) <= 0.0):
        raise ValueError("process scales must be strictly increasing")
    if observation.ndim != 1 or len(observation) == 0 or np.any(observation <= 0.0):
        raise ValueError("observation standard deviations must be positive")
    if scores.shape != (len(process), len(observation)) or not np.any(np.isfinite(scores)):
        raise ValueError("mean log likelihoods have the wrong shape or no finite value")
    flat_index = int(np.nanargmax(scores))
    process_index, observation_index = np.unravel_index(flat_index, scores.shape)
    start = min(max(process_index - 1, 0), len(process) - 3)
    return {
        "selected_process_scale": float(process[process_index]),
        "selected_observation_standard_deviation": float(observation[observation_index]),
        "selected_mean_log_likelihood": float(scores[process_index, observation_index]),
        "candidate_process_scales": process[start:start + 3].copy(),
        "selected_process_index": int(process_index),
        "selected_observation_index": int(observation_index),
    }


def build_frozen_process_diagonals(reference_parameters: Mapping[str, float], process_scales) -> np.ndarray:
    parameters = _validated_center(reference_parameters)
    scales = np.asarray(process_scales, dtype=np.float64)
    if scales.ndim != 1 or len(scales) == 0 or not np.all(np.isfinite(scales)) or np.any(scales <= 0.0):
        raise ValueError("process_scales must be a nonempty positive finite vector")
    return np.asarray(
        [np.diag(build_process_covariance(parameters, float(scale))) for scale in scales],
        dtype=np.float64,
    )
