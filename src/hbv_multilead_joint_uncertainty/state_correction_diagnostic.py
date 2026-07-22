"""Isolated state-correction propagation diagnostics.

This module does not alter the source snapshot bound to the frozen formal
result.  It adds the smallest reusable pieces needed to diagnose how an
origin-day discharge update propagates through HBV-lite storage and routing
states.
"""

from __future__ import annotations

import copy
import json
import os
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from hbv_joint_uncertainty.hbv_adapter import advance_state
from hbv_joint_uncertainty.imm import normalize_log_weights
from hbv_joint_uncertainty.preflight import CandidateBank, project_hbv_state
from hbv_joint_uncertainty.sigma_filter import (
    FilterStepResult,
    ModifiedUnscentedFilter,
    _finite_observation,
    _finite_vector,
    _gaussian_log_likelihood,
    unscented_transform,
)

from .forecast import (
    _combined_state_and_covariance,
    _interact_for_forecast,
    forecast_from_posterior,
    origin_target_indices,
)


STATE_COUNT = 15
HYDROLOGIC_STATE_COUNT = 5
ROUTING_STATE_COUNT = 10


@dataclass(frozen=True)
class ControlForecastResult:
    predictions: np.ndarray
    candidate_predictions: np.ndarray
    probabilities: np.ndarray
    candidate_states: np.ndarray
    candidate_covariance_diagonals: np.ndarray
    combined_states: np.ndarray
    combined_covariance_diagonals: np.ndarray
    origin_retention: np.ndarray | None


@dataclass(frozen=True)
class StateDiagnosticAssimilationResult:
    lead_days: np.ndarray
    origin_indices: np.ndarray
    target_indices: np.ndarray
    origin_candidate_prior_states: np.ndarray
    origin_candidate_posterior_states: np.ndarray
    origin_candidate_state_corrections: np.ndarray
    origin_candidate_prior_covariance_diagonals: np.ndarray
    origin_candidate_posterior_covariance_diagonals: np.ndarray
    origin_prior_probabilities: np.ndarray
    origin_posterior_probabilities: np.ndarray
    combined_origin_prior_states: np.ndarray
    combined_origin_posterior_states: np.ndarray
    origin_state_update_contributions: np.ndarray
    origin_probability_reweighting_contributions: np.ndarray
    control_origin_candidate_prior_states: dict[str, np.ndarray]
    control_origin_candidate_posterior_states: dict[str, np.ndarray]
    control_origin_candidate_prior_covariance_diagonals: dict[str, np.ndarray]
    control_origin_candidate_posterior_covariance_diagonals: dict[str, np.ndarray]
    control_origin_prior_probabilities: dict[str, np.ndarray]
    control_origin_posterior_probabilities: dict[str, np.ndarray]
    natural_hbv_candidate_state_correction: np.ndarray
    natural_hbv_combined_state_correction: np.ndarray
    natural_hbv_combined_prediction_correction: np.ndarray
    shared_origin_prior_validation: dict[str, float | int]
    state_update_masks: dict[str, np.ndarray]
    controls: dict[str, ControlForecastResult]


@dataclass(frozen=True)
class DiagnosticResumeCheckpoint:
    completed_origin_count: int
    lead_days: np.ndarray
    origin_indices: np.ndarray
    state_update_masks: dict[str, np.ndarray]
    reference_filter_states: np.ndarray
    reference_filter_covariances: np.ndarray
    reference_probabilities: np.ndarray
    reference_combined_state: np.ndarray
    reference_combined_covariance: np.ndarray
    main_arrays: dict[str, np.ndarray]
    control_origin_arrays: dict[str, dict[str, np.ndarray]]
    control_storage: dict[str, dict[str, np.ndarray | None]]


def save_diagnostic_checkpoint(
    path: Path,
    checkpoint: DiagnosticResumeCheckpoint,
    identity: Mapping[str, str],
) -> dict:
    """Atomically save a numeric checkpoint bound to immutable run identities."""
    destination = Path(path)
    identity_values = {str(key): str(value) for key, value in identity.items()}
    if not identity_values:
        raise ValueError("checkpoint identity must be nonempty")
    metadata = {
        "format_version": 1,
        "completed_origin_count": int(checkpoint.completed_origin_count),
        "identity": identity_values,
        "control_ids": sorted(checkpoint.control_storage),
        "mask_ids": sorted(checkpoint.state_update_masks),
        "main_array_names": sorted(checkpoint.main_arrays),
        "control_origin_fields": sorted(checkpoint.control_origin_arrays),
    }
    arrays = {
        "metadata_json": np.asarray(json.dumps(metadata, sort_keys=True)),
        "lead_days": checkpoint.lead_days,
        "origin_indices": checkpoint.origin_indices,
        "reference_filter_states": checkpoint.reference_filter_states,
        "reference_filter_covariances": checkpoint.reference_filter_covariances,
        "reference_probabilities": checkpoint.reference_probabilities,
        "reference_combined_state": checkpoint.reference_combined_state,
        "reference_combined_covariance": checkpoint.reference_combined_covariance,
    }
    for control_id, mask in checkpoint.state_update_masks.items():
        arrays[f"mask::{control_id}"] = mask
    for name, values in checkpoint.main_arrays.items():
        arrays[f"main::{name}"] = values
    for field, controls in checkpoint.control_origin_arrays.items():
        for control_id, values in controls.items():
            arrays[f"origin::{field}::{control_id}"] = values
    for control_id, storage in checkpoint.control_storage.items():
        for field, values in storage.items():
            if values is not None:
                arrays[f"control::{control_id}::{field}"] = values
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.{os.getpid()}.tmp")
    with temporary.open("wb") as handle:
        np.savez_compressed(handle, **arrays)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, destination)
    return {
        "path": str(destination.resolve()),
        "completed_origin_count": int(checkpoint.completed_origin_count),
        "identity": identity_values,
    }


