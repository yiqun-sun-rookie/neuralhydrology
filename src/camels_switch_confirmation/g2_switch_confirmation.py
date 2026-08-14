"""G2: large-sample parameter-switch confirmation run (frozen config g2_frozen_v01).

Per (basin, seed): generate the 15-state synthetic truth with the frozen
rotation and SLZ lognormal noise, synthesize observations, run the 3-member
rising-kernel IMM bank, evaluate the 6 directed switch events against the
id23-verbatim rule, and write per-event verdicts. The main process joins the
outcomes with the frozen G1 prediction labels into the transfer confusion
matrix.

Usage:
    python -X utf8 -m src.camels_switch_confirmation.g2_switch_confirmation --workers 6
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

for _v in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
           "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[2]
if str(_REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "src"))
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from camels_switch_confirmation.g1_precheck import (  # noqa: E402
    LAG_KERNEL, N_SEEDS, PARAM_KEYS, ROTATION, RISING_TABLE, SEED_ENTROPY,
    STAGE_DAYS, STATE_NAMES, WINDOW_DAYS, WINDOW_START, _window_end,
)
from camels_switch_confirmation.batch_control import execute_fail_fast  # noqa: E402

# ---- legacy G2 reference; v01 is historical and does not certify new runs ----
FROZEN_CONFIG = "src/camels_switch_confirmation/configs/g2_frozen_v01.json"
G1_CSV = "results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.csv"
OUT_DIR = "results/23_camels_switch_confirmation/g2_switch_confirmation_v01"
BOUNDS_PRESET = "v5"
LAG_CAP = 10.0
SLZ_LOGNORMAL_SIGMA = 0.02
PROCESS_VARIANCE_SCALE = 1e-4
PROCESS_COVARIANCE_STRUCTURE = "all_hydrologic_states"
PROCESS_COVARIANCE_MODE = "fixed"
PROCESS_STATE_VARIANCE_MULTIPLIER = 1.0
OBSERVATION_VARIANCE_MULTIPLIER = 1.0
STATE_INTERACTION_MODE = "parameter_grouped"
PARAMETER_STATE_MAPPING_MODE = "legacy_projection"
TRANSITION_DIAGONAL = 0.98
INITIAL_COVARIANCE_FRACTION = 0.001
RESPONSE_WINDOW_DAYS = 30
CONSECUTIVE_DAYS = 5
PROB_THRESHOLD_EXCLUSIVE = 0.5
MARGIN_INCLUSIVE = 0.1
N_HYDRO = 5
N_STATE = 15


def rising_routed_discharge(state: np.ndarray, lag_time: float) -> float:
    """Rising-half routed discharge: largest weight on the OLDEST raw runoff."""
    n_lag = int(np.ceil(min(float(lag_time), LAG_CAP)))
    n_lag = max(n_lag, 1)
    weights = np.arange(1, n_lag + 1, dtype=np.float64)
    weights /= weights.sum()
    routing = np.asarray(state, dtype=np.float64)[N_HYDRO:N_HYDRO + n_lag]
    return float(weights @ routing)


class RisingRoutedObservation:
    """Candidate-specific rising-half routed discharge observation."""

    def __init__(self, parameters):
        self.parameters = dict(parameters)

    def __call__(self, state: np.ndarray) -> np.ndarray:
        from hbv_joint_uncertainty.preflight import project_hbv_state
        physical = project_hbv_state(state, self.parameters)
        return np.array(
            [rising_routed_discharge(physical, self.parameters["lag_time"])],
            dtype=np.float64)


def _generate_truth(
    members,
    rain,
    pet,
    temp,
    init_hydro,
    rng,
    bounds,
):
    """15-state stepwise truth: rotation, SLZ lognormal noise, rising routing.

    Returns (truth_q, truth_parfc, switch_days, clip_count). One rng normal per day.
    """
    from hbv_joint_uncertainty.hbv_adapter import advance_state
    state = np.zeros(N_STATE, dtype=np.float64)
    state[:N_HYDRO] = init_hydro
    n_days = min(len(rain), WINDOW_DAYS)
    truth_q = np.zeros(n_days, dtype=np.float64)
    truth_parfc = np.zeros(n_days, dtype=np.float64)
    switch_days = []
    clips = 0
    day = 0
    for stage_pos, member_idx in enumerate(ROTATION):
        params = members[member_idx]
        if stage_pos > 0 and day < n_days:
            switch_days.append((day, member_idx))
        for _ in range(STAGE_DAYS):
            if day >= n_days:
                break
            truth_parfc[day] = float(params["parFC"])
            state = advance_state(state, rain[day], pet[day], temp[day], params,
                                  bounds=bounds)
            noisy = state[4] * np.exp(
                rng.normal(-0.5 * SLZ_LOGNORMAL_SIGMA ** 2, SLZ_LOGNORMAL_SIGMA))
            if not np.isfinite(noisy) or noisy < 0.0:
                clips += 1
                noisy = max(noisy, 0.0) if np.isfinite(noisy) else 0.0
            state[4] = noisy
            truth_q[day] = rising_routed_discharge(state, params["lag_time"])
            day += 1
    return truth_q, truth_parfc, switch_days, clips


def build_filter_process_covariance(parameters, variance_scale, structure):
    """Build the common filter Q while keeping its magnitude definition fixed."""
    from hbv_joint_uncertainty.preflight import build_process_covariance

    all_hydrologic_states = build_process_covariance(parameters, variance_scale)
    if structure == "all_hydrologic_states":
        return all_hydrologic_states
    if structure == "lower_groundwater_state_only":
        lower_groundwater_only = np.zeros_like(all_hydrologic_states)
        lower_groundwater_only[4, 4] = all_hydrologic_states[4, 4]
        return lower_groundwater_only
    raise ValueError(f"unknown filter process covariance structure: {structure}")


def build_state_dependent_lower_groundwater_covariance(
    lower_groundwater_state,
    variance_multiplier,
):
    """Match the first two moments of the truth's multiplicative SLZ noise."""
    state = float(lower_groundwater_state)
    multiplier = float(variance_multiplier)
    if not np.isfinite(state) or state < 0.0:
        raise ValueError("lower-groundwater state must be finite and nonnegative")
    if not np.isfinite(multiplier) or multiplier <= 0.0:
        raise ValueError("process-variance multiplier must be finite and positive")
    covariance = np.zeros((N_STATE, N_STATE), dtype=np.float64)
    covariance[4, 4] = (
        multiplier * np.expm1(SLZ_LOGNORMAL_SIGMA ** 2) * state ** 2
    )
    return covariance


