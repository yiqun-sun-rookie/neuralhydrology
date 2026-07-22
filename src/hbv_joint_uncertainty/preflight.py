"""Core construction and execution for the bounded daily preflight."""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping, Sequence

import numpy as np
import pandas as pd

from .candidates import CandidateDefinition
from .hbv_adapter import HYDRO_STATE_NAMES, STATE_NAMES, advance_state, routed_discharge, simulate_adapter
from .imm import InteractingMultipleModel
from .sigma_filter import ModifiedUnscentedFilter


def _state_vector(values, label: str = "state") -> np.ndarray:
    vector = np.asarray(values, dtype=np.float64)
    if vector.shape != (len(STATE_NAMES),):
        raise ValueError(f"{label} must have shape ({len(STATE_NAMES)},), got {vector.shape}")
    if not np.all(np.isfinite(vector)):
        raise ValueError(f"{label} must contain only finite values")
    return vector


def project_hbv_state(state, parameters: Mapping[str, float]) -> np.ndarray:
    """Project one fifteen-state vector onto the HBV-lite physical domain."""
    projected = _state_vector(state).copy()
    snow = max(float(projected[0]), 0.0)
    maximum_meltwater = float(parameters["parCWH"]) * snow
    projected[0] = snow
    projected[1] = np.clip(projected[1], 0.0, maximum_meltwater)
    projected[2] = np.clip(projected[2], 1e-5, float(parameters["parFC"]))
    projected[3:] = np.maximum(projected[3:], 0.0)
    if not np.all(np.isfinite(projected)):
        raise ValueError("projected HBV-lite state is non-finite")
    return projected


def build_process_covariance(parameters: Mapping[str, float], variance_scale: float) -> np.ndarray:
    """Build diagonal process covariance with exact routing-memory zeros."""
    scale = float(variance_scale)
    if not np.isfinite(scale) or scale <= 0.0:
        raise ValueError("variance_scale must be finite and positive")
    field_capacity = float(parameters["parFC"])
    hydrologic_scales = np.array(
        [
            field_capacity,
            max(float(parameters["parCWH"]) * field_capacity, 1.0),
            field_capacity,
            max(float(parameters["parUZL"]), float(parameters["parPERC"]), 1.0),
            max(float(parameters["parPERC"]) / float(parameters["parK2"]), 1.0),
        ],
        dtype=np.float64,
    )
    diagonal = np.zeros(len(STATE_NAMES), dtype=np.float64)
    diagonal[:5] = scale * hydrologic_scales**2
    return np.diag(diagonal)


def build_transition_matrix(candidate_count: int, diagonal: float) -> np.ndarray:
    """Return a row-stochastic symmetric candidate transition matrix."""
    count = int(candidate_count)
    stay = float(diagonal)
    if count <= 0:
        raise ValueError("candidate_count must be positive")
    if count == 1:
        return np.ones((1, 1), dtype=np.float64)
    if not np.isfinite(stay) or stay < 0.0 or stay > 1.0:
        raise ValueError("diagonal must be finite and between zero and one")
    off_diagonal = (1.0 - stay) / (count - 1)
    matrix = np.full((count, count), off_diagonal, dtype=np.float64)
    np.fill_diagonal(matrix, stay)
    matrix /= matrix.sum(axis=1, keepdims=True)
    return matrix


class ForcingTransition:
    """HBV-lite transition with daily forcing assigned before each filter step."""

    def __init__(self, parameters: Mapping[str, float]):
        self.parameters = dict(parameters)
        self._forcing: tuple[float, float, float] | None = None

    def set_forcing(self, rain: float, pet: float, temperature: float) -> None:
        forcing = np.asarray([rain, pet, temperature], dtype=np.float64)
        if not np.all(np.isfinite(forcing)):
            raise ValueError("daily forcing must contain only finite values")
        self._forcing = tuple(float(value) for value in forcing)

    def __call__(self, state: np.ndarray) -> np.ndarray:
        if self._forcing is None:
            raise RuntimeError("daily forcing must be assigned before transition")
        rain, pet, temperature = self._forcing
        physical = project_hbv_state(state, self.parameters)
        return project_hbv_state(
            advance_state(physical, rain, pet, temperature, self.parameters),
            self.parameters,
        )


