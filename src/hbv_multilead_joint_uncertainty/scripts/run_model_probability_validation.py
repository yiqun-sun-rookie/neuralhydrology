"""Run and package the isolated nine-candidate probability validation."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import psutil


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, STATE_NAMES  # noqa: E402
from hbv_joint_uncertainty.imm import update_model_probabilities  # noqa: E402
from hbv_joint_uncertainty.preflight import build_transition_matrix  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    MethodCandidate,
    build_factorial_transition_matrix,
)
from hbv_multilead_joint_uncertainty.model_probability_validation import (  # noqa: E402
    run_model_probability_validation,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (  # noqa: E402
    _atomic_json_write,
    _environment_manifest,
    _json_write,
    _protected_hashes,
    _sha256,
)


REQUIRED_EVIDENCE_FILES = frozenset(
    {
        "conda_packages.json",
        "config_snapshot.json",
        "environment.json",
        "evidence.npz",
        "git_status.txt",
        "installed_packages.json",
        "parameter_vectors.csv",
        "pip_freeze.txt",
        "preregistration.json",
        "process_noise_covariances.csv",
        "protected_artifact_integrity.json",
        "numerical_stability_check.json",
        "registry_entry.json",
        "resource_preflight.json",
        "source_snapshot/__init__.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/imm.py",
        "source_snapshot/methods.py",
        "source_snapshot/model_probability_validation.py",
        "source_snapshot/preflight.py",
        "source_snapshot/run_model_probability_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/test_hbv_model_probability_validation.py",
        "summary.json",
    }
)


def _source_path(root: Path, configured: str) -> Path:
    path = Path(configured)
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def _checked_table(root: Path, source: dict, dtypes: dict[str, type]) -> pd.DataFrame:
    path = _source_path(root, str(source["path"]))
    if _sha256(path) != str(source["sha256"]):
        raise ValueError(f"source checksum mismatch: {path}")
    return pd.read_csv(path, dtype=dtypes)


def _load_parameter_vectors(
    root: Path, config: dict
) -> tuple[dict[str, dict[str, float]], bytes, str]:
    source = config["parameter_source"]
    table = _checked_table(root, source, {"basin_id": str, "parameter_id": str})
    required = {"basin_id", "parameter_id", *PARAMETER_NAMES}
    if not required.issubset(table.columns):
        raise ValueError("parameter source is missing required columns")
    basin = str(source["source_basin_id"])
    parameter_ids = tuple(str(value) for value in source["parameter_ids"])
    if len(parameter_ids) != 3 or len(set(parameter_ids)) != 3:
        raise ValueError("parameter source must name exactly three candidates")
    basin_rows = table.loc[table["basin_id"].astype(str).str.zfill(8) == basin.zfill(8)]
    selected_rows = []
    vectors = {}
    for parameter_id in parameter_ids:
        rows = basin_rows.loc[basin_rows["parameter_id"].astype(str) == parameter_id]
        if len(rows) != 1:
            raise ValueError(f"expected one parameter row for {parameter_id!r}")
        row = rows.iloc[0]
        selected_rows.append(row)
        vectors[parameter_id] = {name: float(row[name]) for name in PARAMETER_NAMES}
    selected = pd.DataFrame(selected_rows)[["basin_id", "parameter_id", *PARAMETER_NAMES]]
    csv_bytes = selected.to_csv(index=False, lineterminator="\n").encode("utf-8")
    return vectors, csv_bytes, hashlib.sha256(csv_bytes).hexdigest()


def _load_process_covariances(
    root: Path, config: dict
) -> tuple[dict[str, np.ndarray], dict[str, float], bytes, str]:
    source = config["process_noise_source"]
    table = _checked_table(root, source, {"basin_id": str, "process_id": str})
    variance_columns = [f"variance_{name}" for name in STATE_NAMES]
    required = {"basin_id", "process_id", *variance_columns}
    if not required.issubset(table.columns):
        raise ValueError("process-noise source is missing required columns")
    basin = str(source["source_basin_id"])
    process_ids = tuple(str(value) for value in source["process_ids"])
    if len(process_ids) != 3 or len(set(process_ids)) != 3:
        raise ValueError("process-noise source must name exactly three candidates")
    basin_rows = table.loc[table["basin_id"].astype(str).str.zfill(8) == basin.zfill(8)]
    selected_rows = []
    covariances = {}
    scales = {}
    for index, process_id in enumerate(process_ids):
        rows = basin_rows.loc[basin_rows["process_id"].astype(str) == process_id]
        if len(rows) != 1:
            raise ValueError(f"expected one process-noise row for {process_id!r}")
        row = rows.iloc[0]
        diagonal = np.asarray([float(row[column]) for column in variance_columns])
        if np.any(diagonal[:5] <= 0.0) or np.any(diagonal[5:] != 0.0):
            raise ValueError("process covariances must have five positive and ten zero variances")
        covariances[process_id] = np.diag(diagonal)
        scales[process_id] = float(row["variance_scale"]) if "variance_scale" in row else float(index)
        selected_rows.append(row)
    output_columns = ["basin_id", "process_id"]
    if "variance_scale" in table.columns:
        output_columns.append("variance_scale")
    output_columns.extend(variance_columns)
    selected = pd.DataFrame(selected_rows)[output_columns]
    csv_bytes = selected.to_csv(index=False, lineterminator="\n").encode("utf-8")
    return covariances, scales, csv_bytes, hashlib.sha256(csv_bytes).hexdigest()


def _bootstrap_median_interval(
    values: np.ndarray, replicates: int, seed: int
) -> tuple[float, float]:
    if replicates <= 0:
        raise ValueError("bootstrap replicates must be positive")
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(replicates, len(values)))
    statistics = np.median(values[indices], axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def _resource_preflight(config: dict) -> dict:
    trials = len(config["trial_seeds"])
    days = int(config["days"])
    float_bytes = np.dtype(np.float64).itemsize
    dynamic_float_values_per_trial_day = 50
    dynamic_integer_values_per_trial_day = 1
    dynamic_boolean_values_per_trial_day = 1
    dynamic_array_bytes = trials * days * (
        dynamic_float_values_per_trial_day * float_bytes
        + dynamic_integer_values_per_trial_day * np.dtype(np.int64).itemsize
        + dynamic_boolean_values_per_trial_day * np.dtype(np.bool_).itemsize
    )
    parameter_ids = [str(value) for value in config["parameter_source"]["parameter_ids"]]
    process_ids = [str(value) for value in config["process_noise_source"]["process_ids"]]
    candidate_ids = [
        f"{parameter_id}__{process_id}"
        for parameter_id in parameter_ids
        for process_id in process_ids
    ]
    candidate_factors = [
        (parameter_id, process_id)
        for parameter_id in parameter_ids
        for process_id in process_ids
    ]
    static_array_bytes = int(
        np.asarray(config["trial_seeds"], dtype=np.int64).nbytes
        + np.asarray(parameter_ids).nbytes
        + np.asarray(process_ids).nbytes
        + np.asarray(candidate_ids).nbytes
        + np.asarray(candidate_factors).nbytes
        + 2 * np.empty(9, dtype=np.int32).nbytes
        + np.empty((3, len(PARAMETER_NAMES)), dtype=np.float64).nbytes
        + np.empty((3, len(STATE_NAMES), len(STATE_NAMES)), dtype=np.float64).nbytes
        + np.empty((9, 9), dtype=np.float64).nbytes
        + 3 * np.empty(9, dtype=np.float64).nbytes
    )
    per_trial_score_array_bytes = int(6 * trials * float_bytes)
    raw_array_bytes = dynamic_array_bytes + static_array_bytes + per_trial_score_array_bytes
    packaging_and_runtime_allowance = 32 * 1024 * 1024
    estimated_peak = int(4 * raw_array_bytes + packaging_and_runtime_allowance)
    available = int(psutil.virtual_memory().available)
    task_specific_reserve = int(2 * estimated_peak + 64 * 1024 * 1024)
    required_available = estimated_peak + task_specific_reserve
    safe = available >= required_available
    result = {
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "trial_count": trials,
        "days_per_trial": days,
        "candidate_count": 9,
        "execution_parallelism": 1,
        "dynamic_float_values_per_trial_day": dynamic_float_values_per_trial_day,
        "dynamic_integer_values_per_trial_day": dynamic_integer_values_per_trial_day,
        "dynamic_boolean_values_per_trial_day": dynamic_boolean_values_per_trial_day,
        "dynamic_array_bytes": dynamic_array_bytes,
        "static_array_bytes": static_array_bytes,
        "per_trial_score_array_bytes": per_trial_score_array_bytes,
        "raw_numeric_array_bytes": raw_array_bytes,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "available_physical_memory_bytes": available,
        "task_specific_reserve_bytes": task_specific_reserve,
        "task_specific_required_available_bytes": required_available,
        "available_after_estimated_peak_bytes": available - estimated_peak,
        "safe_to_run": safe,
        "estimation_basis": (
            "four copies of every array saved in evidence.npz, including labels, the frozen "
            "extreme-likelihood check, probabilities, likelihoods, truth and random arrays, plus "
            "a 32 MiB packaging allowance and a task-specific two-estimate and 64 MiB reserve"
        ),
        "universal_memory_threshold_used": False,
    }
    if not safe:
        raise MemoryError("model-probability validation lacks its estimated task-specific margin")
    return result


def _verify_complete_output(output: Path, expected_config: dict) -> tuple[dict, dict]:
    checksums = json.loads((output / "checksums.json").read_text(encoding="utf-8"))
    if set(checksums) != REQUIRED_EVIDENCE_FILES:
        raise ValueError("required evidence manifest mismatch")
    actual = {path.relative_to(output).as_posix() for path in output.rglob("*") if path.is_file()}
    if actual != REQUIRED_EVIDENCE_FILES | {"checksums.json"}:
        raise ValueError("required evidence file set mismatch")
    for relative, expected in checksums.items():
        if _sha256(output / relative) != expected:
            raise ValueError(f"existing evidence checksum mismatch: {relative}")
    if json.loads((output / "config_snapshot.json").read_text(encoding="utf-8")) != expected_config:
        raise ValueError("existing evidence config mismatch")
    preregistration = json.loads((output / "preregistration.json").read_text(encoding="utf-8"))
    if preregistration.get("config_sha256") != _sha256(output / "config_snapshot.json"):
        raise ValueError("preregistration config checksum mismatch")
    return (
        json.loads((output / "summary.json").read_text(encoding="utf-8")),
        json.loads((output / "registry_entry.json").read_text(encoding="utf-8")),
    )


def _independent_update(prior: np.ndarray, log_likelihoods: np.ndarray) -> np.ndarray:
    log_joint = np.log(prior) + log_likelihoods
    shifted = log_joint - np.max(log_joint)
    weights = np.exp(shifted)
    return weights / weights.sum()


def run(repo_root: Path, config_path: Path, output_dir: Path, registry_path: Path) -> dict:
    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    registry = registry_path.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    preregistry = registry.with_name(registry.stem + ".preregistered.json")
    config = json.loads(config_file.read_text(encoding="utf-8"))
    if output.name != str(config["experiment_id"]):
        raise ValueError("output directory name must equal experiment_id")
    if output.exists():
        if registry.exists() or incomplete.exists():
            raise FileExistsError(f"refusing to overwrite completed evidence {output}")
        summary, registry_entry = _verify_complete_output(output, config)
        _atomic_json_write(registry, registry_entry)
        if summary.get("status") != "passed":
            raise RuntimeError(f"model-probability validation failed; see {output / 'summary.json'}")
        return summary
    if incomplete.exists() or registry.exists() or preregistry.exists():
        raise FileExistsError("refusing to overwrite incomplete evidence or registry")

    vectors, parameter_csv, parameter_snapshot_hash = _load_parameter_vectors(root, config)
    covariances, scales, process_csv, process_snapshot_hash = _load_process_covariances(
        root, config
    )
    parameter_ids = tuple(vectors)
    process_ids = tuple(covariances)
    definitions = tuple(
        MethodCandidate(
            candidate_id=f"{parameter_id}__{process_id}",
            parameter_id=parameter_id,
            process_id=process_id,
            process_scale=scales[process_id],
            parameters=vectors[parameter_id].copy(),
            process_covariance=covariances[process_id].copy(),
        )
        for parameter_id in parameter_ids
        for process_id in process_ids
    )
    candidate_factors = tuple(
        (definition.parameter_id, definition.process_id) for definition in definitions
    )
    transition = build_factorial_transition_matrix(
        definitions, float(config["factor_stay_probability"])
    )
    trial_seeds = tuple(int(value) for value in config["trial_seeds"])
    if not trial_seeds or len(set(trial_seeds)) != len(trial_seeds):
        raise ValueError("trial_seeds must be nonempty and unique")
    if config["bootstrap"].get("unit") != "trial":
        raise ValueError("bootstrap unit must be trial")
    prefix_days = int(config.get("causal_prefix_days", min(10, int(config["days"]))))
    if prefix_days <= 0 or prefix_days > int(config["days"]):
        raise ValueError("causal_prefix_days must be within the full duration")
    extreme_log_likelihoods = np.asarray(
        config.get(
            "extreme_log_likelihood_vector",
            [-1e300, -1e250, -1e200, -1e150, -1e100, -1e50, -100.0, -10.0, 0.0],
        ),
        dtype=np.float64,
    )
    if extreme_log_likelihoods.shape != (9,) or not np.all(
        np.isfinite(extreme_log_likelihoods)
    ):
        raise ValueError("extreme_log_likelihood_vector must contain nine finite values")
    extreme_prior_probabilities = np.full(9, 1.0 / 9.0)

    registered_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "experiment_id": config["experiment_id"],
        "status": "preregistered",
        "registered_at": registered_at,
        "config_sha256": _sha256(config_file),
        "trial_seeds": list(trial_seeds),
        "candidate_ids": [definition.candidate_id for definition in definitions],
        "candidate_factors": [list(value) for value in candidate_factors],
        "factor_stay_probability": float(config["factor_stay_probability"]),
        "emission_model": "two independent synthetic Gaussian factor diagnostics",
        "extreme_log_likelihood_vector": extreme_log_likelihoods.tolist(),
        "extreme_prior_probabilities": extreme_prior_probabilities.tolist(),
        "state_interaction": False,
        "hydrologic_state_propagation": False,
        "bootstrap_unit": "trial",
        "bootstrap_replicates": int(config["bootstrap"]["replicates"]),
        "gates": config["gates"],
    }
    _atomic_json_write(preregistry, preregistration)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    resource_preflight = _resource_preflight(config)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))

    common_arguments = {
        "trial_seeds": trial_seeds,
        "parameter_ids": parameter_ids,
        "process_ids": process_ids,
        "candidate_factors": candidate_factors,
        "transition_matrix": transition,
        "factor_emission_means": config["factor_emission_means"],
        "emission_standard_deviation": config["emission_standard_deviation"],
    }
    result = run_model_probability_validation(days=config["days"], **common_arguments)
    prefix = run_model_probability_validation(days=prefix_days, **common_arguments)
    extreme_posterior_probabilities = update_model_probabilities(
        extreme_prior_probabilities, extreme_log_likelihoods
    )
    extreme_independent_posterior = _independent_update(
        extreme_prior_probabilities, extreme_log_likelihoods
    )
    extreme_all_finite = bool(np.all(np.isfinite(extreme_posterior_probabilities)))
    extreme_all_nonnegative = bool(np.all(extreme_posterior_probabilities >= 0.0))
    extreme_normalization_error = float(abs(extreme_posterior_probabilities.sum() - 1.0))
    extreme_reconstruction_error = float(
        np.max(np.abs(extreme_posterior_probabilities - extreme_independent_posterior))
    )
    extreme_argmax = int(np.argmax(extreme_posterior_probabilities))

    prefix_errors = [
        np.max(np.abs(result.transition_uniforms[:, :prefix_days] - prefix.transition_uniforms)),
        np.max(
            np.abs(
                result.emission_standard_normals[:, :prefix_days]
                - prefix.emission_standard_normals
            )
        ),
        np.max(np.abs(result.observations[:, :prefix_days] - prefix.observations)),
        np.max(
            np.abs(
                result.candidate_log_likelihoods[:, :prefix_days]
                - prefix.candidate_log_likelihoods
            )
        ),
        np.max(
            np.abs(
                result.posterior_probabilities[:, :prefix_days]
                - prefix.posterior_probabilities
            )
        ),
    ]
    if not np.array_equal(
        result.true_candidate_indices[:, :prefix_days], prefix.true_candidate_indices
    ):
        prefix_errors.append(np.inf)
    causal_prefix_error = float(np.max(prefix_errors))

    trial_count, day_count = result.true_candidate_indices.shape
    recursion_error = 0.0
    posterior_reconstruction_error = 0.0
    factor_marginal_transition_error = 0.0
    factor_transition = build_transition_matrix(3, float(config["factor_stay_probability"]))
    expected_factorial_transition = np.kron(factor_transition, factor_transition)
    factorial_transition_contract_error = float(
        np.max(np.abs(transition - expected_factorial_transition))
    )
    uniform = np.full(9, 1.0 / 9.0)
    for trial in range(trial_count):
        for day in range(day_count):
            expected_prior = (
                uniform
                if day == 0
                else transition.T @ result.posterior_probabilities[trial, day - 1]
            )
            expected_prior = expected_prior / expected_prior.sum()
            recursion_error = max(
                recursion_error,
                float(np.max(np.abs(expected_prior - result.prior_probabilities[trial, day]))),
            )
            expected_posterior = _independent_update(
                expected_prior, result.candidate_log_likelihoods[trial, day]
            )
            posterior_reconstruction_error = max(
                posterior_reconstruction_error,
                float(
                    np.max(
                        np.abs(expected_posterior - result.posterior_probabilities[trial, day])
                    )
                ),
            )
            if day > 0:
                expected_parameter = (
                    factor_transition.T @ result.parameter_posterior_marginals[trial, day - 1]
                )
                expected_process = (
                    factor_transition.T @ result.process_posterior_marginals[trial, day - 1]
                )
                factor_marginal_transition_error = max(
                    factor_marginal_transition_error,
                    float(
                        np.max(
                            np.abs(
                                expected_parameter
                                - result.parameter_prior_marginals[trial, day]
                            )
                        )
                    ),
                    float(
                        np.max(
                            np.abs(
                                expected_process - result.process_prior_marginals[trial, day]
                            )
                        )
                    ),
                )

    true = result.true_candidate_indices
    row = np.arange(trial_count)[:, None]
    day = np.arange(day_count)[None, :]
    true_parameter = true // 3
    true_process = true % 3
    prior_true = result.prior_probabilities[row, day, true]
    posterior_true = result.posterior_probabilities[row, day, true]
    minimum = np.finfo(np.float64).tiny
    prior_log_loss_by_trial = -np.mean(np.log(np.maximum(prior_true, minimum)), axis=1)
    posterior_log_loss_by_trial = -np.mean(np.log(np.maximum(posterior_true, minimum)), axis=1)
    targets = np.eye(9)[true]
    prior_brier_by_trial = np.mean(
        np.sum(np.square(result.prior_probabilities - targets), axis=2), axis=1
    )
    posterior_brier_by_trial = np.mean(
        np.sum(np.square(result.posterior_probabilities - targets), axis=2), axis=1
    )
    log_loss_improvement = prior_log_loss_by_trial - posterior_log_loss_by_trial
    brier_improvement = prior_brier_by_trial - posterior_brier_by_trial
    predicted_joint = np.argmax(result.posterior_probabilities, axis=2)
    predicted_parameter = np.argmax(result.parameter_posterior_marginals, axis=2)
    predicted_process = np.argmax(result.process_posterior_marginals, axis=2)
    prior_predicted_joint = np.argmax(result.prior_probabilities, axis=2)
    prior_predicted_parameter = np.argmax(result.parameter_prior_marginals, axis=2)
    prior_predicted_process = np.argmax(result.process_prior_marginals, axis=2)
    joint_accuracy = float(np.mean(predicted_joint == true))
    joint_prior_accuracy = float(np.mean(prior_predicted_joint == true))
    parameter_accuracy = float(np.mean(predicted_parameter == true_parameter))
    process_accuracy = float(np.mean(predicted_process == true_process))
    parameter_prior_accuracy = float(np.mean(prior_predicted_parameter == true_parameter))
    process_prior_accuracy = float(np.mean(prior_predicted_process == true_process))
    switch_count = int(np.count_nonzero(result.switch_mask))
    switch_posterior_accuracy = float(
        np.mean(predicted_joint[result.switch_mask] == true[result.switch_mask])
    ) if switch_count else float("nan")
    switch_prior_accuracy = float(
        np.mean(prior_predicted_joint[result.switch_mask] == true[result.switch_mask])
    ) if switch_count else float("nan")
    switch_parameter_prior_accuracy = float(
        np.mean(
            prior_predicted_parameter[result.switch_mask]
            == true_parameter[result.switch_mask]
        )
    ) if switch_count else float("nan")
    switch_parameter_posterior_accuracy = float(
        np.mean(predicted_parameter[result.switch_mask] == true_parameter[result.switch_mask])
    ) if switch_count else float("nan")
    switch_process_prior_accuracy = float(
        np.mean(prior_predicted_process[result.switch_mask] == true_process[result.switch_mask])
    ) if switch_count else float("nan")
    switch_process_posterior_accuracy = float(
        np.mean(predicted_process[result.switch_mask] == true_process[result.switch_mask])
    ) if switch_count else float("nan")
    non_switch_or_initial_mask = ~result.switch_mask
    non_switch_joint_prior_accuracy = float(
        np.mean(
            prior_predicted_joint[non_switch_or_initial_mask]
            == true[non_switch_or_initial_mask]
        )
    )
    non_switch_joint_posterior_accuracy = float(
        np.mean(predicted_joint[non_switch_or_initial_mask] == true[non_switch_or_initial_mask])
    )
    non_switch_parameter_prior_accuracy = float(
        np.mean(
            prior_predicted_parameter[non_switch_or_initial_mask]
            == true_parameter[non_switch_or_initial_mask]
        )
    )
    non_switch_parameter_posterior_accuracy = float(
        np.mean(
            predicted_parameter[non_switch_or_initial_mask]
            == true_parameter[non_switch_or_initial_mask]
        )
    )
    non_switch_process_prior_accuracy = float(
        np.mean(
            prior_predicted_process[non_switch_or_initial_mask]
            == true_process[non_switch_or_initial_mask]
        )
    )
    non_switch_process_posterior_accuracy = float(
        np.mean(
            predicted_process[non_switch_or_initial_mask]
            == true_process[non_switch_or_initial_mask]
        )
    )
    switch_true_prior_median = float(np.median(prior_true[result.switch_mask])) if switch_count else float("nan")
    switch_true_posterior_median = (
        float(np.median(posterior_true[result.switch_mask])) if switch_count else float("nan")
    )
    switch_true_probability_improved_fraction = (
        float(
            np.mean(
                posterior_true[result.switch_mask] > prior_true[result.switch_mask]
            )
        )
        if switch_count
        else float("nan")
    )
    posterior_grid = result.posterior_probabilities.reshape(trial_count, day_count, 3, 3)
    factorized = (
        result.parameter_posterior_marginals[:, :, :, None]
        * result.process_posterior_marginals[:, :, None, :]
    )
    factorization_error = float(np.max(np.abs(posterior_grid - factorized)))

    bootstrap = config["bootstrap"]
    log_loss_interval = _bootstrap_median_interval(
        log_loss_improvement,
        int(bootstrap["replicates"]),
        int(bootstrap["seed"]),
    )
    brier_interval = _bootstrap_median_interval(
        brier_improvement,
        int(bootstrap["replicates"]),
        int(bootstrap["seed"]) + 1,
    )
    gate_values = {
        "joint_log_loss_improved_trial_count": int(np.count_nonzero(log_loss_improvement > 0.0)),
        "joint_brier_improved_trial_count": int(np.count_nonzero(brier_improvement > 0.0)),
        "joint_log_loss_improvement_bootstrap_lower": log_loss_interval[0],
        "joint_brier_improvement_bootstrap_lower": brier_interval[0],
        "joint_posterior_accuracy": joint_accuracy,
        "parameter_posterior_accuracy": parameter_accuracy,
        "process_posterior_accuracy": process_accuracy,
        "recursion_maximum_absolute_error": recursion_error,
        "posterior_reconstruction_maximum_absolute_error": posterior_reconstruction_error,
        "factor_marginal_transition_maximum_absolute_error": factor_marginal_transition_error,
        "factorial_transition_contract_maximum_absolute_error": factorial_transition_contract_error,
        "posterior_factorization_maximum_absolute_error": factorization_error,
        "causal_prefix_maximum_absolute_error": causal_prefix_error,
        "extreme_probability_all_finite": extreme_all_finite,
        "extreme_probability_all_nonnegative": extreme_all_nonnegative,
        "extreme_probability_normalization_absolute_error": extreme_normalization_error,
        "extreme_probability_reconstruction_maximum_absolute_error": extreme_reconstruction_error,
        "extreme_probability_argmax": extreme_argmax,
    }
    gates = config["gates"]
    gate_pass = bool(
        gate_values["joint_log_loss_improved_trial_count"]
        >= int(gates["joint_log_loss_improved_trial_count_minimum"])
        and gate_values["joint_brier_improved_trial_count"]
        >= int(gates["joint_brier_improved_trial_count_minimum"])
        and gate_values["joint_posterior_accuracy"]
        >= float(gates["joint_posterior_accuracy_minimum"])
        and gate_values["parameter_posterior_accuracy"]
        >= float(gates["parameter_posterior_accuracy_minimum"])
        and gate_values["process_posterior_accuracy"]
        >= float(gates["process_posterior_accuracy_minimum"])
        and gate_values["recursion_maximum_absolute_error"]
        <= float(gates["recursion_maximum_absolute_error"])
        and gate_values["factor_marginal_transition_maximum_absolute_error"]
        <= float(gates["factor_marginal_transition_maximum_absolute_error"])
        and gate_values["factorial_transition_contract_maximum_absolute_error"]
        <= float(gates.get("factorial_transition_contract_maximum_absolute_error", 1e-12))
        and gate_values["posterior_factorization_maximum_absolute_error"]
        <= float(gates.get("posterior_factorization_maximum_absolute_error", 1e-12))
        and gate_values["posterior_reconstruction_maximum_absolute_error"]
        <= float(gates.get("posterior_reconstruction_maximum_absolute_error", 1e-12))
        and gate_values["causal_prefix_maximum_absolute_error"]
        <= float(gates.get("causal_prefix_maximum_absolute_error", 0.0))
        and gate_values["joint_log_loss_improvement_bootstrap_lower"]
        >= float(gates.get("joint_log_loss_improvement_bootstrap_lower_minimum", -1e300))
        and gate_values["joint_brier_improvement_bootstrap_lower"]
        >= float(gates.get("joint_brier_improvement_bootstrap_lower_minimum", -1e300))
        and gate_values["extreme_probability_all_finite"]
        and gate_values["extreme_probability_all_nonnegative"]
        and gate_values["extreme_probability_normalization_absolute_error"]
        <= float(gates.get("extreme_probability_normalization_absolute_error", 1e-15))
        and gate_values["extreme_probability_reconstruction_maximum_absolute_error"]
        <= float(
            gates.get("extreme_probability_reconstruction_maximum_absolute_error", 1e-15)
        )
        and gate_values["extreme_probability_argmax"]
        == int(gates.get("extreme_probability_expected_argmax", 8))
    )
    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    protected_unchanged = protected_before == protected_after
    passed = bool(gate_pass and protected_unchanged)
    finished_at = dt.datetime.now(dt.timezone.utc).isoformat()
    numerical_stability_check = {
        "check_type": "frozen extreme-log-likelihood execution certificate",
        "executed_during_experiment": True,
        "input_prior_probabilities": extreme_prior_probabilities.tolist(),
        "input_log_likelihoods": extreme_log_likelihoods.tolist(),
        "production_output_probabilities": extreme_posterior_probabilities.tolist(),
        "independent_output_probabilities": extreme_independent_posterior.tolist(),
        "all_finite": extreme_all_finite,
        "all_nonnegative": extreme_all_nonnegative,
        "normalization_absolute_error": extreme_normalization_error,
        "reconstruction_maximum_absolute_error": extreme_reconstruction_error,
        "argmax": extreme_argmax,
        "gates": {
            "normalization_absolute_error_maximum": float(
                gates.get("extreme_probability_normalization_absolute_error", 1e-15)
            ),
            "reconstruction_maximum_absolute_error": float(
                gates.get(
                    "extreme_probability_reconstruction_maximum_absolute_error", 1e-15
                )
            ),
            "expected_argmax": int(gates.get("extreme_probability_expected_argmax", 8)),
            "all_finite_required": True,
            "all_nonnegative_required": True,
        },
        "passed": bool(
            extreme_all_finite
            and extreme_all_nonnegative
            and extreme_normalization_error
            <= float(gates.get("extreme_probability_normalization_absolute_error", 1e-15))
            and extreme_reconstruction_error
            <= float(
                gates.get(
                    "extreme_probability_reconstruction_maximum_absolute_error", 1e-15
                )
            )
            and extreme_argmax == int(gates.get("extreme_probability_expected_argmax", 8))
        ),
    }
    summary = {
        "experiment_id": config["experiment_id"],
        "status": "passed" if passed else "failed",
        "started_at": started_at,
        "finished_at": finished_at,
        "trial_count": trial_count,
        "days_per_trial": day_count,
        "candidate_count": 9,
        "parameter_count": 3,
        "process_noise_count": 3,
        "candidate_ids": [definition.candidate_id for definition in definitions],
        "factor_stay_probability": float(config["factor_stay_probability"]),
        "joint_candidate_stay_probability": float(np.diag(transition)[0]),
        "factorial_transition_contract_maximum_absolute_error": factorial_transition_contract_error,
        "state_interaction": False,
        "hydrologic_state_propagation": False,
        "emission_model": "two independent synthetic Gaussian factor diagnostics",
        "causal_prefix_days": prefix_days,
        "true_switch_count": switch_count,
        "joint_prior_accuracy": joint_prior_accuracy,
        "joint_posterior_accuracy": joint_accuracy,
        "parameter_prior_accuracy": parameter_prior_accuracy,
        "parameter_posterior_accuracy": parameter_accuracy,
        "process_prior_accuracy": process_prior_accuracy,
        "process_posterior_accuracy": process_accuracy,
        "switch_day_joint_posterior_accuracy": switch_posterior_accuracy,
        "switch_day_joint_prior_accuracy": switch_prior_accuracy,
        "switch_day_parameter_prior_accuracy": switch_parameter_prior_accuracy,
        "switch_day_parameter_posterior_accuracy": switch_parameter_posterior_accuracy,
        "switch_day_process_prior_accuracy": switch_process_prior_accuracy,
        "switch_day_process_posterior_accuracy": switch_process_posterior_accuracy,
        "non_switch_or_initial_day_joint_prior_accuracy": non_switch_joint_prior_accuracy,
        "non_switch_or_initial_day_joint_posterior_accuracy": non_switch_joint_posterior_accuracy,
        "non_switch_or_initial_day_parameter_prior_accuracy": non_switch_parameter_prior_accuracy,
        "non_switch_or_initial_day_parameter_posterior_accuracy": non_switch_parameter_posterior_accuracy,
        "non_switch_or_initial_day_process_prior_accuracy": non_switch_process_prior_accuracy,
        "non_switch_or_initial_day_process_posterior_accuracy": non_switch_process_posterior_accuracy,
        "switch_day_true_candidate_prior_probability_median": switch_true_prior_median,
        "switch_day_true_candidate_posterior_probability_median": switch_true_posterior_median,
        "switch_day_true_candidate_probability_improved_fraction": switch_true_probability_improved_fraction,
        "joint_log_loss_prior_by_trial": prior_log_loss_by_trial.tolist(),
        "joint_log_loss_posterior_by_trial": posterior_log_loss_by_trial.tolist(),
        "joint_log_loss_improvement_by_trial": log_loss_improvement.tolist(),
        "joint_log_loss_improvement_bootstrap_interval": list(log_loss_interval),
        "joint_brier_prior_by_trial": prior_brier_by_trial.tolist(),
        "joint_brier_posterior_by_trial": posterior_brier_by_trial.tolist(),
        "joint_brier_improvement_by_trial": brier_improvement.tolist(),
        "joint_brier_improvement_bootstrap_interval": list(brier_interval),
        "posterior_factorization_maximum_absolute_error": factorization_error,
        "numerical_stability_check": numerical_stability_check,
        "gate_values": gate_values,
        "gates": gates,
        "gate_pass": gate_pass,
        "parameter_source_sha256": config["parameter_source"]["sha256"],
        "process_noise_source_sha256": config["process_noise_source"]["sha256"],
        "selected_parameter_snapshot_sha256": parameter_snapshot_hash,
        "selected_process_noise_snapshot_sha256": process_snapshot_hash,
        "protected_artifacts_unchanged": protected_unchanged,
        "scope_limit": (
            "This component tests only probability transition, likelihood updating and factor "
            "marginalization on the frozen three-by-three candidate labels using synthetic Gaussian "
            "diagnostics; it does not test hydrologic likelihood adequacy, state interaction or forecasting."
        ),
    }
    registry_entry = {
        "experiment_id": config["experiment_id"],
        "type": "closed_truth_nine_candidate_probability_recursion",
        "hypothesis": "the frozen factorial transition and likelihood update track a known nine-mode truth",
        "base_config": str(config_file),
        "changed_factor": "observation likelihood information versus transition-only prior probability",
        "fixed_factors": "three parameter labels by three process-noise labels, factor stay probability 0.98",
        "seeds": list(trial_seeds),
        "status": summary["status"],
        "run_dir": str(output),
        "metrics_path": str(output / "summary.json"),
        "paper_name": "synthetic model-probability component",
        "notes": summary["scope_limit"],
    }
    environment, git_status, installed_packages, conda_packages, pip_freeze = (
        _environment_manifest(root, started_at)
    )
    integrity = {
        "configured_paths": list(config.get("protected_paths", ())),
        "before": protected_before,
        "after": protected_after,
        "status": "unchanged" if protected_unchanged else "changed",
    }

    incomplete.mkdir(parents=True)
    try:
        shutil.copy2(config_file, incomplete / "config_snapshot.json")
        (incomplete / "parameter_vectors.csv").write_bytes(parameter_csv)
        (incomplete / "process_noise_covariances.csv").write_bytes(process_csv)
        _json_write(incomplete / "preregistration.json", preregistration)
        _json_write(incomplete / "summary.json", summary)
        _json_write(
            incomplete / "numerical_stability_check.json", numerical_stability_check
        )
        _json_write(incomplete / "registry_entry.json", registry_entry)
        _json_write(incomplete / "resource_preflight.json", resource_preflight)
        _json_write(incomplete / "environment.json", environment)
        _json_write(incomplete / "installed_packages.json", installed_packages)
        _json_write(incomplete / "conda_packages.json", conda_packages)
        _json_write(incomplete / "protected_artifact_integrity.json", integrity)
        (incomplete / "git_status.txt").write_text(git_status + "\n", encoding="utf-8")
        (incomplete / "pip_freeze.txt").write_text(pip_freeze, encoding="utf-8")
        np.savez_compressed(
            incomplete / "evidence.npz",
            trial_seeds=result.trial_seeds,
            parameter_ids=np.asarray(result.parameter_ids),
            process_ids=np.asarray(result.process_ids),
            candidate_ids=np.asarray([definition.candidate_id for definition in definitions]),
            candidate_factors=np.asarray(result.candidate_factors),
            candidate_parameter_indices=result.candidate_parameter_indices,
            candidate_process_indices=result.candidate_process_indices,
            parameter_vectors=np.asarray(
                [[vectors[key][name] for name in PARAMETER_NAMES] for key in parameter_ids]
            ),
            process_covariances=np.stack([covariances[key] for key in process_ids]),
            transition_matrix=result.transition_matrix,
            transition_uniforms=result.transition_uniforms,
            emission_standard_normals=result.emission_standard_normals,
            true_candidate_indices=result.true_candidate_indices,
            observations=result.observations,
            parameter_log_likelihoods=result.parameter_log_likelihoods,
            process_log_likelihoods=result.process_log_likelihoods,
            candidate_log_likelihoods=result.candidate_log_likelihoods,
            prior_probabilities=result.prior_probabilities,
            posterior_probabilities=result.posterior_probabilities,
            parameter_prior_marginals=result.parameter_prior_marginals,
            parameter_posterior_marginals=result.parameter_posterior_marginals,
            process_prior_marginals=result.process_prior_marginals,
            process_posterior_marginals=result.process_posterior_marginals,
            switch_mask=result.switch_mask,
            extreme_prior_probabilities=extreme_prior_probabilities,
            extreme_log_likelihoods=extreme_log_likelihoods,
            extreme_posterior_probabilities=extreme_posterior_probabilities,
            prior_log_loss_by_trial=prior_log_loss_by_trial,
            posterior_log_loss_by_trial=posterior_log_loss_by_trial,
            log_loss_improvement_by_trial=log_loss_improvement,
            prior_brier_by_trial=prior_brier_by_trial,
            posterior_brier_by_trial=posterior_brier_by_trial,
            brier_improvement_by_trial=brier_improvement,
        )
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        sources = {
            "__init__.py": root / "src" / "hbv_multilead_joint_uncertainty" / "__init__.py",
            "model_probability_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "model_probability_validation.py",
            "methods.py": root / "src" / "hbv_multilead_joint_uncertainty" / "methods.py",
            "run_model_probability_validation.py": Path(__file__).resolve(),
            "run_synthetic_truth_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "scripts"
            / "run_synthetic_truth_validation.py",
            "hbv_adapter.py": root / "src" / "hbv_joint_uncertainty" / "hbv_adapter.py",
            "preflight.py": root / "src" / "hbv_joint_uncertainty" / "preflight.py",
            "imm.py": root / "src" / "hbv_joint_uncertainty" / "imm.py",
            "test_hbv_model_probability_validation.py": root
            / "test"
            / "test_hbv_model_probability_validation.py",
        }
        for name, source in sources.items():
            shutil.copy2(source, snapshot / name)
        evidence_paths = sorted(path for path in incomplete.rglob("*") if path.is_file())
        checksums = {
            path.relative_to(incomplete).as_posix(): _sha256(path) for path in evidence_paths
        }
        if set(checksums) != REQUIRED_EVIDENCE_FILES:
            raise ValueError("required evidence manifest mismatch while packaging")
        _json_write(incomplete / "checksums.json", checksums)
        incomplete.replace(output)
        _atomic_json_write(registry, registry_entry)
    except Exception:
        if incomplete.exists():
            shutil.rmtree(incomplete)
        raise
    if not passed:
        raise RuntimeError(f"model-probability validation failed; see {output / 'summary.json'}")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--registry-path", type=Path, required=True)
    args = parser.parse_args()
    run(args.repo_root, args.config, args.output_dir, args.registry_path)


if __name__ == "__main__":
    main()