def build_filter_observation_covariance(sigma_obs, variance_multiplier):
    """Build filter R; the multiplier scales variance, never generated data."""
    sigma = float(sigma_obs)
    multiplier = float(variance_multiplier)
    if not np.isfinite(sigma) or sigma <= 0.0:
        raise ValueError("observation sigma must be finite and positive")
    if not np.isfinite(multiplier) or multiplier <= 0.0:
        raise ValueError("observation-variance multiplier must be finite and positive")
    return np.array([[multiplier * sigma ** 2]], dtype=np.float64)


def assign_common_process_covariance(estimator, covariance) -> None:
    """Assign one identical process covariance copy to every candidate."""
    matrix = np.asarray(covariance, dtype=np.float64)
    if matrix.shape != (N_STATE, N_STATE):
        raise ValueError(
            f"common process covariance must have shape ({N_STATE}, {N_STATE})"
        )
    if not np.all(np.isfinite(matrix)):
        raise ValueError("common process covariance must be finite")
    if not np.allclose(matrix, matrix.T, rtol=0.0, atol=1e-12):
        raise ValueError("common process covariance must be symmetric")
    if np.min(np.linalg.eigvalsh(matrix)) < -1e-12:
        raise ValueError("common process covariance must be positive semidefinite")
    if not getattr(estimator, "filters", None):
        raise ValueError("estimator must contain at least one filter")
    for candidate in estimator.filters:
        candidate.process_covariance = matrix.copy()


def validate_parameter_interaction_contract(
    interaction_mode,
    parameter_state_mapping,
) -> None:
    """Reject incomplete corrected-mode combinations before constructing filters."""
    if interaction_mode not in {
        "full",
        "parameter_grouped",
        "pairwise_path_postcollapse",
    }:
        raise ValueError(f"unknown state interaction mode: {interaction_mode}")
    if parameter_state_mapping not in {"legacy_projection", "conservative_parfc"}:
        raise ValueError(
            f"unknown parameter state mapping: {parameter_state_mapping}"
        )
    if (
        interaction_mode == "pairwise_path_postcollapse"
        and parameter_state_mapping != "conservative_parfc"
    ):
        raise ValueError(
            "pairwise path postcollapse requires conservative parFC state mapping"
        )
    if (
        parameter_state_mapping == "conservative_parfc"
        and interaction_mode not in {"full", "pairwise_path_postcollapse"}
    ):
        raise ValueError(
            "conservative parFC state mapping requires full interaction"
        )


def _build_bank(
    members,
    init_hydro,
    sigma_obs,
    bounds,
    q_scale=PROCESS_VARIANCE_SCALE,
    q_structure=PROCESS_COVARIANCE_STRUCTURE,
    q_mode=PROCESS_COVARIANCE_MODE,
    q_state_multiplier=PROCESS_STATE_VARIANCE_MULTIPLIER,
    filter_r_multiplier=OBSERVATION_VARIANCE_MULTIPLIER,
    interaction_mode=STATE_INTERACTION_MODE,
    parameter_state_mapping=PARAMETER_STATE_MAPPING_MODE,
    model_evidence_scorer=None,
):
    from hbv_joint_uncertainty.imm import (
        InteractingMultipleModel,
        PairwisePathMultipleModel,
    )
    from hbv_joint_uncertainty.hbv_state_mapping import (
        project_hbv_state_conserving_soil_excess,
        remap_parfc_moments,
    )
    from hbv_joint_uncertainty.preflight import (
        ForcingTransition, build_transition_matrix, project_hbv_state)
    from hbv_joint_uncertainty.sigma_filter import (
        ModifiedUnscentedFilter,
        ScaledSigmaPoints,
    )

    validate_parameter_interaction_contract(
        interaction_mode,
        parameter_state_mapping,
    )

    # First-contact amendment (2026-08-07, recorded in prereg): ONE common
    # process covariance built from the CENTER member (theta*), so the three
    # candidates differ only in their dynamics hypothesis (parFC), never in
    # assumed noise. Member-specific Q (the id23 construction) injects a
    # systematic likelihood bias toward the smallest-FC member: its tighter Q
    # gives a sharper innovation variance and a persistently higher likelihood
    # regardless of which member generated the truth (diagnosed on basin
    # 01022500 stage 0: wrong member wins 110-128/180 days under both matched
    # and id23 observation noise).
    if q_mode == "fixed":
        common_q = build_filter_process_covariance(members[0], q_scale, q_structure)
    elif q_mode == "lower_groundwater_state_proportional":
        if q_structure != "lower_groundwater_state_only":
            raise ValueError(
                "state-proportional process covariance requires "
                "lower_groundwater_state_only structure"
            )
        common_q = build_state_dependent_lower_groundwater_covariance(
            init_hydro[4], q_state_multiplier
        )
    else:
        raise ValueError(f"unknown filter process covariance mode: {q_mode}")
    common_r = build_filter_observation_covariance(
        sigma_obs, filter_r_multiplier
    )
    shared_state0 = np.zeros(N_STATE, dtype=np.float64)
    shared_state0[:N_HYDRO] = init_hydro
    if parameter_state_mapping == "conservative_parfc":
        common_state0 = project_hbv_state_conserving_soil_excess(
            shared_state0,
            members[0],
        )
        common_state_scales = np.maximum(np.abs(common_state0), 1.0)
        common_p0 = np.diag(
            (INITIAL_COVARIANCE_FRACTION * common_state_scales) ** 2
        )
        initial_sigma_points = ScaledSigmaPoints(
            N_STATE,
            alpha=0.6874,
            beta=2.0,
            kappa=-2.0,
        )
    filters, transitions = [], []
    for params in members:
        if parameter_state_mapping == "conservative_parfc":
            state0, p0 = remap_parfc_moments(
                common_state0,
                common_p0,
                members[0],
                params,
                initial_sigma_points,
            )
            state_projector = (
                lambda values, p=params: project_hbv_state_conserving_soil_excess(
                    values,
                    p,
                )
            )
        else:
            state0 = project_hbv_state(shared_state0, params)
            state_scales = np.maximum(np.abs(state0), 1.0)
            p0 = np.diag((INITIAL_COVARIANCE_FRACTION * state_scales) ** 2)
            state_projector = lambda values, p=params: __import__(
                "hbv_joint_uncertainty.preflight", fromlist=["project_hbv_state"]
            ).project_hbv_state(values, p)
        transition = ForcingTransition(
            params,
            parameter_bounds=bounds,
            state_projector=(
                state_projector
                if parameter_state_mapping == "conservative_parfc"
                else None
            ),
        )
        filters.append(ModifiedUnscentedFilter(
            state=state0, covariance=p0,
            transition=transition,
            observation=RisingRoutedObservation(params),
            process_covariance=common_q,
            observation_covariance=common_r,
            state_projector=state_projector,
            alpha=0.6874, beta=2.0, kappa=-2.0,
        ))
        transitions.append(transition)
    pairwise_moment_transform = None
    if parameter_state_mapping == "conservative_parfc":
        def pairwise_moment_transform(source, destination, mean, covariance):
            return remap_parfc_moments(
                mean,
                covariance,
                members[source],
                members[destination],
                filters[source].sigma_generator,
            )
    transition_matrix = build_transition_matrix(
        len(members),
        TRANSITION_DIAGONAL,
    )
    initial_probabilities = np.full(len(members), 1.0 / len(members))
    if interaction_mode == "pairwise_path_postcollapse":
        estimator = PairwisePathMultipleModel(
            filters=filters,
            transition_matrix=transition_matrix,
            initial_probabilities=initial_probabilities,
            pairwise_moment_transform=pairwise_moment_transform,
            model_evidence_scorer=model_evidence_scorer,
        )
        estimator.recursive_probability_representation = "ordinary_float"
    else:
        estimator = InteractingMultipleModel(
            filters=filters,
            transition_matrix=transition_matrix,
            initial_probabilities=initial_probabilities,
            parameter_groups=list(range(len(members))),
            pairwise_moment_transform=pairwise_moment_transform,
            model_evidence_scorer=model_evidence_scorer,
        )
    estimator.interaction_mode = interaction_mode
    estimator.parameter_state_mapping = parameter_state_mapping
    return estimator, transitions


