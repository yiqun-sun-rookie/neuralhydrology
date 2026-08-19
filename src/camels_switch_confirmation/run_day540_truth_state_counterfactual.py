"""One-state-mean counterfactual for the day-540 parFC failure.

The executable contract is deliberately locked to basin 07184000, design
seed 0, Gaussian model evidence, and the pairwise-path post-observation
collapse estimator.  Synthetic truth is used once as a diagnostic
intervention; this module does not implement an operational method.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from camels_switch_confirmation.g1_precheck import (
    PARAM_KEYS,
    ROTATION,
    SEED_ENTROPY,
    STAGE_DAYS,
    WINDOW_DAYS,
)
from camels_switch_confirmation.g2_switch_confirmation import (
    N_HYDRO,
    N_STATE,
    SLZ_LOGNORMAL_SIGMA,
    _atomic_save_npz,
    _build_bank,
    _evaluate_events,
    rising_routed_discharge,
)
from camels_switch_confirmation.register_parameter_path_design90 import (
    collection_fingerprint,
)
from hbv_joint_uncertainty.hbv_adapter import advance_state
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds


EXPERIMENT_ID = "CAMELS_PARFC_DAY540_TRUTH_STATE_COUNTERFACTUAL_07184000_S0_01"
BASIN_ID = "07184000"
SEED = 0
INTERVENTION_DAY = 540
INTERVENTION_SOURCE_INDEX = 2
INTERVENTION_TARGET_INDEX = 0
EXPECTED_FROZEN_FINGERPRINT = (
    "57d8fef9037c29d0a68f915d5337f3be7bfab2224ebada575be6161e070126e6"
)
SOURCE_FIELDS = (
    "probabilities",
    "log_probabilities",
    "truth_q",
    "observations",
    "basin_id",
    "seed",
    "switch_days",
    "rotation",
    "stage_days",
    "true_candidate_indices",
    "truth_parfc",
    "candidate_parameter_names",
    "candidate_parameter_vectors",
    "truth_clip_count",
    "observation_sigma",
    "rain",
    "pet",
    "temperature",
    "filter_process_variance_scale",
    "filter_process_covariance_structure",
    "filter_q_mode",
    "filter_q_state_multiplier",
    "filter_observation_variance_multiplier",
    "state_interaction_mode",
    "parameter_state_mapping",
    "arm_id",
    "path_initial_probabilities",
    "path_initial_states",
    "path_initial_covariances",
    "path_source_probabilities",
    "path_source_states",
    "path_source_covariances",
)


@dataclass(frozen=True)
class TruthReplay:
    source_states: np.ndarray
    posterior_states: np.ndarray
    discharge: np.ndarray
    parfc: np.ndarray
    switch_days: tuple[tuple[int, int], ...]
    clip_count: int


@dataclass(frozen=True)
class StateMeanInterventionRecord:
    source_index: int
    state_before: np.ndarray
    state_after: np.ndarray
    covariance_before: np.ndarray
    covariance_after: np.ndarray
    probabilities_before: np.ndarray
    probabilities_after: np.ndarray


def replay_truth_with_states(
    members,
    rain,
    pet,
    temperature,
    initial_hydrology,
    rng,
    bounds,
) -> TruthReplay:
    """Replay the registered truth and retain states before and after each day."""
    rain = np.asarray(rain, dtype=np.float64)
    pet = np.asarray(pet, dtype=np.float64)
    temperature = np.asarray(temperature, dtype=np.float64)
    if rain.ndim != 1 or pet.shape != rain.shape or temperature.shape != rain.shape:
        raise ValueError("rain, pet, and temperature must be equal one-dimensional arrays")
    if not np.all(np.isfinite(rain)) or not np.all(np.isfinite(pet)) or not np.all(
        np.isfinite(temperature)
    ):
        raise ValueError("truth forcing must be finite")
    initial_hydrology = np.asarray(initial_hydrology, dtype=np.float64)
    if initial_hydrology.shape != (N_HYDRO,) or not np.all(
        np.isfinite(initial_hydrology)
    ):
        raise ValueError(f"initial_hydrology must be a finite {N_HYDRO}-vector")
    if len(members) != len(set(ROTATION)):
        raise ValueError("truth replay requires the registered three candidates")

    n_days = min(len(rain), WINDOW_DAYS)
    source_states = np.empty((n_days, N_STATE), dtype=np.float64)
    posterior_states = np.empty_like(source_states)
    discharge = np.empty(n_days, dtype=np.float64)
    parfc = np.empty(n_days, dtype=np.float64)
    state = np.zeros(N_STATE, dtype=np.float64)
    state[:N_HYDRO] = initial_hydrology
    switch_days: list[tuple[int, int]] = []
    clip_count = 0
    day = 0
    for stage_position, member_index in enumerate(ROTATION):
        parameters = members[member_index]
        if stage_position > 0 and day < n_days:
            switch_days.append((day, member_index))
        for _ in range(STAGE_DAYS):
            if day >= n_days:
                break
            source_states[day] = state
            parfc[day] = float(parameters["parFC"])
            state = advance_state(
                state,
                rain[day],
                pet[day],
                temperature[day],
                parameters,
                bounds=bounds,
            )
            noisy_lower_groundwater = state[4] * np.exp(
                rng.normal(
                    -0.5 * SLZ_LOGNORMAL_SIGMA**2,
                    SLZ_LOGNORMAL_SIGMA,
                )
            )
            if not np.isfinite(noisy_lower_groundwater) or noisy_lower_groundwater < 0.0:
                clip_count += 1
                noisy_lower_groundwater = (
                    max(noisy_lower_groundwater, 0.0)
                    if np.isfinite(noisy_lower_groundwater)
                    else 0.0
                )
            state[4] = noisy_lower_groundwater
            posterior_states[day] = state
            discharge[day] = rising_routed_discharge(
                state,
                parameters["lag_time"],
            )
            day += 1
        if day >= n_days:
            break
    return TruthReplay(
        source_states=source_states,
        posterior_states=posterior_states,
        discharge=discharge,
        parfc=parfc,
        switch_days=tuple(switch_days),
        clip_count=clip_count,
    )


def apply_truth_state_mean_intervention(
    estimator,
    truth_source_state,
    *,
    expected_source_index: int,
) -> StateMeanInterventionRecord:
    """Replace exactly one dominant source-candidate mean and nothing else."""
    probabilities = np.asarray(estimator.probabilities, dtype=np.float64)
    if probabilities.shape != (len(estimator.filters),):
        raise ValueError("estimator probabilities do not match its candidate bank")
    if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
        raise ValueError("estimator probabilities must be finite and nonnegative")
    maximum = float(np.max(probabilities))
    dominant = np.flatnonzero(probabilities == maximum)
    expected = int(expected_source_index)
    if dominant.shape != (1,) or int(dominant[0]) != expected:
        raise ValueError(
            f"dominant source candidate must be uniquely index {expected}"
        )
    replacement = np.asarray(truth_source_state, dtype=np.float64)
    candidate = estimator.filters[expected]
    if replacement.shape != np.asarray(candidate.state).shape:
        raise ValueError("truth source state shape does not match the candidate state")
    if not np.all(np.isfinite(replacement)):
        raise ValueError("truth source state must be finite")

    state_before = candidate.state.copy()
    covariance_before = candidate.covariance.copy()
    probabilities_before = probabilities.copy()
    candidate.state = replacement.copy()
    return StateMeanInterventionRecord(
        source_index=expected,
        state_before=state_before,
        state_after=candidate.state.copy(),
        covariance_before=covariance_before,
        covariance_after=candidate.covariance.copy(),
        probabilities_before=probabilities_before,
        probabilities_after=np.asarray(estimator.probabilities).copy(),
    )


def validate_run_paths(source_task, frozen_root, output_root):
    """Validate source and output isolation before any diagnostic write."""
    source = Path(source_task).resolve()
    frozen = Path(frozen_root).resolve()
    output = Path(output_root).resolve()
    if not frozen.is_dir():
        raise FileNotFoundError(f"frozen result root is missing: {frozen}")
    if not source.is_file():
        raise FileNotFoundError(f"source task is missing: {source}")
    if frozen not in source.parents:
        raise ValueError("source task must be inside the frozen result root")
    if output.exists():
        raise FileExistsError(f"output root already exists: {output}")
    if output == frozen or frozen in output.parents:
        raise ValueError("output root must be outside the frozen result root")
    return source, frozen, output


def _sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json_new(path: str | Path, payload: dict) -> None:
    target = Path(path)
    encoded = (
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")
    with target.open("xb") as handle:
        handle.write(encoded)


def _load_source(path: str | Path) -> dict[str, np.ndarray]:
    with np.load(Path(path), allow_pickle=False) as archive:
        missing = sorted(set(SOURCE_FIELDS) - set(archive.files))
        if missing:
            raise ValueError(f"source task is missing fields: {missing}")
        source = {name: archive[name].copy() for name in SOURCE_FIELDS}
    if str(source["basin_id"].item()) != BASIN_ID:
        raise ValueError(f"diagnostic is locked to basin {BASIN_ID}")
    if int(source["seed"].item()) != SEED:
        raise ValueError(f"diagnostic is locked to seed {SEED}")
    if str(source["arm_id"].item()) != "P":
        raise ValueError("source task must be the frozen nine-path arm")
    if str(source["state_interaction_mode"].item()) != "pairwise_path_postcollapse":
        raise ValueError("source task must use pairwise-path post-observation collapse")
    if str(source["parameter_state_mapping"].item()) != "conservative_parfc":
        raise ValueError("source task must use conservative parFC state mapping")
    if str(source["filter_q_mode"].item()) != "fixed":
        raise ValueError("source task must use the registered fixed process covariance")
    if source["probabilities"].shape != (WINDOW_DAYS, 3):
        raise ValueError("source task must contain 1260 days and three candidates")
    if source["candidate_parameter_vectors"].shape != (3, len(PARAM_KEYS)):
        raise ValueError("source task candidate parameter shape is invalid")
    if source["path_initial_states"].shape != (3, N_STATE):
        raise ValueError("source task initial state shape is invalid")
    if source["path_initial_covariances"].shape != (3, N_STATE, N_STATE):
        raise ValueError("source task initial covariance shape is invalid")
    if source["path_source_states"].shape != (WINDOW_DAYS, 3, N_STATE):
        raise ValueError("source task source-state audit shape is invalid")
    if source["path_source_covariances"].shape != (
        WINDOW_DAYS,
        3,
        N_STATE,
        N_STATE,
    ):
        raise ValueError("source task source-covariance audit shape is invalid")
    return source


def _members_and_initial_hydrology(source: dict[str, np.ndarray]):
    names = tuple(str(value) for value in source["candidate_parameter_names"])
    if names != tuple(PARAM_KEYS):
        raise ValueError("candidate parameter names do not match the registered order")
    members = [
        {name: float(value) for name, value in zip(names, row)}
        for row in source["candidate_parameter_vectors"]
    ]
    initial_hydrology = source["path_initial_states"][0, :N_HYDRO].copy()
    return members, initial_hydrology


def _truth_replay_from_source(source: dict[str, np.ndarray]) -> TruthReplay:
    members, initial_hydrology = _members_and_initial_hydrology(source)
    rng = np.random.default_rng(
        np.random.SeedSequence((SEED_ENTROPY, int(BASIN_ID), SEED))
    )
    replay = replay_truth_with_states(
        members,
        source["rain"],
        source["pet"],
        source["temperature"],
        initial_hydrology,
        rng,
        resolve_hbv_bounds("v5"),
    )
    if not np.array_equal(replay.discharge, source["truth_q"]):
        raise ValueError("replayed truth discharge does not bitwise match the source task")
    if not np.array_equal(replay.parfc, source["truth_parfc"]):
        raise ValueError("replayed truth parFC does not bitwise match the source task")
    expected_switch_days = tuple(
        zip(
            source["switch_days"].tolist(),
            source["rotation"][1:].tolist(),
        )
    )
    if replay.switch_days != expected_switch_days:
        raise ValueError("replayed switch days do not match the source task")
    if replay.clip_count != int(source["truth_clip_count"].item()):
        raise ValueError("replayed truth clip count does not match the source task")
    return replay


def _build_gaussian_path_estimator(source: dict[str, np.ndarray]):
    members, initial_hydrology = _members_and_initial_hydrology(source)
    estimator, transitions = _build_bank(
        members,
        initial_hydrology,
        float(source["observation_sigma"].item()),
        resolve_hbv_bounds("v5"),
        q_scale=float(source["filter_process_variance_scale"].item()),
        q_structure=str(source["filter_process_covariance_structure"].item()),
        q_mode=str(source["filter_q_mode"].item()),
        q_state_multiplier=float(source["filter_q_state_multiplier"].item()),
        filter_r_multiplier=float(
            source["filter_observation_variance_multiplier"].item()
        ),
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
        model_evidence_scorer=None,
    )
    if estimator.model_evidence_scorer is not None:
        raise ValueError("counterfactual must use the original Gaussian model evidence")
    observed_states = np.asarray([item.state for item in estimator.filters])
    observed_covariances = np.asarray(
        [item.covariance for item in estimator.filters]
    )
    if not np.array_equal(observed_states, source["path_initial_states"]):
        raise ValueError("rebuilt initial states do not bitwise match the source task")
    if not np.array_equal(
        observed_covariances,
        source["path_initial_covariances"],
    ):
        raise ValueError("rebuilt initial covariances do not bitwise match the source task")
    if not np.array_equal(
        estimator.probabilities,
        source["path_initial_probabilities"],
    ):
        raise ValueError("rebuilt initial probabilities do not bitwise match the source task")
    return estimator, transitions


def _assert_bitwise_equal(observed, expected, message: str) -> None:
    observed_array = np.asarray(observed)
    expected_array = np.asarray(expected)
    supports_nan = observed_array.dtype.kind in "fc" and expected_array.dtype.kind in "fc"
    if not np.array_equal(
        observed_array,
        expected_array,
        equal_nan=supports_nan,
    ):
        raise AssertionError(message)


def run_counterfactual_arrays(source: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    """Run the locked online counterfactual and return its complete audit arrays."""
    truth = _truth_replay_from_source(source)
    estimator, transitions = _build_gaussian_path_estimator(source)
    n_days, n_candidates = source["probabilities"].shape
    probabilities = np.empty((n_days, n_candidates), dtype=np.float64)
    log_probabilities = np.empty_like(probabilities)
    source_probabilities = np.empty_like(probabilities)
    source_states = np.empty((n_days, n_candidates, N_STATE), dtype=np.float64)
    source_covariances = np.empty(
        (n_days, n_candidates, N_STATE, N_STATE),
        dtype=np.float64,
    )
    branch_shape = (n_days, n_candidates, n_candidates)
    branch_prior_logs = np.empty(branch_shape, dtype=np.float64)
    branch_model_evidence = np.full(branch_shape, -np.inf, dtype=np.float64)
    branch_gaussian_likelihoods = np.full(branch_shape, np.nan, dtype=np.float64)
    branch_posterior_logs = np.empty(branch_shape, dtype=np.float64)
    branch_posterior_probabilities = np.empty(branch_shape, dtype=np.float64)
    branch_active_mask = np.zeros(branch_shape, dtype=bool)
    combined_states = np.empty((n_days, N_STATE), dtype=np.float64)
    combined_covariances = np.empty((n_days, N_STATE, N_STATE), dtype=np.float64)
    intervention_record = None
    intervention_candidate_states_before = None
    intervention_candidate_states_after = None
    intervention_candidate_covariances_before = None
    intervention_global_state_before = None
    intervention_global_state_after = None
    intervention_global_covariance_before = None
    intervention_global_covariance_after = None

    for day in range(n_days):
        current_probabilities = estimator.probabilities.copy()
        current_states = np.asarray(
            [candidate.state.copy() for candidate in estimator.filters]
        )
        current_covariances = np.asarray(
            [candidate.covariance.copy() for candidate in estimator.filters]
        )
        if day <= INTERVENTION_DAY:
            _assert_bitwise_equal(
                current_probabilities,
                source["path_source_probabilities"][day],
                f"pre-intervention source probabilities diverged on day {day}",
            )
            _assert_bitwise_equal(
                current_states,
                source["path_source_states"][day],
                f"pre-intervention source states diverged on day {day}",
            )
            _assert_bitwise_equal(
                current_covariances,
                source["path_source_covariances"][day],
                f"pre-intervention source covariances diverged on day {day}",
            )

        if day == INTERVENTION_DAY:
            intervention_candidate_states_before = current_states.copy()
            intervention_candidate_covariances_before = current_covariances.copy()
            intervention_global_state_before = estimator.state.copy()
            intervention_global_covariance_before = estimator.covariance.copy()
            intervention_record = apply_truth_state_mean_intervention(
                estimator,
                truth.source_states[day],
                expected_source_index=INTERVENTION_SOURCE_INDEX,
            )
            intervention_candidate_states_after = np.asarray(
                [candidate.state.copy() for candidate in estimator.filters]
            )
            intervention_global_state_after = estimator.state.copy()
            intervention_global_covariance_after = estimator.covariance.copy()
            current_states = intervention_candidate_states_after.copy()

        source_probabilities[day] = estimator.probabilities
        source_states[day] = current_states
        source_covariances[day] = np.asarray(
            [candidate.covariance.copy() for candidate in estimator.filters]
        )
        for transition in transitions:
            transition.set_forcing(
                source["rain"][day],
                source["pet"][day],
                source["temperature"][day],
            )
        result = estimator.step(np.array([source["observations"][day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
        branch_prior_logs[day] = result.branch_prior_log_probabilities
        branch_model_evidence[day] = result.branch_log_evidences
        branch_posterior_logs[day] = result.branch_posterior_log_probabilities
        branch_posterior_probabilities[day] = result.branch_posterior_probabilities
        branch_active_mask[day] = result.branch_active_mask
        combined_states[day] = result.combined_state
        combined_covariances[day] = result.combined_covariance
        for source_index in range(n_candidates):
            for destination_index in range(n_candidates):
                branch = result.branch_results[source_index][destination_index]
                if branch is not None:
                    branch_gaussian_likelihoods[
                        day,
                        source_index,
                        destination_index,
                    ] = branch.log_likelihood

    if intervention_record is None:
        raise AssertionError("the registered day-540 intervention was not applied")
    _assert_bitwise_equal(
        branch_model_evidence,
        np.where(branch_active_mask, branch_gaussian_likelihoods, -np.inf),
        "saved model evidence is not the original Gaussian branch likelihood",
    )
    _assert_bitwise_equal(
        intervention_candidate_states_after[:INTERVENTION_SOURCE_INDEX],
        intervention_candidate_states_before[:INTERVENTION_SOURCE_INDEX],
        "a nonintervened candidate state changed",
    )
    _assert_bitwise_equal(
        intervention_candidate_states_after[INTERVENTION_SOURCE_INDEX + 1 :],
        intervention_candidate_states_before[INTERVENTION_SOURCE_INDEX + 1 :],
        "a nonintervened candidate state changed",
    )
    _assert_bitwise_equal(
        intervention_candidate_covariances_before,
        source["path_source_covariances"][INTERVENTION_DAY],
        "intervention covariance snapshot differs from the frozen source",
    )
    _assert_bitwise_equal(
        intervention_record.covariance_after,
        intervention_record.covariance_before,
        "the intervention changed the source-candidate covariance",
    )
    _assert_bitwise_equal(
        intervention_record.probabilities_after,
        intervention_record.probabilities_before,
        "the intervention changed candidate probabilities",
    )
    _assert_bitwise_equal(
        intervention_global_state_after,
        intervention_global_state_before,
        "the intervention changed the stored global state",
    )
    _assert_bitwise_equal(
        intervention_global_covariance_after,
        intervention_global_covariance_before,
        "the intervention changed the stored global covariance",
    )
    return {
        "probabilities": probabilities,
        "log_probabilities": log_probabilities,
        "baseline_probabilities": source["probabilities"].copy(),
        "baseline_log_probabilities": source["log_probabilities"].copy(),
        "true_candidate_indices": source["true_candidate_indices"].copy(),
        "truth_q": source["truth_q"].copy(),
        "observations": source["observations"].copy(),
        "rain": source["rain"].copy(),
        "pet": source["pet"].copy(),
        "temperature": source["temperature"].copy(),
        "truth_source_states": truth.source_states.copy(),
        "truth_posterior_states": truth.posterior_states.copy(),
        "source_probabilities": source_probabilities,
        "source_states": source_states,
        "source_covariances": source_covariances,
        "branch_prior_log_probabilities": branch_prior_logs,
        "branch_model_log_evidences": branch_model_evidence,
        "branch_gaussian_log_likelihoods": branch_gaussian_likelihoods,
        "branch_posterior_log_probabilities": branch_posterior_logs,
        "branch_posterior_probabilities": branch_posterior_probabilities,
        "branch_active_mask": branch_active_mask,
        "combined_states": combined_states,
        "combined_covariances": combined_covariances,
        "basin_id": np.array(BASIN_ID),
        "seed": np.array(SEED, dtype=np.int64),
        "model_evidence_distribution": np.array("gaussian"),
        "state_interaction_mode": np.array("pairwise_path_postcollapse"),
        "parameter_state_mapping": np.array("conservative_parfc"),
        "intervention_day": np.array(INTERVENTION_DAY, dtype=np.int64),
        "intervention_count": np.array(1, dtype=np.int64),
        "intervention_source_index": np.array(
            INTERVENTION_SOURCE_INDEX,
            dtype=np.int64,
        ),
        "intervention_target_index": np.array(
            INTERVENTION_TARGET_INDEX,
            dtype=np.int64,
        ),
        "intervention_state_before": intervention_record.state_before.copy(),
        "intervention_state_after": intervention_record.state_after.copy(),
        "intervention_truth_source_state": truth.source_states[
            INTERVENTION_DAY
        ].copy(),
        "intervention_state_delta": (
            intervention_record.state_after - intervention_record.state_before
        ),
        "intervention_covariance_before": (
            intervention_record.covariance_before.copy()
        ),
        "intervention_covariance_after": (
            intervention_record.covariance_after.copy()
        ),
        "intervention_probabilities_before": (
            intervention_record.probabilities_before.copy()
        ),
        "intervention_probabilities_after": (
            intervention_record.probabilities_after.copy()
        ),
        "intervention_candidate_states_before": (
            intervention_candidate_states_before.copy()
        ),
        "intervention_candidate_states_after": (
            intervention_candidate_states_after.copy()
        ),
        "intervention_candidate_covariances_before": (
            intervention_candidate_covariances_before.copy()
        ),
        "intervention_global_state_before": intervention_global_state_before.copy(),
        "intervention_global_state_after": intervention_global_state_after.copy(),
        "intervention_global_covariance_before": (
            intervention_global_covariance_before.copy()
        ),
        "intervention_global_covariance_after": (
            intervention_global_covariance_after.copy()
        ),
    }


def _longest_run(mask) -> int:
    longest = current = 0
    for value in np.asarray(mask, dtype=bool):
        current = current + 1 if value else 0
        longest = max(longest, current)
    return int(longest)


def _metrics(probabilities, log_probabilities, true_indices, start, end) -> dict:
    probabilities = np.asarray(probabilities)[start:end]
    log_probabilities = np.asarray(log_probabilities)[start:end]
    true_indices = np.asarray(true_indices, dtype=np.int64)[start:end]
    row = np.arange(end - start)
    true_probabilities = probabilities[row, true_indices]
    true_log_probabilities = log_probabilities[row, true_indices]
    truth = np.eye(probabilities.shape[1], dtype=np.float64)[true_indices]
    return {
        "start_day": int(start),
        "end_day_inclusive": int(end - 1),
        "days": int(end - start),
        "mean_true_probability": float(np.mean(true_probabilities)),
        "median_true_probability": float(np.median(true_probabilities)),
        "final_true_probability": float(true_probabilities[-1]),
        "multiclass_brier_score": float(
            np.mean(np.sum((probabilities - truth) ** 2, axis=1))
        ),
        "mean_true_negative_log_probability": float(
            np.mean(-true_log_probabilities)
        ),
        "zero_true_probability_days": int(np.sum(true_probabilities == 0.0)),
        "true_probability_below_0_01_days": int(
            np.sum(true_probabilities < 0.01)
        ),
        "true_probability_above_0_5_days": int(
            np.sum(true_probabilities > 0.5)
        ),
        "longest_above_0_5_run_days": _longest_run(
            true_probabilities > 0.5
        ),
        "longest_below_0_01_run_days": _longest_run(
            true_probabilities < 0.01
        ),
    }


def _events(probabilities, source: dict[str, np.ndarray]) -> list[dict]:
    switch_pairs = tuple(
        zip(
            source["switch_days"].tolist(),
            source["rotation"][1:].tolist(),
        )
    )
    return [
        {
            "switch_day": int(event["switch_day"]),
            "new_member": int(event["new_member"]),
            "passed": bool(event["passed"]),
            "response_start_days": (
                None
                if event["response_start"] is None
                else int(event["response_start"])
            ),
        }
        for event in _evaluate_events(probabilities, switch_pairs)
    ]


def summarize_counterfactual(
    arrays: dict[str, np.ndarray],
    source: dict[str, np.ndarray],
) -> dict:
    true_indices = arrays["true_candidate_indices"]
    baseline_events = _events(arrays["baseline_probabilities"], source)
    counterfactual_events = _events(arrays["probabilities"], source)

    def summarize_arm(probability_key, log_key, events):
        return {
            "events_passed": int(sum(event["passed"] for event in events)),
            "events_total": len(events),
            "events": events,
            "full_period": _metrics(
                arrays[probability_key],
                arrays[log_key],
                true_indices,
                0,
                WINDOW_DAYS,
            ),
            "days_540_719": _metrics(
                arrays[probability_key],
                arrays[log_key],
                true_indices,
                540,
                720,
            ),
            "days_720_899": _metrics(
                arrays[probability_key],
                arrays[log_key],
                true_indices,
                720,
                900,
            ),
        }

    baseline = summarize_arm(
        "baseline_probabilities",
        "baseline_log_probabilities",
        baseline_events,
    )
    counterfactual = summarize_arm(
        "probabilities",
        "log_probabilities",
        counterfactual_events,
    )
    baseline_event = next(
        event for event in baseline_events if event["switch_day"] == INTERVENTION_DAY
    )
    counterfactual_event = next(
        event
        for event in counterfactual_events
        if event["switch_day"] == INTERVENTION_DAY
    )
    baseline_stage = baseline["days_540_719"]
    counterfactual_stage = counterfactual["days_540_719"]
    return {
        "experiment_id": EXPERIMENT_ID,
        "baseline": baseline,
        "counterfactual": counterfactual,
        "day540_intervention": {
            "source_candidate_index": INTERVENTION_SOURCE_INDEX,
            "new_true_candidate_index": INTERVENTION_TARGET_INDEX,
            "baseline_event_passed": baseline_event["passed"],
            "counterfactual_event_passed": counterfactual_event["passed"],
            "counterfactual_response_start_days": counterfactual_event[
                "response_start_days"
            ],
            "zero_day_reduction": int(
                baseline_stage["zero_true_probability_days"]
                - counterfactual_stage["zero_true_probability_days"]
            ),
            "mean_true_probability_change": float(
                counterfactual_stage["mean_true_probability"]
                - baseline_stage["mean_true_probability"]
            ),
            "multiclass_brier_change": float(
                counterfactual_stage["multiclass_brier_score"]
                - baseline_stage["multiclass_brier_score"]
            ),
        },
        "claim_boundary": {
            "causal_state_trigger_diagnostic": "tested_for_one_basin_seed",
            "operational_method": "not_tested",
            "cross_basin_generality": "not_tested",
            "complete_state_accuracy": "not_tested",
            "forecast_value": "not_tested",
            "real_observation_assimilation_value": "not_tested",
        },
    }


def _implementation_hashes(repo_root: Path, source_task: Path) -> dict:
    paths = {
        "source_task": source_task,
        "runner": Path(__file__),
        "g2_switch_confirmation": (
            repo_root / "src/camels_switch_confirmation/g2_switch_confirmation.py"
        ),
        "imm": repo_root / "src/hbv_joint_uncertainty/imm.py",
        "hbv_adapter": repo_root / "src/hbv_joint_uncertainty/hbv_adapter.py",
        "hbv_state_mapping": (
            repo_root / "src/hbv_joint_uncertainty/hbv_state_mapping.py"
        ),
        "sigma_filter": repo_root / "src/hbv_joint_uncertainty/sigma_filter.py",
    }
    return {
        name: {"path": str(path.resolve()), "sha256": _sha256_file(path)}
        for name, path in paths.items()
    }


def run_counterfactual(source_task, frozen_root, output_root) -> dict:
    source_path, frozen_path, output_path = validate_run_paths(
        source_task,
        frozen_root,
        output_root,
    )
    fingerprint_before = collection_fingerprint(frozen_path)
    if (
        fingerprint_before["sha256_of_newline_joined_sorted_entries"]
        != EXPECTED_FROZEN_FINGERPRINT
    ):
        raise ValueError("frozen result fingerprint does not match the registered value")
    source = _load_source(source_path)
    arrays = run_counterfactual_arrays(source)
    summary = summarize_counterfactual(arrays, source)
    fingerprint_after = collection_fingerprint(frozen_path)
    if fingerprint_after != fingerprint_before:
        raise RuntimeError("frozen result collection changed during the diagnostic")
    repo_root = Path(__file__).resolve().parents[2]
    git_head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    contract = {
        "experiment_id": EXPERIMENT_ID,
        "status": "single_truth_state_counterfactual_not_operational_method",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "basin_id": BASIN_ID,
        "seed": SEED,
        "task_count": 1,
        "changed_factor": (
            "day540_preupdate_dominant_source_candidate_fifteen_state_mean_"
            "replaced_with_synthetic_truth"
        ),
        "fixed_factors": {
            "model_evidence_distribution": "gaussian",
            "state_interaction_mode": "pairwise_path_postcollapse",
            "parameter_state_mapping": "conservative_parfc",
            "candidate_probabilities_at_intervention": "unchanged",
            "candidate_covariances_at_intervention": "unchanged",
            "forcing_observations_parameters_transition_and_noise": "unchanged",
        },
        "intervention_day": INTERVENTION_DAY,
        "intervention_source_index": INTERVENTION_SOURCE_INDEX,
        "intervention_target_index": INTERVENTION_TARGET_INDEX,
        "source_frozen_root": str(frozen_path),
        "source_frozen_fingerprint_before": fingerprint_before,
        "implementation": _implementation_hashes(repo_root, source_path),
        "git_head": git_head,
        "runtime": {
            "python": sys.version,
            "executable": sys.executable,
            "platform": platform.platform(),
            "numpy": np.__version__,
        },
        "claim_boundary": summary["claim_boundary"],
    }
    output_path.mkdir(parents=True, exist_ok=False)
    _write_json_new(output_path / "run_contract.json", contract)
    _atomic_save_npz(output_path / "counterfactual.npz", **arrays)
    _write_json_new(output_path / "summary.json", summary)
    return summary


def _load_result(path: Path) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as archive:
        return {name: archive[name].copy() for name in archive.files}


def verify_counterfactual(source_task, frozen_root, output_root) -> dict:
    source_path = Path(source_task).resolve()
    frozen_path = Path(frozen_root).resolve()
    output_path = Path(output_root).resolve()
    if not frozen_path.is_dir():
        raise FileNotFoundError(f"frozen result root is missing: {frozen_path}")
    if not source_path.is_file():
        raise FileNotFoundError(f"source task is missing: {source_path}")
    if frozen_path not in source_path.parents:
        raise ValueError("source task must be inside the frozen result root")
    if output_path == frozen_path or frozen_path in output_path.parents:
        raise ValueError("output root must be outside the frozen result root")
    if not output_path.is_dir():
        raise FileNotFoundError(f"counterfactual output root is missing: {output_path}")
    verification_path = output_path / "verification.json"
    if verification_path.exists():
        raise FileExistsError(f"verification already exists: {verification_path}")
    with (output_path / "run_contract.json").open(encoding="utf-8") as handle:
        contract = json.load(handle)
    if contract.get("experiment_id") != EXPERIMENT_ID:
        raise AssertionError("run contract experiment identity is invalid")
    if contract.get("basin_id") != BASIN_ID or int(contract.get("seed", -1)) != SEED:
        raise AssertionError("run contract task identity is invalid")
    if (
        contract["source_frozen_fingerprint_before"][
            "sha256_of_newline_joined_sorted_entries"
        ]
        != EXPECTED_FROZEN_FINGERPRINT
    ):
        raise AssertionError("run contract frozen fingerprint is invalid")
    if contract["implementation"]["source_task"]["sha256"] != _sha256_file(
        source_path
    ):
        raise AssertionError("run contract source-task hash is invalid")
    source = _load_source(source_path)
    saved = _load_result(output_path / "counterfactual.npz")
    replayed = run_counterfactual_arrays(source)
    if set(saved) != set(replayed):
        raise AssertionError("saved and replayed result fields differ")
    for name in sorted(saved):
        _assert_bitwise_equal(
            saved[name],
            replayed[name],
            f"saved result field does not bitwise replay: {name}",
        )
    recomputed_summary = summarize_counterfactual(saved, source)
    with (output_path / "summary.json").open(encoding="utf-8") as handle:
        recorded_summary = json.load(handle)
    if recomputed_summary != recorded_summary:
        raise AssertionError("recorded summary does not match the reloaded result")
    fingerprint = collection_fingerprint(frozen_path)
    if (
        fingerprint["sha256_of_newline_joined_sorted_entries"]
        != EXPECTED_FROZEN_FINGERPRINT
    ):
        raise AssertionError("frozen result fingerprint changed")
    result_files = sorted(
        path for path in output_path.rglob("*") if path.is_file()
    )
    verification = {
        "experiment_id": EXPERIMENT_ID,
        "status": "PASS",
        "truth_discharge_bitwise_replayed": True,
        "preintervention_days_bitwise_match_frozen_source": True,
        "single_state_mean_intervention_replayed": True,
        "saved_result_bitwise_replayed": True,
        "summary_recomputed_after_reload": True,
        "frozen_result_fingerprint": fingerprint,
        "result_files": [
            {
                "path": path.relative_to(output_path).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": _sha256_file(path),
            }
            for path in result_files
        ],
    }
    _write_json_new(verification_path, verification)
    return verification


def _parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("run", "verify"))
    parser.add_argument("--source-task", type=Path, required=True)
    parser.add_argument("--frozen-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    if args.mode == "run":
        payload = run_counterfactual(
            args.source_task,
            args.frozen_root,
            args.output_root,
        )
    else:
        payload = verify_counterfactual(
            args.source_task,
            args.frozen_root,
            args.output_root,
        )
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
