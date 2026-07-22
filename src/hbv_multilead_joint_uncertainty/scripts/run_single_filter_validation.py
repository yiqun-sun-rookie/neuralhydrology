"""Run and package the closed-truth single-filter state validation."""

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

from hbv_multilead_joint_uncertainty.single_filter_validation import (  # noqa: E402
    run_independent_single_filter_state_validation,
    run_single_filter_state_validation,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import generate_reference_truth  # noqa: E402
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
        "pip_freeze.txt",
        "preregistration.json",
        "protected_artifact_integrity.json",
        "registry_entry.json",
        "resource_preflight.json",
        "source_snapshot/__init__.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/hbv_lite_numpy.py",
        "source_snapshot/preflight.py",
        "source_snapshot/run_single_filter_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/sigma_filter.py",
        "source_snapshot/single_filter_validation.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_joint_uncertainty_sigma_filter.py",
        "source_snapshot/test_hbv_synthetic_truth.py",
        "summary.json",
    }
)


def _required_evidence_files(expected_config: dict) -> frozenset[str]:
    if "seeds" in expected_config["forcing"]:
        return REQUIRED_EVIDENCE_FILES
    return REQUIRED_EVIDENCE_FILES - {"preregistration.json"}


def _verify_complete_output(output: Path, expected_config: dict) -> tuple[dict, dict]:
    with (output / "checksums.json").open("r", encoding="utf-8") as handle:
        checksums = json.load(handle)
    required_files = _required_evidence_files(expected_config)
    if set(checksums) != required_files:
        raise ValueError("required evidence manifest mismatch")
    actual_files = {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file()
    }
    if actual_files != required_files | {"checksums.json"}:
        raise ValueError("required evidence file set mismatch")
    for relative, expected in checksums.items():
        if _sha256(output / relative) != expected:
            raise ValueError(f"existing evidence checksum mismatch: {relative}")
    with (output / "config_snapshot.json").open("r", encoding="utf-8") as handle:
        if json.load(handle) != expected_config:
            raise ValueError("existing evidence config mismatch")
    with (output / "summary.json").open("r", encoding="utf-8") as handle:
        summary = json.load(handle)
    with (output / "registry_entry.json").open("r", encoding="utf-8") as handle:
        registry_entry = json.load(handle)
    if "seeds" in expected_config["forcing"]:
        with (output / "preregistration.json").open("r", encoding="utf-8") as handle:
            preregistration = json.load(handle)
        if preregistration.get("config_sha256") != _sha256(output / "config_snapshot.json"):
            raise ValueError("preregistration config checksum mismatch")
    return summary, registry_entry