def _evaluate_events(probs, switch_days):
    """id23-verbatim rule per switch: within 30 d, a 5-day run with new-true
    posterior > 0.5 (strict) and margin >= 0.1, run entirely inside window."""
    events = []
    n_days = probs.shape[0]
    for switch_day, new_idx in switch_days:
        window_end = min(switch_day + RESPONSE_WINDOW_DAYS, n_days)
        passed, start = False, None
        latest_start = window_end - CONSECUTIVE_DAYS
        for t0 in range(switch_day, latest_start + 1):
            seg = probs[t0:t0 + CONSECUTIVE_DAYS]
            new_p = seg[:, new_idx]
            others = np.delete(seg, new_idx, axis=1).max(axis=1)
            if np.all(new_p > PROB_THRESHOLD_EXCLUSIVE) and \
               np.all(new_p - others >= MARGIN_INCLUSIVE):
                passed, start = True, t0 - switch_day
                break
        events.append({"switch_day": switch_day, "new_member": new_idx,
                       "passed": passed, "response_start": start})
    return events


def classify_basin_verdict(events_total, events_passed) -> str:
    """Apply the registered two-seed basin rule only to complete evidence."""
    total = int(events_total)
    passed = int(events_passed)
    if total < 0 or passed < 0 or passed > total:
        raise ValueError("event counts must satisfy 0 <= passed <= total")
    expected_total = (len(ROTATION) - 1) * N_SEEDS
    if total != expected_total:
        return "not_evaluated_incomplete_design_seeds"
    if passed == expected_total:
        return "pass"
    if passed >= 8:
        return "partial"
    return "fail"


def _atomic_save_npz(path: Path, **arrays) -> None:
    """Write one new compressed task artifact without overwriting evidence."""
    target = Path(path)
    if target.exists():
        raise FileExistsError(f"task output already exists: {target}")
    temporary = target.with_suffix(".tmp.npz")
    if temporary.exists():
        raise FileExistsError(f"temporary task output already exists: {temporary}")
    np.savez_compressed(temporary, **arrays)
    os.link(temporary, target)
    temporary.unlink()


def _allocate_pairwise_path_audit(
    n_days,
    n_candidates,
    n_state,
    n_observation,
) -> dict[str, np.ndarray]:
    """Allocate one complete path audit with explicit inactive sentinels."""
    shape = (int(n_days), int(n_candidates), int(n_candidates))
    state_shape = shape + (int(n_state),)
    covariance_shape = state_shape + (int(n_state),)
    observation_shape = shape + (int(n_observation),)
    innovation_covariance_shape = observation_shape + (int(n_observation),)
    candidate_state_shape = (
        int(n_days), int(n_candidates), int(n_state)
    )
    candidate_covariance_shape = candidate_state_shape + (int(n_state),)
    combined_state_shape = (int(n_days), int(n_state))
    combined_covariance_shape = combined_state_shape + (int(n_state),)
    return {
        "path_initial_probabilities": np.full(
            int(n_candidates), np.nan, dtype=np.float64
        ),
        "path_initial_states": np.full(
            (int(n_candidates), int(n_state)), np.nan, dtype=np.float64
        ),
        "path_initial_covariances": np.full(
            (int(n_candidates), int(n_state), int(n_state)),
            np.nan,
            dtype=np.float64,
        ),
        "path_source_probabilities": np.full(
            (int(n_days), int(n_candidates)), np.nan, dtype=np.float64
        ),
        "path_source_states": np.full(
            candidate_state_shape, np.nan, dtype=np.float64
        ),
        "path_source_covariances": np.full(
            candidate_covariance_shape, np.nan, dtype=np.float64
        ),
        "path_candidate_prior_probabilities": np.full(
            (int(n_days), int(n_candidates)), np.nan, dtype=np.float64
        ),
        "path_branch_prior_log_probabilities": np.full(
            shape, -np.inf, dtype=np.float64
        ),
        "path_branch_posterior_log_probabilities": np.full(
            shape, -np.inf, dtype=np.float64
        ),
        "path_branch_posterior_probabilities": np.full(
            shape, np.nan, dtype=np.float64
        ),
        "path_destination_raw_probabilities": np.full(
            (int(n_days), int(n_candidates)), np.nan, dtype=np.float64
        ),
        "path_posterior_probabilities": np.full(
            (int(n_days), int(n_candidates)), np.nan, dtype=np.float64
        ),
        "path_destination_raw_conditional_probabilities": np.full(
            shape, np.nan, dtype=np.float64
        ),
        "path_destination_conditional_probabilities": np.full(
            shape, np.nan, dtype=np.float64
        ),
        "path_posterior_log_probabilities": np.full(
            (int(n_days), int(n_candidates)), -np.inf, dtype=np.float64
        ),
        "path_branch_active_mask": np.zeros(shape, dtype=bool),
        "path_branch_log_likelihoods": np.full(
            shape, -np.inf, dtype=np.float64
        ),
        "path_branch_prior_observations": np.full(
            observation_shape, np.nan, dtype=np.float64
        ),
        "path_branch_innovations": np.full(
            observation_shape, np.nan, dtype=np.float64
        ),
        "path_branch_innovation_covariances": np.full(
            innovation_covariance_shape, np.nan, dtype=np.float64
        ),
        "path_branch_prior_states": np.full(
            state_shape, np.nan, dtype=np.float64
        ),
        "path_branch_posterior_states": np.full(
            state_shape, np.nan, dtype=np.float64
        ),
        "path_branch_prior_covariances": np.full(
            covariance_shape, np.nan, dtype=np.float64
        ),
        "path_branch_posterior_covariances": np.full(
            covariance_shape, np.nan, dtype=np.float64
        ),
        "path_destination_states": np.full(
            candidate_state_shape, np.nan, dtype=np.float64
        ),
        "path_destination_covariances": np.full(
            candidate_covariance_shape, np.nan, dtype=np.float64
        ),
        "path_combined_states": np.full(
            combined_state_shape, np.nan, dtype=np.float64
        ),
        "path_combined_covariances": np.full(
            combined_covariance_shape, np.nan, dtype=np.float64
        ),
        "path_destination_reference_indices": np.full(
            (int(n_days), int(n_candidates)), -1, dtype=np.int64
        ),
        "path_global_reference_indices": np.full(
            int(n_days), -1, dtype=np.int64
        ),
        "path_direct_states": np.full(
            combined_state_shape, np.nan, dtype=np.float64
        ),
        "path_direct_covariances": np.full(
            combined_covariance_shape, np.nan, dtype=np.float64
        ),
        "path_direct_nested_state_absolute_differences": np.full(
            combined_state_shape, np.nan, dtype=np.float64
        ),
        "path_direct_nested_state_relative_differences": np.full(
            combined_state_shape, np.nan, dtype=np.float64
        ),
        "path_direct_nested_state_ulp_distances": np.full(
            combined_state_shape,
            np.iinfo(np.uint64).max,
            dtype=np.uint64,
        ),
        "path_direct_nested_covariance_absolute_differences": np.full(
            combined_covariance_shape, np.nan, dtype=np.float64
        ),
        "path_direct_nested_covariance_relative_differences": np.full(
            combined_covariance_shape, np.nan, dtype=np.float64
        ),
        "path_direct_nested_covariance_ulp_distances": np.full(
            combined_covariance_shape,
            np.iinfo(np.uint64).max,
            dtype=np.uint64,
        ),
        "path_direct_nested_state_max_abs_difference": np.full(
            int(n_days), np.nan, dtype=np.float64
        ),
        "path_direct_nested_covariance_max_abs_difference": np.full(
            int(n_days), np.nan, dtype=np.float64
        ),
    }


