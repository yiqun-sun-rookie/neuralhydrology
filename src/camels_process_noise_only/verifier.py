"""Independently verify CAMELS-US process-noise-only run artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd


_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[2]
for _path in (_REPO_ROOT / "src", _REPO_ROOT):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

from camels_process_noise_only.contract import load_design_config  # noqa: E402
from hbv_joint_uncertainty.hbv_adapter import advance_state  # noqa: E402
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds  # noqa: E402


PARAMETER_KEYS = (
    "parTT",
    "parCFMAX",
    "parCFR",
    "parCWH",
    "parFC",
    "parBETA",
    "parLP",
    "parK0",
    "parK1",
    "parUZL",
    "parPERC",
    "parK2",
    "lag_time",
)
N_STATE = 15
N_CANDIDATES = 3


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _registered_file(relative_value: str, label: str) -> Path:
    relative = Path(str(relative_value))
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"{label} must be repository relative")
    path = _REPO_ROOT / relative
    if not path.is_file():
        raise FileNotFoundError(f"registered {label} is missing: {path}")
    return path


def verify_registered_inputs_independently(config: Mapping) -> dict:
    """Rehash the registered tables and all raw files after a completed run."""
    inputs = config["inputs"]
    selection = config["design_selection"]
    registered = (
        (
            _registered_file(
                inputs["forcing_input_manifest"], "forcing input manifest"
            ),
            inputs["forcing_input_manifest_sha256"],
            "forcing input manifest",
        ),
        (
            _registered_file(
                inputs["forcing_coverage_table"], "forcing coverage table"
            ),
            inputs["forcing_coverage_table_sha256"],
            "forcing coverage table",
        ),
        (
            _registered_file(selection["basin_list"], "basin list"),
            selection["basin_list_sha256"],
            "basin list",
        ),
        (
            _registered_file(inputs["parameter_table"], "parameter table"),
            inputs["parameter_table_sha256"],
            "parameter table",
        ),
        (
            _registered_file(inputs["g1_precheck_table"], "precheck table"),
            inputs["g1_precheck_table_sha256"],
            "precheck table",
        ),
    )
    for path, expected_hash, label in registered:
        observed_hash = _sha256_file(path)
        if observed_hash != str(expected_hash):
            raise ValueError(
                f"registered {label} SHA-256 changed: expected {expected_hash}, "
                f"observed {observed_hash}"
            )
    manifest_path = registered[0][0]
    manifest = pd.read_csv(manifest_path, keep_default_na=False)
    required = {"category", "basin_id", "relative_path", "bytes", "sha256"}
    if not required.issubset(manifest.columns):
        raise ValueError("registered input manifest lacks required columns")
    if manifest["relative_path"].duplicated().any():
        raise ValueError("registered input manifest contains duplicate paths")
    for row in manifest.itertuples(index=False):
        path = _registered_file(row.relative_path, "input file")
        if path.stat().st_size != int(row.bytes):
            raise ValueError(f"registered input file size changed: {row.relative_path}")
        if _sha256_file(path) != str(row.sha256):
            raise ValueError(
                f"registered input file SHA-256 changed: {row.relative_path}"
            )
    return {
        "forcing_input_manifest_sha256": _sha256_file(manifest_path),
        "forcing_input_manifest_rows": int(len(manifest)),
        "forcing_coverage_table_sha256": _sha256_file(registered[1][0]),
        "basin_list_sha256": _sha256_file(registered[2][0]),
        "parameter_table_sha256": _sha256_file(registered[3][0]),
        "g1_precheck_table_sha256": _sha256_file(registered[4][0]),
    }


def _rising_routed_discharge(state: np.ndarray, lag_time: float) -> float:
    n_lag = max(1, int(np.ceil(min(float(lag_time), 10.0))))
    weights = np.arange(1, n_lag + 1, dtype=np.float64)
    weights /= weights.sum()
    return float(weights @ state[5 : 5 + n_lag])


def _independent_physical_projection(
    state: np.ndarray,
    parameters: Mapping[str, float],
) -> np.ndarray:
    """Reconstruct the fifteen-state physical projection without runner code."""
    raw = np.asarray(state, dtype=np.float64)
    if raw.shape != (N_STATE,) or not np.all(np.isfinite(raw)):
        raise ValueError("truth state must be one finite fifteen-state vector")
    projected = raw.copy()
    projected[0] = max(float(projected[0]), 0.0)
    maximum_meltwater = float(parameters["parCWH"]) * projected[0]
    projected[1] = np.clip(projected[1], 0.0, maximum_meltwater)
    projected[2] = np.clip(projected[2], 1e-5, float(parameters["parFC"]))
    projected[3:] = np.maximum(projected[3:], 0.0)
    return projected


def _independent_domain_projection_check(
    raw_state: np.ndarray,
    projected_state: np.ndarray,
    tolerance_multiplier: float,
) -> dict:
    """Independently apply the registered componentwise float64 tolerance."""
    raw = np.asarray(raw_state, dtype=np.float64)
    projected = np.asarray(projected_state, dtype=np.float64)
    difference = np.abs(projected - raw)
    scale = np.maximum.reduce(
        (np.ones_like(raw), np.abs(raw), np.abs(projected))
    )
    tolerance = (
        float(tolerance_multiplier) * np.finfo(np.float64).eps * scale
    )
    ratios = difference / tolerance
    return {
        "maximum_absolute_difference": float(np.max(difference)),
        "maximum_tolerance_ratio": float(np.max(ratios)),
        "nonzero_difference_count": int(np.count_nonzero(difference)),
        "violated": bool(np.any(difference > tolerance)),
    }


def verify_probability_evidence(
    probabilities,
    log_probabilities,
    tolerance: float,
) -> dict:
    """Verify ordinary and log probability arrays without score clipping."""
    values = np.asarray(probabilities, dtype=np.float64)
    logs = np.asarray(log_probabilities, dtype=np.float64)
    if values.ndim != 2 or values.shape[1] != N_CANDIDATES:
        raise ValueError("probabilities must have shape (days, 3)")
    if logs.shape != values.shape:
        raise ValueError("log probabilities must match probability shape")
    if not np.all(np.isfinite(values)) or np.any(values < 0.0):
        raise ValueError("probabilities must be finite and nonnegative")
    if not np.all(np.isfinite(logs)):
        raise ValueError("log probabilities must be finite")
    sum_error = float(np.max(np.abs(values.sum(axis=1) - 1.0)))
    if sum_error > float(tolerance):
        raise ValueError(
            f"daily probability sum error {sum_error} exceeds {tolerance}"
        )
    reconstructed = np.exp(logs)
    reconstruction_error = float(np.max(np.abs(reconstructed - values)))
    if not np.allclose(
        reconstructed,
        values,
        rtol=1e-12,
        atol=np.finfo(np.float64).tiny,
    ):
        raise ValueError(
            "ordinary probability and log probability evidence disagree; "
            f"maximum error is {reconstruction_error}"
        )
    return {
        "maximum_probability_sum_error": sum_error,
        "maximum_probability_log_reconstruction_error": reconstruction_error,
        "zero_probability_count": int(np.sum(values == 0.0)),
    }


def independent_event(probabilities, true_index: int, config: Mapping) -> dict:
    """Recompute one event without importing the runner contract scorer."""
    values = np.asarray(probabilities, dtype=np.float64)
    if values.ndim != 2 or values.shape[1] != N_CANDIDATES or len(values) < 180:
        raise ValueError("event probabilities must contain at least 180 days and 3 candidates")
    if not np.all(np.isfinite(values)) or np.any(values < 0.0):
        raise ValueError("event probabilities must be finite and nonnegative")
    if not np.allclose(values.sum(axis=1), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("event probability rows must sum to one")
    candidate = int(true_index)
    if candidate not in (0, 1, 2):
        raise ValueError("true_index must be 0, 1, or 2")
    start = int(config["event_rule"]["scoring_day_start_one_based"]) - 1
    end = int(config["event_rule"]["scoring_day_end_one_based"])
    segment = values[start:end]
    means = segment.mean(axis=0)
    true_mean = float(means[candidate])
    runner_up = float(np.max(np.delete(means, candidate)))
    margin = true_mean - runner_up
    other_daily = np.max(np.delete(segment, candidate, axis=1), axis=1)
    argmax_days = int(np.sum(segment[:, candidate] > other_daily))
    rules = config["event_rule"]
    passed = bool(
        true_mean >= float(rules["minimum_mean_true_probability"])
        and margin >= float(rules["minimum_mean_margin"])
        and argmax_days >= int(rules["minimum_true_daily_argmax_days"])
    )
    return {
        "passed": passed,
        "mean_true_probability": true_mean,
        "mean_runner_up_probability": runner_up,
        "mean_margin": float(margin),
        "true_daily_argmax_days": argmax_days,
    }


def _stable_indices(config: Mapping) -> np.ndarray:
    stage_days = int(config["truth"]["stage_days"])
    start = int(config["probability_metrics"]["stable_day_start_one_based"]) - 1
    end = int(config["probability_metrics"]["stable_day_end_one_based"])
    result = []
    for stage in range(1, len(config["truth"]["rotation"])):
        offset = stage * stage_days
        result.extend(range(offset + start, offset + end))
    return np.asarray(result, dtype=np.int64)


def _classwise_calibration_error(
    probabilities: np.ndarray,
    truth: np.ndarray,
    bin_edges: np.ndarray,
) -> float:
    errors = []
    total = len(truth)
    for candidate in range(N_CANDIDATES):
        candidate_probabilities = probabilities[:, candidate]
        outcomes = (truth == candidate).astype(np.float64)
        bins = np.digitize(candidate_probabilities, bin_edges[1:-1], right=False)
        candidate_error = 0.0
        for bin_index in range(len(bin_edges) - 1):
            selected = bins == bin_index
            count = int(selected.sum())
            if count == 0:
                continue
            candidate_error += count / total * abs(
                float(candidate_probabilities[selected].mean())
                - float(outcomes[selected].mean())
            )
        errors.append(candidate_error)
    return float(np.mean(errors))


def _independent_probability_score_arrays(
    probabilities,
    log_probabilities,
    truth_indices,
    config: Mapping,
) -> tuple[dict, np.ndarray, np.ndarray, np.ndarray]:
    ordinary = np.asarray(probabilities, dtype=np.float64)
    logs = np.asarray(log_probabilities, dtype=np.float64)
    truth = np.asarray(truth_indices, dtype=np.int64)
    expected_days = int(config["truth"]["window_days"])
    if ordinary.shape != (expected_days, N_CANDIDATES):
        raise ValueError("probabilities have the wrong full-window shape")
    if logs.shape != ordinary.shape or truth.shape != (expected_days,):
        raise ValueError("log probabilities or truth indices have the wrong shape")
    stable = _stable_indices(config)
    scored_probabilities = ordinary[stable]
    scored_logs = logs[stable]
    scored_truth = truth[stable]
    one_hot = np.eye(N_CANDIDATES)[scored_truth]
    per_day_brier = np.sum((scored_probabilities - one_hot) ** 2, axis=1)
    per_day_negative_log_probability = -scored_logs[
        np.arange(len(stable)), scored_truth
    ]
    calibration = _classwise_calibration_error(
        scored_probabilities,
        scored_truth,
        np.asarray(
            config["probability_metrics"]["calibration_bin_edges"],
            dtype=np.float64,
        ),
    )
    metrics = {
        "n_days": int(len(stable)),
        "multiclass_brier": float(per_day_brier.mean()),
        "true_negative_log_probability": float(
            per_day_negative_log_probability.mean()
        ),
        "classwise_expected_calibration_error": calibration,
    }
    return (
        metrics,
        per_day_brier,
        per_day_negative_log_probability,
        scored_probabilities,
    )


def independent_probability_scores(
    probabilities,
    log_probabilities,
    truth_indices,
    config: Mapping,
) -> dict:
    """Recompute stable-period probability metrics independently."""
    metrics, _, _, _ = _independent_probability_score_arrays(
        probabilities, log_probabilities, truth_indices, config
    )
    return metrics


def apply_success_gate(metrics: Mapping, config: Mapping) -> dict:
    """Apply every registered scientific condition conjunctively."""
    gate = config["success_gate"]
    probability_metrics = config["probability_metrics"]
    direction_rates = metrics["direction_pass_rates"]
    direction_intervals = metrics["direction_pass_rate_intervals"]
    conditions = {
        "overall_event_pass_rate": float(metrics["overall_event_pass_rate"])
        >= float(gate["minimum_overall_event_pass_rate"]),
        "each_direction_event_pass_rate": min(direction_rates.values())
        >= float(gate["minimum_each_direction_pass_rate"]),
        "overall_interval_lower": float(
            metrics["overall_event_pass_rate_interval"]["lower"]
        )
        >= float(gate["minimum_overall_cluster_interval_lower"]),
        "worst_direction_interval_lower": min(
            interval["lower"] for interval in direction_intervals.values()
        )
        >= float(gate["minimum_worst_direction_cluster_interval_lower"]),
        "seed_event_agreement": float(metrics["seed_event_agreement"])
        >= float(gate["minimum_seed_event_agreement"]),
        "brier_mean": float(metrics["multiclass_brier"])
        <= float(probability_metrics["maximum_mean_multiclass_brier"]),
        "brier_interval_upper_below_uniform": float(
            metrics["multiclass_brier_interval"]["upper"]
        )
        < float(probability_metrics["multiclass_brier_uniform_baseline"]),
        "log_score_mean_below_uniform": float(
            metrics["true_negative_log_probability"]
        )
        < float(
            probability_metrics["true_negative_log_probability_uniform_baseline"]
        ),
        "log_score_interval_upper_below_uniform": float(
            metrics["true_negative_log_probability_interval"]["upper"]
        )
        < float(
            probability_metrics["true_negative_log_probability_uniform_baseline"]
        ),
        "calibration_error": float(
            metrics["classwise_expected_calibration_error"]
        )
        <= float(
            probability_metrics["maximum_classwise_expected_calibration_error"]
        ),
    }
    return {
        "scientific_status": "passed" if all(conditions.values()) else "not_passed",
        "conditions": {key: bool(value) for key, value in conditions.items()},
    }


def _expected_truth_indices(config: Mapping) -> np.ndarray:
    return np.repeat(
        np.asarray(config["truth"]["rotation"], dtype=np.int64),
        int(config["truth"]["stage_days"]),
    )


def _verify_task(
    task_path: Path,
    expected_basin_id: str,
    expected_seed: int,
    config: Mapping,
    config_sha256: str,
) -> tuple[list[dict], dict, dict]:
    with np.load(task_path, allow_pickle=False) as archive:
        arrays = {key: archive[key] for key in archive.files}
    required = {
        "basin_id",
        "seed",
        "config_sha256",
        "parameter_names",
        "candidate_parameter_vectors",
        "candidate_lognormal_sigmas",
        "sigma_obs",
        "probabilities",
        "log_probabilities",
        "prior_probabilities",
        "true_candidate_indices",
        "truth_discharge",
        "observations",
        "truth_states",
        "deterministic_lower_groundwater",
        "truth_standard_normals",
        "truth_applied_sigmas",
        "candidate_process_variances",
        "candidate_predicted_lower_groundwater",
        "combined_states",
        "rain",
        "pet",
        "temperature",
        "initial_hydrologic_state",
        "switch_days",
        "switch_old_indices",
        "switch_new_indices",
        "truth_projection_nonzero_day_count",
        "truth_projection_maximum_absolute_difference",
        "truth_projection_maximum_tolerance_ratio",
        "truth_domain_violation_count",
        "truth_state_replacement_count",
        "interaction_mode",
        "observation_variance_multiplier",
    }
    missing = sorted(required.difference(arrays))
    if missing:
        raise ValueError(f"{task_path.name} is missing arrays: {missing}")
    basin_id = str(arrays["basin_id"].item()).zfill(8)
    seed = int(arrays["seed"].item())
    if basin_id != expected_basin_id or seed != expected_seed:
        raise ValueError(f"task identity mismatch in {task_path.name}")
    if str(arrays["config_sha256"].item()) != config_sha256:
        raise ValueError(f"config SHA-256 mismatch in {task_path.name}")
    if str(arrays["interaction_mode"].item()) != "full":
        raise ValueError(f"interaction mode is not full in {task_path.name}")
    if float(arrays["observation_variance_multiplier"].item()) != 1.0:
        raise ValueError(f"observation variance multiplier changed in {task_path.name}")
    if int(arrays["truth_domain_violation_count"].item()) != 0:
        raise ValueError(f"truth physical-domain violation detected in {task_path.name}")
    if int(arrays["truth_state_replacement_count"].item()) != 0:
        raise ValueError(f"truth state replacement detected in {task_path.name}")

    candidate_parameters = np.asarray(
        arrays["candidate_parameter_vectors"], dtype=np.float64
    )
    if candidate_parameters.shape != (3, len(PARAMETER_KEYS)):
        raise ValueError(f"candidate parameter shape mismatch in {task_path.name}")
    if not np.array_equal(candidate_parameters, np.tile(candidate_parameters[0], (3, 1))):
        raise ValueError(f"candidate parameters differ in {task_path.name}")
    parameter_names = tuple(str(value) for value in arrays["parameter_names"])
    if parameter_names != PARAMETER_KEYS:
        raise ValueError(f"parameter order mismatch in {task_path.name}")
    parameters = dict(zip(PARAMETER_KEYS, candidate_parameters[0]))
    expected_sigmas = np.asarray(
        config["truth"]["candidate_lognormal_sigmas"], dtype=np.float64
    )
    if not np.array_equal(arrays["candidate_lognormal_sigmas"], expected_sigmas):
        raise ValueError(f"candidate sigma mismatch in {task_path.name}")

    evidence = verify_probability_evidence(
        arrays["probabilities"],
        arrays["log_probabilities"],
        float(config["integrity"]["probability_sum_absolute_tolerance"]),
    )
    n_days = int(config["truth"]["window_days"])
    expected_truth = _expected_truth_indices(config)
    true_indices = np.asarray(arrays["true_candidate_indices"], dtype=np.int64)
    if not np.array_equal(true_indices, expected_truth):
        raise ValueError(f"true candidate schedule mismatch in {task_path.name}")
    expected_applied_sigmas = expected_sigmas[expected_truth]
    if not np.array_equal(arrays["truth_applied_sigmas"], expected_applied_sigmas):
        raise ValueError(f"applied truth sigma mismatch in {task_path.name}")

    entropy = int(config["seeds"]["entropy"])
    truth_rng = np.random.default_rng(
        np.random.SeedSequence((entropy, int(basin_id), seed, 0))
    )
    expected_normals = truth_rng.normal(size=n_days)
    if not np.array_equal(arrays["truth_standard_normals"], expected_normals):
        raise ValueError(f"truth random stream mismatch in {task_path.name}")
    observation_rng = np.random.default_rng(
        np.random.SeedSequence((entropy, int(basin_id), seed, 1))
    )
    sigma_obs = float(arrays["sigma_obs"].item())
    expected_observations = np.asarray(arrays["truth_discharge"]) + observation_rng.normal(
        0.0, sigma_obs, size=n_days
    )
    observation_error = float(
        np.max(np.abs(expected_observations - arrays["observations"]))
    )
    if observation_error != 0.0:
        raise ValueError(f"observation stream mismatch in {task_path.name}")

    predicted_lower = np.asarray(
        arrays["candidate_predicted_lower_groundwater"], dtype=np.float64
    )
    candidate_variances = np.asarray(
        arrays["candidate_process_variances"], dtype=np.float64
    )
    expected_variances = predicted_lower**2 * np.expm1(expected_sigmas[None, :] ** 2)
    variance_error = float(np.max(np.abs(candidate_variances - expected_variances)))
    if not np.allclose(
        candidate_variances, expected_variances, rtol=1e-14, atol=0.0
    ):
        raise ValueError(f"candidate process variance mismatch in {task_path.name}")

    rain = np.asarray(arrays["rain"], dtype=np.float64)
    pet = np.asarray(arrays["pet"], dtype=np.float64)
    temperature = np.asarray(arrays["temperature"], dtype=np.float64)
    truth_states = np.asarray(arrays["truth_states"], dtype=np.float64)
    deterministic_lower = np.asarray(
        arrays["deterministic_lower_groundwater"], dtype=np.float64
    )
    if rain.shape != (n_days,) or pet.shape != (n_days,) or temperature.shape != (n_days,):
        raise ValueError(f"forcing shape mismatch in {task_path.name}")
    if truth_states.shape != (n_days, N_STATE):
        raise ValueError(f"truth state shape mismatch in {task_path.name}")
    state = np.zeros(N_STATE, dtype=np.float64)
    state[:5] = np.asarray(arrays["initial_hydrologic_state"], dtype=np.float64)
    tolerance_multiplier = float(
        config["truth"]["domain_check"]["tolerance_multiplier"]
    )
    initial_domain_check = _independent_domain_projection_check(
        state,
        _independent_physical_projection(state, parameters),
        tolerance_multiplier,
    )
    if initial_domain_check["violated"]:
        raise ValueError(f"initial truth state violates the domain in {task_path.name}")
    replay_states = np.empty_like(truth_states)
    replay_discharge = np.empty(n_days, dtype=np.float64)
    replay_deterministic_lower = np.empty(n_days, dtype=np.float64)
    projection_nonzero_day_count = 0
    projection_maximum_absolute_difference = 0.0
    projection_maximum_tolerance_ratio = 0.0
    bounds = resolve_hbv_bounds("v5")
    for day in range(n_days):
        state = advance_state(
            state,
            rain[day],
            pet[day],
            temperature[day],
            parameters,
            bounds=bounds,
        )
        replay_deterministic_lower[day] = state[4]
        sigma = expected_applied_sigmas[day]
        state[4] *= np.exp(-0.5 * sigma**2 + sigma * expected_normals[day])
        domain_check = _independent_domain_projection_check(
            state,
            _independent_physical_projection(state, parameters),
            tolerance_multiplier,
        )
        if domain_check["nonzero_difference_count"] > 0:
            projection_nonzero_day_count += 1
        projection_maximum_absolute_difference = max(
            projection_maximum_absolute_difference,
            domain_check["maximum_absolute_difference"],
        )
        projection_maximum_tolerance_ratio = max(
            projection_maximum_tolerance_ratio,
            domain_check["maximum_tolerance_ratio"],
        )
        if domain_check["violated"]:
            raise ValueError(
                f"truth state violates the registered tolerance on day {day} "
                f"in {task_path.name}"
            )
        replay_states[day] = state
        replay_discharge[day] = _rising_routed_discharge(state, parameters["lag_time"])
    state_error = float(np.max(np.abs(replay_states - truth_states)))
    deterministic_error = float(
        np.max(np.abs(replay_deterministic_lower - deterministic_lower))
    )
    discharge_error = float(
        np.max(np.abs(replay_discharge - arrays["truth_discharge"]))
    )
    if state_error != 0.0 or deterministic_error != 0.0 or discharge_error != 0.0:
        raise ValueError(
            f"truth replay mismatch in {task_path.name}: state={state_error}, "
            f"deterministic={deterministic_error}, discharge={discharge_error}"
        )
    stored_nonzero_days = int(
        arrays["truth_projection_nonzero_day_count"].item()
    )
    stored_maximum_difference = float(
        arrays["truth_projection_maximum_absolute_difference"].item()
    )
    stored_maximum_ratio = float(
        arrays["truth_projection_maximum_tolerance_ratio"].item()
    )
    if (
        stored_nonzero_days != projection_nonzero_day_count
        or stored_maximum_difference != projection_maximum_absolute_difference
        or stored_maximum_ratio != projection_maximum_tolerance_ratio
    ):
        raise ValueError(
            f"truth projection diagnostics mismatch in {task_path.name}"
        )

    stage_days = int(config["truth"]["stage_days"])
    rotation = [int(value) for value in config["truth"]["rotation"]]
    expected_switch_days = np.arange(1, len(rotation), dtype=np.int64) * stage_days
    if not np.array_equal(arrays["switch_days"], expected_switch_days):
        raise ValueError(f"switch days mismatch in {task_path.name}")
    if not np.array_equal(arrays["switch_old_indices"], np.asarray(rotation[:-1])):
        raise ValueError(f"switch old indices mismatch in {task_path.name}")
    if not np.array_equal(arrays["switch_new_indices"], np.asarray(rotation[1:])):
        raise ValueError(f"switch new indices mismatch in {task_path.name}")

    events = []
    for event_index, switch_day in enumerate(expected_switch_days):
        old_index = rotation[event_index]
        new_index = rotation[event_index + 1]
        stage_probabilities = arrays["probabilities"][
            switch_day : switch_day + stage_days
        ]
        event = independent_event(stage_probabilities, new_index, config)
        events.append(
            {
                "basin_id": basin_id,
                "seed": seed,
                "event_index": event_index,
                "direction": f"{old_index}->{new_index}",
                "old_candidate": old_index,
                "new_candidate": new_index,
                **event,
            }
        )
    scores, per_day_brier, per_day_nll, stable_probabilities = (
        _independent_probability_score_arrays(
            arrays["probabilities"],
            arrays["log_probabilities"],
            true_indices,
            config,
        )
    )
    task_record = {
        "basin_id": basin_id,
        "seed": seed,
        **scores,
        **evidence,
        "maximum_candidate_variance_error": variance_error,
        "maximum_truth_replay_state_error": state_error,
        "maximum_truth_replay_discharge_error": discharge_error,
        "maximum_observation_replay_error": observation_error,
        "truth_projection_nonzero_day_count": projection_nonzero_day_count,
        "truth_projection_maximum_absolute_difference": (
            projection_maximum_absolute_difference
        ),
        "truth_projection_maximum_tolerance_ratio": (
            projection_maximum_tolerance_ratio
        ),
        "truth_domain_violation_count": 0,
        "truth_state_replacement_count": 0,
        "task_sha256": _sha256_file(task_path),
    }
    score_arrays = {
        "per_day_brier": per_day_brier,
        "per_day_nll": per_day_nll,
        "stable_probabilities": stable_probabilities,
        "stable_truth": true_indices[_stable_indices(config)],
    }
    return events, task_record, score_arrays


def _interval(values: np.ndarray) -> dict:
    return {
        "lower": float(np.percentile(values, 2.5)),
        "upper": float(np.percentile(values, 97.5)),
    }


def _cluster_bootstrap(
    events: pd.DataFrame,
    tasks: pd.DataFrame,
    config: Mapping,
) -> dict:
    basin_ids = sorted(events["basin_id"].unique())
    basin_overall = (
        events.groupby("basin_id")["passed"].mean().reindex(basin_ids).to_numpy()
    )
    direction_table = (
        events.groupby(["basin_id", "direction"])["passed"]
        .mean()
        .unstack("direction")
        .reindex(basin_ids)
    )
    task_basin = tasks.groupby("basin_id")[[
        "multiclass_brier",
        "true_negative_log_probability",
    ]].mean().reindex(basin_ids)
    if direction_table.isna().any().any() or task_basin.isna().any().any():
        raise ValueError("cluster bootstrap inputs are incomplete")
    replicates = int(config["bootstrap"]["replicates"])
    rng = np.random.default_rng(int(config["bootstrap"]["seed"]))
    indices = rng.integers(0, len(basin_ids), size=(replicates, len(basin_ids)))
    overall_samples = basin_overall[indices].mean(axis=1)
    direction_values = direction_table.to_numpy(dtype=np.float64)
    direction_samples = direction_values[indices].mean(axis=1)
    brier_values = task_basin["multiclass_brier"].to_numpy(dtype=np.float64)
    nll_values = task_basin["true_negative_log_probability"].to_numpy(
        dtype=np.float64
    )
    return {
        "overall": _interval(overall_samples),
        "directions": {
            direction: _interval(direction_samples[:, index])
            for index, direction in enumerate(direction_table.columns)
        },
        "brier": _interval(brier_values[indices].mean(axis=1)),
        "negative_log_probability": _interval(nll_values[indices].mean(axis=1)),
    }


def _atomic_json(path: Path, content: Mapping) -> None:
    if path.exists():
        raise FileExistsError(f"verification output already exists: {path}")
    temporary = path.with_suffix(path.suffix + ".tmp")
    if temporary.exists():
        raise FileExistsError(f"verification temporary output exists: {temporary}")
    with temporary.open("x", encoding="utf-8") as handle:
        json.dump(content, handle, indent=2, sort_keys=True)
        handle.write("\n")
    temporary.replace(path)


def _atomic_csv(path: Path, frame: pd.DataFrame) -> None:
    if path.exists():
        raise FileExistsError(f"verification output already exists: {path}")
    temporary = path.with_suffix(path.suffix + ".tmp")
    if temporary.exists():
        raise FileExistsError(f"verification temporary output exists: {temporary}")
    frame.to_csv(temporary, index=False)
    temporary.replace(path)


def verify_run(
    run_dir: str | Path,
    config_path: str | Path,
    basin_list_path: str | Path,
    expected_basin_count: int,
    mode: str,
) -> tuple[dict, dict]:
    """Verify every task, write evidence once, and return integrity/science."""
    if mode not in {"smoke", "design"}:
        raise ValueError("mode must be smoke or design")
    run_path = Path(run_dir).resolve()
    config_path = Path(config_path).resolve()
    basin_list_path = Path(basin_list_path).resolve()
    config = load_design_config(config_path)
    required_basin_count = (
        1 if mode == "smoke" else int(config["design_selection"]["basin_count"])
    )
    if int(expected_basin_count) != required_basin_count:
        raise ValueError(
            f"{mode} verification requires exactly {required_basin_count} basin(s)"
        )
    registered_inputs = verify_registered_inputs_independently(config)
    config_sha256 = _sha256_file(config_path)
    summary_path = run_path / "runner_summary.json"
    records_path = run_path / "runner_records.csv"
    if not summary_path.is_file() or not records_path.is_file():
        raise FileNotFoundError("runner summary or records file is missing")
    with summary_path.open("r", encoding="utf-8") as handle:
        runner_summary = json.load(handle)
    if runner_summary.get("config_sha256") != config_sha256:
        raise ValueError("runner summary config SHA-256 mismatch")
    if runner_summary.get("basin_list_sha256") != _sha256_file(basin_list_path):
        raise ValueError("runner summary basin-list SHA-256 mismatch")
    if _sha256_file(basin_list_path) != registered_inputs["basin_list_sha256"]:
        raise ValueError("supplied basin list differs from the registered basin list")
    if runner_summary.get("seeds") != [0, 1]:
        raise ValueError("runner used unauthorized seeds")
    if runner_summary.get("experiment_id") != config["experiment_id"]:
        raise ValueError("runner experiment identity mismatch")
    if runner_summary.get("configuration_status") != config["configuration_status"]:
        raise ValueError("runner configuration status mismatch")
    if runner_summary.get("configuration_revision") != config[
        "configuration_revision"
    ]:
        raise ValueError("runner configuration revision mismatch")
    for field in (
        "forcing_input_manifest_sha256",
        "forcing_coverage_table_sha256",
        "parameter_table_sha256",
        "g1_precheck_table_sha256",
    ):
        if runner_summary.get(field) != registered_inputs[field]:
            raise ValueError(f"runner summary {field} mismatch")
    if runner_summary.get("forcing_input_manifest_rows") != registered_inputs[
        "forcing_input_manifest_rows"
    ]:
        raise ValueError("runner summary forcing input manifest row count mismatch")
    basin_list = pd.read_csv(basin_list_path, dtype={"basin_id": str})
    expected_basins = (
        basin_list["basin_id"].astype(str).str.zfill(8).iloc[:expected_basin_count]
    ).tolist()
    if len(expected_basins) != expected_basin_count or len(set(expected_basins)) != len(
        expected_basins
    ):
        raise ValueError("expected basin set is incomplete or duplicated")
    expected_tasks = {
        (basin_id, seed) for basin_id in expected_basins for seed in (0, 1)
    }
    if (
        int(runner_summary.get("n_basins", -1)) != len(expected_basins)
        or int(runner_summary.get("n_tasks", -1)) != len(expected_tasks)
        or int(runner_summary.get("n_success", -1)) != len(expected_tasks)
        or int(runner_summary.get("n_failed", -1)) != 0
    ):
        raise ValueError("runner summary task counts mismatch")
    records = pd.read_csv(records_path, dtype={"basin_id": str})
    records["basin_id"] = records["basin_id"].str.zfill(8)
    actual_records = set(zip(records["basin_id"], records["seed"].astype(int)))
    if actual_records != expected_tasks:
        raise ValueError("runner record basin-seed set mismatch")
    if not (records["run_status"] == "success").all():
        raise ValueError("runner records contain failed tasks")
    task_paths = sorted((run_path / "tasks").glob("*.npz"))
    if len(task_paths) != len(expected_tasks):
        raise ValueError("task file count mismatch")

    all_events = []
    task_records = []
    all_stable_probabilities = []
    all_stable_truth = []
    maximum_sum_error = 0.0
    maximum_log_error = 0.0
    maximum_variance_error = 0.0
    maximum_truth_state_error = 0.0
    maximum_truth_discharge_error = 0.0
    maximum_truth_projection_difference = 0.0
    maximum_truth_projection_tolerance_ratio = 0.0
    truth_projection_nonzero_day_count = 0
    truth_domain_violation_count = 0
    truth_state_replacement_count = 0
    zero_probability_count = 0
    for basin_id, seed in sorted(expected_tasks):
        task_path = run_path / "tasks" / f"{basin_id}_s{seed}.npz"
        if not task_path.is_file():
            raise FileNotFoundError(f"missing task file {task_path}")
        events, task_record, score_arrays = _verify_task(
            task_path, basin_id, seed, config, config_sha256
        )
        all_events.extend(events)
        task_records.append(task_record)
        all_stable_probabilities.append(score_arrays["stable_probabilities"])
        all_stable_truth.append(score_arrays["stable_truth"])
        maximum_sum_error = max(
            maximum_sum_error, task_record["maximum_probability_sum_error"]
        )
        maximum_log_error = max(
            maximum_log_error,
            task_record["maximum_probability_log_reconstruction_error"],
        )
        maximum_variance_error = max(
            maximum_variance_error,
            task_record["maximum_candidate_variance_error"],
        )
        maximum_truth_state_error = max(
            maximum_truth_state_error,
            task_record["maximum_truth_replay_state_error"],
        )
        maximum_truth_discharge_error = max(
            maximum_truth_discharge_error,
            task_record["maximum_truth_replay_discharge_error"],
        )
        maximum_truth_projection_difference = max(
            maximum_truth_projection_difference,
            task_record["truth_projection_maximum_absolute_difference"],
        )
        maximum_truth_projection_tolerance_ratio = max(
            maximum_truth_projection_tolerance_ratio,
            task_record["truth_projection_maximum_tolerance_ratio"],
        )
        truth_projection_nonzero_day_count += int(
            task_record["truth_projection_nonzero_day_count"]
        )
        truth_domain_violation_count += int(
            task_record["truth_domain_violation_count"]
        )
        truth_state_replacement_count += int(
            task_record["truth_state_replacement_count"]
        )
        zero_probability_count += int(task_record["zero_probability_count"])

    events_frame = pd.DataFrame(all_events).sort_values(
        ["basin_id", "seed", "event_index"]
    )
    tasks_frame = pd.DataFrame(task_records).sort_values(["basin_id", "seed"])
    expected_event_count = len(expected_tasks) * 6
    if len(events_frame) != expected_event_count:
        raise ValueError("event count mismatch")
    direction_rates = {
        direction: float(group["passed"].mean())
        for direction, group in events_frame.groupby("direction", sort=True)
    }
    if len(direction_rates) != 6:
        raise ValueError("six directed transitions were not recovered")
    seed_table = events_frame.pivot(
        index=["basin_id", "direction"], columns="seed", values="passed"
    )
    if set(seed_table.columns) != {0, 1} or seed_table.isna().any().any():
        raise ValueError("seed agreement table is incomplete")
    seed_agreement = float((seed_table[0] == seed_table[1]).mean())
    pooled_probabilities = np.concatenate(all_stable_probabilities, axis=0)
    pooled_truth = np.concatenate(all_stable_truth, axis=0)
    pooled_one_hot = np.eye(N_CANDIDATES)[pooled_truth]
    pooled_brier = float(
        np.mean(np.sum((pooled_probabilities - pooled_one_hot) ** 2, axis=1))
    )
    pooled_nll = float(tasks_frame["true_negative_log_probability"].mean())
    pooled_calibration = _classwise_calibration_error(
        pooled_probabilities,
        pooled_truth,
        np.asarray(
            config["probability_metrics"]["calibration_bin_edges"], dtype=float
        ),
    )
    bootstrap = _cluster_bootstrap(events_frame, tasks_frame, config)
    metrics = {
        "overall_event_pass_rate": float(events_frame["passed"].mean()),
        "direction_pass_rates": direction_rates,
        "overall_event_pass_rate_interval": bootstrap["overall"],
        "direction_pass_rate_intervals": bootstrap["directions"],
        "seed_event_agreement": seed_agreement,
        "multiclass_brier": pooled_brier,
        "multiclass_brier_interval": bootstrap["brier"],
        "true_negative_log_probability": pooled_nll,
        "true_negative_log_probability_interval": bootstrap[
            "negative_log_probability"
        ],
        "classwise_expected_calibration_error": pooled_calibration,
    }
    gate_result = apply_success_gate(metrics, config)
    scientific = {
        "experiment_id": config["experiment_id"],
        "evidence_scope": config["evidence_scope"],
        "mode": mode,
        "scientific_status": (
            "not_evaluated_smoke"
            if mode == "smoke"
            else gate_result["scientific_status"]
        ),
        "conditions": gate_result["conditions"],
        **metrics,
    }
    integrity = {
        "integrity_status": "passed",
        "experiment_id": config["experiment_id"],
        "mode": mode,
        "run_dir": str(run_path),
        "config_sha256": config_sha256,
        "basin_list_sha256": _sha256_file(basin_list_path),
        "runner_summary_sha256": _sha256_file(summary_path),
        "runner_records_sha256": _sha256_file(records_path),
        **registered_inputs,
        "n_basins": len(expected_basins),
        "n_tasks": len(expected_tasks),
        "n_events": len(events_frame),
        "zero_truth_domain_violations": truth_domain_violation_count == 0,
        "zero_truth_state_replacements": truth_state_replacement_count == 0,
        "truth_projection_nonzero_day_count": truth_projection_nonzero_day_count,
        "maximum_truth_projection_absolute_difference": (
            maximum_truth_projection_difference
        ),
        "maximum_truth_projection_tolerance_ratio": (
            maximum_truth_projection_tolerance_ratio
        ),
        "maximum_probability_sum_error": maximum_sum_error,
        "maximum_probability_log_reconstruction_error": maximum_log_error,
        "zero_probability_count": zero_probability_count,
        "maximum_candidate_variance_error": maximum_variance_error,
        "maximum_truth_replay_state_error": maximum_truth_state_error,
        "maximum_truth_replay_discharge_error": maximum_truth_discharge_error,
    }
    _atomic_csv(run_path / "events.csv", events_frame)
    _atomic_csv(run_path / "task_verification.csv", tasks_frame)
    _atomic_json(run_path / "verification.json", integrity)
    _atomic_json(run_path / "scientific_summary.json", scientific)
    return integrity, scientific


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument(
        "--config",
        default="src/camels_process_noise_only/configs/camels_process_noise_only_01a_design.json",
    )
    parser.add_argument("--basin-list", required=True)
    parser.add_argument("--expected-basin-count", type=int, required=True)
    parser.add_argument("--mode", choices=("smoke", "design"), required=True)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        integrity, scientific = verify_run(
            run_dir=arguments.run_dir,
            config_path=arguments.config,
            basin_list_path=arguments.basin_list,
            expected_basin_count=arguments.expected_basin_count,
            mode=arguments.mode,
        )
    except Exception as error:  # noqa: BLE001
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"integrity": integrity, "scientific": scientific}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
