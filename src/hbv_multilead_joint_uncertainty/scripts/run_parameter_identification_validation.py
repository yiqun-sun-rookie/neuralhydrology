"""Run and package identification of three complete parameter vectors."""

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

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.parameter_identification_validation import (  # noqa: E402
    run_parameter_identification_validation,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (  # noqa: E402
    _atomic_json_write,
    _environment_manifest,
    _forcing,
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
        "protected_artifact_integrity.json",
        "registry_entry.json",
        "resource_preflight.json",
        "source_snapshot/__init__.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/hbv_lite_numpy.py",
        "source_snapshot/imm.py",
        "source_snapshot/parameter_identification_validation.py",
        "source_snapshot/preflight.py",
        "source_snapshot/run_parameter_identification_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/sigma_filter.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_parameter_identification_validation.py",
        "summary.json",
    }
)


def _bootstrap_interval(values: np.ndarray, replicates: int, seed: int) -> tuple[float, float]:
    if replicates <= 0:
        raise ValueError("bootstrap replicates must be positive")
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(replicates, len(values)))
    statistics = np.median(values[indices], axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def _source_path(root: Path, configured: str) -> Path:
    path = Path(configured)
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def _load_parameter_vectors(root: Path, config: dict) -> tuple[dict, bytes, str]:
    source = config["parameter_source"]
    path = _source_path(root, source["path"])
    actual_hash = _sha256(path)
    if actual_hash != str(source["sha256"]):
        raise ValueError("parameter source checksum mismatch")
    table = pd.read_csv(path, dtype={"basin_id": str, "parameter_id": str})
    required_columns = {"basin_id", "parameter_id", *PARAMETER_NAMES}
    if not required_columns.issubset(table.columns):
        raise ValueError("parameter source is missing required columns")
    source_basin = str(source["source_basin_id"])
    expected_ids = tuple(str(value) for value in source["parameter_ids"])
    if len(expected_ids) != 3 or len(set(expected_ids)) != 3:
        raise ValueError("parameter source must name exactly three unique parameter vectors")
    rows = table.loc[table["basin_id"].astype(str).str.zfill(8) == source_basin.zfill(8)]
    selected_rows = []
    vectors = {}
    for parameter_id in expected_ids:
        matching = rows.loc[rows["parameter_id"] == parameter_id]
        if len(matching) != 1:
            raise ValueError(f"expected one source row for parameter {parameter_id!r}")
        selected_rows.append(matching.iloc[0])
        vectors[parameter_id] = {
            name: float(matching.iloc[0][name]) for name in PARAMETER_NAMES
        }
    selected = pd.DataFrame(selected_rows)[["basin_id", "parameter_id", *PARAMETER_NAMES]]
    csv_bytes = selected.to_csv(index=False, lineterminator="\n").encode("utf-8")
    selected_hash = hashlib.sha256(csv_bytes).hexdigest()
    return vectors, csv_bytes, selected_hash


def _resource_preflight(config: dict) -> dict:
    trials = len(config["forcing"]["seeds"])
    days = int(config["forcing"]["days"])
    duration = int(config["duration_days"])
    candidates = 3
    float_bytes = np.dtype(np.float64).itemsize
    forcing_bytes = trials * days * 3 * float_bytes
    saved_bytes = trials * duration * (
        1 + candidates + candidates + candidates + candidates * 15
    ) * float_bytes
    reference_bytes = candidates * days * (15 + 2) * float_bytes
    working_bytes = candidates * 8 * (31 * 15 + 15 * 15) * float_bytes
    packaging_and_runtime_allowance = 32 * 1024 * 1024
    estimated_peak = int(
        3 * (forcing_bytes + saved_bytes + reference_bytes)
        + working_bytes
        + packaging_and_runtime_allowance
    )
    available = int(psutil.virtual_memory().available)
    required_available = 4 * estimated_peak
    safe = available >= required_available
    result = {
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "trial_count": trials,
        "parameter_count": candidates,
        "forcing_days_per_trial": days,
        "assimilation_days_per_trial": duration,
        "execution_parallelism": 1,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "available_physical_memory_bytes": available,
        "task_specific_required_available_bytes": required_available,
        "available_after_estimated_peak_bytes": available - estimated_peak,
        "safe_to_run": safe,
        "estimation_basis": (
            "three copies of saved arrays, three parameter-specific truth trajectories, "
            "three sequential candidate-filter working sets, and 32 MiB packaging allowance"
        ),
    }
    if not safe:
        raise MemoryError("parameter-identification run lacks its task-specific memory margin")
    return result


def _verify_complete_output(output: Path, expected_config: dict) -> tuple[dict, dict]:
    with (output / "checksums.json").open("r", encoding="utf-8") as handle:
        checksums = json.load(handle)
    if set(checksums) != REQUIRED_EVIDENCE_FILES:
        raise ValueError("required evidence manifest mismatch")
    actual_files = {
        path.relative_to(output).as_posix() for path in output.rglob("*") if path.is_file()
    }
    if actual_files != REQUIRED_EVIDENCE_FILES | {"checksums.json"}:
        raise ValueError("required evidence file set mismatch")
    for relative, expected in checksums.items():
        if _sha256(output / relative) != expected:
            raise ValueError(f"existing evidence checksum mismatch: {relative}")
    with (output / "config_snapshot.json").open("r", encoding="utf-8") as handle:
        if json.load(handle) != expected_config:
            raise ValueError("existing evidence config mismatch")
    preregistration = json.loads((output / "preregistration.json").read_text(encoding="utf-8"))
    if preregistration.get("config_sha256") != _sha256(output / "config_snapshot.json"):
        raise ValueError("preregistration config checksum mismatch")
    summary = json.loads((output / "summary.json").read_text(encoding="utf-8"))
    registry_entry = json.loads((output / "registry_entry.json").read_text(encoding="utf-8"))
    return summary, registry_entry


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
            raise RuntimeError(f"parameter identification failed; see {output / 'summary.json'}")
        return summary
    if incomplete.exists() or registry.exists() or preregistry.exists():
        raise FileExistsError("refusing to overwrite incomplete evidence or registry")

    forcing_seeds = tuple(int(value) for value in config["forcing"]["seeds"])
    true_parameter_ids = tuple(str(value) for value in config["forcing"]["true_parameter_ids"])
    if len(forcing_seeds) == 0 or len(set(forcing_seeds)) != len(forcing_seeds):
        raise ValueError("forcing seeds must be nonempty and unique")
    if len(true_parameter_ids) != len(forcing_seeds):
        raise ValueError("true parameter labels must match forcing seeds")
    parameter_vectors, parameter_csv, parameter_snapshot_hash = _load_parameter_vectors(root, config)

    registered_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "experiment_id": config["experiment_id"],
        "status": "preregistered",
        "registered_at": registered_at,
        "config_sha256": _sha256(config_file),
        "forcing_realization_ids": list(forcing_seeds),
        "true_parameter_ids": list(true_parameter_ids),
        "parameter_ids": list(parameter_vectors),
        "interaction_mode": "none",
        "process_covariance": "zero",
        "bootstrap_replicates": int(config["bootstrap"]["replicates"]),
        "gates": config["gates"],
    }
    _atomic_json_write(preregistry, preregistration)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    resource_preflight = _resource_preflight(config)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))

    forcing_trials = []
    for seed in forcing_seeds:
        trial_config = dict(config)
        trial_forcing = dict(config["forcing"])
        trial_forcing["seed"] = seed
        trial_config["forcing"] = trial_forcing
        forcing_trials.append(_forcing(trial_config))
    forcing = np.stack(forcing_trials)
    result = run_parameter_identification_validation(
        forcing_realizations=forcing,
        forcing_realization_ids=forcing_seeds,
        parameter_vectors=parameter_vectors,
        true_parameter_ids=true_parameter_ids,
        start_day=config["start_day"],
        duration_days=config["duration_days"],
        initial_covariance_fraction=config["initial_covariance_fraction"],
        observation_standard_deviation=config["observation_standard_deviation"],
    )

    parameter_ids = result.parameter_ids
    id_to_index = {parameter_id: index for index, parameter_id in enumerate(parameter_ids)}
    true_indices = np.asarray([id_to_index[value] for value in result.true_parameter_ids])
    terminal_window = int(config["terminal_window_days"])
    if terminal_window <= 0 or terminal_window > int(config["duration_days"]):
        raise ValueError("terminal_window_days must be within the assimilation duration")
    terminal_probabilities = np.mean(
        result.posterior_probabilities[:, -terminal_window:, :], axis=1
    )
    terminal_true_probability = terminal_probabilities[
        np.arange(len(true_indices)), true_indices
    ]
    predicted_indices = np.argmax(terminal_probabilities, axis=1)
    correct = predicted_indices == true_indices
    correct_by_parameter = {
        parameter_id: int(np.count_nonzero(correct[true_indices == index]))
        for index, parameter_id in enumerate(parameter_ids)
    }
    trial_count_by_parameter = {
        parameter_id: int(np.count_nonzero(true_indices == index))
        for index, parameter_id in enumerate(parameter_ids)
    }
    candidate_error = np.sqrt(
        np.mean(
            np.square(
                result.candidate_prior_discharge - result.truth_discharge[:, :, None]
            ),
            axis=1,
        )
    )
    true_candidate_lowest_error_count = int(
        np.count_nonzero(np.argmin(candidate_error, axis=1) == true_indices)
    )
    bootstrap = config["bootstrap"]
    probability_interval = _bootstrap_interval(
        terminal_true_probability,
        int(bootstrap["replicates"]),
        int(bootstrap["seed"]),
    )
    gates = config["gates"]
    gate_values = {
        "correct_classification_count": int(np.count_nonzero(correct)),
        "correct_classification_count_by_parameter": correct_by_parameter,
        "median_terminal_true_probability": float(np.median(terminal_true_probability)),
        "terminal_true_probability_bootstrap_lower": probability_interval[0],
    }
    gate_pass = bool(
        gate_values["correct_classification_count"]
        >= int(gates["correct_classification_count_minimum"])
        and all(
            value >= int(gates["correct_classification_count_per_parameter_minimum"])
            for value in correct_by_parameter.values()
        )
        and gate_values["median_terminal_true_probability"]
        >= float(gates["median_terminal_true_probability_minimum"])
        and gate_values["terminal_true_probability_bootstrap_lower"]
        >= float(gates["terminal_true_probability_bootstrap_lower_minimum"])
    )
    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    protected_unchanged = protected_before == protected_after
    passed = bool(gate_pass and protected_unchanged)
    finished_at = dt.datetime.now(dt.timezone.utc).isoformat()
    summary = {
        "experiment_id": config["experiment_id"],
        "status": "passed" if passed else "failed",
        "started_at": started_at,
        "finished_at": finished_at,
        "trial_count": len(forcing_seeds),
        "parameter_count": 3,
        "parameter_ids": list(parameter_ids),
        "trial_count_by_parameter": trial_count_by_parameter,
        "interaction_mode": "none",
        "parameter_switching": False,
        "process_covariance": "zero",
        "generated_observation_noise": "none",
        "terminal_window_days": terminal_window,
        "terminal_true_probability_by_trial": terminal_true_probability.tolist(),
        "predicted_parameter_ids": [parameter_ids[index] for index in predicted_indices],
        "true_parameter_ids": list(result.true_parameter_ids),
        "candidate_prior_discharge_root_mean_square_error_by_trial": candidate_error.tolist(),
        "true_candidate_lowest_discharge_error_count": true_candidate_lowest_error_count,
        "terminal_true_probability_bootstrap_interval": list(probability_interval),
        "gate_values": gate_values,
        "gates": gates,
        "gate_pass": gate_pass,
        "parameter_source_sha256": config["parameter_source"]["sha256"],
        "selected_parameter_snapshot_sha256": parameter_snapshot_hash,
        "protected_artifacts_unchanged": protected_unchanged,
        "scope_limit": (
            "This component isolates fixed-vector identification with deterministic truth, "
            "zero process covariance, no generated observation noise, no switching, and no interaction."
        ),
    }
    registry_entry = {
        "experiment_id": config["experiment_id"],
        "type": "closed_truth_three_complete_parameter_vector_identification",
        "hypothesis": "fixed-model likelihood identifies the complete vector that generated truth",
        "base_config": str(config_file),
        "changed_factor": "which of the three complete parameter vectors generates truth",
        "fixed_factors": "independent forcing, zero process covariance, no switching, no interaction",
        "seeds": list(forcing_seeds),
        "status": summary["status"],
        "run_dir": str(output),
        "metrics_path": str(output / "summary.json"),
        "paper_name": "synthetic parameter identification component",
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
        _json_write(incomplete / "preregistration.json", preregistration)
        _json_write(incomplete / "summary.json", summary)
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
            forcing=forcing,
            forcing_realization_ids=result.forcing_realization_ids,
            parameter_ids=np.asarray(result.parameter_ids),
            parameter_vectors=np.asarray(
                [[parameter_vectors[key][name] for name in PARAMETER_NAMES] for key in parameter_ids]
            ),
            true_parameter_ids=np.asarray(result.true_parameter_ids),
            true_parameter_indices=true_indices,
            truth_discharge=result.truth_discharge,
            candidate_prior_discharge=result.candidate_prior_discharge,
            candidate_log_likelihoods=result.candidate_log_likelihoods,
            posterior_probabilities=result.posterior_probabilities,
            candidate_posterior_states=result.candidate_posterior_states,
            process_covariance=result.process_covariance,
            terminal_probabilities=terminal_probabilities,
            terminal_true_probability=terminal_true_probability,
            candidate_prior_discharge_root_mean_square_error=candidate_error,
        )
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        sources = {
            "__init__.py": root / "src" / "hbv_multilead_joint_uncertainty" / "__init__.py",
            "parameter_identification_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "parameter_identification_validation.py",
            "synthetic_truth.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "synthetic_truth.py",
            "run_parameter_identification_validation.py": Path(__file__).resolve(),
            "run_synthetic_truth_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "scripts"
            / "run_synthetic_truth_validation.py",
            "hbv_adapter.py": root / "src" / "hbv_joint_uncertainty" / "hbv_adapter.py",
            "preflight.py": root / "src" / "hbv_joint_uncertainty" / "preflight.py",
            "sigma_filter.py": root / "src" / "hbv_joint_uncertainty" / "sigma_filter.py",
            "imm.py": root / "src" / "hbv_joint_uncertainty" / "imm.py",
            "hbv_lite_numpy.py": root / "src" / "scl_hydro" / "hbv_lite_numpy.py",
            "test_hbv_parameter_identification_validation.py": root
            / "test"
            / "test_hbv_parameter_identification_validation.py",
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
        raise RuntimeError(f"parameter identification failed; see {output / 'summary.json'}")
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