class RoutedDischargeObservation:
    """Candidate-specific routed discharge observation."""

    def __init__(self, parameters: Mapping[str, float]):
        self.parameters = dict(parameters)

    def __call__(self, state: np.ndarray) -> np.ndarray:
        physical = project_hbv_state(state, self.parameters)
        return np.array([routed_discharge(physical, self.parameters["lag_time"])], dtype=np.float64)


@dataclass(frozen=True)
class CandidateBank:
    estimator: InteractingMultipleModel
    transitions: tuple[ForcingTransition, ...]
    definitions: tuple[CandidateDefinition, ...]


@dataclass(frozen=True)
class AssimilationResult:
    prior_discharge: np.ndarray
    candidate_prior_discharge: np.ndarray
    prior_probabilities: np.ndarray
    posterior_probabilities: np.ndarray
    combined_states: np.ndarray


@dataclass(frozen=True)
class WarmupAudit:
    parameter_id: str
    maximum_discharge_error: float
    maximum_final_store_error: float
    maximum_saved_state_error: float | None = None


@dataclass(frozen=True)
class BasinPreflightResult:
    basin_id: str
    dates: np.ndarray
    observations: np.ndarray
    assimilation: AssimilationResult
    definitions: tuple[CandidateDefinition, ...]
    warmup_audits: tuple[WarmupAudit, ...]


def warm_parameter_states(
    rain,
    pet,
    temp,
    definitions: Sequence[CandidateDefinition],
    tolerance: float = 1e-8,
    authoritative_simulator=None,
    expected_final_stores: Mapping[str, Sequence[float] | Mapping[str, float]] | None = None,
) -> tuple[dict[str, np.ndarray], tuple[WarmupAudit, ...]]:
    """Warm each unique parameter vector and enforce adapter equivalence."""
    if authoritative_simulator is None:
        from scl_hydro.hbv_lite_numpy import simulate_hbv_lite

        authoritative_simulator = simulate_hbv_lite
    rain_values = np.asarray(rain, dtype=np.float64)
    pet_values = np.asarray(pet, dtype=np.float64)
    temperature_values = np.asarray(temp, dtype=np.float64)
    if rain_values.ndim != 1 or rain_values.shape != pet_values.shape or rain_values.shape != temperature_values.shape:
        raise ValueError("warmup rain, pet, and temp must be one-dimensional arrays with identical shape")
    if len(rain_values) == 0:
        raise ValueError("warmup period must contain at least one day")
    if not np.all(np.isfinite(np.concatenate((rain_values, pet_values, temperature_values)))):
        raise ValueError("warmup forcing must contain only finite values")
    allowed_error = float(tolerance)
    if not np.isfinite(allowed_error) or allowed_error < 0.0:
        raise ValueError("tolerance must be finite and nonnegative")

    unique_parameters: dict[str, dict[str, float]] = {}
    for definition in definitions:
        existing = unique_parameters.get(definition.parameter_id)
        if existing is not None and existing != definition.parameters:
            raise ValueError(f"parameter identifier {definition.parameter_id!r} has conflicting vectors")
        unique_parameters[definition.parameter_id] = definition.parameters
    if not unique_parameters:
        raise ValueError("definitions must be nonempty")
    expected_stores = dict(expected_final_stores or {})
    unknown_expected = set(expected_stores) - set(unique_parameters)
    if unknown_expected:
        raise ValueError(f"saved warmup states reference unknown parameter identifiers: {sorted(unknown_expected)}")

    states = {}
    audits = []
    for parameter_id, parameters in unique_parameters.items():
        reference_discharge, reference_final = authoritative_simulator(
            rain_values,
            pet_values,
            temperature_values,
            parameters,
        )
        adapter_discharge, adapter_states = simulate_adapter(
            rain_values,
            pet_values,
            temperature_values,
            parameters,
        )
        reference_discharge = np.asarray(reference_discharge, dtype=np.float64)
        reference_stores = np.array(
            [reference_final[name] for name in HYDRO_STATE_NAMES],
            dtype=np.float64,
        )
        discharge_error = float(np.max(np.abs(adapter_discharge - reference_discharge)))
        store_error = float(np.max(np.abs(adapter_states[-1, :5] - reference_stores)))
        if not np.all(np.isfinite([discharge_error, store_error])):
            raise ValueError(f"adapter equivalence for {parameter_id} produced non-finite errors")
        if max(discharge_error, store_error) > allowed_error:
            raise ValueError(
                f"adapter equivalence failed for {parameter_id}: discharge error={discharge_error}, "
                f"final-store error={store_error}, tolerance={allowed_error}"
            )
        saved_state_error = None
        if parameter_id in expected_stores:
            expected = expected_stores[parameter_id]
            if isinstance(expected, Mapping):
                expected = [expected[name] for name in HYDRO_STATE_NAMES]
            expected_vector = np.asarray(expected, dtype=np.float64)
            if expected_vector.shape != (len(HYDRO_STATE_NAMES),) or not np.all(np.isfinite(expected_vector)):
                raise ValueError(f"saved warmup state for {parameter_id} must contain five finite stores")
            saved_state_error = float(np.max(np.abs(adapter_states[-1, :5] - expected_vector)))
            if saved_state_error > allowed_error:
                raise ValueError(
                    f"saved warmup state mismatch for {parameter_id}: error={saved_state_error}, "
                    f"tolerance={allowed_error}"
                )
        states[parameter_id] = adapter_states[-1].copy()
        audits.append(
            WarmupAudit(
                parameter_id=parameter_id,
                maximum_discharge_error=discharge_error,
                maximum_final_store_error=store_error,
                maximum_saved_state_error=saved_state_error,
            )
        )
    return states, tuple(audits)


