"""Serial matched execution of the five daily multi-lead methods."""

from __future__ import annotations

from dataclasses import dataclass
from collections.abc import Callable
from typing import Mapping, Sequence

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import simulate_adapter

from .forecast import origin_target_indices, run_multilead_assimilation
from .methods import METHOD_ORDER, MethodCandidate, build_method_bank, build_method_definitions


@dataclass(frozen=True)
class MethodRunResult:
    lead_days: np.ndarray
    origin_indices: np.ndarray
    target_indices: np.ndarray
    predictions: np.ndarray
    target_observations: np.ndarray | None
    candidate_ids: tuple[str, ...]
    candidate_predictions: np.ndarray
    probabilities: np.ndarray
    candidate_covariance_diagonals: np.ndarray | None
    combined_covariance_diagonals: np.ndarray | None


def _finite_forcing(values) -> np.ndarray:
    forcing = np.asarray(values, dtype=np.float64)
    if forcing.ndim != 2 or forcing.shape[1] != 3 or len(forcing) <= 1:
        raise ValueError("forcing must be a daily array with rain, PET, and temperature columns")
    if not np.all(np.isfinite(forcing)) or np.any(forcing[:, :2] < 0.0):
        raise ValueError("forcing must be finite with nonnegative rain and PET")
    return forcing


def run_open_loop_multilead(
    forcing,
    center_parameters: Mapping[str, float],
    initial_state,
    lead_days: Sequence[int] = (1, 3, 7),
) -> MethodRunResult:
    forcing_values = _finite_forcing(forcing)
    origins, targets = origin_target_indices(len(forcing_values), lead_days)
    discharge, _ = simulate_adapter(
        forcing_values[:, 0],
        forcing_values[:, 1],
        forcing_values[:, 2],
        dict(center_parameters),
        initial_state=initial_state,
    )
    predictions = discharge[targets]
    return MethodRunResult(
        lead_days=np.asarray(tuple(lead_days), dtype=np.int64),
        origin_indices=origins,
        target_indices=targets,
        predictions=predictions,
        target_observations=None,
        candidate_ids=("trained_center_open_loop",),
        candidate_predictions=predictions[:, :, None].copy(),
        probabilities=np.ones((*predictions.shape, 1), dtype=np.float64),
        candidate_covariance_diagonals=None,
        combined_covariance_diagonals=None,
    )


def _filtered_result(result, candidates: Sequence[MethodCandidate], observations: np.ndarray) -> MethodRunResult:
    return MethodRunResult(
        lead_days=result.lead_days,
        origin_indices=result.origin_indices,
        target_indices=result.target_indices,
        predictions=result.predictions,
        target_observations=observations[result.target_indices],
        candidate_ids=tuple(candidate.candidate_id for candidate in candidates),
        candidate_predictions=result.candidate_predictions,
        probabilities=result.probabilities,
        candidate_covariance_diagonals=result.candidate_covariance_diagonals,
        combined_covariance_diagonals=result.combined_covariance_diagonals,
    )


def run_five_methods(
    forcing,
    observations,
    parameter_vectors,
    process_scales,
    process_covariances,
    selected_process_id: str,
    initial_states,
    initial_covariance,
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
    interaction_mode: str,
    lead_days: Sequence[int] = (1, 3, 7),
    progress_callback: Callable[[str, int, int], None] | None = None,
) -> dict[str, MethodRunResult]:
    forcing_values = _finite_forcing(forcing)
    observed_values = np.asarray(observations, dtype=np.float64)
    if observed_values.shape != (len(forcing_values),):
        raise ValueError("observations must contain one value per forcing day")
    origins, _ = origin_target_indices(len(forcing_values), lead_days)
    if not np.all(np.isfinite(observed_values[origins])):
        raise ValueError("observations must be finite on every assimilation origin")
    methods = build_method_definitions(
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=selected_process_id,
    )
    open_result = run_open_loop_multilead(
        forcing_values,
        center_parameters=parameter_vectors["trained_center"],
        initial_state=initial_states["trained_center"],
        lead_days=lead_days,
    )
    results = {
        "open_loop": MethodRunResult(
            **{
                **open_result.__dict__,
                "target_observations": observed_values[open_result.target_indices],
            }
        )
    }
    if progress_callback is not None:
        progress_callback("open_loop", len(open_result.origin_indices), len(open_result.origin_indices))
    for method in METHOD_ORDER[1:]:
        candidates = methods[method]
        bank = build_method_bank(
            candidates=candidates,
            initial_states=initial_states,
            initial_covariance=initial_covariance,
            observation_standard_deviation=observation_standard_deviation,
            factor_transition_stay_probability=factor_transition_stay_probability,
            interaction_mode=interaction_mode,
        )
        filtered = run_multilead_assimilation(
            forcing=forcing_values,
            observations=observed_values,
            bank=bank,
            lead_days=lead_days,
            interaction_mode=interaction_mode,
            progress_callback=(
                None
                if progress_callback is None
                else lambda completed, total, current=method: progress_callback(current, completed, total)
            ),
        )
        results[method] = _filtered_result(filtered, candidates, observed_values)
    return results