def load_diagnostic_checkpoint(
    path: Path,
    expected_identity: Mapping[str, str],
) -> DiagnosticResumeCheckpoint:
    """Load a checkpoint only when every immutable identity matches exactly."""
    source = Path(path)
    with np.load(source, allow_pickle=False) as loaded:
        metadata = json.loads(str(loaded["metadata_json"].item()))
        expected = {str(key): str(value) for key, value in expected_identity.items()}
        if metadata.get("format_version") != 1 or metadata.get("identity") != expected:
            raise ValueError("diagnostic checkpoint identity mismatch")
        files = set(loaded.files)
        masks = {
            control_id: loaded[f"mask::{control_id}"].copy()
            for control_id in metadata["mask_ids"]
        }
        main_arrays = {
            name: loaded[f"main::{name}"].copy()
            for name in metadata["main_array_names"]
        }
        control_origin_arrays = {}
        for field in metadata["control_origin_fields"]:
            control_origin_arrays[field] = {
                control_id: loaded[f"origin::{field}::{control_id}"].copy()
                for control_id in metadata["mask_ids"]
            }
        control_storage = {}
        for control_id in metadata["control_ids"]:
            prefix = f"control::{control_id}::"
            storage = {
                name[len(prefix):]: loaded[name].copy()
                for name in files
                if name.startswith(prefix)
            }
            storage.setdefault("origin_retention", None)
            control_storage[control_id] = storage
        return DiagnosticResumeCheckpoint(
            completed_origin_count=int(metadata["completed_origin_count"]),
            lead_days=loaded["lead_days"].copy(),
            origin_indices=loaded["origin_indices"].copy(),
            state_update_masks=masks,
            reference_filter_states=loaded["reference_filter_states"].copy(),
            reference_filter_covariances=loaded["reference_filter_covariances"].copy(),
            reference_probabilities=loaded["reference_probabilities"].copy(),
            reference_combined_state=loaded["reference_combined_state"].copy(),
            reference_combined_covariance=loaded["reference_combined_covariance"].copy(),
            main_arrays=main_arrays,
            control_origin_arrays=control_origin_arrays,
            control_storage=control_storage,
        )


def _validated_leads(lead_days: Sequence[int]) -> np.ndarray:
    values = np.asarray(lead_days)
    if values.ndim != 1 or len(values) == 0 or values.dtype.kind not in "iu":
        raise ValueError("lead days must be a nonempty one-dimensional integer array")
    leads = values.astype(np.int64, copy=False)
    if np.any(leads <= 0) or np.any(np.diff(leads) <= 0):
        raise ValueError("lead days must be positive, unique, and strictly increasing")
    return leads


class WeightedStateUpdateFilter(ModifiedUnscentedFilter):
    """Modified unscented filter with row-wise measurement-update weights."""

    def __init__(self, *args, state_update_weights, **kwargs):
        super().__init__(*args, **kwargs)
        weights = np.asarray(state_update_weights, dtype=np.float64)
        if (
            weights.shape != (self.n_state,)
            or not np.all(np.isfinite(weights))
            or np.any(weights < 0.0)
            or np.any(weights > 1.0)
        ):
            raise ValueError(
                f"state update weights must be finite values in [0, 1] with shape ({self.n_state},)"
            )
        self.state_update_weights = weights.copy()

    def update(self, observation) -> FilterStepResult:
        if np.all(self.state_update_weights == 1.0):
            return super().update(observation)
        if self._prior_state is None or self._prior_covariance is None:
            raise RuntimeError("predict must be called before update")

        observed = _finite_observation(observation, self.n_observation)
        sigmas = self.sigma_generator.sigma_points(self._prior_state, self._prior_covariance)
        observation_sigmas = np.asarray([self.observation(point.copy()) for point in sigmas], dtype=np.float64)
        if observation_sigmas.shape == (len(sigmas),):
            observation_sigmas = observation_sigmas[:, None]
        expected_shape = (len(sigmas), self.n_observation)
        if observation_sigmas.shape != expected_shape:
            raise ValueError(
                f"observation function returned shape {observation_sigmas.shape}; expected {expected_shape}"
            )
        if not np.all(np.isfinite(observation_sigmas)):
            raise ValueError("observation function returned non-finite values")

        prior_observation, innovation_covariance = unscented_transform(
            observation_sigmas,
            self.sigma_generator.mean_weights,
            self.sigma_generator.covariance_weights,
            self.observation_covariance,
        )
        state_deviations = sigmas - self._prior_state
        observation_deviations = observation_sigmas - prior_observation
        cross_covariance = np.einsum(
            "i,ij,ik->jk",
            self.sigma_generator.covariance_weights,
            state_deviations,
            observation_deviations,
        )
        try:
            gain = np.linalg.solve(innovation_covariance.T, cross_covariance.T).T
        except np.linalg.LinAlgError as error:
            raise ValueError("innovation covariance is singular") from error

        weighted_gain = self.state_update_weights[:, None] * gain
        innovation = observed - prior_observation
        posterior_state = self._prior_state + weighted_gain @ innovation
        if self.state_projector is not None:
            posterior_state = _finite_vector(
                self.state_projector(posterior_state.copy()),
                self.n_state,
                "projected posterior state",
            )
            locked = self.state_update_weights == 0.0
            posterior_state[locked] = self._prior_state[locked]

        posterior_covariance = (
            self._prior_covariance
            - weighted_gain @ cross_covariance.T
            - cross_covariance @ weighted_gain.T
            + weighted_gain @ innovation_covariance @ weighted_gain.T
        )
        posterior_covariance = 0.5 * (posterior_covariance + posterior_covariance.T)
        if not np.all(np.isfinite(posterior_state)) or not np.all(np.isfinite(posterior_covariance)):
            raise ValueError("posterior state or covariance is non-finite")

        log_likelihood = _gaussian_log_likelihood(innovation, innovation_covariance)
        result = FilterStepResult(
            prior_state=self._prior_state.copy(),
            prior_covariance=self._prior_covariance.copy(),
            prior_observation=prior_observation.copy(),
            innovation=innovation.copy(),
            innovation_covariance=innovation_covariance.copy(),
            posterior_state=posterior_state.copy(),
            posterior_covariance=posterior_covariance.copy(),
            log_likelihood=log_likelihood,
        )
        self.state = posterior_state
        self.covariance = posterior_covariance
        self._prior_state = None
        self._prior_covariance = None
        return result


def lead_decay_retention(lead_days: Sequence[int], half_life_days: float) -> np.ndarray:
    """Return the preregistered empirical sensitivity retention."""
    leads = _validated_leads(lead_days)
    half_life = float(half_life_days)
    if not np.isfinite(half_life) or half_life <= 0.0:
        raise ValueError("half life must be finite and positive")
    return np.asarray(2.0 ** (-(leads - 1) / half_life), dtype=np.float64)