def build_candidate_bank(
    definitions: Sequence[CandidateDefinition],
    initial_states: Mapping[str, np.ndarray],
    config: Mapping,
) -> CandidateBank:
    """Construct the nine-filter bank from warmed parameter-specific states."""
    candidates = tuple(definitions)
    if not candidates:
        raise ValueError("definitions must be nonempty")
    covariance_fraction = float(config["initial_covariance_fraction"])
    observation_standard_deviation = float(config["observation_standard_deviation_mm_day"])
    if covariance_fraction <= 0.0 or observation_standard_deviation <= 0.0:
        raise ValueError("covariance fraction and observation standard deviation must be positive")

    filters = []
    transitions = []
    for definition in candidates:
        if definition.parameter_id not in initial_states:
            raise ValueError(f"missing warmed state for parameter vector {definition.parameter_id!r}")
        state = project_hbv_state(initial_states[definition.parameter_id], definition.parameters)
        state_scales = np.maximum(np.abs(state), 1.0)
        initial_covariance = np.diag((covariance_fraction * state_scales)**2)
        transition = ForcingTransition(definition.parameters)
        observation = RoutedDischargeObservation(definition.parameters)
        projector = lambda values, p=definition.parameters: project_hbv_state(values, p)
        filters.append(
            ModifiedUnscentedFilter(
                state=state,
                covariance=initial_covariance,
                transition=transition,
                observation=observation,
                process_covariance=build_process_covariance(
                    definition.parameters, definition.noise_variance_scale
                ),
                observation_covariance=np.array([[observation_standard_deviation**2]]),
                state_projector=projector,
                alpha=0.6874,
                beta=2.0,
                kappa=-2.0,
            )
        )
        transitions.append(transition)

    transition_matrix = build_transition_matrix(len(candidates), float(config["transition_diagonal"]))
    estimator = InteractingMultipleModel(
        filters=filters,
        transition_matrix=transition_matrix,
        initial_probabilities=np.full(len(candidates), 1.0 / len(candidates), dtype=np.float64),
        parameter_groups=[definition.parameter_group for definition in candidates],
    )
    return CandidateBank(estimator=estimator, transitions=tuple(transitions), definitions=candidates)