def _bootstrap_interval(values: np.ndarray, replicates: int, seed: int) -> tuple[float, float]:
    if replicates <= 0:
        raise ValueError("bootstrap replicates must be positive")
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(replicates, len(values)))
    statistics = np.median(values[indices], axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def _resource_preflight(config: dict) -> dict:
    trial_count = len(config["forcing"]["seeds"])
    day_count = int(config["forcing"]["days"])
    duration = int(config["duration_days"])
    float_bytes = np.dtype(np.float64).itemsize
    forcing_and_truth_bytes = trial_count * day_count * (3 + 15 + 1) * float_bytes
    saved_trial_arrays_bytes = trial_count * duration * (4 * 15 + 4) * float_bytes
    filter_working_bytes = 8 * (31 * 15 + 15 * 15) * float_bytes
    packaging_and_runtime_allowance = 32 * 1024 * 1024
    estimated_peak = int(
        3 * (forcing_and_truth_bytes + saved_trial_arrays_bytes)
        + filter_working_bytes
        + packaging_and_runtime_allowance
    )
    available = int(psutil.virtual_memory().available)
    task_specific_required_available = 4 * estimated_peak
    safe_to_run = available >= task_specific_required_available
    result = {
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "trial_count": trial_count,
        "forcing_days_per_trial": day_count,
        "assimilation_days_per_trial": duration,
        "execution_parallelism": 1,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "available_physical_memory_bytes": available,
        "task_specific_required_available_bytes": task_specific_required_available,
        "available_after_estimated_peak_bytes": available - estimated_peak,
        "safe_to_run": safe_to_run,
        "estimation_basis": (
            "three copies of persisted forcing, truth, state, and prediction arrays; "
            "one sequential filter working set; and 32 MiB packaging/runtime allowance"
        ),
    }
    if not safe_to_run:
        raise MemoryError(
            "single-filter validation memory estimate does not leave the task-specific margin"
        )
    return result


def run(repo_root: Path, config_path: Path, output_dir: Path, registry_path: Path) -> dict:
    root = repo_root.resolve()
    output = output_dir.resolve()
    registry = registry_path.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    with config_path.resolve().open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    if output.name != str(config["experiment_id"]):
        raise ValueError("output directory name must equal experiment_id")
    if output.exists():
        if registry.exists() or incomplete.exists():
            raise FileExistsError(f"refusing to overwrite completed evidence {output}")
        summary, registry_entry = _verify_complete_output(output, config)
        _atomic_json_write(registry, registry_entry)
        if summary.get("status") != "passed":
            raise RuntimeError(f"single-filter validation failed; see {output / 'summary.json'}")
        return summary
    preregistry = registry.with_name(registry.stem + ".preregistered.json")
    if incomplete.exists() or registry.exists() or preregistry.exists():
        raise FileExistsError("refusing to overwrite incomplete evidence or registry")
    forcing_seeds = tuple(int(seed) for seed in config["forcing"].get("seeds", ()))
    if len(forcing_seeds) < 2 or len(set(forcing_seeds)) != len(forcing_seeds):
        raise ValueError("forcing.seeds must contain at least two unique integer seeds")
    preregistered_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "experiment_id": config["experiment_id"],
        "status": "preregistered",
        "registered_at": preregistered_at,
        "config_sha256": _sha256(config_path.resolve()),
        "forcing_realization_ids": list(forcing_seeds),
        "trial_unit": "independent_forcing_realization",
        "primary_control": "same_filter_without_observation_updates",
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
        trial_forcing.pop("seeds", None)
        trial_forcing["seed"] = seed
        trial_config["forcing"] = trial_forcing
        forcing_trials.append(_forcing(trial_config))
    forcing = np.stack(forcing_trials)
    parameters = {name: float(value) for name, value in config["parameters"].items()}
    truths = [generate_reference_truth(values, parameters) for values in forcing]
    full_truth_states = np.stack([truth.states for truth in truths])
    full_truth_discharge = np.stack([truth.discharge for truth in truths])
    result = run_independent_single_filter_state_validation(
        forcing_realizations=forcing,
        truth_state_realizations=full_truth_states,
        truth_discharge_realizations=full_truth_discharge,
        forcing_realization_ids=forcing_seeds,
        parameters=parameters,
        start_day=config["start_day"],
        duration_days=config["duration_days"],
        perturbation_scales=config["perturbation_scales"],
        perturbation_seed=config["perturbation_seed"],
        observation_standard_deviation=config["observation_standard_deviation"],
    )
    open_state = result.open_loop_state_normalized_root_mean_square_error
    control_state = result.no_observation_filter_state_normalized_root_mean_square_error
    filtered_state = result.filtered_state_normalized_root_mean_square_error
    open_flow = result.open_loop_one_day_root_mean_square_error
    control_flow = result.no_observation_filter_one_day_root_mean_square_error
    filtered_flow = result.filtered_one_day_root_mean_square_error
    if np.any(control_state <= 0.0) or np.any(control_flow <= 0.0):
        raise ValueError("same-filter control trial errors must be positive")
    state_change = 100.0 * (filtered_state / control_state - 1.0)
    flow_change = 100.0 * (filtered_flow / control_flow - 1.0)
    state_change_from_open_loop = 100.0 * (filtered_state / open_state - 1.0)
    flow_change_from_open_loop = 100.0 * (filtered_flow / open_flow - 1.0)
    bootstrap = config["bootstrap"]
    state_interval = _bootstrap_interval(
        state_change, int(bootstrap["replicates"]), int(bootstrap["seed"])
    )
    flow_interval = _bootstrap_interval(
        flow_change, int(bootstrap["replicates"]), int(bootstrap["seed"]) + 1
    )
    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    protected_unchanged = protected_before == protected_after
    gates = config["gates"]
    gate_values = {
        "state_median_change_percent": float(np.median(state_change)),
        "flow_median_change_percent": float(np.median(flow_change)),
        "state_bootstrap_upper_percent": state_interval[1],
        "flow_bootstrap_upper_percent": flow_interval[1],
    }
    gate_pass = bool(
        gate_values["state_median_change_percent"]
        <= float(gates["state_median_change_percent_maximum"])
        and gate_values["flow_median_change_percent"]
        <= float(gates["flow_median_change_percent_maximum"])
        and gate_values["state_bootstrap_upper_percent"]
        <= float(gates["state_bootstrap_upper_percent_maximum"])
        and gate_values["flow_bootstrap_upper_percent"]
        <= float(gates["flow_bootstrap_upper_percent_maximum"])
    )
    passed = bool(gate_pass and protected_unchanged)
    finished_at = dt.datetime.now(dt.timezone.utc).isoformat()
    state_improvement_count = int(np.count_nonzero(state_change < 0.0))
    flow_improvement_count = int(np.count_nonzero(flow_change < 0.0))
    summary = {
        "experiment_id": config["experiment_id"],
        "status": "passed" if passed else "failed",
        "started_at": started_at,
        "finished_at": finished_at,
        "trial_count": int(len(result.start_days)),
        "trial_unit": "independent_forcing_realization",
        "primary_control": "same_filter_without_observation_updates",
        "secondary_control": "deterministic_open_loop",
        "duration_days": int(config["duration_days"]),
        "state_change_percent_by_trial": state_change.tolist(),
        "flow_change_percent_by_trial": flow_change.tolist(),
        "state_change_from_deterministic_open_loop_percent_by_trial": (
            state_change_from_open_loop.tolist()
        ),
        "flow_change_from_deterministic_open_loop_percent_by_trial": (
            flow_change_from_open_loop.tolist()
        ),
        "state_improvement_count": state_improvement_count,
        "flow_improvement_count": flow_improvement_count,
        "state_bootstrap_percentile_interval": list(state_interval),
        "flow_bootstrap_percentile_interval": list(flow_interval),
        "gate_values": gate_values,
        "gates": gates,
        "gate_pass": gate_pass,
        "protected_artifacts_unchanged": protected_unchanged,
        "interpretation": (
            f"Observation updating improved the five-state metric in {state_improvement_count}/"
            f"{len(result.start_days)} independent forcing realizations and the one-day discharge "
            f"metric in {flow_improvement_count}/{len(result.start_days)} realizations."
        ),
    }
    registry_entry = {
        "experiment_id": config["experiment_id"],
        "type": "closed_truth_single_filter_validation",
        "hypothesis": "daily discharge updates reduce five-state and one-day flow error",
        "changed_factor": "observation update versus the same filter prediction without observation update",
        "fixed_factors": "independent forcing realizations, truth, complete parameter vector, initial state and covariance, and zero process covariance",
        "forcing_realization_ids": list(forcing_seeds),
        "seed": int(config["perturbation_seed"]),
        "status": summary["status"],
        "run_dir": str(output),
        "metrics_path": str(output / "summary.json"),
    }
    environment, git_status, installed_packages, conda_packages, pip_freeze = _environment_manifest(
        root, started_at
    )
    integrity = {
        "configured_paths": list(config.get("protected_paths", ())),
        "before": protected_before,
        "after": protected_after,
        "status": "unchanged" if protected_unchanged else "changed",
    }

    incomplete.mkdir(parents=True)
    try:
        shutil.copy2(config_path.resolve(), incomplete / "config_snapshot.json")
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
            full_truth_states=full_truth_states,
            full_truth_discharge=full_truth_discharge,
            forcing_realization_ids=result.forcing_realization_ids,
            start_days=result.start_days,
            perturbation_signs=result.perturbation_signs,
            process_covariance=result.process_covariance,
            truth_states=result.truth_states,
            open_loop_states=result.open_loop_states,
            no_observation_filter_states=result.no_observation_filter_states,
            filtered_states=result.filtered_states,
            truth_one_day_discharge=result.truth_one_day_discharge,
            open_loop_one_day_predictions=result.open_loop_one_day_predictions,
            no_observation_filter_one_day_predictions=(
                result.no_observation_filter_one_day_predictions
            ),
            filtered_one_day_predictions=result.filtered_one_day_predictions,
            open_loop_state_error=open_state,
            no_observation_filter_state_error=control_state,
            filtered_state_error=filtered_state,
            open_loop_flow_error=open_flow,
            no_observation_filter_flow_error=control_flow,
            filtered_flow_error=filtered_flow,
        )
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        sources = {
            "__init__.py": root / "src" / "hbv_multilead_joint_uncertainty" / "__init__.py",
            "single_filter_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "single_filter_validation.py",
            "synthetic_truth.py": root / "src" / "hbv_multilead_joint_uncertainty" / "synthetic_truth.py",
            "run_single_filter_validation.py": Path(__file__).resolve(),
            "run_synthetic_truth_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "scripts"
            / "run_synthetic_truth_validation.py",
            "hbv_adapter.py": root / "src" / "hbv_joint_uncertainty" / "hbv_adapter.py",
            "preflight.py": root / "src" / "hbv_joint_uncertainty" / "preflight.py",
            "sigma_filter.py": root / "src" / "hbv_joint_uncertainty" / "sigma_filter.py",
            "hbv_lite_numpy.py": root / "src" / "scl_hydro" / "hbv_lite_numpy.py",
            "test_hbv_joint_uncertainty_sigma_filter.py": root
            / "test"
            / "test_hbv_joint_uncertainty_sigma_filter.py",
            "test_hbv_synthetic_truth.py": root / "test" / "test_hbv_synthetic_truth.py",
        }
        for name, source in sources.items():
            shutil.copy2(source, snapshot / name)
        paths = sorted(path for path in incomplete.rglob("*") if path.is_file())
        checksums = {path.relative_to(incomplete).as_posix(): _sha256(path) for path in paths}
        if set(checksums) != _required_evidence_files(config):
            raise ValueError("required evidence manifest mismatch while packaging")
        _json_write(incomplete / "checksums.json", checksums)
        incomplete.replace(output)
        _atomic_json_write(registry, registry_entry)
    except Exception:
        if incomplete.exists():
            shutil.rmtree(incomplete)
        raise
    if not passed:
        raise RuntimeError(f"single-filter validation failed; see {output / 'summary.json'}")
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