def physical_lead_retention(
    lead_days: Sequence[int],
    parameters: Mapping[str, float],
    origin_state: Sequence[float],
) -> np.ndarray:
    """Derive state-specific retention from frozen recession and routing terms."""
    leads = _validated_leads(lead_days)
    required = ("parK0", "parK1", "parUZL", "parK2", "lag_time")
    if any(name not in parameters for name in required):
        raise ValueError(f"parameters must include {required}")
    values = {name: float(parameters[name]) for name in required}
    if not np.all(np.isfinite(list(values.values()))):
        raise ValueError("physical retention parameters must be finite")
    if not (0.0 <= values["parK0"] <= 1.0):
        raise ValueError("parK0 must be within [0, 1]")
    if not (0.0 <= values["parK1"] <= 1.0):
        raise ValueError("parK1 must be within [0, 1]")
    if not (0.0 <= values["parK2"] <= 1.0):
        raise ValueError("parK2 must be within [0, 1]")
    if values["parUZL"] < 0.0:
        raise ValueError("parUZL must be nonnegative")
    if not (1.0 <= values["lag_time"] <= ROUTING_STATE_COUNT):
        raise ValueError("lag_time must be within [1, 10]")
    state = np.asarray(origin_state, dtype=np.float64)
    if state.shape != (STATE_COUNT,) or not np.all(np.isfinite(state)):
        raise ValueError("origin state must be one finite fifteen-state vector")

    retention = np.ones((len(leads), STATE_COUNT), dtype=np.float64)
    upper_daily = 1.0 - values["parK1"]
    if state[3] > values["parUZL"]:
        upper_daily *= 1.0 - values["parK0"]
    lower_daily = 1.0 - values["parK2"]
    retention[:, 3] = upper_daily ** (leads - 1)
    retention[:, 4] = lower_daily ** (leads - 1)

    active_lags = int(np.ceil(values["lag_time"]))
    routing_weights = np.arange(active_lags, 0, -1, dtype=np.float64)
    routing_weights /= routing_weights.sum()
    for row, lead in enumerate(leads):
        if int(lead) == 1:
            continue
        shift = int(lead) - 1
        retention[row, HYDROLOGIC_STATE_COUNT:] = 0.0
        for routing_index in range(active_lags):
            shifted_index = routing_index + shift
            if shifted_index < active_lags:
                retention[row, HYDROLOGIC_STATE_COUNT + routing_index] = (
                    routing_weights[shifted_index] / routing_weights[routing_index]
                )
    return retention


def decompose_combined_origin_correction(
    prior_states,
    posterior_states,
    prior_probabilities,
    posterior_probabilities,
) -> dict[str, np.ndarray]:
    """Separate within-candidate state updates from probability reweighting."""
    prior = np.asarray(prior_states, dtype=np.float64)
    posterior = np.asarray(posterior_states, dtype=np.float64)
    prior_weights = np.asarray(prior_probabilities, dtype=np.float64)
    posterior_weights = np.asarray(posterior_probabilities, dtype=np.float64)
    if prior.ndim != 2 or posterior.shape != prior.shape or not np.all(np.isfinite(prior)):
        raise ValueError("prior and posterior states must be matching finite matrices")
    if not np.all(np.isfinite(posterior)):
        raise ValueError("prior and posterior states must be matching finite matrices")
    expected_weight_shape = (prior.shape[0],)
    for weights in (prior_weights, posterior_weights):
        if (
            weights.shape != expected_weight_shape
            or not np.all(np.isfinite(weights))
            or np.any(weights < 0.0)
            or abs(float(weights.sum()) - 1.0) > 1e-12
        ):
            raise ValueError("candidate probabilities must be finite, nonnegative, and sum to one")

    combined_prior = prior_weights @ prior
    combined_posterior = posterior_weights @ posterior
    state_update = posterior_weights @ (posterior - prior)
    probability_reweighting = (posterior_weights - prior_weights) @ prior
    return {
        "combined_prior_state": combined_prior,
        "combined_posterior_state": combined_posterior,
        "state_update_contribution": state_update,
        "probability_reweighting_contribution": probability_reweighting,
        "total_correction": state_update + probability_reweighting,
    }


def blend_target_state_correction(
    reference_state,
    removed_state,
    reference_covariance,
    removed_covariance,
    retention: float,
) -> tuple[np.ndarray, np.ndarray]:
    """Blend a propagated sensitivity branch at a fixed scalar retention."""
    fraction = float(retention)
    if not np.isfinite(fraction) or fraction < 0.0 or fraction > 1.0:
        raise ValueError("retention must be finite and within [0, 1]")
    reference = np.asarray(reference_state, dtype=np.float64)
    removed = np.asarray(removed_state, dtype=np.float64)
    reference_cov = np.asarray(reference_covariance, dtype=np.float64)
    removed_cov = np.asarray(removed_covariance, dtype=np.float64)
    if reference.ndim != 1 or removed.shape != reference.shape:
        raise ValueError("reference and removed states must be matching vectors")
    expected_covariance_shape = (len(reference), len(reference))
    if reference_cov.shape != expected_covariance_shape or removed_cov.shape != expected_covariance_shape:
        raise ValueError("reference and removed covariances must match the state dimension")
    if not all(np.all(np.isfinite(value)) for value in (reference, removed, reference_cov, removed_cov)):
        raise ValueError("state and covariance inputs must be finite")
    if fraction == 1.0:
        return reference.copy(), reference_cov.copy()
    if fraction == 0.0:
        return removed.copy(), removed_cov.copy()
    state = removed + fraction * (reference - removed)
    covariance = removed_cov + fraction * (reference_cov - removed_cov)
    covariance = 0.5 * (covariance + covariance.T)
    return state, covariance


def apply_origin_mean_retention(prior_states, posterior_states, retention) -> np.ndarray:
    """Scale candidate posterior-minus-prior mean corrections elementwise."""
    prior = np.asarray(prior_states, dtype=np.float64)
    posterior = np.asarray(posterior_states, dtype=np.float64)
    weights = np.asarray(retention, dtype=np.float64)
    if prior.ndim != 2 or posterior.shape != prior.shape or weights.shape != prior.shape:
        raise ValueError("prior, posterior, and retention arrays must have matching candidate-by-state shape")
    if not all(np.all(np.isfinite(value)) for value in (prior, posterior, weights)):
        raise ValueError("prior, posterior, and retention arrays must be finite")
    if np.any(weights < 0.0) or np.any(weights > 1.0):
        raise ValueError("retention values must be within [0, 1]")
    return prior + weights * (posterior - prior)


def validate_replay_arrays(
    replayed: Mapping[str, np.ndarray],
    saved: Mapping[str, np.ndarray],
    maximum_absolute_error: float,
    maximum_relative_error: float,
    relative_error_denominator_floor: float,
) -> dict:
    """Report frozen maximum absolute and scaled relative replay errors."""
    if set(replayed) != set(saved) or not saved:
        raise ValueError("replayed and saved arrays must contain identical nonempty keys")
    absolute_tolerance = float(maximum_absolute_error)
    relative_tolerance = float(maximum_relative_error)
    floor = float(relative_error_denominator_floor)
    if (
        not np.all(np.isfinite([absolute_tolerance, relative_tolerance, floor]))
        or absolute_tolerance < 0.0
        or relative_tolerance < 0.0
        or floor <= 0.0
    ):
        raise ValueError("replay tolerances must be finite and nonnegative, with a positive denominator floor")

    reports = {}
    global_absolute = 0.0
    global_relative = 0.0
    for name in saved:
        replayed_values = np.asarray(replayed[name])
        saved_values = np.asarray(saved[name])
        if replayed_values.shape != saved_values.shape:
            raise ValueError(
                f"replayed array {name} shape {replayed_values.shape} differs from saved shape {saved_values.shape}"
            )
        if not np.issubdtype(replayed_values.dtype, np.number) or not np.issubdtype(saved_values.dtype, np.number):
            raise ValueError(f"replayed array {name} must be numeric")
        replayed_float = replayed_values.astype(np.float64, copy=False)
        saved_float = saved_values.astype(np.float64, copy=False)
        if not np.all(np.isfinite(replayed_float)) or not np.all(np.isfinite(saved_float)):
            raise ValueError(f"replayed array {name} must be finite")
        absolute = np.abs(replayed_float - saved_float)
        relative = absolute / np.maximum(np.abs(saved_float), floor)
        array_absolute = float(np.max(absolute, initial=0.0))
        array_relative = float(np.max(relative, initial=0.0))
        reports[name] = {
            "shape": list(saved_float.shape),
            "maximum_absolute_error": array_absolute,
            "maximum_relative_error": array_relative,
            "passed": bool(
                array_absolute <= absolute_tolerance and array_relative <= relative_tolerance
            ),
        }
        global_absolute = max(global_absolute, array_absolute)
        global_relative = max(global_relative, array_relative)
    return {
        "passed": bool(global_absolute <= absolute_tolerance and global_relative <= relative_tolerance),
        "maximum_absolute_error": global_absolute,
        "maximum_relative_error": global_relative,
        "maximum_absolute_error_allowed": absolute_tolerance,
        "maximum_relative_error_allowed": relative_tolerance,
        "relative_error_denominator_floor": floor,
        "arrays": reports,
    }