def _ordered_float64_index(value: float) -> int:
    """Map one finite float to a monotone unsigned integer after zero folding."""
    scalar = float(value)
    if not np.isfinite(scalar):
        raise ValueError("path direct diagnostics require finite values")
    if scalar == 0.0:
        scalar = 0.0
    bits = int(np.asarray(scalar, dtype=np.float64).view(np.uint64).item())
    sign_bit = 1 << 63
    if bits & sign_bit:
        return (~bits) & ((1 << 64) - 1)
    return bits | sign_bit


def _direct_nested_diagnostics(direct, nested):
    """Return fixed elementwise absolute, relative, and float-spacing diagnostics."""
    direct_values = np.asarray(direct, dtype=np.float64)
    nested_values = np.asarray(nested, dtype=np.float64)
    if direct_values.shape != nested_values.shape:
        raise ValueError("path direct and nested moments have incompatible shapes")
    if not np.all(np.isfinite(direct_values)) or not np.all(
        np.isfinite(nested_values)
    ):
        raise ValueError("path direct diagnostics require finite values")
    absolute = np.empty_like(direct_values)
    relative = np.empty_like(direct_values)
    ulp_distance = np.empty(direct_values.shape, dtype=np.uint64)
    for index in np.ndindex(direct_values.shape):
        direct_value = float(direct_values[index])
        nested_value = float(nested_values[index])
        difference = abs(direct_value - nested_value)
        scale = max(1.0, abs(direct_value), abs(nested_value))
        relative_value = difference / scale
        if not np.isfinite(difference) or not np.isfinite(relative_value):
            raise ValueError("path direct diagnostics are non-finite")
        absolute[index] = difference
        relative[index] = relative_value
        direct_index = _ordered_float64_index(direct_value)
        nested_index = _ordered_float64_index(nested_value)
        ulp_distance[index] = abs(direct_index - nested_index)
    return absolute, relative, ulp_distance


