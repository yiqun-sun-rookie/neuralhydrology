"""Run and package identification of three fixed process-noise covariances."""

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
from hbv_joint_uncertainty.preflight import (  # noqa: E402
    ForcingTransition,
    RoutedDischargeObservation,
)
from hbv_multilead_joint_uncertainty.process_noise_identification_validation import (  # noqa: E402
    run_process_noise_identification_validation,
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
        "observation_noise.csv",
        "parameter_vector.csv",
        "pip_freeze.txt",
        "preregistration.json",
        "process_noise_covariances.csv",
        "protected_artifact_integrity.json",
        "registry_entry.json",
        "resource_preflight.json",
        "source_snapshot/__init__.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/hbv_lite_numpy.py",
        "source_snapshot/imm.py",
        "source_snapshot/preflight.py",
        "source_snapshot/process_noise_identification_validation.py",
        "source_snapshot/run_process_noise_identification_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/sigma_filter.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_process_noise_identification_validation.py",
        "summary.json",
    }
)


def _source_path(root: Path, configured: str) -> Path:
    path = Path(configured)
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def _checked_table(root: Path, source: dict, string_columns: dict[str, type]) -> pd.DataFrame:
    path = _source_path(root, str(source["path"]))
    if _sha256(path) != str(source["sha256"]):
        raise ValueError(f"source checksum mismatch: {path}")
    return pd.read_csv(path, dtype=string_columns)


def _select_single_row(table: pd.DataFrame, basin_id: str, label: str) -> pd.Series:
    if "basin_id" not in table.columns:
        raise ValueError(f"{label} source is missing basin_id")
    rows = table.loc[table["basin_id"].astype(str).str.zfill(8) == str(basin_id).zfill(8)]
    if len(rows) != 1:
        raise ValueError(f"expected one {label} row for the configured source basin")
    return rows.iloc[0]


def _load_parameter(root: Path, config: dict) -> tuple[dict[str, float], bytes, str]:
    source = config["parameter_source"]
    table = _checked_table(root, source, {"basin_id": str, "parameter_id": str})
    required = {"basin_id", "parameter_id", *PARAMETER_NAMES}
    if not required.issubset(table.columns):
        raise ValueError("parameter source is missing required columns")
    basin = str(source["source_basin_id"])
    parameter_id = str(source["parameter_id"])
    rows = table.loc[
        (table["basin_id"].astype(str).str.zfill(8) == basin.zfill(8))
        & (table["parameter_id"].astype(str) == parameter_id)
    ]
    if len(rows) != 1:
        raise ValueError("expected one configured parameter row")
    selected = rows[["basin_id", "parameter_id", *PARAMETER_NAMES]].copy()
    csv_bytes = selected.to_csv(index=False, lineterminator="\n").encode("utf-8")
    values = {name: float(rows.iloc[0][name]) for name in PARAMETER_NAMES}
    return values, csv_bytes, hashlib.sha256(csv_bytes).hexdigest()


def _load_process_covariances(
    root: Path, config: dict
) -> tuple[dict[str, np.ndarray], bytes, str]:
    source = config["process_noise_source"]
    table = _checked_table(root, source, {"basin_id": str, "process_id": str})
    variance_columns = [f"variance_{name}" for name in STATE_NAMES]
    required = {"basin_id", "process_id", *variance_columns}
    if not required.issubset(table.columns):
        raise ValueError("process-noise source is missing required columns")
    process_ids = tuple(str(value) for value in source["process_ids"])
    if len(process_ids) != 3 or len(set(process_ids)) != 3:
        raise ValueError("process-noise source must name exactly three candidates")
    basin = str(source["source_basin_id"])
    basin_rows = table.loc[table["basin_id"].astype(str).str.zfill(8) == basin.zfill(8)]
    selected_rows = []
    covariances = {}
    for process_id in process_ids:
        rows = basin_rows.loc[basin_rows["process_id"].astype(str) == process_id]
        if len(rows) != 1:
            raise ValueError(f"expected one process-noise row for {process_id!r}")
        row = rows.iloc[0]
        diagonal = np.asarray([float(row[column]) for column in variance_columns])
        covariances[process_id] = np.diag(diagonal)
        selected_rows.append(row)
    selected = pd.DataFrame(selected_rows)[["basin_id", "process_id", *variance_columns]]
    csv_bytes = selected.to_csv(index=False, lineterminator="\n").encode("utf-8")
    return covariances, csv_bytes, hashlib.sha256(csv_bytes).hexdigest()