def _weighted_bank(bank: CandidateBank, state_update_weights: np.ndarray) -> CandidateBank:
    branch = copy.deepcopy(bank)
    weights = np.asarray(state_update_weights, dtype=np.float64)
    if weights.shape != (branch.estimator.n_state,):
        raise ValueError("each state update mask must match the state dimension")
    replacements = []
    for candidate, transition in zip(branch.estimator.filters, branch.transitions):
        replacement = WeightedStateUpdateFilter(
            state=candidate.state.copy(),
            covariance=candidate.covariance.copy(),
            transition=transition,
            observation=candidate.observation,
            process_covariance=candidate.process_covariance.copy(),
            observation_covariance=candidate.observation_covariance.copy(),
            state_projector=candidate.state_projector,
            alpha=candidate.sigma_generator.alpha,
            beta=candidate.sigma_generator.beta,
            kappa=candidate.sigma_generator.kappa,
            state_update_weights=weights,
        )
        replacements.append(replacement)
    branch.estimator.filters = replacements
    return branch


def _assimilate_and_capture(bank: CandidateBank, observation: float, interaction_mode: str) -> dict:
    prior_probabilities = _interact_for_forecast(bank.estimator, interaction_mode)
    candidate_results = tuple(candidate.step(observation) for candidate in bank.estimator.filters)
    log_prior = np.full(len(prior_probabilities), -np.inf, dtype=np.float64)
    positive = prior_probabilities > 0.0
    log_prior[positive] = np.log(prior_probabilities[positive])
    posterior_probabilities = normalize_log_weights(
        log_prior + np.asarray([result.log_likelihood for result in candidate_results], dtype=np.float64)
    )
    posterior_states = np.asarray([result.posterior_state for result in candidate_results], dtype=np.float64)
    posterior_covariances = np.asarray(
        [result.posterior_covariance for result in candidate_results], dtype=np.float64
    )
    combined_state, combined_covariance = _combined_state_and_covariance(
        bank.estimator,
        posterior_probabilities,
        posterior_states,
        posterior_covariances,
    )
    bank.estimator.probabilities = posterior_probabilities.copy()
    bank.estimator.state = combined_state.copy()
    bank.estimator.covariance = combined_covariance.copy()
    return {
        "prior_probabilities": prior_probabilities,
        "posterior_probabilities": posterior_probabilities,
        "prior_states": np.asarray([result.prior_state for result in candidate_results], dtype=np.float64),
        "posterior_states": posterior_states,
        "prior_covariances": np.asarray(
            [result.prior_covariance for result in candidate_results], dtype=np.float64
        ),
        "posterior_covariances": posterior_covariances,
    }


def _set_candidate_means(bank: CandidateBank, candidate_means: np.ndarray) -> CandidateBank:
    branch = copy.deepcopy(bank)
    means = np.asarray(candidate_means, dtype=np.float64)
    expected = (len(branch.estimator.filters), branch.estimator.n_state)
    if means.shape != expected or not np.all(np.isfinite(means)):
        raise ValueError(f"candidate means must have finite shape {expected}")
    covariances = []
    for candidate, mean in zip(branch.estimator.filters, means):
        candidate.state = mean.copy()
        candidate._prior_state = None
        candidate._prior_covariance = None
        covariances.append(candidate.covariance.copy())
    combined_state, combined_covariance = _combined_state_and_covariance(
        branch.estimator,
        branch.estimator.probabilities,
        means,
        covariances,
    )
    branch.estimator.state = combined_state.copy()
    branch.estimator.covariance = combined_covariance.copy()
    return branch


def _allocate_control(origin_count: int, lead_count: int, candidate_count: int, state_count: int):
    return {
        "predictions": np.empty((origin_count, lead_count), dtype=np.float64),
        "candidate_predictions": np.empty((origin_count, lead_count, candidate_count), dtype=np.float64),
        "probabilities": np.empty((origin_count, lead_count, candidate_count), dtype=np.float64),
        "candidate_states": np.empty(
            (origin_count, lead_count, candidate_count, state_count), dtype=np.float64
        ),
        "candidate_covariance_diagonals": np.empty(
            (origin_count, lead_count, candidate_count, state_count), dtype=np.float64
        ),
        "combined_states": np.empty((origin_count, lead_count, state_count), dtype=np.float64),
        "combined_covariance_diagonals": np.empty(
            (origin_count, lead_count, state_count), dtype=np.float64
        ),
        "origin_retention": None,
    }


def _store_forecast(storage: dict, origin_row: int, lead_rows, forecast) -> None:
    rows = np.asarray(lead_rows, dtype=np.int64)
    storage["predictions"][origin_row, rows] = forecast.combined_predictions
    storage["candidate_predictions"][origin_row, rows] = forecast.candidate_predictions
    storage["probabilities"][origin_row, rows] = forecast.probabilities
    storage["candidate_states"][origin_row, rows] = forecast.candidate_states
    storage["candidate_covariance_diagonals"][origin_row, rows] = (
        forecast.candidate_covariance_diagonals
    )
    storage["combined_states"][origin_row, rows] = forecast.combined_states
    storage["combined_covariance_diagonals"][origin_row, rows] = (
        forecast.combined_covariance_diagonals
    )


def _finalize_control(storage: dict) -> ControlForecastResult:
    return ControlForecastResult(**storage)