def _record_pairwise_path_audit(
    audit,
    day,
    source_probabilities,
    source_states,
    source_covariances,
    result,
) -> None:
    """Save one postcollapse result and compute fixed nonblocking diagnostics."""
    day_index = int(day)
    source_values = np.asarray(source_probabilities, dtype=np.float64)
    source_state_values = np.asarray(source_states, dtype=np.float64)
    source_covariance_values = np.asarray(source_covariances, dtype=np.float64)
    candidate_count = audit["path_source_probabilities"].shape[1]
    if source_values.shape != (candidate_count,):
        raise ValueError("path source probabilities have an incompatible shape")
    if source_state_values.shape != audit["path_source_states"].shape[1:]:
        raise ValueError("path source states have an incompatible shape")
    if source_covariance_values.shape != audit["path_source_covariances"].shape[1:]:
        raise ValueError("path source covariances have an incompatible shape")
    if day_index == 0:
        audit["path_initial_probabilities"] = source_values.copy()
        audit["path_initial_states"] = source_state_values.copy()
        audit["path_initial_covariances"] = source_covariance_values.copy()
    audit["path_source_probabilities"][day_index] = source_values
    audit["path_source_states"][day_index] = source_state_values
    audit["path_source_covariances"][day_index] = source_covariance_values
    audit["path_candidate_prior_probabilities"][day_index] = (
        result.prior_probabilities
    )
    audit["path_branch_prior_log_probabilities"][day_index] = (
        result.branch_prior_log_probabilities
    )
    audit["path_branch_posterior_log_probabilities"][day_index] = (
        result.branch_posterior_log_probabilities
    )
    audit["path_branch_posterior_probabilities"][day_index] = (
        result.branch_posterior_probabilities
    )
    audit["path_destination_raw_probabilities"][day_index] = (
        result.destination_raw_probabilities
    )
    audit["path_posterior_probabilities"][day_index] = (
        result.posterior_probabilities
    )
    audit["path_destination_raw_conditional_probabilities"][day_index] = (
        result.destination_raw_conditional_probabilities
    )
    audit["path_destination_conditional_probabilities"][day_index] = (
        result.destination_conditional_probabilities
    )
    audit["path_posterior_log_probabilities"][day_index] = (
        result.posterior_log_probabilities
    )
    audit["path_branch_active_mask"][day_index] = result.branch_active_mask
    audit["path_destination_reference_indices"][day_index] = (
        result.destination_reference_indices
    )
    audit["path_global_reference_indices"][day_index] = (
        result.global_reference_index
    )

    for source in range(candidate_count):
        for destination in range(candidate_count):
            branch = result.branch_results[source][destination]
            if branch is None:
                continue
            audit["path_branch_log_likelihoods"][day_index, source, destination] = (
                branch.log_likelihood
            )
            audit["path_branch_prior_observations"][day_index, source, destination] = (
                branch.prior_observation
            )
            audit["path_branch_innovations"][day_index, source, destination] = (
                branch.innovation
            )
            audit["path_branch_innovation_covariances"][day_index, source, destination] = (
                branch.innovation_covariance
            )
            audit["path_branch_prior_states"][day_index, source, destination] = (
                branch.prior_state
            )
            audit["path_branch_posterior_states"][day_index, source, destination] = (
                branch.posterior_state
            )
            audit["path_branch_prior_covariances"][day_index, source, destination] = (
                branch.prior_covariance
            )
            audit["path_branch_posterior_covariances"][day_index, source, destination] = (
                branch.posterior_covariance
            )

    audit["path_destination_states"][day_index] = result.destination_states
    audit["path_destination_covariances"][day_index] = (
        result.destination_covariances
    )
    audit["path_combined_states"][day_index] = result.combined_state
    audit["path_combined_covariances"][day_index] = result.combined_covariance
    audit["path_direct_states"][day_index] = result.direct_state
    audit["path_direct_covariances"][day_index] = result.direct_covariance
    state_absolute, state_relative, state_ulp = _direct_nested_diagnostics(
        result.direct_state,
        result.combined_state,
    )
    covariance_absolute, covariance_relative, covariance_ulp = (
        _direct_nested_diagnostics(
            result.direct_covariance,
            result.combined_covariance,
        )
    )
    audit["path_direct_nested_state_absolute_differences"][day_index] = (
        state_absolute
    )
    audit["path_direct_nested_state_relative_differences"][day_index] = (
        state_relative
    )
    audit["path_direct_nested_state_ulp_distances"][day_index] = state_ulp
    audit["path_direct_nested_covariance_absolute_differences"][day_index] = (
        covariance_absolute
    )
    audit["path_direct_nested_covariance_relative_differences"][day_index] = (
        covariance_relative
    )
    audit["path_direct_nested_covariance_ulp_distances"][day_index] = (
        covariance_ulp
    )
    audit["path_direct_nested_state_max_abs_difference"][day_index] = float(
        np.max(state_absolute)
    )
    audit["path_direct_nested_covariance_max_abs_difference"][day_index] = float(
        np.max(covariance_absolute)
    )


def _finalize_pairwise_path_audit(audit, estimator) -> dict[str, np.ndarray]:
    """Attach fixed path semantics; old estimators return no path fields."""
    if audit is None:
        return {}
    arrays = {name: values.copy() for name, values in audit.items()}
    candidate_count = int(estimator.transition_matrix.shape[0])
    arrays.update({
        "path_transition_matrix": estimator.transition_matrix.copy(),
        "path_initial_probability_axis_order": np.asarray(
            ["candidate"]
        ),
        "path_initial_state_axis_order": np.asarray(
            ["candidate", "state"]
        ),
        "path_initial_covariance_axis_order": np.asarray(
            ["candidate", "state_row", "state_column"]
        ),
        "path_source_probability_axis_order": np.asarray(
            ["day", "source_candidate"]
        ),
        "path_source_state_axis_order": np.asarray(
            ["day", "source_candidate", "state"]
        ),
        "path_source_covariance_axis_order": np.asarray(
            ["day", "source_candidate", "state_row", "state_column"]
        ),
        "path_probability_axis_order": np.asarray(
            ["day", "candidate"]
        ),
        "path_branch_axis_order": np.asarray(
            ["day", "source_candidate", "destination_candidate"]
        ),
        "path_transition_axis_order": np.asarray(
            ["source_candidate", "destination_candidate"]
        ),
        "path_destination_probability_axis_order": np.asarray(
            ["day", "destination_candidate"]
        ),
        "path_destination_conditional_probability_axis_order": np.asarray(
            ["day", "source_candidate", "destination_candidate"]
        ),
        "path_destination_reference_index_axis_order": np.asarray(
            ["day", "destination_candidate"]
        ),
        "path_global_reference_index_axis_order": np.asarray(
            ["day"]
        ),
        "path_branch_flatten_indices": np.asarray(
            [
                (source, destination)
                for source in range(candidate_count)
                for destination in range(candidate_count)
            ],
            dtype=np.int64,
        ),
        "path_branch_flatten_index_axis_order": np.asarray(
            ["flattened_branch", "source_destination_coordinate"]
        ),
        "path_branch_flatten_order": np.asarray(
            "source_major_destination_minor"
        ),
        "path_reference_selection": np.asarray(
            "maximum_weight_then_lowest_original_index"
        ),
        "path_initial_snapshot_timing": np.asarray(
            "before_day_0_step"
        ),
        "path_observation_axis_order": np.asarray(
            [
                "day",
                "source_candidate",
                "destination_candidate",
                "observation",
            ]
        ),
        "path_innovation_covariance_axis_order": np.asarray(
            [
                "day",
                "source_candidate",
                "destination_candidate",
                "observation_row",
                "observation_column",
            ]
        ),
        "path_state_axis_order": np.asarray(
            ["day", "source_candidate", "destination_candidate", "state"]
        ),
        "path_covariance_axis_order": np.asarray(
            [
                "day",
                "source_candidate",
                "destination_candidate",
                "state_row",
                "state_column",
            ]
        ),
        "path_candidate_state_axis_order": np.asarray(
            ["day", "candidate", "state"]
        ),
        "path_candidate_covariance_axis_order": np.asarray(
            ["day", "candidate", "state_row", "state_column"]
        ),
        "path_combined_state_axis_order": np.asarray(
            ["day", "state"]
        ),
        "path_combined_covariance_axis_order": np.asarray(
            ["day", "state_row", "state_column"]
        ),
        "path_direct_state_axis_order": np.asarray(
            ["day", "state"]
        ),
        "path_direct_covariance_axis_order": np.asarray(
            ["day", "state_row", "state_column"]
        ),
        "path_direct_nested_state_diagnostic_axis_order": np.asarray(
            ["day", "state"]
        ),
        "path_direct_nested_covariance_diagnostic_axis_order": np.asarray(
            ["day", "state_row", "state_column"]
        ),
        "path_unique_global_moment_role": np.asarray(
            "authoritative_nested_destination_mixture"
        ),
        "path_direct_global_moment_role": np.asarray(
            "nonblocking_diagnostic_only"
        ),
        "path_recursive_probability_representation": np.array(
            estimator.recursive_probability_representation
        ),
        "path_hypothesis_collapse_timing": np.array(
            estimator.hypothesis_collapse_timing
        ),
    })
    return arrays