def run_assimilation(
    rain,
    pet,
    temp,
    observations,
    bank: CandidateBank,
    monitor_callback: Callable[[int, int], None] | None = None,
    monitor_interval_seconds: float = 60.0,
) -> AssimilationResult:
    """Run a finite contiguous daily series and retain forecast-before-update values."""
    rain_values = np.asarray(rain, dtype=np.float64)
    pet_values = np.asarray(pet, dtype=np.float64)
    temperature_values = np.asarray(temp, dtype=np.float64)
    observed_values = np.asarray(observations, dtype=np.float64)
    shapes = {values.shape for values in (rain_values, pet_values, temperature_values, observed_values)}
    if len(shapes) != 1 or rain_values.ndim != 1:
        raise ValueError("rain, pet, temp, and observations must be one-dimensional arrays with identical shape")
    if not np.all(np.isfinite(np.concatenate((rain_values, pet_values, temperature_values, observed_values)))):
        raise ValueError("assimilation inputs must contain only finite values")

    n_days = len(rain_values)
    if n_days == 0:
        raise ValueError("assimilation period must contain at least one day")
    interval = float(monitor_interval_seconds)
    if not np.isfinite(interval) or interval <= 0.0:
        raise ValueError("monitor_interval_seconds must be finite and positive")
    n_candidates = len(bank.definitions)
    prior_discharge = np.empty(n_days, dtype=np.float64)
    candidate_prior_discharge = np.empty((n_days, n_candidates), dtype=np.float64)
    prior_probabilities = np.empty((n_days, n_candidates), dtype=np.float64)
    posterior_probabilities = np.empty((n_days, n_candidates), dtype=np.float64)
    combined_states = np.empty((n_days, len(STATE_NAMES)), dtype=np.float64)

    last_monitor = time.monotonic()
    if monitor_callback is not None:
        monitor_callback(0, n_days)
    last_reported_day = 0
    for day in range(n_days):
        for transition in bank.transitions:
            transition.set_forcing(rain_values[day], pet_values[day], temperature_values[day])
        step = bank.estimator.step(observed_values[day])
        prior_discharge[day] = float(step.combined_prior_observation[0])
        candidate_prior_discharge[day] = [
            float(candidate.prior_observation[0]) for candidate in step.candidate_results
        ]
        prior_probabilities[day] = step.prior_probabilities
        posterior_probabilities[day] = step.posterior_probabilities
        combined_states[day] = step.combined_state
        if monitor_callback is not None and time.monotonic() - last_monitor >= interval:
            monitor_callback(day + 1, n_days)
            last_monitor = time.monotonic()
            last_reported_day = day + 1

    if monitor_callback is not None and last_reported_day != n_days:
        monitor_callback(n_days, n_days)

    if np.max(np.abs(posterior_probabilities.sum(axis=1) - 1.0), initial=0.0) > 1e-12:
        raise ValueError("saved posterior probabilities do not sum to one within 1e-12")
    if np.max(np.abs(prior_probabilities.sum(axis=1) - 1.0), initial=0.0) > 1e-12:
        raise ValueError("saved prior probabilities do not sum to one within 1e-12")
    reconstructed_prior = np.sum(prior_probabilities * candidate_prior_discharge, axis=1)
    if not np.allclose(prior_discharge, reconstructed_prior, rtol=1e-12, atol=1e-12):
        raise ValueError("combined prior discharge is not the weighted forecast before the observation update")
    if not all(
        np.all(np.isfinite(values))
        for values in (
            prior_discharge,
            candidate_prior_discharge,
            prior_probabilities,
            posterior_probabilities,
            combined_states,
        )
    ):
        raise ValueError("assimilation result contains non-finite values")
    return AssimilationResult(
        prior_discharge=prior_discharge,
        candidate_prior_discharge=candidate_prior_discharge,
        prior_probabilities=prior_probabilities,
        posterior_probabilities=posterior_probabilities,
        combined_states=combined_states,
    )