def run_state_diagnostic_assimilation(
    forcing,
    observations,
    bank: CandidateBank,
    state_update_masks: Mapping[str, Sequence[float]],
    lead_days: Sequence[int] = (1, 3, 7),
    interaction_mode: str | None = None,
    progress_callback=None,
    checkpoint_callback=None,
    resume_checkpoint: DiagnosticResumeCheckpoint | None = None,
) -> StateDiagnosticAssimilationResult:
    """Replay state updates and matched origin-mean counterfactuals causally."""
    forcing_values = np.asarray(forcing, dtype=np.float64)
    observed_values = np.asarray(observations, dtype=np.float64)
    if forcing_values.ndim != 2 or forcing_values.shape[1] != 3 or not np.all(np.isfinite(forcing_values)):
        raise ValueError("forcing must be a finite daily array with three columns")
    if observed_values.shape != (len(forcing_values),):
        raise ValueError("observations must contain one value per forcing day")
    leads = _validated_leads(lead_days)
    origins, targets = origin_target_indices(len(forcing_values), leads)
    if not np.all(np.isfinite(observed_values[origins])):
        raise ValueError("observations must be finite at every assimilation origin")
    if "current_joint_all_fifteen_states" not in state_update_masks:
        raise ValueError("state update masks must include the frozen all-state reference")
    if any(
        candidate._prior_state is not None or candidate._prior_covariance is not None
        for candidate in bank.estimator.filters
    ):
        raise ValueError("input bank must contain posterior-ready filters")

    masks = {}
    for control_id, values in state_update_masks.items():
        mask = np.asarray(values, dtype=np.float64)
        if (
            mask.shape != (bank.estimator.n_state,)
            or not np.all(np.isfinite(mask))
            or np.any(mask < 0.0)
            or np.any(mask > 1.0)
        ):
            raise ValueError(f"state update mask {control_id} is invalid")
        masks[str(control_id)] = mask.copy()

    mode = interaction_mode or getattr(bank.estimator, "interaction_mode", "full")
    origin_count = len(origins)
    lead_count = len(leads)
    candidate_count = len(bank.estimator.filters)
    state_count = bank.estimator.n_state
    origin_prior_states = np.empty((origin_count, candidate_count, state_count), dtype=np.float64)
    origin_posterior_states = np.empty_like(origin_prior_states)
    origin_prior_covariance_diagonals = np.empty_like(origin_prior_states)
    origin_posterior_covariance_diagonals = np.empty_like(origin_prior_states)
    origin_prior_probabilities = np.empty((origin_count, candidate_count), dtype=np.float64)
    origin_posterior_probabilities = np.empty_like(origin_prior_probabilities)
    combined_prior_states = np.empty((origin_count, state_count), dtype=np.float64)
    combined_posterior_states = np.empty_like(combined_prior_states)
    state_update_contributions = np.empty_like(combined_prior_states)
    probability_reweighting_contributions = np.empty_like(combined_prior_states)

    reference_id = "current_joint_all_fifteen_states"
    if not np.array_equal(masks[reference_id], np.ones(state_count, dtype=np.float64)):
        raise ValueError("the frozen all-state reference mask must contain only ones")
    control_origin_shapes = {
        "prior_states": (origin_count, candidate_count, state_count),
        "posterior_states": (origin_count, candidate_count, state_count),
        "prior_covariance_diagonals": (origin_count, candidate_count, state_count),
        "posterior_covariance_diagonals": (origin_count, candidate_count, state_count),
        "prior_probabilities": (origin_count, candidate_count),
        "posterior_probabilities": (origin_count, candidate_count),
    }
    control_origin_arrays = {
        field: {
            control_id: np.empty(shape, dtype=np.float64) for control_id in masks
        }
        for field, shape in control_origin_shapes.items()
    }

    branch_ids = (
        "origin_mean_correction_removed",
        "three_day_half_life_additional_mean_taper_sensitivity",
    )
    control_storage = {
        control_id: _allocate_control(origin_count, lead_count, candidate_count, state_count)
        for control_id in (*masks, *branch_ids)
    }
    control_storage["three_day_half_life_additional_mean_taper_sensitivity"][
        "origin_retention"
    ] = np.empty(
        (origin_count, lead_count, candidate_count, state_count), dtype=np.float64
    )

    maximum_lead = int(leads[-1])
    maximum_shared_prior_state_difference = 0.0
    maximum_shared_prior_covariance_difference = 0.0
    maximum_shared_prior_probability_difference = 0.0
    reference_bank = _weighted_bank(bank, masks[reference_id])
    main_arrays = {
        "origin_prior_states": origin_prior_states,
        "origin_posterior_states": origin_posterior_states,
        "origin_prior_covariance_diagonals": origin_prior_covariance_diagonals,
        "origin_posterior_covariance_diagonals": origin_posterior_covariance_diagonals,
        "origin_prior_probabilities": origin_prior_probabilities,
        "origin_posterior_probabilities": origin_posterior_probabilities,
        "combined_prior_states": combined_prior_states,
        "combined_posterior_states": combined_posterior_states,
        "state_update_contributions": state_update_contributions,
        "probability_reweighting_contributions": probability_reweighting_contributions,
    }
    start_origin_row = 0
    if resume_checkpoint is not None:
        checkpoint = resume_checkpoint
        if not np.array_equal(checkpoint.lead_days, leads) or not np.array_equal(
            checkpoint.origin_indices, origins
        ):
            raise ValueError("diagnostic checkpoint lead or origin indices do not match")
        if set(checkpoint.state_update_masks) != set(masks) or any(
            not np.array_equal(checkpoint.state_update_masks[key], masks[key]) for key in masks
        ):
            raise ValueError("diagnostic checkpoint state masks do not match")
        start_origin_row = int(checkpoint.completed_origin_count)
        if start_origin_row <= 0 or start_origin_row > origin_count:
            raise ValueError("diagnostic checkpoint completion index is outside the resumable range")
        for candidate, state, covariance in zip(
            reference_bank.estimator.filters,
            checkpoint.reference_filter_states,
            checkpoint.reference_filter_covariances,
        ):
            candidate.state = state.copy()
            candidate.covariance = covariance.copy()
            candidate._prior_state = None
            candidate._prior_covariance = None
        reference_bank.estimator.probabilities = checkpoint.reference_probabilities.copy()
        reference_bank.estimator.state = checkpoint.reference_combined_state.copy()
        reference_bank.estimator.covariance = checkpoint.reference_combined_covariance.copy()
        for name, destination in main_arrays.items():
            destination[:start_origin_row] = checkpoint.main_arrays[name]
        for field, controls in control_origin_arrays.items():
            for control_id, destination in controls.items():
                destination[:start_origin_row] = checkpoint.control_origin_arrays[field][control_id]
        for control_id, storage in control_storage.items():
            saved = checkpoint.control_storage[control_id]
            for field, destination in storage.items():
                if destination is not None:
                    destination[:start_origin_row] = saved[field]

    def build_checkpoint(completed: int) -> DiagnosticResumeCheckpoint:
        return DiagnosticResumeCheckpoint(
            completed_origin_count=completed,
            lead_days=leads.copy(),
            origin_indices=origins.copy(),
            state_update_masks={key: value.copy() for key, value in masks.items()},
            reference_filter_states=np.asarray(
                [candidate.state for candidate in reference_bank.estimator.filters],
                dtype=np.float64,
            ),
            reference_filter_covariances=np.asarray(
                [candidate.covariance for candidate in reference_bank.estimator.filters],
                dtype=np.float64,
            ),
            reference_probabilities=reference_bank.estimator.probabilities.copy(),
            reference_combined_state=reference_bank.estimator.state.copy(),
            reference_combined_covariance=reference_bank.estimator.covariance.copy(),
            main_arrays={
                name: values[:completed].copy() for name, values in main_arrays.items()
            },
            control_origin_arrays={
                field: {
                    control_id: values[:completed].copy()
                    for control_id, values in controls.items()
                }
                for field, controls in control_origin_arrays.items()
            },
            control_storage={
                control_id: {
                    field: None if values is None else values[:completed].copy()
                    for field, values in storage.items()
                }
                for control_id, storage in control_storage.items()
            },
        )

    for origin_row in range(start_origin_row, origin_count):
        origin = int(origins[origin_row])
        captured = {}
        origin_banks = {reference_id: reference_bank}
        origin_banks.update(
            {
                control_id: _weighted_bank(reference_bank, mask)
                for control_id, mask in masks.items()
                if control_id != reference_id
            }
        )
        for control_id, control_bank in origin_banks.items():
            rain, pet, temperature = forcing_values[origin]
            for transition in control_bank.transitions:
                transition.set_forcing(rain, pet, temperature)
            captured[control_id] = _assimilate_and_capture(
                control_bank, observed_values[origin], mode
            )
            future = forcing_values[origin + 1:origin + maximum_lead + 1]
            forecast = forecast_from_posterior(
                control_bank,
                future,
                lead_days=leads,
                interaction_mode=mode,
            )
            _store_forecast(control_storage[control_id], origin_row, np.arange(lead_count), forecast)
            control_origin_arrays["prior_states"][control_id][origin_row] = captured[control_id][
                "prior_states"
            ]
            control_origin_arrays["posterior_states"][control_id][origin_row] = captured[
                control_id
            ]["posterior_states"]
            control_origin_arrays["prior_covariance_diagonals"][control_id][origin_row] = np.asarray(
                [np.diag(value) for value in captured[control_id]["prior_covariances"]]
            )
            control_origin_arrays["posterior_covariance_diagonals"][control_id][
                origin_row
            ] = np.asarray(
                [np.diag(value) for value in captured[control_id]["posterior_covariances"]]
            )
            control_origin_arrays["prior_probabilities"][control_id][origin_row] = captured[
                control_id
            ]["prior_probabilities"]
            control_origin_arrays["posterior_probabilities"][control_id][origin_row] = captured[
                control_id
            ]["posterior_probabilities"]

        reference_capture = captured[reference_id]
        for control_id in masks:
            if control_id == reference_id:
                continue
            state_difference = float(
                np.max(
                    np.abs(captured[control_id]["prior_states"] - reference_capture["prior_states"]),
                    initial=0.0,
                )
            )
            covariance_difference = float(
                np.max(
                    np.abs(
                        captured[control_id]["prior_covariances"]
                        - reference_capture["prior_covariances"]
                    ),
                    initial=0.0,
                )
            )
            probability_difference = float(
                np.max(
                    np.abs(
                        captured[control_id]["prior_probabilities"]
                        - reference_capture["prior_probabilities"]
                    ),
                    initial=0.0,
                )
            )
            maximum_shared_prior_state_difference = max(
                maximum_shared_prior_state_difference, state_difference
            )
            maximum_shared_prior_covariance_difference = max(
                maximum_shared_prior_covariance_difference, covariance_difference
            )
            maximum_shared_prior_probability_difference = max(
                maximum_shared_prior_probability_difference, probability_difference
            )
            if state_difference != 0.0:
                raise ValueError(f"state-mask branch {control_id} does not share prior states")
            if covariance_difference != 0.0:
                raise ValueError(f"state-mask branch {control_id} does not share prior covariances")
            if probability_difference != 0.0:
                raise ValueError(f"state-mask branch {control_id} does not share prior probabilities")
        prior_states = reference_capture["prior_states"]
        posterior_states = reference_capture["posterior_states"]
        origin_prior_states[origin_row] = prior_states
        origin_posterior_states[origin_row] = posterior_states
        origin_prior_covariance_diagonals[origin_row] = np.asarray(
            [np.diag(value) for value in reference_capture["prior_covariances"]]
        )
        origin_posterior_covariance_diagonals[origin_row] = np.asarray(
            [np.diag(value) for value in reference_capture["posterior_covariances"]]
        )
        origin_prior_probabilities[origin_row] = reference_capture["prior_probabilities"]
        origin_posterior_probabilities[origin_row] = reference_capture["posterior_probabilities"]
        decomposition = decompose_combined_origin_correction(
            prior_states,
            posterior_states,
            reference_capture["prior_probabilities"],
            reference_capture["posterior_probabilities"],
        )
        combined_prior_states[origin_row] = decomposition["combined_prior_state"]
        combined_posterior_states[origin_row] = decomposition["combined_posterior_state"]
        state_update_contributions[origin_row] = decomposition["state_update_contribution"]
        probability_reweighting_contributions[origin_row] = decomposition[
            "probability_reweighting_contribution"
        ]

        future = forcing_values[origin + 1:origin + maximum_lead + 1]
        removed_bank = _set_candidate_means(reference_bank, prior_states)
        removed_forecast = forecast_from_posterior(
            removed_bank,
            future,
            lead_days=leads,
            interaction_mode=mode,
        )
        _store_forecast(
            control_storage["origin_mean_correction_removed"],
            origin_row,
            np.arange(lead_count),
            removed_forecast,
        )

        sensitivity_scalar = lead_decay_retention(leads, half_life_days=3.0)
        sensitivity_retention = np.broadcast_to(
            sensitivity_scalar[:, None, None],
            (lead_count, candidate_count, state_count),
        ).copy()
        control_storage["three_day_half_life_additional_mean_taper_sensitivity"][
            "origin_retention"
        ][
            origin_row
        ] = sensitivity_retention

        for lead_row, lead in enumerate(leads):
            adjusted_means = apply_origin_mean_retention(
                prior_states,
                posterior_states,
                sensitivity_retention[lead_row],
            )
            decay_bank = _set_candidate_means(reference_bank, adjusted_means)
            decay_forecast = forecast_from_posterior(
                decay_bank,
                future[:int(lead)],
                lead_days=(int(lead),),
                interaction_mode=mode,
            )
            _store_forecast(
                control_storage["three_day_half_life_additional_mean_taper_sensitivity"],
                origin_row,
                [lead_row],
                decay_forecast,
            )

        completed = origin_row + 1
        if checkpoint_callback is not None:
            checkpoint_callback(completed, origin_count, build_checkpoint(completed))
        if progress_callback is not None:
            progress_callback(completed, origin_count)

    controls = {
        control_id: _finalize_control(storage) for control_id, storage in control_storage.items()
    }
    natural_candidate = (
        controls[reference_id].candidate_states
        - controls["origin_mean_correction_removed"].candidate_states
    )
    natural_combined = (
        controls[reference_id].combined_states
        - controls["origin_mean_correction_removed"].combined_states
    )
    natural_prediction = (
        controls[reference_id].predictions
        - controls["origin_mean_correction_removed"].predictions
    )
    return StateDiagnosticAssimilationResult(
        lead_days=leads.copy(),
        origin_indices=origins,
        target_indices=targets,
        origin_candidate_prior_states=origin_prior_states,
        origin_candidate_posterior_states=origin_posterior_states,
        origin_candidate_state_corrections=origin_posterior_states - origin_prior_states,
        origin_candidate_prior_covariance_diagonals=origin_prior_covariance_diagonals,
        origin_candidate_posterior_covariance_diagonals=origin_posterior_covariance_diagonals,
        origin_prior_probabilities=origin_prior_probabilities,
        origin_posterior_probabilities=origin_posterior_probabilities,
        combined_origin_prior_states=combined_prior_states,
        combined_origin_posterior_states=combined_posterior_states,
        origin_state_update_contributions=state_update_contributions,
        origin_probability_reweighting_contributions=probability_reweighting_contributions,
        control_origin_candidate_prior_states=control_origin_arrays["prior_states"],
        control_origin_candidate_posterior_states=control_origin_arrays["posterior_states"],
        control_origin_candidate_prior_covariance_diagonals=control_origin_arrays[
            "prior_covariance_diagonals"
        ],
        control_origin_candidate_posterior_covariance_diagonals=control_origin_arrays[
            "posterior_covariance_diagonals"
        ],
        control_origin_prior_probabilities=control_origin_arrays["prior_probabilities"],
        control_origin_posterior_probabilities=control_origin_arrays["posterior_probabilities"],
        natural_hbv_candidate_state_correction=natural_candidate,
        natural_hbv_combined_state_correction=natural_combined,
        natural_hbv_combined_prediction_correction=natural_prediction,
        shared_origin_prior_validation={
            "compared_origin_count": int(origin_count),
            "compared_branch_count": int(len(masks) - 1),
            "maximum_candidate_state_absolute_difference": (
                maximum_shared_prior_state_difference
            ),
            "maximum_candidate_full_covariance_absolute_difference": (
                maximum_shared_prior_covariance_difference
            ),
            "maximum_model_probability_absolute_difference": (
                maximum_shared_prior_probability_difference
            ),
        },
        state_update_masks=masks,
        controls=controls,
    )