def _load_observation_noise(root: Path, config: dict) -> tuple[float, bytes, str]:
    source = config["observation_noise_source"]
    table = _checked_table(root, source, {"basin_id": str})
    required = {"basin_id", "standard_deviation_mm_day"}
    if not required.issubset(table.columns):
        raise ValueError("observation-noise source is missing required columns")
    row = _select_single_row(table, str(source["source_basin_id"]), "observation-noise")
    selected = pd.DataFrame([row])[["basin_id", "standard_deviation_mm_day"]]
    csv_bytes = selected.to_csv(index=False, lineterminator="\n").encode("utf-8")
    standard_deviation = float(row["standard_deviation_mm_day"])
    if not np.isfinite(standard_deviation) or standard_deviation <= 0.0:
        raise ValueError("observation standard deviation must be finite and positive")
    return standard_deviation, csv_bytes, hashlib.sha256(csv_bytes).hexdigest()


def _validated_blocks(config: dict) -> tuple[dict, ...]:
    blocks = tuple(dict(value) for value in config["matched_blocks"])
    if not blocks:
        raise ValueError("matched_blocks must be nonempty")
    ids = tuple(str(value["block_id"]) for value in blocks)
    if any(not value for value in ids) or len(set(ids)) != len(ids):
        raise ValueError("matched block identifiers must be nonempty and unique")
    for key in ("forcing_seed", "process_noise_seed", "observation_noise_seed"):
        values = [value[key] for value in blocks]
        if any(isinstance(value, bool) or int(value) != value for value in values):
            raise ValueError(f"{key} values must be integers")
        if len(set(int(value) for value in values)) != len(values):
            raise ValueError(f"{key} values must be unique across matched blocks")
    return blocks