def _load_complete_period(
    basin_id: str,
    config: Mapping,
    repo_root: Path,
    start_date: str,
    end_date: str,
    data_loader,
) -> tuple[pd.DataFrame, pd.Series]:
    data_root = Path(config["data_root"])
    if not data_root.is_absolute():
        data_root = Path(repo_root) / data_root
    forcing, observations, _ = data_loader(
        basin_id,
        data_root=data_root,
        start_date=start_date,
        end_date=end_date,
        forcing=config["parameter_source"]["forcing"],
        pet_method=config["parameter_source"]["pet_method"],
        keep_obs_nan_days=True,
    )
    expected_index = pd.date_range(start_date, end_date, freq="D")
    if not forcing.index.equals(expected_index) or not observations.index.equals(expected_index):
        raise ValueError(
            f"basin {basin_id} period {start_date} through {end_date} is not a complete contiguous daily series"
        )
    required_columns = ["prcp", "ep", "tmean"]
    if any(column not in forcing.columns for column in required_columns):
        raise ValueError(f"basin {basin_id} forcing is missing one of {required_columns}")
    if not np.all(np.isfinite(forcing[required_columns].to_numpy(dtype=np.float64))):
        raise ValueError(f"basin {basin_id} forcing contains non-finite values")
    return forcing, observations


def run_basin_preflight(
    basin_id: str,
    definitions: Sequence[CandidateDefinition],
    config: Mapping,
    repo_root: Path,
    max_days: int | None = None,
    data_loader=None,
    monitor_callback: Callable[[int, int], None] | None = None,
    expected_center_stores: Sequence[float] | Mapping[str, float] | None = None,
) -> BasinPreflightResult:
    """Load, warm, and assimilate one frozen daily basin period."""
    if data_loader is None:
        from hydroagent.data_loading import load_camels_basin

        data_loader = load_camels_basin
    warm_forcing, _ = _load_complete_period(
        basin_id,
        config,
        repo_root,
        config["warmup_start"],
        config["warmup_end"],
        data_loader,
    )
    evaluation_forcing, observations = _load_complete_period(
        basin_id,
        config,
        repo_root,
        config["evaluation_start"],
        config["evaluation_end"],
        data_loader,
    )
    if observations.isna().any() or not np.all(np.isfinite(observations.to_numpy(dtype=np.float64))):
        missing_count = int(observations.isna().sum())
        raise ValueError(f"basin {basin_id} has {missing_count} missing evaluation observation days")
    if max_days is not None:
        limit = int(max_days)
        if limit <= 0:
            raise ValueError("max_days must be positive")
        evaluation_forcing = evaluation_forcing.iloc[:limit]
        observations = observations.iloc[:limit]

    candidates = tuple(definitions)
    warmed_states, audits = warm_parameter_states(
        warm_forcing["prcp"].to_numpy(dtype=np.float64),
        warm_forcing["ep"].to_numpy(dtype=np.float64),
        warm_forcing["tmean"].to_numpy(dtype=np.float64),
        candidates,
        tolerance=1e-8,
        expected_final_stores=(
            {"trained_center": expected_center_stores} if expected_center_stores is not None else None
        ),
    )
    bank = build_candidate_bank(candidates, warmed_states, config)
    assimilation = run_assimilation(
        evaluation_forcing["prcp"].to_numpy(dtype=np.float64),
        evaluation_forcing["ep"].to_numpy(dtype=np.float64),
        evaluation_forcing["tmean"].to_numpy(dtype=np.float64),
        observations.to_numpy(dtype=np.float64),
        bank,
        monitor_callback=monitor_callback,
        monitor_interval_seconds=float(config["resource"]["monitor_interval_seconds"]),
    )
    return BasinPreflightResult(
        basin_id=str(basin_id).zfill(8),
        dates=evaluation_forcing.index.strftime("%Y-%m-%d").to_numpy(),
        observations=observations.to_numpy(dtype=np.float64),
        assimilation=assimilation,
        definitions=candidates,
        warmup_audits=audits,
    )