def diagnostic_result_arrays(result: StateDiagnosticAssimilationResult) -> dict[str, np.ndarray]:
    """Flatten a diagnostic result into an audit-friendly array mapping."""
    arrays = {
        "lead_days": result.lead_days.copy(),
        "origin_indices": result.origin_indices.copy(),
        "target_indices": result.target_indices.copy(),
        "origin_candidate_prior_states": result.origin_candidate_prior_states.copy(),
        "origin_candidate_posterior_states": result.origin_candidate_posterior_states.copy(),
        "origin_candidate_state_corrections": result.origin_candidate_state_corrections.copy(),
        "origin_candidate_prior_covariance_diagonals": (
            result.origin_candidate_prior_covariance_diagonals.copy()
        ),
        "origin_candidate_posterior_covariance_diagonals": (
            result.origin_candidate_posterior_covariance_diagonals.copy()
        ),
        "origin_prior_probabilities": result.origin_prior_probabilities.copy(),
        "origin_posterior_probabilities": result.origin_posterior_probabilities.copy(),
        "combined_origin_prior_states": result.combined_origin_prior_states.copy(),
        "combined_origin_posterior_states": result.combined_origin_posterior_states.copy(),
        "origin_state_update_contributions": result.origin_state_update_contributions.copy(),
        "origin_probability_reweighting_contributions": (
            result.origin_probability_reweighting_contributions.copy()
        ),
        "natural_hbv_candidate_state_correction": (
            result.natural_hbv_candidate_state_correction.copy()
        ),
        "natural_hbv_combined_state_correction": (
            result.natural_hbv_combined_state_correction.copy()
        ),
        "natural_hbv_combined_prediction_correction": (
            result.natural_hbv_combined_prediction_correction.copy()
        ),
        "shared_origin_prior_compared_origin_count": np.asarray(
            result.shared_origin_prior_validation["compared_origin_count"], dtype=np.int64
        ),
        "shared_origin_prior_compared_branch_count": np.asarray(
            result.shared_origin_prior_validation["compared_branch_count"], dtype=np.int64
        ),
        "shared_origin_prior_maximum_candidate_state_absolute_difference": np.asarray(
            result.shared_origin_prior_validation[
                "maximum_candidate_state_absolute_difference"
            ],
            dtype=np.float64,
        ),
        "shared_origin_prior_maximum_candidate_full_covariance_absolute_difference": np.asarray(
            result.shared_origin_prior_validation[
                "maximum_candidate_full_covariance_absolute_difference"
            ],
            dtype=np.float64,
        ),
        "shared_origin_prior_maximum_model_probability_absolute_difference": np.asarray(
            result.shared_origin_prior_validation[
                "maximum_model_probability_absolute_difference"
            ],
            dtype=np.float64,
        ),
    }
    for control_id, mask in result.state_update_masks.items():
        arrays[f"{control_id}__state_update_mask"] = mask.copy()
        arrays[f"{control_id}__origin_candidate_prior_states"] = (
            result.control_origin_candidate_prior_states[control_id].copy()
        )
        arrays[f"{control_id}__origin_candidate_posterior_states"] = (
            result.control_origin_candidate_posterior_states[control_id].copy()
        )
        arrays[f"{control_id}__origin_candidate_prior_covariance_diagonals"] = (
            result.control_origin_candidate_prior_covariance_diagonals[control_id].copy()
        )
        arrays[f"{control_id}__origin_candidate_posterior_covariance_diagonals"] = (
            result.control_origin_candidate_posterior_covariance_diagonals[control_id].copy()
        )
        arrays[f"{control_id}__origin_prior_probabilities"] = (
            result.control_origin_prior_probabilities[control_id].copy()
        )
        arrays[f"{control_id}__origin_posterior_probabilities"] = (
            result.control_origin_posterior_probabilities[control_id].copy()
        )
    for control_id, control in result.controls.items():
        arrays[f"{control_id}__predictions"] = control.predictions.copy()
        arrays[f"{control_id}__candidate_predictions"] = control.candidate_predictions.copy()
        arrays[f"{control_id}__probabilities"] = control.probabilities.copy()
        arrays[f"{control_id}__candidate_states"] = control.candidate_states.copy()
        arrays[f"{control_id}__candidate_covariance_diagonals"] = (
            control.candidate_covariance_diagonals.copy()
        )
        arrays[f"{control_id}__combined_states"] = control.combined_states.copy()
        arrays[f"{control_id}__combined_covariance_diagonals"] = (
            control.combined_covariance_diagonals.copy()
        )
        if control.origin_retention is not None:
            arrays[f"{control_id}__origin_retention"] = control.origin_retention.copy()
    return arrays