def _run_one(args_tuple):
    (basin_id, seed_k, data_root, row, q_scale, q_structure, q_mode,
     q_state_multiplier, filter_r_multiplier, interaction_mode,
     parameter_state_mapping, probability_directory, arm_id) = args_tuple
    import sys as _sys
    if str(_REPO_ROOT / "src") not in _sys.path:
        _sys.path.insert(0, str(_REPO_ROOT / "src"))
    from hydroagent.data_loading import load_camels_basin
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds
    from camels_switch_confirmation.bank import build_bank as build_members

    t0 = time.time()
    try:
        params = {k: float(row[f"p_{k}"]) for k in PARAM_KEYS}
        lag_capped = params["lag_time"] > LAG_CAP
        params["lag_time"] = min(params["lag_time"], LAG_CAP)
        init_hydro = np.array([float(row[f"state_{s}"]) for s in STATE_NAMES])
        sigma_obs = float(row["sigma_obs"])

        v_bounds = resolve_hbv_bounds(BOUNDS_PRESET)
        members, _ = build_members(params, v_bounds["parFC"])

        forcing, _, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=WINDOW_START, end_date=_window_end(),
            forcing="maurer", pet_method="oudin", keep_obs_nan_days=True)
        rain = forcing["prcp"].values.astype(np.float64)
        pet_col = "ep" if "ep" in forcing.columns else "pet"
        pet = forcing[pet_col].values.astype(np.float64)
        temp = (forcing["tmean"].values.astype(np.float64)
                if "tmean" in forcing.columns else np.zeros_like(rain))

        truth_rng = np.random.default_rng(
            np.random.SeedSequence((SEED_ENTROPY, int(basin_id), seed_k)))
        obs_rng = np.random.default_rng(
            np.random.SeedSequence((SEED_ENTROPY, int(basin_id), seed_k, 1)))

        truth_q, truth_parfc, switch_days, clips = _generate_truth(
            members,
            rain,
            pet,
            temp,
            init_hydro,
            truth_rng,
            v_bounds,
        )
        n_days = len(truth_q)
        observations = truth_q + obs_rng.normal(0.0, sigma_obs, size=n_days)

        estimator, transitions = _build_bank(
            members,
            init_hydro,
            sigma_obs,
            v_bounds,
            q_scale=q_scale,
            q_structure=q_structure,
            q_mode=q_mode,
            q_state_multiplier=q_state_multiplier,
            filter_r_multiplier=filter_r_multiplier,
            interaction_mode=interaction_mode,
            parameter_state_mapping=parameter_state_mapping,
        )
        probs = np.zeros((n_days, len(members)), dtype=np.float64)
        log_probs = np.zeros((n_days, len(members)), dtype=np.float64)
        process_variances = np.zeros(n_days, dtype=np.float64)
        path_audit = None
        if interaction_mode == "pairwise_path_postcollapse":
            path_audit = _allocate_pairwise_path_audit(
                n_days=n_days,
                n_candidates=len(members),
                n_state=N_STATE,
                n_observation=1,
            )
        for day in range(n_days):
            for tr in transitions:
                tr.set_forcing(rain[day], pet[day], temp[day])
            if q_mode == "lower_groundwater_state_proportional":
                predicted_reference = transitions[0](estimator.state.copy())
                common_q = build_state_dependent_lower_groundwater_covariance(
                    predicted_reference[4], q_state_multiplier
                )
                assign_common_process_covariance(estimator, common_q)
            process_variances[day] = estimator.filters[0].process_covariance[4, 4]
            source_probabilities = estimator.probabilities.copy()
            source_states = None
            source_covariances = None
            if path_audit is not None:
                source_states = np.asarray([
                    candidate.state.copy() for candidate in estimator.filters
                ])
                source_covariances = np.asarray([
                    candidate.covariance.copy() for candidate in estimator.filters
                ])
            result = estimator.step(np.array([observations[day]]))
            probs[day] = result.posterior_probabilities
            log_probs[day] = result.posterior_log_probabilities
            if path_audit is not None:
                _record_pairwise_path_audit(
                    path_audit,
                    day,
                    source_probabilities,
                    source_states,
                    source_covariances,
                    result,
                )

        events = _evaluate_events(probs, switch_days)
        candidate_parameter_vectors = np.asarray(
            [[float(member[key]) for key in PARAM_KEYS] for member in members],
            dtype=np.float64,
        )
        true_candidate_indices = np.repeat(
            np.asarray(ROTATION, dtype=np.int64),
            STAGE_DAYS,
        )[:n_days]
        out_dir = Path(probability_directory)
        task_arrays = {
            "probabilities": probs,
            "log_probabilities": log_probs,
            "truth_q": truth_q,
            "observations": observations,
            "basin_id": np.array(str(basin_id)),
            "seed": np.array(int(seed_k), dtype=np.int64),
            "switch_days": np.array([d for d, _ in switch_days]),
            "rotation": np.asarray(ROTATION, dtype=np.int64),
            "stage_days": np.array(STAGE_DAYS, dtype=np.int64),
            "true_candidate_indices": true_candidate_indices,
            "truth_parfc": truth_parfc,
            "candidate_parameter_names": np.asarray(PARAM_KEYS),
            "candidate_parameter_vectors": candidate_parameter_vectors,
            "truth_slz_lognormal_sigma": np.array(
                SLZ_LOGNORMAL_SIGMA,
                dtype=np.float64,
            ),
            "truth_clip_count": np.array(clips, dtype=np.int64),
            "observation_sigma": np.array(sigma_obs, dtype=np.float64),
            "rain": rain,
            "pet": pet,
            "temperature": temp,
            "filter_process_variance_scale": np.array(
                q_scale if q_mode == "fixed" else np.nan
            ),
            "filter_process_covariance_structure": np.array(q_structure),
            "filter_q_mode": np.array(q_mode),
            "filter_q_state_multiplier": np.array(q_state_multiplier),
            "filter_observation_variance_multiplier": np.array(
                filter_r_multiplier
            ),
            "state_interaction_mode": np.array(interaction_mode),
            "parameter_state_mapping": np.array(parameter_state_mapping),
            "arm_id": np.array(str(arm_id)),
            "filter_process_lower_groundwater_variance": process_variances,
        }
        task_arrays.update(_finalize_pairwise_path_audit(path_audit, estimator))
        _atomic_save_npz(
            out_dir / f"{basin_id}_s{seed_k}.npz",
            **task_arrays,
        )

        rec = {"basin_id": basin_id, "seed": seed_k, "run_status": "success",
               "error_message": "", "lag_capped": bool(lag_capped),
               "truth_clip_count": clips,
               "arm_id": str(arm_id),
               "state_interaction_mode": interaction_mode,
               "parameter_state_mapping": parameter_state_mapping,
               "n_events": len(events),
               "n_events_passed": sum(e["passed"] for e in events),
               "_elapsed_s": round(time.time() - t0, 2)}
        if path_audit is not None:
            rec.update({
                "hypothesis_collapse_timing": "after_observation",
                "recursive_probability_representation": "ordinary_float",
            })
        for i, e in enumerate(events):
            rec[f"event{i}_pass"] = bool(e["passed"])
            rec[f"event{i}_start"] = (e["response_start"]
                                      if e["response_start"] is not None else -1)
            rec[f"event{i}_new_member"] = e["new_member"]
            sd = e["switch_day"]
            rec[f"event{i}_window_rain_mm"] = float(
                np.sum(rain[sd:sd + RESPONSE_WINDOW_DAYS]))
        return rec
    except Exception as exc:  # noqa: BLE001
        return {"basin_id": basin_id, "seed": seed_k, "run_status": "failed",
                "error_message": f"{type(exc).__name__}: {exc}",
                "arm_id": str(arm_id),
                "_elapsed_s": round(time.time() - t0, 2)}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data-root", default="data/camels_us")
    p.add_argument("--workers", type=int, default=6)
    p.add_argument("--limit", type=int, default=None,
                   help="limit number of BASINS (each still runs both seeds)")
    p.add_argument("--q-scale", type=float, default=PROCESS_VARIANCE_SCALE,
                   help="filter process-noise variance scale (EXPLORATORY sweeps only; "
                        "the frozen value is 1e-4)")
    p.add_argument(
        "--q-structure",
        choices=("all_hydrologic_states", "lower_groundwater_state_only"),
        default=PROCESS_COVARIANCE_STRUCTURE,
        help=("filter process-covariance structure (EXPLORATORY sweeps only; "
              "the frozen structure is all_hydrologic_states)"),
    )
    p.add_argument(
        "--q-mode",
        choices=("fixed", "lower_groundwater_state_proportional"),
        default=PROCESS_COVARIANCE_MODE,
        help=("filter process-covariance mode (EXPLORATORY sweeps only; "
              "state proportional matches the truth-noise first two moments)"),
    )
    p.add_argument(
        "--q-state-multiplier",
        type=float,
        default=PROCESS_STATE_VARIANCE_MULTIPLIER,
        help="positive variance multiplier for state-proportional process noise",
    )
    p.add_argument(
        "--filter-r-multiplier",
        type=float,
        default=OBSERVATION_VARIANCE_MULTIPLIER,
        help="positive multiplier on filter observation variance; data stay fixed",
    )
    p.add_argument(
        "--interaction-mode",
        choices=(
            "parameter_grouped",
            "full",
            "pairwise_path_postcollapse",
        ),
        default=STATE_INTERACTION_MODE,
        help="candidate-state interaction; legacy default keeps parameter groups separate",
    )
    p.add_argument(
        "--parameter-state-mapping",
        choices=("legacy_projection", "conservative_parfc"),
        default=PARAMETER_STATE_MAPPING_MODE,
        help="state treatment across soil-capacity hypotheses",
    )
    p.add_argument(
        "--seed",
        type=int,
        choices=tuple(range(N_SEEDS)),
        default=None,
        help="run one design seed only; default runs every registered design seed",
    )
    p.add_argument("--out-tag", default="",
                   help="suffix for the output dir, e.g. q1e5 (exploratory sweeps)")
    args = p.parse_args(argv)
    if args.workers <= 0:
        p.error("--workers must be positive")
    if args.limit is not None and args.limit <= 0:
        p.error("--limit must be positive")
    if not np.isfinite(args.q_scale) or args.q_scale <= 0.0:
        p.error("--q-scale must be finite and positive")
    if not np.isfinite(args.q_state_multiplier) or args.q_state_multiplier <= 0.0:
        p.error("--q-state-multiplier must be finite and positive")
    if not np.isfinite(args.filter_r_multiplier) or args.filter_r_multiplier <= 0.0:
        p.error("--filter-r-multiplier must be finite and positive")
    if args.q_mode == "lower_groundwater_state_proportional" and \
       args.q_structure != "lower_groundwater_state_only":
        p.error(
            "--q-mode lower_groundwater_state_proportional requires "
            "--q-structure lower_groundwater_state_only"
        )
    try:
        validate_parameter_interaction_contract(
            args.interaction_mode,
            args.parameter_state_mapping,
        )
    except ValueError as error:
        p.error(str(error))
    corrected_mode = (
        args.interaction_mode != STATE_INTERACTION_MODE
        or args.parameter_state_mapping != PARAMETER_STATE_MAPPING_MODE
    )
    if corrected_mode and not args.out_tag.strip():
        p.error("corrected interaction runs require a nonempty --out-tag")

    table = pd.read_csv(_REPO_ROOT / RISING_TABLE, dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    rows = table.to_dict("records")
    if args.limit:
        rows = rows[: args.limit]

    g1 = pd.read_csv(_REPO_ROOT / G1_CSV, dtype={"basin_id": str})
    g1["basin_id"] = g1["basin_id"].str.zfill(8)
    g1_map = g1.set_index("basin_id")[["sigma_obs", "predicted_identifiable"]]

    out_dir = _REPO_ROOT / (OUT_DIR + (f"_{args.out_tag}" if args.out_tag else ""))
    if out_dir.exists():
        p.error(f"output directory already exists: {out_dir}")
    out_dir.mkdir(parents=True, exist_ok=False)
    probability_directory = out_dir / "probs"
    probability_directory.mkdir(exist_ok=False)

    selected_seeds = tuple(range(N_SEEDS)) if args.seed is None else (args.seed,)
    work = []
    for r in rows:
        sigma = g1_map.loc[r["basin_id"], "sigma_obs"]
        r = dict(r)
        r["sigma_obs"] = float(sigma)
        for k in selected_seeds:
            work.append((r["basin_id"], k, args.data_root, r, args.q_scale,
                         args.q_structure, args.q_mode,
                         args.q_state_multiplier, args.filter_r_multiplier,
                         args.interaction_mode, args.parameter_state_mapping,
                         str(probability_directory), "legacy_cli"))

    print(f"[{time.strftime('%H:%M:%S')}] G2 run: {len(rows)} basins x "
          f"{len(selected_seeds)} seeds = {len(work)} tasks")
    print(
        "filter Q: "
        f"mode={args.q_mode}, structure={args.q_structure}, "
        f"fixed_variance_scale={args.q_scale:g}, "
        f"state_variance_multiplier={args.q_state_multiplier:g}; "
        f"filter R variance multiplier={args.filter_r_multiplier:g}"
    )
    print(
        "state interaction: "
        f"mode={args.interaction_mode}, "
        f"parameter_state_mapping={args.parameter_state_mapping}"
    )
    t_start = time.time()
    execution = execute_fail_fast(
        work=work,
        worker=_run_one,
        task_key=lambda item: {
            "basin_id": item[0],
            "seed": item[1],
            "arm_id": item[-1],
        },
        max_workers=args.workers,
    )
    df = pd.DataFrame(execution.records)
    if not df.empty:
        df = df.sort_values("task_index").reset_index(drop=True)
    df.to_csv(out_dir / "g2_events.csv", index=False)

    # ---- basin verdicts + transfer confusion matrix ----
    ok = df[df["run_status"] == "success"]
    verdicts = []
    for bid, grp in ok.groupby("basin_id"):
        total = int(grp["n_events"].sum())
        passed = int(grp["n_events_passed"].sum())
        verdict = classify_basin_verdict(total, passed)
        verdicts.append({"basin_id": bid, "events_total": total,
                         "events_passed": passed, "verdict": verdict})
    verdict_columns = ["basin_id", "events_total", "events_passed", "verdict"]
    vdf = pd.DataFrame(verdicts, columns=verdict_columns)
    g1_columns = [
        "basin_id", "predicted_identifiable", "r_min", "nse_calibration_table"
    ]
    if vdf.empty:
        for column in g1_columns[1:]:
            vdf[column] = pd.Series(dtype=g1[column].dtype)
    else:
        vdf = vdf.merge(g1[g1_columns], on="basin_id", validate="one_to_one")
    vdf.to_csv(out_dir / "g2_basin_verdicts.csv", index=False)

    summary = {"config": None,
               "configuration_status": "development_unfrozen",
               "execution_status": execution.execution_status,
               "scientific_aggregation_status": (
                   "evaluated_complete_execution"
                   if execution.execution_status == "complete"
                   else "not_evaluated_incomplete_execution"
               ),
               "q_scale": args.q_scale if args.q_mode == "fixed" else None,
               "q_structure": args.q_structure,
               "q_mode": args.q_mode,
               "q_state_multiplier": args.q_state_multiplier,
               "filter_r_multiplier": args.filter_r_multiplier,
               "state_interaction_mode": args.interaction_mode,
               "parameter_state_mapping": args.parameter_state_mapping,
               "seeds": list(selected_seeds),
               "basin_verdict_status": (
                   "evaluated_two_design_seeds"
                   if args.seed is None
                   else "not_evaluated_incomplete_design_seeds"
               ),
               "out_tag": args.out_tag, "n_tasks": len(work),
               "n_submitted": execution.n_submitted,
               "n_success": int(len(ok)),
               "n_failed": int((df["run_status"] == "failed").sum()),
               "n_cancelled_before_start": execution.n_cancelled_before_start,
               "n_not_submitted_after_failure": (
                   execution.n_not_submitted_after_failure
               ),
               "n_completed_after_stop": execution.n_completed_after_stop,
               "first_failure": execution.first_failure,
               "wall_clock_min": round((time.time() - t_start) / 60, 1)}
    if args.interaction_mode == "pairwise_path_postcollapse":
        summary.update({
            "hypothesis_collapse_timing": "after_observation",
            "recursive_probability_representation": "ordinary_float",
        })
    if execution.execution_status != "complete":
        summary["basin_verdict_status"] = "not_evaluated_incomplete_execution"
    if len(vdf) and args.seed is None and execution.execution_status == "complete":
        pred = vdf[vdf["predicted_identifiable"]]
        unpred = vdf[~vdf["predicted_identifiable"]]
        pass_rate_pred = float((pred["verdict"] == "pass").mean()) if len(pred) else float("nan")
        pass_rate_unpred = float((unpred["verdict"] == "pass").mean()) if len(unpred) else float("nan")
        # one-sided two-proportion z-test
        z = p_val = float("nan")
        if len(pred) and len(unpred):
            x1, n1 = (pred["verdict"] == "pass").sum(), len(pred)
            x2, n2 = (unpred["verdict"] == "pass").sum(), len(unpred)
            pool_p = (x1 + x2) / (n1 + n2)
            se = np.sqrt(pool_p * (1 - pool_p) * (1 / n1 + 1 / n2))
            if se > 0:
                from math import erf, sqrt
                z = float((x1 / n1 - x2 / n2) / se)
                p_val = float(0.5 * (1 - erf(z / sqrt(2))))
        summary.update({
            "n_basins": len(vdf),
            "confusion": {
                "predicted_identifiable": {
                    "n": int(len(pred)),
                    "pass": int((pred["verdict"] == "pass").sum()),
                    "partial": int((pred["verdict"] == "partial").sum()),
                    "fail": int((pred["verdict"] == "fail").sum())},
                "predicted_fail": {
                    "n": int(len(unpred)),
                    "pass": int((unpred["verdict"] == "pass").sum()),
                    "partial": int((unpred["verdict"] == "partial").sum()),
                    "fail": int((unpred["verdict"] == "fail").sum())}},
            "pass_rate_predicted": pass_rate_pred,
            "pass_rate_unpredicted": pass_rate_unpred,
            "transfer_gate_rate_ok": bool(pass_rate_pred >= 0.80) if np.isfinite(pass_rate_pred) else None,
            "z": z, "p_one_sided": p_val,
            "transfer_gate_significant": bool(p_val < 0.05) if np.isfinite(p_val) else None,
        })
    elif len(vdf) and execution.execution_status == "complete":
        summary["n_basins"] = int(len(vdf))
    (out_dir / "g2_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if execution.execution_status == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())
