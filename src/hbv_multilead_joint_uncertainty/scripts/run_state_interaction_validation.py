"""Run and package the closed nine-candidate state-interaction validation."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import sys
from pathlib import Path

import numpy as np
import psutil


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, STATE_NAMES  # noqa: E402
from hbv_joint_uncertainty.preflight import build_transition_matrix  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    MethodCandidate,
    build_factorial_transition_matrix,
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
from hbv_multilead_joint_uncertainty.state_interaction_validation import (  # noqa: E402
    run_state_interaction_validation,
)


REQUIRED_EVIDENCE_FILES = frozenset(
    {
        "conda_packages.json",
        "config_snapshot.json",
        "environment.json",
        "evidence.npz",
        "git_status.txt",
        "installed_packages.json",
        "moment_conservation_certificate.json",
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
        "source_snapshot/imm.py",
        "source_snapshot/methods.py",
        "source_snapshot/model_probability_validation.py",
        "source_snapshot/preflight.py",
        "source_snapshot/run_model_probability_validation.py",
        "source_snapshot/run_state_interaction_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/state_interaction_validation.py",
        "source_snapshot/test_hbv_state_interaction_validation.py",
        "summary.json",
    }
)


def _candidate_metadata(parameter_ids: tuple[str, ...], process_ids: tuple[str, ...]):
    candidate_ids = tuple(
        f"{parameter_id}__{process_id}"
        for parameter_id in parameter_ids
        for process_id in process_ids
    )
    candidate_factors = tuple(
        (parameter_id, process_id)
        for parameter_id in parameter_ids
        for process_id in process_ids
    )
    parameter_indices = np.repeat(np.arange(3, dtype=np.int32), 3)
    process_indices = np.tile(np.arange(3, dtype=np.int32), 3)
    return candidate_ids, candidate_factors, parameter_indices, process_indices


def _expected_evidence_array_bytes(
    config: dict, parameter_ids: tuple[str, ...], process_ids: tuple[str, ...]
) -> int:
    trials = len(config["trial_seeds"])
    steps = int(config["steps"])
    candidates = 9
    states = 15
    modes = 3
    candidate_ids, candidate_factors, parameter_indices, process_indices = (
        _candidate_metadata(parameter_ids, process_ids)
    )
    arrays = [
        np.asarray(config["trial_seeds"], dtype=np.int64),
        np.asarray(parameter_ids),
        np.asarray(process_ids),
        np.asarray(candidate_ids),
        np.asarray(candidate_factors),
        parameter_indices,
        process_indices,
        np.empty((3, len(PARAMETER_NAMES)), dtype=np.float64),
        np.empty((3, states, states), dtype=np.float64),
        np.empty((candidates, candidates), dtype=np.float64),
        np.empty(states, dtype=np.float64),
        np.empty((trials, steps + 1, candidates), dtype=np.float64),
        np.empty((trials, steps + 1, candidates, states), dtype=np.float64),
        np.empty((trials, steps + 1, candidates, states, states), dtype=np.float64),
        np.empty((trials, steps, candidates, candidates), dtype=np.float64),
        np.empty((trials, steps + 1, candidates), dtype=np.float64),
        np.empty((trials, steps + 1, candidates, states), dtype=np.float64),
        np.empty((trials, steps + 1, candidates, states, states), dtype=np.float64),
        np.empty((trials, steps, candidates, candidates), dtype=np.float64),
        np.empty((trials, steps + 1, states), dtype=np.float64),
        np.empty((trials, steps + 1, states, states), dtype=np.float64),
        np.empty((trials, steps + 1, states), dtype=np.float64),
        np.empty((trials, steps + 1, states, states), dtype=np.float64),
        np.asarray(("full", "parameter_grouped", "none")),
        np.empty((modes, steps + 1, candidates), dtype=np.float64),
        np.empty((modes, steps + 1, candidates, states), dtype=np.float64),
        np.empty((modes, steps + 1, candidates, states, states), dtype=np.float64),
        np.empty((modes, steps + 1, states), dtype=np.float64),
        np.empty((modes, steps + 1, states, states), dtype=np.float64),
    ]
    return int(sum(array.nbytes for array in arrays))


def _resource_preflight(
    config: dict, parameter_ids: tuple[str, ...], process_ids: tuple[str, ...]
) -> dict:
    expected_array_bytes = _expected_evidence_array_bytes(
        config, parameter_ids, process_ids
    )
    packaging_and_runtime_allowance = 64 * 1024 * 1024
    estimated_peak = int(4 * expected_array_bytes + packaging_and_runtime_allowance)
    available = int(psutil.virtual_memory().available)
    task_specific_reserve = int(2 * estimated_peak + 64 * 1024 * 1024)
    required_available = estimated_peak + task_specific_reserve
    safe = available >= required_available
    result = {
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "trial_count": len(config["trial_seeds"]),
        "interaction_steps": int(config["steps"]),
        "candidate_count": 9,
        "state_dimension": 15,
        "execution_parallelism": 1,
        "expected_evidence_array_bytes": expected_array_bytes,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "available_physical_memory_bytes": available,
        "task_specific_reserve_bytes": task_specific_reserve,
        "task_specific_required_available_bytes": required_available,
        "available_after_estimated_peak_bytes": available - estimated_peak,
        "safe_to_run": safe,
        "estimation_basis": (
            "four copies of every array saved in evidence.npz, including full production and "
            "independent-reference covariance trajectories and the three-mode counterexample, "
            "plus a 64 MiB packaging allowance and a task-specific two-estimate and 64 MiB reserve"
        ),
        "universal_memory_threshold_used": False,
    }
    if not safe:
        raise MemoryError("state-interaction validation lacks its task-specific memory margin")
    return result


def _maximum_absolute_error(left: np.ndarray, right: np.ndarray) -> float:
    return float(np.max(np.abs(np.asarray(left) - np.asarray(right))))


def _saved_numeric_finiteness(arrays: dict[str, np.ndarray]) -> dict:
    numeric_names = [
        name
        for name, values in arrays.items()
        if np.issubdtype(np.asarray(values).dtype, np.number)
    ]
    nonfinite_names = [
        name for name in numeric_names if not np.all(np.isfinite(arrays[name]))
    ]
    return {
        "numeric_array_names": numeric_names,
        "nonfinite_numeric_array_names": nonfinite_names,
        "all_numeric_arrays_finite": not nonfinite_names,
    }


def _prefix_error(full, prefix, prefix_steps: int) -> float:
    point_fields = (
        "production_probabilities",
        "production_states",
        "production_covariances",
        "reference_probabilities",
        "reference_states",
        "reference_covariances",
        "production_combined_means",
        "production_combined_covariances",
        "reference_combined_means",
        "reference_combined_covariances",
    )
    step_fields = (
        "production_conditional_weights",
        "reference_conditional_weights",
    )
    counterexample_fields = (
        "counterexample_probabilities",
        "counterexample_states",
        "counterexample_covariances",
        "counterexample_combined_means",
        "counterexample_combined_covariances",
    )
    errors = []
    for name in point_fields:
        errors.append(
            _maximum_absolute_error(
                getattr(full, name)[:, : prefix_steps + 1], getattr(prefix, name)
            )
        )
    for name in step_fields:
        errors.append(
            _maximum_absolute_error(
                getattr(full, name)[:, :prefix_steps], getattr(prefix, name)
            )
        )
    for name in counterexample_fields:
        errors.append(
            _maximum_absolute_error(
                getattr(full, name)[:, : prefix_steps + 1], getattr(prefix, name)
            )
        )
    return float(max(errors))


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
    if output.exists():
        if registry.exists() or incomplete.exists():
            raise FileExistsError(f"refusing to overwrite completed evidence {output}")
        summary, registry_entry = _verify_complete_output(output, config)
        _atomic_json_write(registry, registry_entry)
        if summary.get("status") != "passed":
            raise RuntimeError(f"state-interaction validation failed; see {output / 'summary.json'}")
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
    candidate_ids, candidate_factors, parameter_indices, process_indices = (
        _candidate_metadata(parameter_ids, process_ids)
    )
    transition = build_factorial_transition_matrix(
        definitions, float(config["factor_stay_probability"])
    )
    parameter_groups = tuple(parameter_id for parameter_id, _ in candidate_factors)
    trial_seeds = tuple(int(value) for value in config["trial_seeds"])
    if not trial_seeds or len(set(trial_seeds)) != len(trial_seeds):
        raise ValueError("trial_seeds must be nonempty and unique")
    steps = int(config["steps"])
    prefix_steps = int(config["causal_prefix_steps"])
    if prefix_steps <= 0 or prefix_steps >= steps:
        raise ValueError("causal_prefix_steps must be positive and shorter than steps")

    registered_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "experiment_id": config["experiment_id"],
        "status": "preregistered",
        "registered_at": registered_at,
        "config_sha256": _sha256(config_file),
        "trial_seeds": list(trial_seeds),
        "candidate_ids": list(candidate_ids),
        "candidate_factors": [list(value) for value in candidate_factors],
        "state_dimension": 15,
        "interaction_steps": steps,
        "factor_stay_probability": float(config["factor_stay_probability"]),
        "tested_formal_mode": "full",
        "diagnostic_modes": ["parameter_grouped", "none"],
        "hydrologic_state_propagation": False,
        "filter_update": False,
        "gates": config["gates"],
    }
    _atomic_json_write(preregistry, preregistration)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    resource_preflight = _resource_preflight(config, parameter_ids, process_ids)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))
    common_arguments = {
        "trial_seeds": trial_seeds,
        "transition_matrix": transition,
        "parameter_groups": parameter_groups,
        "state_scales": config["state_scales"],
    }
    result = run_state_interaction_validation(steps=steps, **common_arguments)
    prefix = run_state_interaction_validation(steps=prefix_steps, **common_arguments)
    parameter_vector_array = np.asarray(
        [[vectors[key][name] for name in PARAMETER_NAMES] for key in parameter_ids]
    )
    process_covariance_array = np.stack([covariances[key] for key in process_ids])
    evidence_arrays = {
        "trial_seeds": result.trial_seeds,
        "parameter_ids": np.asarray(parameter_ids),
        "process_ids": np.asarray(process_ids),
        "candidate_ids": np.asarray(candidate_ids),
        "candidate_factors": np.asarray(candidate_factors),
        "candidate_parameter_indices": parameter_indices,
        "candidate_process_indices": process_indices,
        "parameter_vectors": parameter_vector_array,
        "process_covariances": process_covariance_array,
        "transition_matrix": result.transition_matrix,
        "state_scales": result.state_scales,
        "production_probabilities": result.production_probabilities,
        "production_states": result.production_states,
        "production_covariances": result.production_covariances,
        "production_conditional_weights": result.production_conditional_weights,
        "reference_probabilities": result.reference_probabilities,
        "reference_states": result.reference_states,
        "reference_covariances": result.reference_covariances,
        "reference_conditional_weights": result.reference_conditional_weights,
        "production_combined_means": result.production_combined_means,
        "production_combined_covariances": result.production_combined_covariances,
        "reference_combined_means": result.reference_combined_means,
        "reference_combined_covariances": result.reference_combined_covariances,
        "counterexample_modes": np.asarray(result.counterexample_modes),
        "counterexample_probabilities": result.counterexample_probabilities,
        "counterexample_states": result.counterexample_states,
        "counterexample_covariances": result.counterexample_covariances,
        "counterexample_combined_means": result.counterexample_combined_means,
        "counterexample_combined_covariances": result.counterexample_combined_covariances,
    }
    finiteness = _saved_numeric_finiteness(evidence_arrays)

    probability_error = _maximum_absolute_error(
        result.production_probabilities, result.reference_probabilities
    )
    weight_error = _maximum_absolute_error(
        result.production_conditional_weights,
        result.reference_conditional_weights,
    )
    state_error = _maximum_absolute_error(
        result.production_states, result.reference_states
    )
    covariance_error = _maximum_absolute_error(
        result.production_covariances, result.reference_covariances
    )
    combined_mean_reference_error = _maximum_absolute_error(
        result.production_combined_means, result.reference_combined_means
    )
    combined_covariance_reference_error = _maximum_absolute_error(
        result.production_combined_covariances,
        result.reference_combined_covariances,
    )
    initial_means = result.production_combined_means[:, :1]
    initial_combined_covariances = result.production_combined_covariances[:, :1]
    mean_conservation_error = _maximum_absolute_error(
        result.production_combined_means,
        np.repeat(initial_means, steps + 1, axis=1),
    )
    covariance_conservation_error = _maximum_absolute_error(
        result.production_combined_covariances,
        np.repeat(initial_combined_covariances, steps + 1, axis=1),
    )
    minimum_eigenvalue = float(
        np.min(
            np.linalg.eigvalsh(
                result.production_covariances.reshape(-1, 15, 15)
            )
        )
    )
    symmetry_error = _maximum_absolute_error(
        result.production_covariances,
        np.swapaxes(result.production_covariances, -1, -2),
    )
    conditional_weight_sum_error = float(
        np.max(np.abs(result.production_conditional_weights.sum(axis=-1) - 1.0))
    )
    causal_prefix_error = _prefix_error(result, prefix, prefix_steps)
    counterexample_initial_mean = result.counterexample_combined_means[:, 0]
    counterexample_final_mean = result.counterexample_combined_means[:, -1]
    counterexample_full_mean_drift = _maximum_absolute_error(
        result.counterexample_combined_means[0],
        np.repeat(result.counterexample_combined_means[0, :1], steps + 1, axis=0),
    )
    counterexample_full_covariance_drift = _maximum_absolute_error(
        result.counterexample_combined_covariances[0],
        np.repeat(
            result.counterexample_combined_covariances[0, :1], steps + 1, axis=0
        ),
    )
    counterexample_grouped_mean_drift = abs(
        float(counterexample_final_mean[1, 0] - counterexample_initial_mean[1, 0])
    )
    counterexample_none_mean_drift = abs(
        float(counterexample_final_mean[2, 0] - counterexample_initial_mean[2, 0])
    )
    literal_factor_transition = np.full(
        (3, 3),
        float(
            config.get(
                "expected_factor_switch_probability",
                (1.0 - float(config["factor_stay_probability"])) / 2.0,
            )
        ),
        dtype=np.float64,
    )
    np.fill_diagonal(
        literal_factor_transition, float(config["factor_stay_probability"])
    )
    transition_contract_error = _maximum_absolute_error(
        transition, np.kron(literal_factor_transition, literal_factor_transition)
    )
    finite = bool(finiteness["all_numeric_arrays_finite"])
    gate_values = {
        "production_reference_probability_maximum_absolute_error": probability_error,
        "production_reference_weight_maximum_absolute_error": weight_error,
        "production_reference_state_maximum_absolute_error": state_error,
        "production_reference_covariance_maximum_absolute_error": covariance_error,
        "production_reference_combined_mean_maximum_absolute_error": combined_mean_reference_error,
        "production_reference_combined_covariance_maximum_absolute_error": combined_covariance_reference_error,
        "full_combined_mean_conservation_maximum_absolute_error": mean_conservation_error,
        "full_combined_covariance_conservation_maximum_absolute_error": covariance_conservation_error,
        "minimum_candidate_covariance_eigenvalue": minimum_eigenvalue,
        "candidate_covariance_symmetry_maximum_absolute_error": symmetry_error,
        "conditional_weight_sum_maximum_absolute_error": conditional_weight_sum_error,
        "causal_prefix_maximum_absolute_error": causal_prefix_error,
        "factorial_transition_contract_maximum_absolute_error": transition_contract_error,
        "counterexample_full_mean_drift_maximum_absolute_error": counterexample_full_mean_drift,
        "counterexample_full_covariance_drift_maximum_absolute_error": counterexample_full_covariance_drift,
        "counterexample_grouped_mean_drift_absolute_error": counterexample_grouped_mean_drift,
        "counterexample_none_mean_drift_absolute_error": counterexample_none_mean_drift,
        "all_saved_numeric_arrays_finite": finite,
    }
    gates = config["gates"]
    gate_pass = bool(
        probability_error
        <= float(gates["production_reference_probability_maximum_absolute_error"])
        and weight_error
        <= float(gates["production_reference_weight_maximum_absolute_error"])
        and state_error
        <= float(gates["production_reference_state_maximum_absolute_error"])
        and covariance_error
        <= float(gates["production_reference_covariance_maximum_absolute_error"])
        and combined_mean_reference_error
        <= float(
            gates.get(
                "production_reference_combined_mean_maximum_absolute_error", 1e-12
            )
        )
        and combined_covariance_reference_error
        <= float(
            gates.get(
                "production_reference_combined_covariance_maximum_absolute_error", 1e-9
            )
        )
        and mean_conservation_error
        <= float(gates["full_combined_mean_conservation_maximum_absolute_error"])
        and covariance_conservation_error
        <= float(gates["full_combined_covariance_conservation_maximum_absolute_error"])
        and minimum_eigenvalue
        >= float(gates["minimum_candidate_covariance_eigenvalue"])
        and symmetry_error
        <= float(gates.get("candidate_covariance_symmetry_maximum_absolute_error", 1e-12))
        and conditional_weight_sum_error
        <= float(gates["conditional_weight_sum_maximum_absolute_error"])
        and causal_prefix_error <= float(gates["causal_prefix_maximum_absolute_error"])
        and transition_contract_error
        <= float(gates.get("factorial_transition_contract_maximum_absolute_error", 1e-14))
        and counterexample_full_mean_drift
        <= float(gates["counterexample_full_mean_drift_maximum_absolute_error"])
        and counterexample_full_covariance_drift
        <= float(gates["counterexample_full_covariance_drift_maximum_absolute_error"])
        and counterexample_grouped_mean_drift
        >= float(gates["counterexample_grouped_mean_drift_minimum_absolute_error"])
        and counterexample_none_mean_drift
        >= float(gates["counterexample_none_mean_drift_minimum_absolute_error"])
        and finite
    )
    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    protected_unchanged = protected_before == protected_after
    passed = bool(gate_pass and protected_unchanged)
    finished_at = dt.datetime.now(dt.timezone.utc).isoformat()
    certificate = {
        "experiment_id": config["experiment_id"],
        "check_type": "frozen full-bank conditional mixture-moment conservation certificate",
        "tested_candidate_count": 9,
        "tested_state_dimension": 15,
        "tested_interaction_steps": steps,
        "production_mode": "full",
        "diagnostic_modes": ["parameter_grouped", "none"],
        "gate_values": gate_values,
        "gates": gates,
        "saved_numeric_array_names": finiteness["numeric_array_names"],
        "nonfinite_saved_numeric_array_names": finiteness[
            "nonfinite_numeric_array_names"
        ],
        "passed": gate_pass,
        "scope_limit": (
            "This certificate tests state and covariance mixture algebra under identity dynamics. "
            "It does not test hydrologic propagation, observation likelihoods, filtering or forecasts."
        ),
    }
    summary = {
        "experiment_id": config["experiment_id"],
        "status": "passed" if passed else "failed",
        "started_at": started_at,
        "finished_at": finished_at,
        "trial_count": len(trial_seeds),
        "interaction_steps": steps,
        "candidate_count": 9,
        "parameter_count": 3,
        "process_noise_count": 3,
        "state_dimension": 15,
        "candidate_ids": list(candidate_ids),
        "tested_formal_mode": "full",
        "diagnostic_modes": ["parameter_grouped", "none"],
        "counterexample_initial_first_state_mean": float(counterexample_initial_mean[0, 0]),
        "counterexample_full_final_first_state_mean": float(counterexample_final_mean[0, 0]),
        "counterexample_grouped_final_first_state_mean": float(counterexample_final_mean[1, 0]),
        "counterexample_none_final_first_state_mean": float(counterexample_final_mean[2, 0]),
        "saved_numeric_array_count": len(finiteness["numeric_array_names"]),
        "nonfinite_saved_numeric_array_names": finiteness[
            "nonfinite_numeric_array_names"
        ],
        "gate_values": gate_values,
        "gates": gates,
        "gate_pass": gate_pass,
        "parameter_source_sha256": config["parameter_source"]["sha256"],
        "process_noise_source_sha256": config["process_noise_source"]["sha256"],
        "selected_parameter_snapshot_sha256": parameter_snapshot_hash,
        "selected_process_noise_snapshot_sha256": process_snapshot_hash,
        "protected_artifacts_unchanged": protected_unchanged,
        "scope_limit": certificate["scope_limit"],
    }
    registry_entry = {
        "experiment_id": config["experiment_id"],
        "type": "closed_truth_nine_candidate_state_interaction",
        "hypothesis": "full interaction preserves first and second mixture moments under identity dynamics",
        "base_config": str(config_file),
        "changed_factor": "full interaction versus parameter-grouped and no-interaction diagnostics",
        "fixed_factors": "three parameter labels by three process-noise labels, fifteen state coordinates, identity dynamics",
        "seeds": list(trial_seeds),
        "status": summary["status"],
        "run_dir": str(output),
        "metrics_path": str(output / "summary.json"),
        "paper_name": "synthetic state-interaction component",
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
        _json_write(incomplete / "moment_conservation_certificate.json", certificate)
        _json_write(incomplete / "registry_entry.json", registry_entry)
        _json_write(incomplete / "resource_preflight.json", resource_preflight)
        _json_write(incomplete / "environment.json", environment)
        _json_write(incomplete / "installed_packages.json", installed_packages)
        _json_write(incomplete / "conda_packages.json", conda_packages)
        _json_write(incomplete / "protected_artifact_integrity.json", integrity)
        (incomplete / "git_status.txt").write_text(git_status + "\n", encoding="utf-8")
        (incomplete / "pip_freeze.txt").write_text(pip_freeze, encoding="utf-8")
        np.savez_compressed(incomplete / "evidence.npz", **evidence_arrays)
        with np.load(incomplete / "evidence.npz") as saved:
            actual_array_bytes = int(sum(saved[name].nbytes for name in saved.files))
        if actual_array_bytes != resource_preflight["expected_evidence_array_bytes"]:
            raise ValueError(
                "saved evidence array bytes differ from the resource preflight estimate"
            )
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        sources = {
            "__init__.py": root / "src" / "hbv_multilead_joint_uncertainty" / "__init__.py",
            "forecast.py": root / "src" / "hbv_multilead_joint_uncertainty" / "forecast.py",
            "methods.py": root / "src" / "hbv_multilead_joint_uncertainty" / "methods.py",
            "model_probability_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "model_probability_validation.py",
            "state_interaction_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "state_interaction_validation.py",
            "run_state_interaction_validation.py": Path(__file__).resolve(),
            "run_model_probability_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "scripts"
            / "run_model_probability_validation.py",
            "run_synthetic_truth_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "scripts"
            / "run_synthetic_truth_validation.py",
            "hbv_adapter.py": root / "src" / "hbv_joint_uncertainty" / "hbv_adapter.py",
            "preflight.py": root / "src" / "hbv_joint_uncertainty" / "preflight.py",
            "imm.py": root / "src" / "hbv_joint_uncertainty" / "imm.py",
            "test_hbv_state_interaction_validation.py": root
            / "test"
            / "test_hbv_state_interaction_validation.py",
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
        raise RuntimeError(f"state-interaction validation failed; see {output / 'summary.json'}")
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