def hbv_water_balance_residual(
    state,
    rain: float,
    pet: float,
    temperature: float,
    parameters: Mapping[str, float],
) -> dict[str, float]:
    """Independently evaluate one deterministic HBV-lite water balance."""
    current = project_hbv_state(state, parameters)
    precipitation = float(rain)
    potential_evaporation = float(pet)
    air_temperature = float(temperature)
    if (
        not np.all(np.isfinite([precipitation, potential_evaporation, air_temperature]))
        or precipitation < 0.0
        or potential_evaporation < 0.0
    ):
        raise ValueError("rain and potential evaporation must be finite and nonnegative")
    p = {name: float(value) for name, value in parameters.items()}
    required = (
        "parTT",
        "parCFMAX",
        "parCFR",
        "parCWH",
        "parFC",
        "parBETA",
        "parLP",
    )
    if any(name not in p for name in required):
        raise ValueError(f"parameters must include {required}")

    snowpack, meltwater, soil = (float(value) for value in current[:3])
    eps = 1e-5
    if air_temperature < p["parTT"]:
        snowfall = precipitation
        rainfall = 0.0
    else:
        snowfall = 0.0
        rainfall = precipitation
    snowpack += snowfall
    melt = np.clip(p["parCFMAX"] * (air_temperature - p["parTT"]), 0.0, snowpack)
    meltwater += float(melt)
    snowpack -= float(melt)
    refreezing = np.clip(
        p["parCFR"] * p["parCFMAX"] * (p["parTT"] - air_temperature),
        0.0,
        meltwater,
    )
    snowpack += float(refreezing)
    meltwater -= float(refreezing)
    to_soil = max(meltwater - p["parCWH"] * snowpack, 0.0)
    meltwater -= to_soil
    soil_wetness = np.clip(soil / (p["parFC"] + eps), 0.0, 1.0) ** p["parBETA"]
    recharge = (rainfall + to_soil) * soil_wetness
    soil += rainfall + to_soil - recharge
    excess = max(soil - p["parFC"], 0.0)
    soil -= excess
    evaporation_factor = np.clip(soil / (p["parLP"] * p["parFC"] + eps), 0.0, 1.0)
    actual_evaporation = min(potential_evaporation * evaporation_factor, soil)

    next_state = advance_state(
        current,
        precipitation,
        potential_evaporation,
        air_temperature,
        dict(parameters),
    )
    storage_before = float(np.sum(current[:HYDROLOGIC_STATE_COUNT]))
    storage_after = float(np.sum(next_state[:HYDROLOGIC_STATE_COUNT]))
    storage_change = storage_after - storage_before
    raw_runoff = float(next_state[HYDROLOGIC_STATE_COUNT])
    residual = storage_change - (precipitation - actual_evaporation - raw_runoff)
    return {
        "storage_before_mm": storage_before,
        "storage_after_mm": storage_after,
        "storage_change_mm": storage_change,
        "precipitation_mm": precipitation,
        "actual_evaporation_mm": float(actual_evaporation),
        "raw_runoff_mm": raw_runoff,
        "residual_mm": float(residual),
        "absolute_residual_mm": abs(float(residual)),
    }


