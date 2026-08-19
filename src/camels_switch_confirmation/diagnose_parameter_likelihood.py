"""Replay registered parFC failures and decompose extreme posterior confidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd


DIAGNOSTIC_STATUS = "registered_design_seed_failure_diagnostic_not_validation"
SELECTION_THRESHOLD = 1000.0
SEVERE_DAY_THRESHOLD = 100.0
REPLAY_TOLERANCE = 1e-12
DECOMPOSITION_TOLERANCE = 1e-8


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def select_extreme_tasks(
    task_metrics: pd.DataFrame,
    threshold: float = SELECTION_THRESHOLD,
) -> pd.DataFrame:
    """Select C-arm tasks strictly above the registered stable-NLL threshold."""
    required = {
        "arm_id",
        "basin_id",
        "seed",
        "true_negative_log_probability",
    }
    if not required.issubset(task_metrics.columns):
        missing = sorted(required.difference(task_metrics.columns))
        raise ValueError("task metrics lack columns: " + ", ".join(missing))
    threshold_value = float(threshold)
    if not np.isfinite(threshold_value) or threshold_value <= 0.0:
        raise ValueError("selection threshold must be finite and positive")
    frame = task_metrics.copy()
    frame["basin_id"] = frame["basin_id"].astype(str).str.zfill(8)
    frame["seed"] = pd.to_numeric(frame["seed"], errors="raise").astype(int)
    frame["true_negative_log_probability"] = pd.to_numeric(
        frame["true_negative_log_probability"], errors="raise"
    )
    selected = frame[
        (frame["arm_id"].astype(str) == "C")
        & (frame["true_negative_log_probability"] > threshold_value)
    ].copy()
    if selected.empty:
        raise ValueError("selection produced no diagnostic tasks")
    if not np.all(np.isfinite(selected["true_negative_log_probability"])):
        raise ValueError("selected task scores must be finite")
    if not set(selected["seed"]).issubset({0, 1}):
        raise ValueError("diagnostic tasks must use design seeds 0 and 1 only")
    if selected.duplicated(["basin_id", "seed"]).any():
        raise ValueError("selected task table contains duplicate basin-seed tasks")
    return selected.sort_values(
        ["true_negative_log_probability", "basin_id", "seed"],
        ascending=[False, True, True],
        kind="mergesort",
    ).reset_index(drop=True)


def decompose_gaussian_log_odds(
    *,
    winner_prior_probability: float,
    true_prior_probability: float,
    winner_innovation: float,
    true_innovation: float,
    winner_innovation_variance: float,
    true_innovation_variance: float,
) -> dict[str, float]:
    """Decompose scalar-Gaussian winner-vs-truth posterior log odds."""
    values = {
        "winner_prior_probability": float(winner_prior_probability),
        "true_prior_probability": float(true_prior_probability),
        "winner_innovation": float(winner_innovation),
        "true_innovation": float(true_innovation),
        "winner_innovation_variance": float(winner_innovation_variance),
        "true_innovation_variance": float(true_innovation_variance),
    }
    if not all(np.isfinite(value) for value in values.values()):
        raise ValueError("decomposition inputs must be finite")
    for name in (
        "winner_prior_probability",
        "true_prior_probability",
        "winner_innovation_variance",
        "true_innovation_variance",
    ):
        if values[name] <= 0.0:
            raise ValueError(f"{name} must be positive")

    prior_log_odds = np.log(
        values["winner_prior_probability"] / values["true_prior_probability"]
    )
    residual_contribution = -0.5 * (
        values["winner_innovation"] ** 2
        / values["winner_innovation_variance"]
        - values["true_innovation"] ** 2
        / values["true_innovation_variance"]
    )
    log_variance_contribution = -0.5 * np.log(
        values["winner_innovation_variance"]
        / values["true_innovation_variance"]
    )
    winner_log_likelihood = -0.5 * (
        np.log(2.0 * np.pi * values["winner_innovation_variance"])
        + values["winner_innovation"] ** 2
        / values["winner_innovation_variance"]
    )
    true_log_likelihood = -0.5 * (
        np.log(2.0 * np.pi * values["true_innovation_variance"])
        + values["true_innovation"] ** 2
        / values["true_innovation_variance"]
    )
    likelihood_log_odds = winner_log_likelihood - true_log_likelihood
    posterior_log_odds = prior_log_odds + likelihood_log_odds
    reconstructed = (
        prior_log_odds
        + residual_contribution
        + log_variance_contribution
    )
    closure_error = abs(float(posterior_log_odds - reconstructed))
    if closure_error > DECOMPOSITION_TOLERANCE:
        raise ValueError(
            "Gaussian log-odds decomposition does not close within tolerance"
        )
    return {
        "prior_log_odds": float(prior_log_odds),
        "residual_contribution": float(residual_contribution),
        "log_variance_contribution": float(log_variance_contribution),
        "likelihood_log_odds": float(likelihood_log_odds),
        "posterior_log_odds": float(posterior_log_odds),
        "closure_error": closure_error,
    }


def write_npz_exclusive(path: str | Path, **arrays) -> None:
    """Atomically create one compressed trace and refuse every overwrite."""
    target = Path(path)
    if target.exists():
        raise FileExistsError(f"task trace already exists: {target}")
    temporary = target.with_suffix(".tmp.npz")
    if temporary.exists():
        raise FileExistsError(f"temporary task trace already exists: {temporary}")
    np.savez_compressed(temporary, **arrays)
    os.link(temporary, target)
    temporary.unlink()


def _maximum_absolute_difference(left, right) -> float:
    first = np.asarray(left, dtype=np.float64)
    second = np.asarray(right, dtype=np.float64)
    if first.shape != second.shape:
        raise ValueError(
            f"registered replay array shape changed: {first.shape} != {second.shape}"
        )
    if first.size == 0:
        return 0.0
    return float(np.max(np.abs(first - second)))


def _load_registered_row(
    repo_root: Path,
    config: Mapping,
    basin_id: str,
) -> dict:
    inputs = config["inputs"]
    parameters = pd.read_csv(
        repo_root / inputs["parameter_table"], dtype={"basin_id": str}
    )
    precheck = pd.read_csv(
        repo_root / inputs["g1_precheck_table"], dtype={"basin_id": str}
    )
    for frame in (parameters, precheck):
        frame["basin_id"] = frame["basin_id"].astype(str).str.zfill(8)
        if frame["basin_id"].duplicated().any():
            raise ValueError("registered input table contains duplicate basin identifiers")
    selected = parameters[parameters["basin_id"] == basin_id].merge(
        precheck[["basin_id", "sigma_obs"]],
        on="basin_id",
        how="left",
        validate="one_to_one",
    )
    if len(selected) != 1:
        raise ValueError(f"expected one registered row for basin {basin_id}")
    return selected.iloc[0].to_dict()


def _find_arm_c(config: Mapping) -> dict:
    matches = [dict(arm) for arm in config["arms"] if arm.get("arm_id") == "C"]
    if len(matches) != 1:
        raise ValueError("parent configuration must contain exactly one arm C")
    arm = matches[0]
    expected = {
        "arm_id": "C",
        "interaction_mode": "full",
        "parameter_state_mapping": "conservative_parfc",
    }
    if arm != expected:
        raise ValueError("parent arm-C contract changed")
    return arm


def replay_task(
    *,
    repo_root: str | Path,
    parent_config_path: str | Path,
    basin_id: str,
    seed: int,
    reference_probability_path: str | Path,
    maximum_days: int | None = None,
) -> dict[str, np.ndarray]:
    """Replay one registered C-arm task and retain candidate-level diagnostics."""
    from camels_switch_confirmation.bank import build_bank as build_members
    from camels_switch_confirmation.g1_precheck import (
        PARAM_KEYS,
        ROTATION,
        SEED_ENTROPY,
        STAGE_DAYS,
        STATE_NAMES,
        WINDOW_START,
        _window_end,
    )
    from camels_switch_confirmation.g2_switch_confirmation import (
        BOUNDS_PRESET,
        LAG_CAP,
        N_STATE,
        _build_bank,
        _generate_truth,
    )
    from hydroagent.data_loading import load_camels_basin
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds

    root = Path(repo_root).resolve()
    parent_path = Path(parent_config_path).resolve()
    reference_path = Path(reference_probability_path).resolve()
    with parent_path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    if config.get("experiment_id") != "CAMELS_PARFC_STATE_INTERACTION_01B_DESIGN90":
        raise ValueError("unexpected parent experiment")
    arm = _find_arm_c(config)
    basin = str(basin_id).zfill(8)
    seed_value = int(seed)
    if seed_value not in {0, 1}:
        raise ValueError("diagnostic replay may use design seeds 0 and 1 only")
    row = _load_registered_row(root, config, basin)
    parameters = {key: float(row[f"p_{key}"]) for key in PARAM_KEYS}
    parameters["lag_time"] = min(parameters["lag_time"], LAG_CAP)
    initial_hydrologic_state = np.array(
        [float(row[f"state_{name}"]) for name in STATE_NAMES],
        dtype=np.float64,
    )
    observation_sigma = float(row["sigma_obs"])
    bounds = resolve_hbv_bounds(BOUNDS_PRESET)
    members, _ = build_members(parameters, bounds["parFC"])

    forcing, _, _ = load_camels_basin(
        basin,
        data_root=root / config["inputs"]["data_root"],
        start_date=WINDOW_START,
        end_date=_window_end(),
        forcing=config["inputs"]["forcing"],
        pet_method=config["inputs"]["pet_method"],
        keep_obs_nan_days=True,
    )
    rain = forcing["prcp"].values.astype(np.float64)
    pet_column = "ep" if "ep" in forcing.columns else "pet"
    pet = forcing[pet_column].values.astype(np.float64)
    temperature = (
        forcing["tmean"].values.astype(np.float64)
        if "tmean" in forcing.columns
        else np.zeros_like(rain)
    )
    truth_rng = np.random.default_rng(
        np.random.SeedSequence((SEED_ENTROPY, int(basin), seed_value))
    )
    observation_rng = np.random.default_rng(
        np.random.SeedSequence((SEED_ENTROPY, int(basin), seed_value, 1))
    )
    truth_q, _, truth_clip_count = _generate_truth(
        members,
        rain,
        pet,
        temperature,
        initial_hydrologic_state,
        truth_rng,
        bounds,
    )
    observations = truth_q + observation_rng.normal(
        0.0, observation_sigma, size=len(truth_q)
    )

    with np.load(reference_path, allow_pickle=False) as source:
        reference = {name: source[name].copy() for name in source.files}
    if str(reference["basin_id"].item()).zfill(8) != basin:
        raise ValueError("reference basin does not match requested replay")
    if int(reference["seed"].item()) != seed_value:
        raise ValueError("reference seed does not match requested replay")
    if str(reference["arm_id"].item()) != "C":
        raise ValueError("reference task is not arm C")
    if int(reference["truth_clip_count"].item()) != truth_clip_count:
        raise ValueError("truth clipping count differs from registered task")

    truth_difference = _maximum_absolute_difference(truth_q, reference["truth_q"])
    observation_difference = _maximum_absolute_difference(
        observations, reference["observations"]
    )
    for label, replayed, registered in (
        ("rain", rain, reference["rain"]),
        ("pet", pet, reference["pet"]),
        ("temperature", temperature, reference["temperature"]),
    ):
        if not np.array_equal(replayed, registered):
            raise ValueError(f"{label} changed from registered parent task")
    candidate_vectors = np.asarray(
        [[float(member[key]) for key in PARAM_KEYS] for member in members],
        dtype=np.float64,
    )
    if not np.array_equal(candidate_vectors, reference["candidate_parameter_vectors"]):
        raise ValueError("candidate parameter vectors changed")
    if truth_difference != 0.0 or observation_difference != 0.0:
        raise ValueError("truth or observations changed from registered parent task")

    filter_config = config["filter"]
    if filter_config["q_mode"] != "fixed":
        raise ValueError("diagnostic replay currently requires the registered fixed Q")
    estimator, transitions = _build_bank(
        members,
        initial_hydrologic_state,
        observation_sigma,
        bounds,
        q_scale=float(filter_config["q_scale"]),
        q_structure=str(filter_config["q_structure"]),
        q_mode=str(filter_config["q_mode"]),
        q_state_multiplier=float(filter_config["q_state_multiplier"]),
        filter_r_multiplier=float(filter_config["observation_variance_multiplier"]),
        interaction_mode=str(arm["interaction_mode"]),
        parameter_state_mapping=str(arm["parameter_state_mapping"]),
    )
    total_days = len(truth_q)
    traced_days = total_days if maximum_days is None else int(maximum_days)
    if traced_days <= 0 or traced_days > total_days:
        raise ValueError("maximum_days must be between 1 and the full task length")
    n_candidates = len(members)
    vector_shape = (traced_days, n_candidates)
    state_shape = (traced_days, n_candidates, N_STATE)
    before_probability = np.zeros(vector_shape, dtype=np.float64)
    prior_probability = np.zeros(vector_shape, dtype=np.float64)
    posterior_probability = np.zeros(vector_shape, dtype=np.float64)
    posterior_log_probability = np.zeros(vector_shape, dtype=np.float64)
    predicted_observation = np.zeros(vector_shape, dtype=np.float64)
    innovation = np.zeros(vector_shape, dtype=np.float64)
    innovation_variance = np.zeros(vector_shape, dtype=np.float64)
    standardized_innovation_squared = np.zeros(vector_shape, dtype=np.float64)
    log_likelihood = np.zeros(vector_shape, dtype=np.float64)
    pre_interaction_state = np.zeros(state_shape, dtype=np.float64)
    mixed_state = np.zeros(state_shape, dtype=np.float64)
    predicted_state = np.zeros(state_shape, dtype=np.float64)
    posterior_state = np.zeros(state_shape, dtype=np.float64)
    pre_covariance_diagonal = np.zeros(state_shape, dtype=np.float64)
    mixed_covariance_diagonal = np.zeros(state_shape, dtype=np.float64)
    predicted_covariance_diagonal = np.zeros(state_shape, dtype=np.float64)
    posterior_covariance_diagonal = np.zeros(state_shape, dtype=np.float64)
    covariance_sm_suz = {
        key: np.zeros(vector_shape, dtype=np.float64)
        for key in ("pre", "mixed", "predicted", "posterior")
    }

    for day in range(traced_days):
        for transition in transitions:
            transition.set_forcing(rain[day], pet[day], temperature[day])
        before_probability[day] = estimator.probabilities.copy()
        for candidate_index, candidate in enumerate(estimator.filters):
            pre_interaction_state[day, candidate_index] = candidate.state
            pre_covariance_diagonal[day, candidate_index] = np.diag(
                candidate.covariance
            )
            covariance_sm_suz["pre"][day, candidate_index] = (
                candidate.covariance[2, 3]
            )
        prior = estimator.interact()
        prior_probability[day] = prior
        for candidate_index, candidate in enumerate(estimator.filters):
            mixed_state[day, candidate_index] = candidate.state
            mixed_covariance_diagonal[day, candidate_index] = np.diag(
                candidate.covariance
            )
            covariance_sm_suz["mixed"][day, candidate_index] = (
                candidate.covariance[2, 3]
            )
        result = estimator.update_after_interaction(
            np.array([observations[day]], dtype=np.float64),
            prior,
        )
        posterior_probability[day] = result.posterior_probabilities
        posterior_log_probability[day] = result.posterior_log_probabilities
        for candidate_index, candidate_result in enumerate(result.candidate_results):
            predicted_observation[day, candidate_index] = (
                candidate_result.prior_observation[0]
            )
            innovation[day, candidate_index] = candidate_result.innovation[0]
            innovation_variance[day, candidate_index] = (
                candidate_result.innovation_covariance[0, 0]
            )
            if innovation_variance[day, candidate_index] <= 0.0:
                raise ValueError("candidate innovation variance must be positive")
            standardized_innovation_squared[day, candidate_index] = (
                innovation[day, candidate_index] ** 2
                / innovation_variance[day, candidate_index]
            )
            log_likelihood[day, candidate_index] = candidate_result.log_likelihood
            predicted_state[day, candidate_index] = candidate_result.prior_state
            posterior_state[day, candidate_index] = candidate_result.posterior_state
            predicted_covariance_diagonal[day, candidate_index] = np.diag(
                candidate_result.prior_covariance
            )
            posterior_covariance_diagonal[day, candidate_index] = np.diag(
                candidate_result.posterior_covariance
            )
            covariance_sm_suz["predicted"][day, candidate_index] = (
                candidate_result.prior_covariance[2, 3]
            )
            covariance_sm_suz["posterior"][day, candidate_index] = (
                candidate_result.posterior_covariance[2, 3]
            )

    probability_difference = _maximum_absolute_difference(
        posterior_probability,
        reference["probabilities"][:traced_days],
    )
    log_probability_difference = _maximum_absolute_difference(
        posterior_log_probability,
        reference["log_probabilities"][:traced_days],
    )
    if probability_difference > REPLAY_TOLERANCE:
        raise ValueError("replayed probabilities differ from registered parent")
    if log_probability_difference > REPLAY_TOLERANCE:
        raise ValueError("replayed stable log probabilities differ from parent")
    numeric_arrays = (
        before_probability,
        prior_probability,
        posterior_probability,
        posterior_log_probability,
        predicted_observation,
        innovation,
        innovation_variance,
        standardized_innovation_squared,
        log_likelihood,
        pre_interaction_state,
        mixed_state,
        predicted_state,
        posterior_state,
        pre_covariance_diagonal,
        mixed_covariance_diagonal,
        predicted_covariance_diagonal,
        posterior_covariance_diagonal,
    )
    if not all(np.all(np.isfinite(array)) for array in numeric_arrays):
        raise ValueError("diagnostic replay produced non-finite values")

    true_candidate_indices = np.repeat(
        np.asarray(ROTATION, dtype=np.int64), STAGE_DAYS
    )[:traced_days]
    return {
        "basin_id": np.array(basin),
        "seed": np.array(seed_value, dtype=np.int64),
        "n_days_traced": np.array(traced_days, dtype=np.int64),
        "true_candidate_indices": true_candidate_indices,
        "truth_q": truth_q[:traced_days],
        "observations": observations[:traced_days],
        "rain": rain[:traced_days],
        "pet": pet[:traced_days],
        "temperature": temperature[:traced_days],
        "candidate_parameter_names": np.asarray(PARAM_KEYS),
        "candidate_parameter_vectors": candidate_vectors,
        "model_probabilities_before_transition": before_probability,
        "prior_model_probabilities": prior_probability,
        "posterior_probabilities": posterior_probability,
        "posterior_log_probabilities": posterior_log_probability,
        "predicted_observation": predicted_observation,
        "innovation": innovation,
        "innovation_variance": innovation_variance,
        "standardized_innovation_squared": standardized_innovation_squared,
        "log_likelihood": log_likelihood,
        "pre_interaction_state": pre_interaction_state,
        "mixed_state": mixed_state,
        "predicted_state": predicted_state,
        "posterior_state": posterior_state,
        "pre_interaction_covariance_diagonal": pre_covariance_diagonal,
        "mixed_covariance_diagonal": mixed_covariance_diagonal,
        "predicted_covariance_diagonal": predicted_covariance_diagonal,
        "posterior_covariance_diagonal": posterior_covariance_diagonal,
        "pre_interaction_covariance_sm_suz": covariance_sm_suz["pre"],
        "mixed_covariance_sm_suz": covariance_sm_suz["mixed"],
        "predicted_covariance_sm_suz": covariance_sm_suz["predicted"],
        "posterior_covariance_sm_suz": covariance_sm_suz["posterior"],
        "observation_variance": np.array(
            observation_sigma**2
            * float(filter_config["observation_variance_multiplier"]),
            dtype=np.float64,
        ),
        "truth_maximum_absolute_difference": np.array(truth_difference),
        "observation_maximum_absolute_difference": np.array(
            observation_difference
        ),
        "probability_maximum_absolute_difference": np.array(
            probability_difference
        ),
        "log_probability_maximum_absolute_difference": np.array(
            log_probability_difference
        ),
        "reference_probability_sha256": np.array(sha256_file(reference_path)),
    }


def _registered_path(repo_root: Path, relative_path: str, label: str) -> Path:
    value = Path(str(relative_path))
    if value.is_absolute() or ".." in value.parts:
        raise ValueError(f"{label} must be a repository-relative path")
    resolved = (repo_root / value).resolve()
    try:
        resolved.relative_to(repo_root)
    except ValueError as error:
        raise ValueError(f"{label} escapes the repository root") from error
    return resolved


def verify_content_manifest(repo_root: str | Path, manifest_path: str | Path) -> int:
    """Rehash every file named by a registered relative-path manifest."""
    root = Path(repo_root).resolve()
    manifest = Path(manifest_path)
    if not manifest.is_absolute():
        manifest = root / manifest
    frame = pd.read_csv(manifest, keep_default_na=False)
    required = {"relative_path", "bytes", "sha256"}
    if not required.issubset(frame.columns):
        raise ValueError("content manifest lacks relative_path, bytes, or sha256")
    if frame.empty or frame["relative_path"].duplicated().any():
        raise ValueError("content manifest must contain unique nonempty paths")
    for row in frame.to_dict("records"):
        relative = Path(str(row["relative_path"]))
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("content manifest path must be repository relative")
        path = root / relative
        if not path.is_file():
            raise FileNotFoundError(f"content manifest file is missing: {relative}")
        if path.stat().st_size != int(row["bytes"]) or sha256_file(path) != str(
            row["sha256"]
        ):
            raise ValueError(f"content manifest mismatch: {relative}")
    return int(len(frame))


def _verify_registered_diagnostic(
    repo_root: Path,
    config_path: Path,
    expected_config_sha256: str,
) -> dict:
    observed_config_hash = sha256_file(config_path)
    if observed_config_hash != expected_config_sha256:
        raise ValueError("diagnostic configuration SHA-256 changed")
    with config_path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    if config.get("configuration_status") != DIAGNOSTIC_STATUS:
        raise ValueError("diagnostic configuration status changed")
    if config.get("design_seeds_only") is not True:
        raise ValueError("diagnostic must be restricted to design seeds")
    if config.get("reserved_validation_seeds_used") is not False:
        raise ValueError("reserved validation seeds cannot be used")
    registered_files = config.get("registered_files")
    if not isinstance(registered_files, Mapping) or not registered_files:
        raise ValueError("diagnostic configuration lacks registered files")
    for label, entry in registered_files.items():
        path = _registered_path(repo_root, entry["path"], label)
        if not path.is_file():
            raise FileNotFoundError(f"registered file is missing: {label}")
        if sha256_file(path) != entry["sha256"]:
            raise ValueError(f"registered file SHA-256 changed: {label}")
    raw_manifest = _registered_path(
        repo_root, config["raw_input_manifest"], "raw input manifest"
    )
    manifest_rows = verify_content_manifest(repo_root, raw_manifest)
    if manifest_rows != 184:
        raise ValueError("registered raw input manifest must contain 184 rows")
    output = _registered_path(repo_root, config["output_root"], "output root")
    temporary = output.with_name(output.name + ".tmp")
    if output.exists() or temporary.exists():
        raise FileExistsError("diagnostic output or temporary output already exists")
    return config


def _write_csv_exclusive(frame: pd.DataFrame, path: Path) -> None:
    if path.exists():
        raise FileExistsError(f"diagnostic CSV already exists: {path}")
    frame.to_csv(path, index=False, mode="x")


def _write_json_exclusive(value: Mapping, path: Path) -> None:
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def _trace_rows(trace: Mapping[str, np.ndarray]):
    basin_id = str(np.asarray(trace["basin_id"]).item())
    seed = int(np.asarray(trace["seed"]).item())
    n_days = int(np.asarray(trace["n_days_traced"]).item())
    true_indices = np.asarray(trace["true_candidate_indices"], dtype=int)
    candidate_rows = []
    severe_rows = []
    for day in range(n_days):
        true_index = int(true_indices[day])
        posterior = trace["posterior_probabilities"][day]
        posterior_logs = trace["posterior_log_probabilities"][day]
        winner_index = int(np.argmax(posterior))
        true_nll = float(-posterior_logs[true_index])
        for candidate_index in range(3):
            candidate_rows.append(
                {
                    "basin_id": basin_id,
                    "seed": seed,
                    "day_index": day,
                    "stage_index": day // 180,
                    "candidate_index": candidate_index,
                    "true_candidate_index": true_index,
                    "winner_candidate_index": winner_index,
                    "prior_probability": float(
                        trace["prior_model_probabilities"][day, candidate_index]
                    ),
                    "posterior_probability": float(
                        posterior[candidate_index]
                    ),
                    "posterior_log_probability": float(
                        posterior_logs[candidate_index]
                    ),
                    "predicted_observation": float(
                        trace["predicted_observation"][day, candidate_index]
                    ),
                    "innovation": float(
                        trace["innovation"][day, candidate_index]
                    ),
                    "innovation_variance": float(
                        trace["innovation_variance"][day, candidate_index]
                    ),
                    "standardized_innovation_squared": float(
                        trace["standardized_innovation_squared"][
                            day, candidate_index
                        ]
                    ),
                    "log_likelihood": float(
                        trace["log_likelihood"][day, candidate_index]
                    ),
                }
            )
        if true_nll > SEVERE_DAY_THRESHOLD:
            if winner_index == true_index:
                raise ValueError("severe true-candidate NLL cannot have a true winner")
            decomposition = decompose_gaussian_log_odds(
                winner_prior_probability=float(
                    trace["prior_model_probabilities"][day, winner_index]
                ),
                true_prior_probability=float(
                    trace["prior_model_probabilities"][day, true_index]
                ),
                winner_innovation=float(trace["innovation"][day, winner_index]),
                true_innovation=float(trace["innovation"][day, true_index]),
                winner_innovation_variance=float(
                    trace["innovation_variance"][day, winner_index]
                ),
                true_innovation_variance=float(
                    trace["innovation_variance"][day, true_index]
                ),
            )
            stored_log_odds = float(
                posterior_logs[winner_index] - posterior_logs[true_index]
            )
            stored_closure = abs(
                stored_log_odds - decomposition["posterior_log_odds"]
            )
            if stored_closure > DECOMPOSITION_TOLERANCE:
                raise ValueError("stored posterior log odds do not close")
            residual_dominant = abs(decomposition["residual_contribution"]) >= abs(
                decomposition["log_variance_contribution"]
            )
            severe_rows.append(
                {
                    "basin_id": basin_id,
                    "seed": seed,
                    "day_index": day,
                    "stage_index": day // 180,
                    "stage_day": day % 180 + 1,
                    "true_candidate_index": true_index,
                    "winner_candidate_index": winner_index,
                    "true_negative_log_probability": true_nll,
                    "true_probability": float(posterior[true_index]),
                    "winner_probability": float(posterior[winner_index]),
                    "observation": float(trace["observations"][day]),
                    "truth_q": float(trace["truth_q"][day]),
                    "true_predicted_observation": float(
                        trace["predicted_observation"][day, true_index]
                    ),
                    "winner_predicted_observation": float(
                        trace["predicted_observation"][day, winner_index]
                    ),
                    "true_innovation": float(
                        trace["innovation"][day, true_index]
                    ),
                    "winner_innovation": float(
                        trace["innovation"][day, winner_index]
                    ),
                    "true_innovation_variance": float(
                        trace["innovation_variance"][day, true_index]
                    ),
                    "winner_innovation_variance": float(
                        trace["innovation_variance"][day, winner_index]
                    ),
                    "true_standardized_innovation_squared": float(
                        trace["standardized_innovation_squared"][day, true_index]
                    ),
                    "winner_standardized_innovation_squared": float(
                        trace["standardized_innovation_squared"][day, winner_index]
                    ),
                    **decomposition,
                    "stored_posterior_log_odds": stored_log_odds,
                    "stored_closure_error": stored_closure,
                    "daily_dominant_component": (
                        "residual_squared" if residual_dominant else "log_variance"
                    ),
                    "true_mixed_soil_water": float(
                        trace["mixed_state"][day, true_index, 2]
                    ),
                    "winner_mixed_soil_water": float(
                        trace["mixed_state"][day, winner_index, 2]
                    ),
                    "true_mixed_upper_groundwater": float(
                        trace["mixed_state"][day, true_index, 3]
                    ),
                    "winner_mixed_upper_groundwater": float(
                        trace["mixed_state"][day, winner_index, 3]
                    ),
                    "true_predicted_soil_water": float(
                        trace["predicted_state"][day, true_index, 2]
                    ),
                    "winner_predicted_soil_water": float(
                        trace["predicted_state"][day, winner_index, 2]
                    ),
                    "true_predicted_upper_groundwater": float(
                        trace["predicted_state"][day, true_index, 3]
                    ),
                    "winner_predicted_upper_groundwater": float(
                        trace["predicted_state"][day, winner_index, 3]
                    ),
                }
            )
    return candidate_rows, severe_rows


def run_diagnostic(
    *,
    repo_root: str | Path,
    config_path: str | Path,
    expected_config_sha256: str,
) -> dict:
    root = Path(repo_root).resolve()
    configuration = Path(config_path).resolve()
    config = _verify_registered_diagnostic(
        root, configuration, expected_config_sha256
    )
    parent_config = _registered_path(
        root, config["parent_config"], "parent configuration"
    )
    task_table_path = _registered_path(
        root, config["task_table"], "diagnostic task table"
    )
    task_metrics_path = _registered_path(
        root, config["parent_task_metrics"], "parent task metrics"
    )
    registered_tasks = pd.read_csv(
        task_table_path, dtype={"basin_id": str}
    )
    current_selection = select_extreme_tasks(
        pd.read_csv(task_metrics_path, dtype={"basin_id": str}),
        threshold=float(config["selection_threshold_exclusive"]),
    )
    registered_keys = list(
        zip(
            registered_tasks["basin_id"].astype(str).str.zfill(8),
            registered_tasks["seed"].astype(int),
        )
    )
    current_keys = list(
        zip(current_selection["basin_id"], current_selection["seed"])
    )
    if registered_keys != current_keys or len(registered_keys) != 10:
        raise ValueError("registered diagnostic task selection changed")

    for task in registered_tasks.to_dict("records"):
        basin = str(task["basin_id"]).zfill(8)
        seed = int(task["seed"])
        reference = _registered_path(
            root,
            str(task["source_probability_path"]),
            f"source probability {basin} seed {seed}",
        )
        if reference.stat().st_size != int(task["source_probability_bytes"]):
            raise ValueError("source probability byte count changed")
        if sha256_file(reference) != str(task["source_probability_sha256"]):
            raise ValueError("source probability SHA-256 changed")

    output = _registered_path(root, config["output_root"], "output root")
    output.mkdir(exist_ok=False)
    trace_directory = output / "traces"
    trace_directory.mkdir(exist_ok=False)
    candidate_rows = []
    severe_rows = []
    task_rows = []
    try:
        for task in registered_tasks.to_dict("records"):
            basin = str(task["basin_id"]).zfill(8)
            seed = int(task["seed"])
            reference = _registered_path(
                root,
                str(task["source_probability_path"]),
                f"source probability {basin} seed {seed}",
            )
            if sha256_file(reference) != str(task["source_probability_sha256"]):
                raise ValueError("source probability SHA-256 changed")
            trace = replay_task(
                repo_root=root,
                parent_config_path=parent_config,
                basin_id=basin,
                seed=seed,
                reference_probability_path=reference,
            )
            write_npz_exclusive(
                trace_directory / f"{basin}_s{seed}.npz", **trace
            )
            task_candidates, task_severe = _trace_rows(trace)
            candidate_rows.extend(task_candidates)
            severe_rows.extend(task_severe)
            task_rows.append(
                {
                    "basin_id": basin,
                    "seed": seed,
                    "candidate_day_rows": len(task_candidates),
                    "severe_day_count": len(task_severe),
                    "probability_maximum_absolute_difference": float(
                        trace["probability_maximum_absolute_difference"]
                    ),
                    "log_probability_maximum_absolute_difference": float(
                        trace["log_probability_maximum_absolute_difference"]
                    ),
                    "trace_file": f"traces/{basin}_s{seed}.npz",
                    "trace_sha256": sha256_file(
                        trace_directory / f"{basin}_s{seed}.npz"
                    ),
                }
            )
        candidate_frame = pd.DataFrame(candidate_rows)
        severe_frame = pd.DataFrame(severe_rows)
        task_frame = pd.DataFrame(task_rows)
        if len(candidate_frame) != 10 * 1260 * 3:
            raise ValueError("diagnostic candidate-day row count is incomplete")
        if severe_frame.empty:
            raise ValueError("diagnostic found no registered severe days")
        maximum_probability_difference = float(
            task_frame["probability_maximum_absolute_difference"].max()
        )
        maximum_log_probability_difference = float(
            task_frame["log_probability_maximum_absolute_difference"].max()
        )
        if maximum_probability_difference > REPLAY_TOLERANCE:
            raise ValueError("diagnostic probability replay exceeds tolerance")
        if maximum_log_probability_difference > REPLAY_TOLERANCE:
            raise ValueError("diagnostic log-probability replay exceeds tolerance")
        _write_csv_exclusive(candidate_frame, output / "candidate_days.csv")
        _write_csv_exclusive(severe_frame, output / "severe_days.csv")
        _write_csv_exclusive(task_frame, output / "task_summary.csv")

        residual_dominant = int(
            (severe_frame["daily_dominant_component"] == "residual_squared").sum()
        )
        variance_dominant = int(
            (severe_frame["daily_dominant_component"] == "log_variance").sum()
        )
        residual_fraction = residual_dominant / len(severe_frame)
        variance_fraction = variance_dominant / len(severe_frame)
        if residual_fraction >= 0.8:
            classification = "prediction_mean_or_state_path_dominated"
        elif variance_fraction >= 0.8:
            classification = "innovation_variance_dominated"
        else:
            classification = "mixed_or_unresolved"
        stage_counts = {
            str(int(key)): int(value)
            for key, value in severe_frame["stage_index"].value_counts().sort_index().items()
        }
        pair_counts = {
            f"{int(true)}->{int(winner)}": int(len(group))
            for (true, winner), group in severe_frame.groupby(
                ["true_candidate_index", "winner_candidate_index"]
            )
        }
        summary = {
            "experiment_id": config["experiment_id"],
            "configuration_status": config["configuration_status"],
            "config_sha256": expected_config_sha256,
            "diagnostic_status": "complete",
            "task_count": int(len(task_frame)),
            "candidate_day_rows": int(len(candidate_frame)),
            "severe_day_threshold_exclusive": SEVERE_DAY_THRESHOLD,
            "severe_day_count": int(len(severe_frame)),
            "maximum_probability_replay_difference": maximum_probability_difference,
            "maximum_log_probability_replay_difference": maximum_log_probability_difference,
            "residual_squared_dominant_days": residual_dominant,
            "log_variance_dominant_days": variance_dominant,
            "residual_squared_dominant_fraction": residual_fraction,
            "log_variance_dominant_fraction": variance_fraction,
            "registered_cause_classification": classification,
            "median_prior_log_odds": float(
                severe_frame["prior_log_odds"].median()
            ),
            "median_residual_contribution": float(
                severe_frame["residual_contribution"].median()
            ),
            "median_log_variance_contribution": float(
                severe_frame["log_variance_contribution"].median()
            ),
            "median_true_absolute_innovation": float(
                severe_frame["true_innovation"].abs().median()
            ),
            "median_winner_absolute_innovation": float(
                severe_frame["winner_innovation"].abs().median()
            ),
            "median_true_innovation_variance": float(
                severe_frame["true_innovation_variance"].median()
            ),
            "median_winner_innovation_variance": float(
                severe_frame["winner_innovation_variance"].median()
            ),
            "maximum_decomposition_closure_error": float(
                severe_frame[["closure_error", "stored_closure_error"]]
                .to_numpy()
                .max()
            ),
            "severe_days_by_stage_zero_based": stage_counts,
            "severe_days_by_true_to_winner": pair_counts,
            "files": {
                "candidate_days": "candidate_days.csv",
                "severe_days": "severe_days.csv",
                "task_summary": "task_summary.csv",
                "trace_directory": "traces",
            },
            "claim_boundary": (
                "failure-selected design-seed diagnosis only; no correction, "
                "validation, 531-basin inference, state-accuracy claim, or forecast claim"
            ),
        }
        _write_json_exclusive(summary, output / "diagnostic_summary.json")
        return summary
    except Exception as error:
        failure_path = output / "failure.json"
        if not failure_path.exists():
            _write_json_exclusive(
                {
                    "experiment_id": config.get("experiment_id"),
                    "diagnostic_status": "failed",
                    "error_type": type(error).__name__,
                    "error_message": str(error),
                },
                failure_path,
            )
        raise


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--config-sha256", required=True)
    arguments = parser.parse_args(argv)
    repository_root = Path(__file__).resolve().parents[2]
    summary = run_diagnostic(
        repo_root=repository_root,
        config_path=arguments.config,
        expected_config_sha256=arguments.config_sha256,
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