def _bootstrap_mean_interval(
    values: np.ndarray, replicates: int, seed: int
) -> tuple[float, float]:
    if replicates <= 0:
        raise ValueError("bootstrap replicates must be positive")
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(replicates, len(values)))
    statistics = np.mean(values[indices], axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def _bootstrap_median_interval(
    values: np.ndarray, replicates: int, seed: int
) -> tuple[float, float]:
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(replicates, len(values)))
    statistics = np.median(values[indices], axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def _bootstrap_grouped_median_interval(
    values: np.ndarray,
    group_ids: np.ndarray,
    replicates: int,
    seed: int,
) -> tuple[float, float]:
    observations = np.asarray(values, dtype=np.float64)
    groups = np.asarray(group_ids).astype(str)
    if observations.ndim != 1 or groups.shape != observations.shape:
        raise ValueError("values and group_ids must be equal-length one-dimensional arrays")
    if len(observations) == 0 or not np.all(np.isfinite(observations)):
        raise ValueError("grouped bootstrap values must be nonempty and finite")
    if replicates <= 0:
        raise ValueError("bootstrap replicates must be positive")
    unique_groups = tuple(dict.fromkeys(groups.tolist()))
    grouped_indices = [np.flatnonzero(groups == group) for group in unique_groups]
    group_sizes = {len(indices) for indices in grouped_indices}
    if len(group_sizes) != 1:
        raise ValueError("matched bootstrap groups must have equal size")
    grouped_values = np.stack([observations[indices] for indices in grouped_indices])
    rng = np.random.default_rng(seed)
    sampled_groups = rng.integers(
        0,
        len(unique_groups),
        size=(replicates, len(unique_groups)),
    )
    samples = grouped_values[sampled_groups].reshape(replicates, -1)
    statistics = np.median(samples, axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def _resource_preflight(config: dict, process_candidate_count: int) -> dict:
    block_count = len(config["matched_blocks"])
    trials = block_count * process_candidate_count
    days = int(config["forcing"]["days"])
    duration = int(config["duration_days"])
    float_bytes = np.dtype(np.float64).itemsize
    forcing_bytes = trials * days * 3 * float_bytes
    truth_bytes = trials * duration * (6 * 15 + 4) * float_bytes
    candidate_bytes = trials * duration * (
        4 * process_candidate_count + process_candidate_count * 15
    ) * float_bytes
    filter_working_bytes = process_candidate_count * 8 * (31 * 15 + 15 * 15) * float_bytes
    packaging_and_runtime_allowance = 32 * 1024 * 1024
    estimated_peak = int(
        3 * (forcing_bytes + truth_bytes + candidate_bytes)
        + filter_working_bytes
        + packaging_and_runtime_allowance
    )
    available = int(psutil.virtual_memory().available)
    task_specific_reserve = int(2 * estimated_peak + 64 * 1024 * 1024)
    required_available = estimated_peak + task_specific_reserve
    safe = available >= required_available
    result = {
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "matched_block_count": block_count,
        "trial_count": trials,
        "process_noise_candidate_count": process_candidate_count,
        "forcing_days_per_trial": days,
        "assimilation_days_per_trial": duration,
        "execution_parallelism": 1,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "available_physical_memory_bytes": available,
        "task_specific_reserve_bytes": task_specific_reserve,
        "task_specific_required_available_bytes": required_available,
        "available_after_estimated_peak_bytes": available - estimated_peak,
        "safe_to_run": safe,
        "estimation_basis": (
            "three in-memory copies of forcing, truth, candidate and packaging arrays; "
            "three sequential filters; plus a task-specific two-estimate and 64 MiB reserve"
        ),
        "universal_memory_threshold_used": False,
    }
    if not safe:
        raise MemoryError("process-noise identification lacks its estimated task-specific margin")
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
            raise RuntimeError(f"process-noise identification failed; see {output / 'summary.json'}")
        return summary
    if incomplete.exists() or registry.exists() or preregistry.exists():
        raise FileExistsError("refusing to overwrite incomplete evidence or registry")

    parameters, parameter_csv, parameter_snapshot_hash = _load_parameter(root, config)
    covariances, process_csv, process_snapshot_hash = _load_process_covariances(root, config)
    observation_std, observation_csv, observation_snapshot_hash = _load_observation_noise(
        root, config
    )
    blocks = _validated_blocks(config)
    process_ids = tuple(covariances)
    if config["bootstrap"].get("unit") != "matched_block":
        raise ValueError("bootstrap unit must be matched_block")

    trial_ids = []
    forcing_block_ids = []
    true_process_ids = []
    process_seeds = []
    observation_seeds = []
    forcing_trials = []
    for block in blocks:
        block_id = str(block["block_id"])
        trial_config = dict(config)
        trial_forcing = dict(config["forcing"])
        trial_forcing["seed"] = int(block["forcing_seed"])
        trial_config["forcing"] = trial_forcing
        forcing = _forcing(trial_config)
        for process_id in process_ids:
            trial_ids.append(f"{block_id}:{process_id}")
            forcing_block_ids.append(block_id)
            true_process_ids.append(process_id)
            process_seeds.append(int(block["process_noise_seed"]))
            observation_seeds.append(int(block["observation_noise_seed"]))
            forcing_trials.append(forcing.copy())

    registered_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "experiment_id": config["experiment_id"],
        "status": "preregistered",
        "registered_at": registered_at,
        "config_sha256": _sha256(config_file),
        "matched_block_ids": [str(block["block_id"]) for block in blocks],
        "trial_ids": trial_ids,
        "process_noise_ids": list(process_ids),
        "true_process_noise_ids": true_process_ids,
        "parameter_id": str(config["parameter_source"]["parameter_id"]),
        "interaction_mode": "none",
        "parameter_switching": False,
        "process_noise_switching": False,
        "generated_observation_noise": "independent Gaussian draws shared within matched block",
        "bootstrap_replicates": int(config["bootstrap"]["replicates"]),
        "bootstrap_unit": "matched_block",
        "gates": config["gates"],
    }
    _atomic_json_write(preregistry, preregistration)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    resource_preflight = _resource_preflight(config, len(process_ids))
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))

    forcing_values = np.stack(forcing_trials)
    result = run_process_noise_identification_validation(
        forcing_realizations=forcing_values,
        trial_ids=trial_ids,
        forcing_block_ids=forcing_block_ids,
        parameter_vector=parameters,
        process_covariances=covariances,
        true_process_noise_ids=true_process_ids,
        process_noise_seeds=process_seeds,
        observation_noise_seeds=observation_seeds,
        start_day=config["start_day"],
        duration_days=config["duration_days"],
        initial_covariance_fraction=config["initial_covariance_fraction"],
        observation_standard_deviation=observation_std,
    )

    maximum_transition_difference = 0.0
    maximum_observation_difference = 0.0
    start_day = int(config["start_day"])
    duration_days = int(config["duration_days"])
    for trial in range(len(trial_ids)):
        transition = ForcingTransition(parameters)
        observation = RoutedDischargeObservation(parameters)
        previous_state = result.initial_truth_states[trial]
        for offset, day in enumerate(range(start_day, start_day + duration_days)):
            rain, potential_evaporation, temperature = forcing_values[trial, day]
            transition.set_forcing(rain, potential_evaporation, temperature)
            adapter_state = transition(previous_state)
            maximum_transition_difference = max(
                maximum_transition_difference,
                float(
                    np.max(
                        np.abs(adapter_state - result.truth_deterministic_states[trial, offset])
                    )
                ),
            )
            adapter_discharge = float(observation(result.truth_states[trial, offset])[0])
            maximum_observation_difference = max(
                maximum_observation_difference,
                abs(adapter_discharge - result.truth_discharge[trial, offset]),
            )
            previous_state = result.truth_states[trial, offset]

    id_to_index = {value: index for index, value in enumerate(result.process_noise_ids)}
    true_indices = np.asarray([id_to_index[value] for value in result.true_process_noise_ids])
    terminal_window = int(config["terminal_window_days"])
    if terminal_window <= 0 or terminal_window > int(config["duration_days"]):
        raise ValueError("terminal_window_days must be within the assimilation duration")
    terminal_probabilities = np.mean(result.posterior_probabilities[:, -terminal_window:, :], axis=1)
    terminal_true_probability = terminal_probabilities[np.arange(len(true_indices)), true_indices]
    predicted_indices = np.argmax(terminal_probabilities, axis=1)
    correct = predicted_indices == true_indices
    correct_by_process = {
        process_id: int(np.count_nonzero(correct[true_indices == index]))
        for index, process_id in enumerate(process_ids)
    }
    trial_count_by_process = {
        process_id: int(np.count_nonzero(true_indices == index))
        for index, process_id in enumerate(process_ids)
    }
    block_accuracy = np.asarray(
        [
            np.mean(correct[np.asarray(result.forcing_block_ids) == str(block["block_id"])])
            for block in blocks
        ],
        dtype=np.float64,
    )
    bootstrap = config["bootstrap"]
    block_accuracy_interval = _bootstrap_mean_interval(
        block_accuracy, int(bootstrap["replicates"]), int(bootstrap["seed"])
    )
    probability_interval = _bootstrap_grouped_median_interval(
        terminal_true_probability,
        np.asarray(result.forcing_block_ids),
        int(bootstrap["replicates"]),
        int(bootstrap["seed"]) + 1,
    )
    candidate_error = np.sqrt(
        np.mean(
            np.square(result.candidate_prior_discharge - result.truth_discharge[:, :, None]),
            axis=1,
        )
    )
    true_candidate_lowest_error_count = int(
        np.count_nonzero(np.argmin(candidate_error, axis=1) == true_indices)
    )
    projection_event = np.any(result.truth_projection_adjustments != 0.0, axis=2)
    projection_count_by_state = {
        state_name: int(np.count_nonzero(result.truth_projection_adjustments[:, :, index]))
        for index, state_name in enumerate(STATE_NAMES[:5])
    }
    projection_count_by_process = {
        process_id: int(np.count_nonzero(projection_event[true_indices == index]))
        for index, process_id in enumerate(process_ids)
    }
    gates = config["gates"]
    gate_values = {
        "correct_classification_count": int(np.count_nonzero(correct)),
        "correct_classification_count_by_process": correct_by_process,
        "median_terminal_true_probability": float(np.median(terminal_true_probability)),
        "matched_block_accuracy_bootstrap_lower": block_accuracy_interval[0],
    }
    gate_pass = bool(
        gate_values["correct_classification_count"]
        >= int(gates["correct_classification_count_minimum"])
        and all(
            value >= int(gates["correct_classification_count_per_process_minimum"])
            for value in correct_by_process.values()
        )
        and gate_values["median_terminal_true_probability"]
        >= float(gates["median_terminal_true_probability_minimum"])
        and gate_values["matched_block_accuracy_bootstrap_lower"]
        >= float(gates["matched_block_accuracy_bootstrap_lower_minimum"])
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
        "matched_block_count": len(blocks),
        "trial_count": len(trial_ids),
        "process_noise_candidate_count": 3,
        "process_noise_ids": list(process_ids),
        "trial_count_by_process": trial_count_by_process,
        "parameter_id": str(config["parameter_source"]["parameter_id"]),
        "interaction_mode": "none",
        "bootstrap_unit": "matched_block",
        "parameter_switching": False,
        "process_noise_switching": False,
        "truth_transition_implementation": "independent_reference_one_day_simulator",
        "independent_truth_transition_maximum_adapter_difference": maximum_transition_difference,
        "independent_truth_observation_maximum_adapter_difference": maximum_observation_difference,
        "generated_observation_noise": "Gaussian with frozen common standard deviation",
        "observation_standard_deviation": observation_std,
        "terminal_window_days": terminal_window,
        "terminal_true_probability_by_trial": terminal_true_probability.tolist(),
        "terminal_true_probability_bootstrap_interval": list(probability_interval),
        "predicted_process_noise_ids": [process_ids[index] for index in predicted_indices],
        "true_process_noise_ids": list(result.true_process_noise_ids),
        "matched_block_accuracy": block_accuracy.tolist(),
        "matched_block_accuracy_bootstrap_interval": list(block_accuracy_interval),
        "candidate_prior_discharge_root_mean_square_error_by_trial": candidate_error.tolist(),
        "true_candidate_lowest_discharge_error_count": true_candidate_lowest_error_count,
        "truth_projection_event_count_by_process": projection_count_by_process,
        "truth_projection_event_count_by_state": projection_count_by_state,
        "truth_projection_event_count": int(np.count_nonzero(projection_event)),
        "truth_projection_event_total": int(projection_event.size),
        "truth_projection_maximum_absolute_adjustment": float(
            np.max(np.abs(result.truth_projection_adjustments))
        ),
        "negative_observation_count": int(np.count_nonzero(result.observed_discharge < 0.0)),
        "observation_count": int(result.observed_discharge.size),
        "gate_values": gate_values,
        "gates": gates,
        "gate_pass": gate_pass,
        "parameter_source_sha256": config["parameter_source"]["sha256"],
        "process_noise_source_sha256": config["process_noise_source"]["sha256"],
        "observation_noise_source_sha256": config["observation_noise_source"]["sha256"],
        "selected_parameter_snapshot_sha256": parameter_snapshot_hash,
        "selected_process_noise_snapshot_sha256": process_snapshot_hash,
        "selected_observation_noise_snapshot_sha256": observation_snapshot_hash,
        "protected_artifacts_unchanged": protected_unchanged,
        "scope_limit": (
            "This component isolates three fixed process-noise covariances under one fixed complete "
            "parameter vector, matched synthetic forcing and random draws, no switching and no interaction."
        ),
    }
    registry_entry = {
        "experiment_id": config["experiment_id"],
        "type": "closed_truth_three_process_noise_identification",
        "hypothesis": "fixed-model likelihood identifies which frozen process covariance generated truth",
        "base_config": str(config_file),
        "changed_factor": "which of the three fixed process covariances generates truth",
        "fixed_factors": "one complete parameter vector, matched forcing and draws, no switching or interaction",
        "seeds": [dict(block) for block in blocks],
        "status": summary["status"],
        "run_dir": str(output),
        "metrics_path": str(output / "summary.json"),
        "paper_name": "synthetic process-noise identification component",
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
        (incomplete / "parameter_vector.csv").write_bytes(parameter_csv)
        (incomplete / "process_noise_covariances.csv").write_bytes(process_csv)
        (incomplete / "observation_noise.csv").write_bytes(observation_csv)
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
            forcing=forcing_values,
            trial_ids=np.asarray(result.trial_ids),
            forcing_block_ids=np.asarray(result.forcing_block_ids),
            process_noise_ids=np.asarray(result.process_noise_ids),
            true_process_noise_ids=np.asarray(result.true_process_noise_ids),
            true_process_noise_indices=true_indices,
            process_noise_seeds=result.process_noise_seeds,
            observation_noise_seeds=result.observation_noise_seeds,
            parameter_vector=np.asarray([parameters[name] for name in PARAMETER_NAMES]),
            process_covariances=result.process_covariances,
            initial_truth_states=result.initial_truth_states,
            truth_deterministic_states=result.truth_deterministic_states,
            process_standard_normals=result.process_standard_normals,
            truth_process_perturbations=result.truth_process_perturbations,
            truth_projection_adjustments=result.truth_projection_adjustments,
            truth_states=result.truth_states,
            truth_discharge=result.truth_discharge,
            observation_standard_normals=result.observation_standard_normals,
            observed_discharge=result.observed_discharge,
            candidate_prior_discharge=result.candidate_prior_discharge,
            candidate_innovation_variances=result.candidate_innovation_variances,
            candidate_log_likelihoods=result.candidate_log_likelihoods,
            posterior_probabilities=result.posterior_probabilities,
            candidate_posterior_states=result.candidate_posterior_states,
            terminal_probabilities=terminal_probabilities,
            terminal_true_probability=terminal_true_probability,
            matched_block_accuracy=block_accuracy,
            candidate_prior_discharge_root_mean_square_error=candidate_error,
        )
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        sources = {
            "__init__.py": root / "src" / "hbv_multilead_joint_uncertainty" / "__init__.py",
            "process_noise_identification_validation.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "process_noise_identification_validation.py",
            "synthetic_truth.py": root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "synthetic_truth.py",
            "run_process_noise_identification_validation.py": Path(__file__).resolve(),
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
            "test_hbv_process_noise_identification_validation.py": root
            / "test"
            / "test_hbv_process_noise_identification_validation.py",
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
        raise RuntimeError(f"process-noise identification failed; see {output / 'summary.json'}")
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