def evaluate_continuation_gate(
    rows,
    expected_basin_count: int = 16,
    gate_control_id: str = "hydrologic_five_states_only",
) -> dict:
    """Apply the frozen three-part gate after per-basin percentage changes."""
    records = [dict(row) for row in rows]
    selected_control = str(gate_control_id)
    if not selected_control:
        raise ValueError("continuation gate control identifier must be nonempty")
    basin_ids = sorted({str(row.get("basin_id")) for row in records})
    if len(basin_ids) != int(expected_basin_count):
        raise ValueError(f"continuation gate requires exactly {expected_basin_count} basins")

    def one_row(basin_id: str, control_id: str, lead_days: int) -> dict:
        matches = [
            row
            for row in records
            if str(row.get("basin_id")) == basin_id
            and str(row.get("control_id")) == control_id
            and int(row.get("lead_days")) == lead_days
        ]
        if len(matches) != 1:
            raise ValueError(
                f"continuation gate requires one row for {basin_id}, {control_id}, lead {lead_days}"
            )
        value = float(matches[0]["rmse"])
        if not np.isfinite(value) or value <= 0.0:
            raise ValueError("continuation gate root-mean-square errors must be finite and positive")
        return matches[0]

    seven_day_changes = []
    one_day_changes = []
    seven_day_wins = 0
    per_basin = []
    for basin_id in basin_ids:
        open_loop_seven = float(one_row(basin_id, "open_loop", 7)["rmse"])
        control_seven = float(one_row(basin_id, selected_control, 7)["rmse"])
        joint_one = float(one_row(basin_id, "current_joint_all_fifteen_states", 1)["rmse"])
        control_one = float(one_row(basin_id, selected_control, 1)["rmse"])
        seven_change = 100.0 * (control_seven - open_loop_seven) / open_loop_seven
        one_change = 100.0 * (control_one - joint_one) / joint_one
        strict_win = control_seven < open_loop_seven
        seven_day_changes.append(seven_change)
        one_day_changes.append(one_change)
        seven_day_wins += int(strict_win)
        per_basin.append(
            {
                "basin_id": basin_id,
                "seven_day_rmse_change_percent_vs_open_loop": seven_change,
                "seven_day_strict_win_vs_open_loop": strict_win,
                "one_day_rmse_increase_percent_vs_current_joint": one_change,
            }
        )
    seven_median = float(np.median(seven_day_changes))
    one_median = float(np.median(one_day_changes))
    conditions = {
        "seven_day_median_not_above_zero": seven_median <= 0.0,
        "seven_day_at_least_nine_strict_wins": seven_day_wins >= 9,
        "one_day_median_increase_not_above_one_percent": one_median <= 1.0,
    }
    passed = bool(all(conditions.values()))
    return {
        "expected_basin_count": int(expected_basin_count),
        "gate_control_id": selected_control,
        "percentages_computed_per_basin_before_median": True,
        "seven_day_median_rmse_change_percent_vs_open_loop": seven_median,
        "seven_day_strict_win_count_vs_open_loop": seven_day_wins,
        "one_day_median_rmse_increase_percent_vs_current_joint": one_median,
        "conditions": conditions,
        "all_conditions_passed": passed,
        "recommend_larger_sample": passed,
        "run_531_automatically": False,
        "per_basin": per_basin,
    }
