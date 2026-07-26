"""Run and package the closed nine-candidate observation-free forecast validation."""

from __future__ import annotations

import argparse
import datetime as dt
import inspect
import json
import shutil
import sys
from pathlib import Path

import numpy as np
import psutil


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.forecast import forecast_from_posterior  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import MethodCandidate  # noqa: E402
from hbv_multilead_joint_uncertainty.observation_free_forecast_validation import (  # noqa: E402
    run_observation_free_forecast_validation,
)
from hbv_multilead_joint_uncertainty.scripts.run_model_probability_validation import (  # noqa: E402
    _load_parameter_vectors,
    _load_process_covariances,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (  # noqa: E402
    _atomic_json_write,
    _environment_manifest,
    _json_write,
    _protected_hashes,
    _sha256,
)


IDENTITY_FORECAST_CONTRACT = {
    "candidate_probabilities": "fixed_at_final_assimilation_posterior",
    "model_transition": "identity",
    "cross_candidate_state_mixing": False,
}


REQUIRED_EVIDENCE_FILES = frozenset(
    {
        "conda_packages.json",
        "config_snapshot.json",
        "environment.json",
        "evidence.npz",
        "forecast_propagation_certificate.json",
        "git_status.txt",
        "installed_packages.json",
        "parameter_vectors.csv",
        "pip_freeze.txt",
        "preregistration.json",
        "process_noise_covariances.csv",
        "protected_artifact_integrity.json",
        "registry_entry.json",
        "resource_preflight.json",
        "source_snapshot/__init__.py",
        "source_snapshot/forecast.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/hbv_lite_numpy.py",
        "source_snapshot/imm.py",
        "source_snapshot/methods.py",
        "source_snapshot/observation_free_forecast_validation.py",
        "source_snapshot/preflight.py",
        "source_snapshot/run_model_probability_validation.py",
        "source_snapshot/run_observation_free_forecast_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/sigma_filter.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_multilead_forecast.py",
        "source_snapshot/test_hbv_observation_free_forecast_validation.py",
        "summary.json",
    }
)


def _forcing_realizations(config: dict) -> np.ndarray:
    seeds = tuple(int(value) for value in config["trial_seeds"])
    forcing = config["forcing"]
    days = int(forcing["warmup_days"]) + int(forcing["forecast_days"])
    if days <= 0:
        raise ValueError("forcing duration must be positive")
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    result = np.empty((len(seeds), days, 3), dtype=np.float64)
    for trial, seed in enumerate(seeds):
        rng = np.random.default_rng(seed)
        result[trial, :, 0] = rng.gamma(
            float(forcing["rain_shape"]), float(forcing["rain_scale"]), size=days
        )
        result[trial, :, 1] = np.maximum(0.0, 2.0 + np.sin(angle))
        result[trial, :, 2] = 4.0 + 12.0 * np.sin(angle - np.pi / 2.0)
    return result


def _numeric_array_byte_estimate(config: dict) -> int:
    trials = len(config["trial_seeds"])
    warmup = int(config["forcing"]["warmup_days"])
    days = int(config["forcing"]["forecast_days"])
    selected = 3
    candidates = 9
    states = 15
    float_shapes = [
        (trials, warmup + days, 3),
        (3, len(PARAMETER_NAMES)),
        (3, states, states),
        (candidates,),
        (trials, candidates, states),
        (trials, candidates, states, states),
        (trials, candidates, states),
        (trials, candidates, states, states),
        (trials, candidates),
        (trials, days),
        (trials, days, candidates),
        (trials, days, candidates),
        (trials, days, candidates, states),
        (trials, days, candidates, states),
        (trials, days, states),
        (trials, days, states),
        (trials, days),
        (trials, days, candidates),
        (trials, days, candidates),
        (trials, days, candidates, states),
        (trials, days, candidates, states, states),
        (trials, days, states),
        (trials, days, states, states),
        (trials, selected),
        (trials, selected, candidates),
        (trials, selected, candidates),
        (trials, selected, candidates, states),
        (trials, selected, candidates, states),
        (trials, selected, states),
        (trials, selected, states),
        (trials, selected),
        (trials, selected, candidates),
        (trials, selected, candidates),
        (trials, selected, candidates, states),
        (trials, selected, candidates, states),
        (trials, selected, states),
        (trials, selected, states),
    ]
    return int(
        trials * np.dtype(np.int64).itemsize
        + sum(int(np.prod(shape)) * np.dtype(np.float64).itemsize for shape in float_shapes)
    )


def _resource_preflight(config: dict) -> dict:
    expected = _numeric_array_byte_estimate(config)
    # The reference holds full candidate covariance paths and repeatedly creates 31
    # sigma points. Four evidence-sized copies plus 96 MiB bounds that live set.
    estimated_peak = int(4 * expected + 96 * 1024 * 1024)
    available = int(psutil.virtual_memory().available)
    reserve = int(max(estimated_peak // 2, 128 * 1024 * 1024))
    required = estimated_peak + reserve
    safe = available >= required
    result = {
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "trial_count": len(config["trial_seeds"]),
        "warmup_days": int(config["forcing"]["warmup_days"]),
        "forecast_days": int(config["forcing"]["forecast_days"]),
        "candidate_count": 9,
        "state_dimension": 15,
        "execution_parallelism": 1,
        "expected_saved_numeric_array_bytes": expected,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "available_physical_memory_bytes": available,
        "task_specific_reserve_bytes": reserve,
        "task_specific_required_available_bytes": required,
        "available_after_estimated_peak_bytes": available - estimated_peak,
        "safe_to_run": safe,
        "estimation_basis": (
            "four copies of all saved numeric arrays plus 96 MiB for one sequential "
            "nine-filter bank, independent 31-point transitions and compressed packaging; "
            "the reserve is the larger of half that estimate and 128 MiB"
        ),
        "universal_memory_threshold_used": False,
    }
    if not safe:
        raise MemoryError("forecast validation lacks its task-specific memory margin")
    return result


def _maximum_error(left, right) -> float:
    return float(np.max(np.abs(np.asarray(left) - np.asarray(right)), initial=0.0))


def _maximum_field_error(pairs) -> float:
    return max((_maximum_error(left, right) for left, right in pairs), default=0.0)


def _numeric_finiteness(arrays: dict[str, np.ndarray]) -> dict:
    names = [
        name
        for name, value in arrays.items()
        if np.issubdtype(np.asarray(value).dtype, np.number)
    ]
    nonfinite = [name for name in names if not np.all(np.isfinite(arrays[name]))]
    return {
        "numeric_array_names": names,
        "nonfinite_numeric_array_names": nonfinite,
        "all_numeric_arrays_finite": not nonfinite,
    }


def _verify_complete_output(output: Path, expected_config: dict) -> tuple[dict, dict]:
    checksums = json.loads((output / "checksums.json").read_text(encoding="utf-8"))
    if set(checksums) != REQUIRED_EVIDENCE_FILES:
        raise ValueError("required evidence manifest mismatch")
    actual = {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file()
    }
    if actual != REQUIRED_EVIDENCE_FILES | {"checksums.json"}:
        raise ValueError("required evidence file set mismatch")
    for relative, expected in checksums.items():
        if _sha256(output / relative) != expected:
            raise ValueError(f"existing evidence checksum mismatch: {relative}")
    if json.loads((output / "config_snapshot.json").read_text(encoding="utf-8")) != expected_config:
        raise ValueError("existing evidence config mismatch")
    return (
        json.loads((output / "summary.json").read_text(encoding="utf-8")),
        json.loads((output / "registry_entry.json").read_text(encoding="utf-8")),
    )


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
    if config.get("forecast_contract") != IDENTITY_FORECAST_CONTRACT:
        raise ValueError("current validation requires the exact identity forecast contract")
    if output.exists():
        if registry.exists() or incomplete.exists():
            raise FileExistsError(f"refusing to overwrite completed evidence {output}")
        summary, registry_entry = _verify_complete_output(output, config)
        _atomic_json_write(registry, registry_entry)
        if summary.get("status") != "passed":
            raise RuntimeError(f"forecast validation failed; see {output / 'summary.json'}")
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
    seeds = tuple(int(value) for value in config["trial_seeds"])
    if not seeds or len(set(seeds)) != len(seeds):
        raise ValueError("trial_seeds must be nonempty and unique")
    formal_leads = tuple(int(value) for value in config["formal_lead_days"])
    if formal_leads != (1, 3, 7) or int(config["causal_prefix_days"]) != 3:
        raise ValueError("formal leads and causal prefix must be one, three and seven days")
    forcing = _forcing_realizations(config)
    covariance_standard_deviations = np.asarray(
        config["initial_covariance_standard_deviations"], dtype=np.float64
    )
    if covariance_standard_deviations.shape != (15,) or np.any(covariance_standard_deviations <= 0.0):
        raise ValueError("initial covariance standard deviations must contain fifteen positive values")
    initial_covariance = np.diag(np.square(covariance_standard_deviations))
    initial_probabilities = np.asarray(config["initial_probabilities"], dtype=np.float64)

    registered_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "experiment_id": config["experiment_id"],
        "status": "preregistered",
        "registered_at": registered_at,
        "config_sha256": _sha256(config_file),
        "trial_seeds": list(seeds),
        "candidate_ids": [candidate.candidate_id for candidate in definitions],
        "state_dimension": 15,
        "forecast_days": int(config["forcing"]["forecast_days"]),
        "formal_lead_days": list(formal_leads),
        "forecast_contract": IDENTITY_FORECAST_CONTRACT.copy(),
        "source_bank_assimilation_transition": "non_identity_validation_fixture",
        "future_discharge_argument": False,
        "gates": config["gates"],
    }
    _atomic_json_write(preregistry, preregistration)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    resource = _resource_preflight(config)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))
    result = run_observation_free_forecast_validation(
        trial_seeds=seeds,
        forcing_realizations=forcing,
        warmup_days=int(config["forcing"]["warmup_days"]),
        forecast_days=int(config["forcing"]["forecast_days"]),
        candidates=definitions,
        initial_covariance=initial_covariance,
        initial_probabilities=initial_probabilities,
        observation_standard_deviation=float(config["observation_standard_deviation"]),
    )
    parameter_vectors = np.asarray(
        [[vectors[key][name] for name in PARAMETER_NAMES] for key in parameter_ids],
        dtype=np.float64,
    )
    process_covariances = np.stack([covariances[key] for key in process_ids])
    evidence_arrays = {
        "trial_seeds": result.trial_seeds,
        "forcing_realizations": result.forcing_realizations,
        "parameter_ids": np.asarray(parameter_ids),
        "process_ids": np.asarray(process_ids),
        "candidate_ids": np.asarray(result.candidate_ids),
        "parameter_vectors": parameter_vectors,
        "process_covariances": process_covariances,
        "initial_probabilities": result.initial_probabilities,
        "initial_candidate_states": result.initial_candidate_states,
        "initial_candidate_covariances": result.initial_candidate_covariances,
        "source_candidate_states_after_forecasts": result.source_candidate_states_after_forecasts,
        "source_candidate_covariances_after_forecasts": result.source_candidate_covariances_after_forecasts,
        "source_probabilities_after_forecasts": result.source_probabilities_after_forecasts,
        "production_combined_predictions": result.production_combined_predictions,
        "production_candidate_predictions": result.production_candidate_predictions,
        "production_probabilities": result.production_probabilities,
        "production_candidate_states": result.production_candidate_states,
        "production_candidate_covariance_diagonals": result.production_candidate_covariance_diagonals,
        "production_combined_states": result.production_combined_states,
        "production_combined_covariance_diagonals": result.production_combined_covariance_diagonals,
        "reference_combined_predictions": result.reference_combined_predictions,
        "reference_candidate_predictions": result.reference_candidate_predictions,
        "reference_probabilities": result.reference_probabilities,
        "reference_candidate_states": result.reference_candidate_states,
        "reference_candidate_covariances": result.reference_candidate_covariances,
        "reference_combined_states": result.reference_combined_states,
        "reference_combined_covariances": result.reference_combined_covariances,
        "production_selected_combined_predictions": result.production_selected_combined_predictions,
        "production_selected_candidate_predictions": result.production_selected_candidate_predictions,
        "production_selected_probabilities": result.production_selected_probabilities,
        "production_selected_candidate_states": result.production_selected_candidate_states,
        "production_selected_candidate_covariance_diagonals": result.production_selected_candidate_covariance_diagonals,
        "production_selected_combined_states": result.production_selected_combined_states,
        "production_selected_combined_covariance_diagonals": result.production_selected_combined_covariance_diagonals,
        "production_three_day_combined_predictions": result.production_three_day_combined_predictions,
        "production_three_day_candidate_predictions": result.production_three_day_candidate_predictions,
        "production_three_day_probabilities": result.production_three_day_probabilities,
        "production_three_day_candidate_states": result.production_three_day_candidate_states,
        "production_three_day_candidate_covariance_diagonals": result.production_three_day_candidate_covariance_diagonals,
        "production_three_day_combined_states": result.production_three_day_combined_states,
        "production_three_day_combined_covariance_diagonals": result.production_three_day_combined_covariance_diagonals,
    }
    finiteness = _numeric_finiteness(evidence_arrays)
    reference_candidate_covariance_diagonals = np.diagonal(
        result.reference_candidate_covariances, axis1=-2, axis2=-1
    )
    reference_combined_covariance_diagonals = np.diagonal(
        result.reference_combined_covariances, axis1=-2, axis2=-1
    )
    production_reference_probability_error = _maximum_error(
        result.production_probabilities, result.reference_probabilities
    )
    forecast_probability_change_error = _maximum_error(
        result.production_probabilities,
        np.broadcast_to(
            result.initial_probabilities,
            result.production_probabilities.shape,
        ),
    )
    state_error = _maximum_error(
        result.production_candidate_states, result.reference_candidate_states
    )
    covariance_diagonal_error = _maximum_error(
        result.production_candidate_covariance_diagonals,
        reference_candidate_covariance_diagonals,
    )
    candidate_prediction_error = _maximum_error(
        result.production_candidate_predictions, result.reference_candidate_predictions
    )
    combined_prediction_error = _maximum_error(
        result.production_combined_predictions, result.reference_combined_predictions
    )
    combined_state_error = _maximum_error(
        result.production_combined_states, result.reference_combined_states
    )
    combined_covariance_diagonal_error = _maximum_error(
        result.production_combined_covariance_diagonals,
        reference_combined_covariance_diagonals,
    )
    selected_indices = np.asarray([0, 2, 6], dtype=np.int64)
    selected_error = _maximum_field_error(
        (
            (result.production_selected_combined_predictions, result.production_combined_predictions[:, selected_indices]),
            (result.production_selected_candidate_predictions, result.production_candidate_predictions[:, selected_indices]),
            (result.production_selected_probabilities, result.production_probabilities[:, selected_indices]),
            (result.production_selected_candidate_states, result.production_candidate_states[:, selected_indices]),
            (result.production_selected_candidate_covariance_diagonals, result.production_candidate_covariance_diagonals[:, selected_indices]),
            (result.production_selected_combined_states, result.production_combined_states[:, selected_indices]),
            (result.production_selected_combined_covariance_diagonals, result.production_combined_covariance_diagonals[:, selected_indices]),
        )
    )
    prefix_error = _maximum_field_error(
        (
            (result.production_three_day_combined_predictions, result.production_combined_predictions[:, :3]),
            (result.production_three_day_candidate_predictions, result.production_candidate_predictions[:, :3]),
            (result.production_three_day_probabilities, result.production_probabilities[:, :3]),
            (result.production_three_day_candidate_states, result.production_candidate_states[:, :3]),
            (result.production_three_day_candidate_covariance_diagonals, result.production_candidate_covariance_diagonals[:, :3]),
            (result.production_three_day_combined_states, result.production_combined_states[:, :3]),
            (result.production_three_day_combined_covariance_diagonals, result.production_combined_covariance_diagonals[:, :3]),
        )
    )
    source_mutation = _maximum_field_error(
        (
            (
                result.source_candidate_states_after_forecasts,
                result.initial_candidate_states,
            ),
            (
                result.source_candidate_covariances_after_forecasts,
                result.initial_candidate_covariances,
            ),
            (
                result.source_probabilities_after_forecasts,
                np.repeat(result.initial_probabilities[None, :], len(seeds), axis=0),
            ),
        )
    )
    probability_sum_error = float(
        np.max(np.abs(result.production_probabilities.sum(axis=-1) - 1.0))
    )
    minimum_covariance_eigenvalue = float(
        np.min(np.linalg.eigvalsh(result.reference_candidate_covariances.reshape(-1, 15, 15)))
    )
    covariance_symmetry_error = _maximum_error(
        result.reference_candidate_covariances,
        np.swapaxes(result.reference_candidate_covariances, -1, -2),
    )
    future_discharge_argument_absent = "observations" not in inspect.signature(
        forecast_from_posterior
    ).parameters
    gate_values = {
        "forecast_probability_change_maximum_absolute_error": forecast_probability_change_error,
        "production_reference_probability_maximum_absolute_error": production_reference_probability_error,
        "candidate_state_maximum_absolute_error": state_error,
        "candidate_covariance_diagonal_maximum_absolute_error": covariance_diagonal_error,
        "candidate_prediction_maximum_absolute_error": candidate_prediction_error,
        "combined_prediction_maximum_absolute_error": combined_prediction_error,
        "combined_state_maximum_absolute_error": combined_state_error,
        "combined_covariance_diagonal_maximum_absolute_error": combined_covariance_diagonal_error,
        "selected_lead_maximum_absolute_error": selected_error,
        "causal_prefix_maximum_absolute_error": prefix_error,
        "source_bank_mutation_maximum_absolute_error": source_mutation,
        "probability_sum_maximum_absolute_error": probability_sum_error,
        "minimum_reference_covariance_eigenvalue": minimum_covariance_eigenvalue,
        "reference_covariance_symmetry_maximum_absolute_error": covariance_symmetry_error,
        "future_discharge_argument_absent": future_discharge_argument_absent,
        "all_saved_numeric_arrays_finite": finiteness["all_numeric_arrays_finite"],
    }
    gates = config["gates"]
    gate_pass = bool(
        forecast_probability_change_error <= float(gates["forecast_probability_change_maximum_absolute_error"])
        and production_reference_probability_error <= float(gates["production_reference_probability_maximum_absolute_error"])
        and state_error <= float(gates["candidate_state_maximum_absolute_error"])
        and covariance_diagonal_error <= float(gates["candidate_covariance_diagonal_maximum_absolute_error"])
        and candidate_prediction_error <= float(gates["candidate_prediction_maximum_absolute_error"])
        and combined_prediction_error <= float(gates["combined_prediction_maximum_absolute_error"])
        and combined_state_error <= float(gates["combined_state_maximum_absolute_error"])
        and combined_covariance_diagonal_error <= float(gates["combined_covariance_diagonal_maximum_absolute_error"])
        and selected_error <= float(gates["selected_lead_maximum_absolute_error"])
        and prefix_error <= float(gates["causal_prefix_maximum_absolute_error"])
        and source_mutation <= float(gates["source_bank_mutation_maximum_absolute_error"])
        and probability_sum_error <= float(gates["probability_sum_maximum_absolute_error"])
        and minimum_covariance_eigenvalue >= float(gates["minimum_reference_covariance_eigenvalue"])
        and covariance_symmetry_error <= float(gates["reference_covariance_symmetry_maximum_absolute_error"])
        and future_discharge_argument_absent
        and finiteness["all_numeric_arrays_finite"]
    )
    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    protected_unchanged = protected_before == protected_after
    passed = bool(gate_pass and protected_unchanged)
    finished_at = dt.datetime.now(dt.timezone.utc).isoformat()
    certificate = {
        "experiment_id": config["experiment_id"],
        "check_type": "causal seven-day nine-candidate observation-free forecast propagation",
        "tested_trial_count": len(seeds),
        "tested_candidate_count": 9,
        "tested_state_dimension": 15,
        "tested_lead_days": list(formal_leads),
        "tested_daily_prefix": list(range(1, int(config["forcing"]["forecast_days"]) + 1)),
        "forecast_contract": IDENTITY_FORECAST_CONTRACT.copy(),
        "candidate_propagation": "independent_without_cross_candidate_mixing",
        "gate_values": gate_values,
        "gates": gates,
        "saved_numeric_array_names": finiteness["numeric_array_names"],
        "nonfinite_saved_numeric_array_names": finiteness["nonfinite_numeric_array_names"],
        "passed": gate_pass,
        "scope_limit": config["scope_limit"],
    }
    summary = {
        "experiment_id": config["experiment_id"],
        "status": "passed" if passed else "failed",
        "started_at": started_at,
        "finished_at": finished_at,
        "trial_count": len(seeds),
        "warmup_days": int(config["forcing"]["warmup_days"]),
        "forecast_days": int(config["forcing"]["forecast_days"]),
        "candidate_count": 9,
        "parameter_count": 3,
        "process_noise_count": 3,
        "state_dimension": 15,
        "candidate_ids": list(result.candidate_ids),
        "formal_lead_days": list(formal_leads),
        "saved_numeric_array_count": len(finiteness["numeric_array_names"]),
        "forecast_contract": IDENTITY_FORECAST_CONTRACT.copy(),
        "nonfinite_saved_numeric_array_names": finiteness["nonfinite_numeric_array_names"],
        "gate_values": gate_values,
        "gates": gates,
        "gate_pass": gate_pass,
        "parameter_source_sha256": config["parameter_source"]["sha256"],
        "process_noise_source_sha256": config["process_noise_source"]["sha256"],
        "selected_parameter_snapshot_sha256": parameter_snapshot_hash,
        "selected_process_noise_snapshot_sha256": process_snapshot_hash,
        "protected_artifacts_unchanged": protected_unchanged,
        "scope_limit": config["scope_limit"],
    }
    registry_entry = {
        "experiment_id": config["experiment_id"],
        "type": "closed_truth_observation_free_forecast_propagation",
        "hypothesis": "production one-through-seven-day propagation matches the independent observation-free recursion",
        "base_config": str(config_file),
        "changed_factor": "forecast lead from one through seven days",
        "fixed_factors": "three complete parameter vectors, three process covariances, fifteen states and fixed posterior weights",
        "seeds": list(seeds),
        "status": summary["status"],
        "run_dir": str(output),
        "metrics_path": str(output / "summary.json"),
        "paper_name": "synthetic observation-free forecast component",
        "notes": config["scope_limit"],
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
        _json_write(incomplete / "forecast_propagation_certificate.json", certificate)
        _json_write(incomplete / "registry_entry.json", registry_entry)
        _json_write(incomplete / "resource_preflight.json", resource)
        _json_write(incomplete / "environment.json", environment)
        _json_write(incomplete / "installed_packages.json", installed_packages)
        _json_write(incomplete / "conda_packages.json", conda_packages)
        _json_write(incomplete / "protected_artifact_integrity.json", integrity)
        (incomplete / "git_status.txt").write_text(git_status + "\n", encoding="utf-8")
        (incomplete / "pip_freeze.txt").write_text(pip_freeze, encoding="utf-8")
        np.savez_compressed(incomplete / "evidence.npz", **evidence_arrays)
        with np.load(incomplete / "evidence.npz") as saved:
            actual_numeric_bytes = int(
                sum(
                    saved[name].nbytes
                    for name in saved.files
                    if np.issubdtype(saved[name].dtype, np.number)
                )
            )
        if actual_numeric_bytes != resource["expected_saved_numeric_array_bytes"]:
            raise ValueError("saved numeric bytes differ from the resource preflight estimate")
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        sources = {
            "__init__.py": root / "src" / "hbv_multilead_joint_uncertainty" / "__init__.py",
            "forecast.py": root / "src" / "hbv_multilead_joint_uncertainty" / "forecast.py",
            "methods.py": root / "src" / "hbv_multilead_joint_uncertainty" / "methods.py",
            "observation_free_forecast_validation.py": root / "src" / "hbv_multilead_joint_uncertainty" / "observation_free_forecast_validation.py",
            "synthetic_truth.py": root / "src" / "hbv_multilead_joint_uncertainty" / "synthetic_truth.py",
            "run_observation_free_forecast_validation.py": Path(__file__).resolve(),
            "run_model_probability_validation.py": root / "src" / "hbv_multilead_joint_uncertainty" / "scripts" / "run_model_probability_validation.py",
            "run_synthetic_truth_validation.py": root / "src" / "hbv_multilead_joint_uncertainty" / "scripts" / "run_synthetic_truth_validation.py",
            "hbv_adapter.py": root / "src" / "hbv_joint_uncertainty" / "hbv_adapter.py",
            "preflight.py": root / "src" / "hbv_joint_uncertainty" / "preflight.py",
            "imm.py": root / "src" / "hbv_joint_uncertainty" / "imm.py",
            "sigma_filter.py": root / "src" / "hbv_joint_uncertainty" / "sigma_filter.py",
            "hbv_lite_numpy.py": root / "src" / "scl_hydro" / "hbv_lite_numpy.py",
            "test_hbv_multilead_forecast.py": root / "test" / "test_hbv_multilead_forecast.py",
            "test_hbv_observation_free_forecast_validation.py": root / "test" / "test_hbv_observation_free_forecast_validation.py",
        }
        for name, source in sources.items():
            shutil.copy2(source, snapshot / name)
        evidence_paths = sorted(path for path in incomplete.rglob("*") if path.is_file())
        checksums = {
            path.relative_to(incomplete).as_posix(): _sha256(path)
            for path in evidence_paths
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
        raise RuntimeError(f"forecast validation failed; see {output / 'summary.json'}")
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
