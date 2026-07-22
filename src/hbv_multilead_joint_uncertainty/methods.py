"""Matched candidate contracts for the five attribution methods."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

import numpy as np

from hbv_joint_uncertainty.candidates import CandidateDefinition
from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES
from hbv_joint_uncertainty.imm import InteractingMultipleModel
from hbv_joint_uncertainty.preflight import (
    CandidateBank,
    ForcingTransition,
    RoutedDischargeObservation,
    build_transition_matrix,
    project_hbv_state,
)
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter


METHOD_ORDER = ("open_loop", "fixed_filter", "parameter_only", "noise_only", "joint")
PARAMETER_ORDER = ("equifinal_diverse_1", "trained_center", "equifinal_diverse_2")
LEGACY_PARAMETER_ORDER = ("equifinal_low_flow", "trained_center", "equifinal_high_flow")
SUPPORTED_PARAMETER_ORDERS = (PARAMETER_ORDER, LEGACY_PARAMETER_ORDER)


def parameter_order_from_identifiers(parameter_ids) -> tuple[str, str, str]:
    """Return the canonical order for a current or legacy three-vector contract."""
    identifiers = tuple(str(value) for value in parameter_ids)
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("parameter identifiers must be unique")
    identifier_set = set(identifiers)
    for order in SUPPORTED_PARAMETER_ORDERS:
        if identifier_set == set(order):
            return order
    raise ValueError("parameter identifiers do not match a supported frozen contract")


@dataclass(frozen=True)
class MethodCandidate:
    candidate_id: str
    parameter_id: str
    process_id: str
    process_scale: float
    parameters: dict[str, float]
    process_covariance: np.ndarray


def build_factorial_transition_matrix(
    candidates: Sequence[MethodCandidate],
    factor_stay_probability: float,
) -> np.ndarray:
    """Give parameter and process-noise factors the same marginal transition prior."""
    definitions = tuple(candidates)
    if not definitions:
        raise ValueError("candidates must be nonempty")
    parameter_ids = tuple(dict.fromkeys(candidate.parameter_id for candidate in definitions))
    process_ids = tuple(dict.fromkeys(candidate.process_id for candidate in definitions))
    expected = {(parameter_id, process_id) for parameter_id in parameter_ids for process_id in process_ids}
    actual = {(candidate.parameter_id, candidate.process_id) for candidate in definitions}
    if len(actual) != len(definitions) or actual != expected:
        raise ValueError("candidates must form one complete parameter-by-process grid")
    parameter_transition = build_transition_matrix(len(parameter_ids), float(factor_stay_probability))
    process_transition = build_transition_matrix(len(process_ids), float(factor_stay_probability))
    parameter_index = {identifier: index for index, identifier in enumerate(parameter_ids)}
    process_index = {identifier: index for index, identifier in enumerate(process_ids)}
    matrix = np.empty((len(definitions), len(definitions)), dtype=np.float64)
    for source_index, source in enumerate(definitions):
        for destination_index, destination in enumerate(definitions):
            matrix[source_index, destination_index] = (
                parameter_transition[
                    parameter_index[source.parameter_id], parameter_index[destination.parameter_id]
                ]
                * process_transition[process_index[source.process_id], process_index[destination.process_id]]
            )
    return matrix


def _validated_parameters(values: Mapping[str, float], parameter_id: str) -> dict[str, float]:
    if set(values) != set(PARAMETER_NAMES):
        raise ValueError(f"parameter vector {parameter_id} must contain exactly thirteen values")
    parameters = {name: float(values[name]) for name in PARAMETER_NAMES}
    if not np.all(np.isfinite(list(parameters.values()))):
        raise ValueError(f"parameter vector {parameter_id} must be finite")
    return parameters


def _validated_process_contract(process_scales, process_covariances):
    if set(process_scales) != set(process_covariances) or len(process_scales) != 3:
        raise ValueError("process contract must contain exactly three matching identifiers")
    result = {}
    scales = {}
    for process_id in process_scales:
        scale = float(process_scales[process_id])
        covariance = np.asarray(process_covariances[process_id], dtype=np.float64)
        if covariance.shape != (15, 15):
            raise ValueError(f"process covariance {process_id} must be a 15 by 15 matrix")
        if not np.all(np.isfinite(covariance)) or not np.allclose(covariance, covariance.T, rtol=0.0, atol=1e-12):
            raise ValueError(f"process covariance {process_id} must be finite and symmetric")
        if np.min(np.linalg.eigvalsh(covariance)) < -1e-12 or not np.isfinite(scale) or scale <= 0.0:
            raise ValueError(f"process contract {process_id} must have positive scale and semidefinite covariance")
        scales[process_id] = scale
        result[process_id] = covariance.copy()
    return scales, result


def build_method_definitions(
    parameter_vectors: Mapping[str, Mapping[str, float]],
    process_scales: Mapping[str, float],
    process_covariances: Mapping[str, np.ndarray],
    selected_process_id: str,
) -> dict[str, tuple[MethodCandidate, ...]]:
    parameter_order = parameter_order_from_identifiers(parameter_vectors)
    parameters = {
        parameter_id: _validated_parameters(parameter_vectors[parameter_id], parameter_id)
        for parameter_id in parameter_order
    }
    scales, covariances = _validated_process_contract(process_scales, process_covariances)
    if selected_process_id not in scales:
        raise ValueError("selected_process_id is outside the process contract")

    def candidate(parameter_id: str, process_id: str) -> MethodCandidate:
        return MethodCandidate(
            candidate_id=f"{parameter_id}__{process_id}",
            parameter_id=parameter_id,
            process_id=process_id,
            process_scale=scales[process_id],
            parameters=parameters[parameter_id].copy(),
            process_covariance=covariances[process_id].copy(),
        )

    center = "trained_center"
    open_loop = (candidate(center, selected_process_id),)
    fixed_filter = (candidate(center, selected_process_id),)
    parameter_only = tuple(candidate(parameter_id, selected_process_id) for parameter_id in parameter_order)
    noise_only = tuple(candidate(center, process_id) for process_id in scales)
    joint = tuple(candidate(parameter_id, process_id) for parameter_id in parameter_order for process_id in scales)
    return {
        "open_loop": open_loop,
        "fixed_filter": fixed_filter,
        "parameter_only": parameter_only,
        "noise_only": noise_only,
        "joint": joint,
    }


def build_method_bank(
    candidates: Sequence[MethodCandidate],
    initial_states: Mapping[str, np.ndarray],
    initial_covariance,
    observation_standard_deviation: float,
    factor_transition_stay_probability: float,
    interaction_mode: str = "full",
) -> CandidateBank:
    definitions = tuple(candidates)
    if not definitions:
        raise ValueError("candidates must be nonempty")
    covariance = np.asarray(initial_covariance, dtype=np.float64)
    if covariance.shape != (15, 15) or not np.all(np.isfinite(covariance)):
        raise ValueError("initial_covariance must be a finite 15 by 15 matrix")
    if not np.allclose(covariance, covariance.T, rtol=0.0, atol=1e-12):
        raise ValueError("initial_covariance must be symmetric")
    observation_std = float(observation_standard_deviation)
    if not np.isfinite(observation_std) or observation_std <= 0.0:
        raise ValueError("observation_standard_deviation must be finite and positive")
    if interaction_mode not in {"full", "parameter_grouped", "none"}:
        raise ValueError("interaction_mode must be full, parameter_grouped, or none")

    filters = []
    transitions = []
    old_definitions = []
    for definition in definitions:
        if definition.parameter_id not in initial_states:
            raise ValueError(f"missing initial state for {definition.parameter_id}")
        state = project_hbv_state(initial_states[definition.parameter_id], definition.parameters)
        transition = ForcingTransition(definition.parameters)
        observation = RoutedDischargeObservation(definition.parameters)
        projector = lambda values, parameters=definition.parameters: project_hbv_state(values, parameters)
        filters.append(
            ModifiedUnscentedFilter(
                state=state,
                covariance=covariance.copy(),
                transition=transition,
                observation=observation,
                process_covariance=definition.process_covariance.copy(),
                observation_covariance=np.array([[observation_std**2]], dtype=np.float64),
                state_projector=projector,
                alpha=0.6874,
                beta=2.0,
                kappa=-2.0,
            )
        )
        transitions.append(transition)
        old_definitions.append(
            CandidateDefinition(
                candidate_id=definition.candidate_id,
                parameter_id=definition.parameter_id,
                noise_variance_scale=definition.process_scale,
                parameters=definition.parameters.copy(),
                parameter_group=tuple(definition.parameters[name] for name in PARAMETER_NAMES),
            )
        )
    transition_matrix = build_factorial_transition_matrix(
        definitions,
        float(factor_transition_stay_probability),
    )
    estimator = InteractingMultipleModel(
        filters=filters,
        transition_matrix=transition_matrix,
        initial_probabilities=np.full(len(filters), 1.0 / len(filters), dtype=np.float64),
        parameter_groups=[definition.parameter_group for definition in old_definitions],
    )
    estimator.interaction_mode = interaction_mode
    return CandidateBank(
        estimator=estimator,
        transitions=tuple(transitions),
        definitions=tuple(old_definitions),
    )
