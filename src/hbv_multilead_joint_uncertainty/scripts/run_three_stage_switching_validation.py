"""Run and freeze one exact-candidate three-stage switching validation."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import psutil


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts.run_model_probability_validation import (  # noqa: E402
    _load_parameter_vectors,
    _load_process_covariances,
)
from hbv_multilead_joint_uncertainty.scripts.run_process_noise_identification_validation import (  # noqa: E402
    _load_observation_noise,
    _validated_blocks,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (  # noqa: E402
    _protected_hashes,
    _sha256,
)
from hbv_multilead_joint_uncertainty.three_stage_switching_validation import (  # noqa: E402
    evaluate_three_stage_switching_result,
    run_three_stage_switching_validation,
)


def _json_write(path: Path, value) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _replace_directory_with_retries(
    source: Path,
    target: Path,
    attempts: int = 5,
    delay_seconds: float = 1.0,
) -> None:
    """Finalize evidence despite a bounded transient Windows directory lock."""

    if attempts <= 0 or delay_seconds < 0.0:
        raise ValueError("attempts must be positive and delay_seconds nonnegative")
    for attempt in range(attempts):
        if not source.is_dir() or target.exists():
            raise FileExistsError("evidence finalization source or target state changed")
        try:
            source.replace(target)
            return
        except PermissionError:
            if attempt + 1 == attempts:
                raise
            time.sleep(delay_seconds)


def _validate_output_is_disjoint_from_protected_paths(
    output: Path, protected_paths
) -> None:
    """Reject output locations that contain or are contained by protected evidence."""

    output_value = output.resolve()
    for configured in protected_paths:
        protected = Path(configured).resolve()
        overlaps = False
        try:
            output_value.relative_to(protected)
            overlaps = True
        except ValueError:
            pass
        try:
            protected.relative_to(output_value)
            overlaps = True
        except ValueError:
            pass
        if overlaps:
            raise ValueError(
                f"output and protected path overlap: {output_value} ; {protected}"
            )


def _atomic_json_write(path: Path, value) -> None:
    temporary = path.with_name(path.name + ".incomplete")
    if path.exists() or temporary.exists():
        raise FileExistsError(f"refusing to overwrite immutable file {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    _json_write(temporary, value)
    temporary.replace(path)


def _forcing_blocks(config: dict, blocks: tuple[dict, ...]) -> np.ndarray:
    forcing = config["forcing"]
    days = (
        int(forcing["warmup_days"])
        + sum(int(value) for value in config["stage_lengths"])
        + int(max(config["lead_days"]))
    )
    reference_days = int(forcing.get("reference_total_days", days))
    if reference_days < days:
        raise ValueError("forcing reference_total_days must cover the requested duration")
    angle = np.linspace(0.0, 2.0 * np.pi, reference_days)[:days]
    result = np.empty((len(blocks), days, 3), dtype=np.float64)
    for index, block in enumerate(blocks):
        rng = np.random.default_rng(int(block["forcing_seed"]))
        result[index, :, 0] = rng.gamma(
            float(forcing["rain_shape"]),
            float(forcing["rain_scale"]),
            size=days,
        )
        result[index, :, 1] = np.maximum(0.0, 2.0 + np.sin(angle))
        result[index, :, 2] = 4.0 + 12.0 * np.sin(angle - np.pi / 2.0)
    return result


def _truth_count(config: dict) -> int:
    return 9 if config["scenario"] == "parameter_process_noise_switch" else 3


def _expected_saved_numeric_bytes(config: dict) -> int:
    blocks = len(config["matched_blocks"])
    truth = _truth_count(config)
    warmup = int(config["forcing"]["warmup_days"])
    assimilation = sum(int(value) for value in config["stage_lengths"])
    leads = len(config["lead_days"])
    active = assimilation + int(max(config["lead_days"]))
    methods = 5
    candidates = 9
    states = 15
    float_shapes = (
        (blocks, warmup + active, 3),
        (3, len(PARAMETER_NAMES)),
        (3, states, states),
        (),
        (blocks, 3, states),
        (blocks, states, states),
        (blocks, active, states),
        (blocks, active),
        (blocks, truth, active, states),
        (blocks, truth, active, states),
        (blocks, truth, active, states),
        (blocks, truth, active, states),
        (blocks, truth, active),
        (blocks, truth, active),
        (blocks, truth, leads),
        (blocks, truth, methods, assimilation, candidates),
        (blocks, truth, methods, assimilation, states),
        (blocks, truth, methods, states),
        (blocks, truth, methods, leads),
        (blocks, truth, methods, leads, candidates),
        (blocks, truth, methods, leads, candidates),
        (blocks, truth, methods, leads),
    )
    integer_shapes = (
        (blocks,),
        (blocks,),
        (3,),
        (leads,),
        (methods,),
        (truth, active),
        (truth, active),
        (truth, active),
        (truth, active),
        (truth,),
        (3,),
        (3,),
    )
    return int(
        sum(np.prod(shape, dtype=np.int64) * 8 for shape in float_shapes)
        + sum(np.prod(shape, dtype=np.int64) * 8 for shape in integer_shapes)
    )


def _resource_preflight(config: dict, repo_root: Path | None = None) -> dict:
    pilot = dict(config["resource_pilot"])
    pilot_source_verified = None
    if "sha256" in pilot:
        if repo_root is None:
            raise ValueError("repo_root is required to verify the resource pilot")
        pilot_path = (repo_root / str(pilot["source"])).resolve()
        if not pilot_path.is_file() or _sha256(pilot_path) != str(pilot["sha256"]):
            raise ValueError("resource pilot checksum mismatch")
        pilot_source_verified = True
    expected = _expected_saved_numeric_bytes(config)
    pilot_growth = int(pilot["observed_peak_resident_memory_growth_bytes"])
    estimated_peak = int(4 * expected + 2 * pilot_growth + 128 * 1024 * 1024)
    available = int(psutil.virtual_memory().available)
    reserve = int(max(estimated_peak // 2, 256 * 1024 * 1024))
    required = estimated_peak + reserve
    pilot_blocks = int(pilot["block_count"])
    if pilot_blocks <= 0:
        raise ValueError("resource pilot block_count must be positive")
    runtime_estimate = (
        float(pilot["elapsed_seconds"])
        * len(config["matched_blocks"])
        / pilot_blocks
    )
    result = {
        "checked_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "scenario": config["scenario"],
        "matched_block_count": len(config["matched_blocks"]),
        "truth_trial_count_per_block": _truth_count(config),
        "state_dimension": 15,
        "execution_parallelism": 1,
        "expected_saved_numeric_array_bytes": expected,
        "pilot_observed_peak_resident_memory_growth_bytes": pilot_growth,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "available_physical_memory_bytes": available,
        "task_specific_reserve_bytes": reserve,
        "task_specific_required_available_bytes": required,
        "available_after_estimated_peak_bytes": available - estimated_peak,
        "estimated_runtime_seconds_from_pilot": runtime_estimate,
        "safe_to_run": bool(available >= required),
        "execution_adjustment_if_unsafe": (
            "Run one matched block at a time and merge only after verifying identical frozen configuration."
        ),
        "universal_memory_threshold_used": False,
        "resource_pilot": pilot,
        "resource_pilot_source_checksum_verified": pilot_source_verified,
        "estimation_basis": (
            "Four copies of all saved numeric arrays, twice the measured one-block peak "
            "resident-memory growth, 128 mebibytes for filter and compressed-output work, "
            "plus a reserve equal to the larger of half the peak estimate and 256 mebibytes."
        ),
    }
    if not result["safe_to_run"]:
        raise MemoryError("task-specific memory estimate lacks a safe current margin")
    return result


def _evidence_arrays(result, parameter_vectors, process_covariances, observation_std):
    parameter_values = np.asarray(
        [
            [parameter_vectors[key][name] for name in PARAMETER_NAMES]
            for key in result.parameter_ids
        ],
        dtype=np.float64,
    )
    covariance_values = np.stack(
        [process_covariances[key] for key in result.process_ids]
    )
    candidate_ids = np.full((len(result.method_names), 9), "", dtype="<U96")
    for method_index, values in enumerate(result.method_candidate_ids):
        candidate_ids[method_index, : len(values)] = values
    return {
        "scenario": np.asarray(result.scenario),
        "block_ids": np.asarray(result.block_ids),
        "process_noise_seeds": result.process_noise_seeds,
        "observation_noise_seeds": result.observation_noise_seeds,
        "forcing_blocks": result.forcing_blocks,
        "warmup_days": np.asarray(result.warmup_days, dtype=np.int64),
        "stage_lengths": result.stage_lengths,
        "assimilation_days": np.asarray(result.assimilation_days, dtype=np.int64),
        "forecast_lead_days": result.forecast_lead_days,
        "method_names": np.asarray(result.method_names),
        "method_candidate_ids": candidate_ids,
        "method_candidate_counts": result.method_candidate_counts,
        "parameter_ids": np.asarray(result.parameter_ids),
        "process_ids": np.asarray(result.process_ids),
        "parameter_vectors": parameter_values,
        "process_covariances": covariance_values,
        "observation_standard_deviation": np.asarray(observation_std),
        "truth_joint_candidate_indices": result.schedule.joint_candidate_indices,
        "truth_parameter_indices": result.schedule.parameter_indices,
        "truth_process_indices": result.schedule.process_indices,
        "truth_primary_candidate_indices": result.schedule.primary_candidate_indices,
        "origin_joint_candidate_indices": result.schedule.origin_joint_candidate_indices,
        "stage_start_days": result.schedule.stage_start_days,
        "stage_end_days": result.schedule.stage_end_days,
        "initial_parameter_states": result.initial_parameter_states,
        "initial_covariances": result.initial_covariances,
        "process_standard_normals": result.process_standard_normals,
        "observation_standard_normals": result.observation_standard_normals,
        "truth_deterministic_states": result.truth_deterministic_states,
        "truth_process_perturbations": result.truth_process_perturbations,
        "truth_projection_adjustments": result.truth_projection_adjustments,
        "truth_states": result.truth_states,
        "truth_discharge": result.truth_discharge,
        "observed_discharge": result.observed_discharge,
        "truth_forecast_discharge": result.truth_forecast_discharge,
        "method_assimilation_probabilities": result.method_assimilation_probabilities,
        "method_assimilation_states": result.method_assimilation_states,
        "method_origin_states": result.method_origin_states,
        "method_predictions": result.method_predictions,
        "method_candidate_predictions": result.method_candidate_predictions,
        "method_forecast_probabilities": result.method_forecast_probabilities,
        "method_absolute_errors": result.method_absolute_errors,
    }


def _maximum_absolute_error(left, right) -> float:
    return float(
        np.max(np.abs(np.asarray(left) - np.asarray(right)), initial=0.0)
    )


def _integrity_checks(result, arrays, process_covariances, observation_std, config):
    covariance_stack = np.stack(
        [process_covariances[key] for key in result.process_ids]
    )
    process_standard_deviations = np.sqrt(
        np.diagonal(covariance_stack, axis1=1, axis2=2)
    )
    scheduled_scales = process_standard_deviations[
        result.schedule.process_indices
    ]
    expected_perturbations = (
        result.process_standard_normals[:, None, :, :]
        * scheduled_scales[None, :, :, :]
    )
    expected_observations = (
        result.truth_discharge
        + float(observation_std) * result.observation_standard_normals[:, None, :]
    )
    mixture_errors = []
    probability_errors = []
    minimum_probability = 1.0
    for method_index, count in enumerate(result.method_candidate_counts):
        active = slice(0, int(count))
        probabilities = result.method_forecast_probabilities[
            :, :, method_index, :, active
        ]
        candidates = result.method_candidate_predictions[
            :, :, method_index, :, active
        ]
        mixture_errors.append(
            _maximum_absolute_error(
                result.method_predictions[:, :, method_index],
                np.sum(probabilities * candidates, axis=-1),
            )
        )
        probability_errors.append(
            _maximum_absolute_error(probabilities.sum(axis=-1), 1.0)
        )
        daily = result.method_assimilation_probabilities[
            :, :, method_index, :, active
        ]
        probability_errors.append(_maximum_absolute_error(daily.sum(axis=-1), 1.0))
        minimum_probability = min(
            minimum_probability,
            float(np.min(probabilities)),
            float(np.min(daily)),
        )
    target_indices = result.assimilation_days + result.forecast_lead_days - 1
    finite_arrays = [
        name
        for name, value in arrays.items()
        if np.issubdtype(np.asarray(value).dtype, np.number)
        and not np.all(np.isfinite(value))
    ]
    gates = config["integrity_gates"]
    values = {
        "truth_process_perturbation_reconstruction_maximum_absolute_error": (
            _maximum_absolute_error(
                result.truth_process_perturbations, expected_perturbations
            )
        ),
        "observation_reconstruction_maximum_absolute_error": _maximum_absolute_error(
            result.observed_discharge, expected_observations
        ),
        "forecast_target_reconstruction_maximum_absolute_error": _maximum_absolute_error(
            result.truth_forecast_discharge,
            result.truth_discharge[:, :, target_indices],
        ),
        "method_mixture_reconstruction_maximum_absolute_error": max(mixture_errors),
        "method_probability_sum_maximum_absolute_error": max(probability_errors),
        "minimum_method_probability": minimum_probability,
        "nonfinite_numeric_array_names": finite_arrays,
    }
    passed = bool(
        values[
            "truth_process_perturbation_reconstruction_maximum_absolute_error"
        ]
        <= float(gates["truth_process_perturbation_reconstruction_maximum_absolute_error"])
        and values["observation_reconstruction_maximum_absolute_error"]
        <= float(gates["observation_reconstruction_maximum_absolute_error"])
        and values["forecast_target_reconstruction_maximum_absolute_error"]
        <= float(gates["forecast_target_reconstruction_maximum_absolute_error"])
        and values["method_mixture_reconstruction_maximum_absolute_error"]
        <= float(gates["method_mixture_reconstruction_maximum_absolute_error"])
        and values["method_probability_sum_maximum_absolute_error"]
        <= float(gates["method_probability_sum_maximum_absolute_error"])
        and values["minimum_method_probability"]
        >= float(gates["minimum_method_probability"])
        and not finite_arrays
    )
    return {**values, "integrity_passed": passed, "configured_gates": gates}


def _counterfactual_check(
    result,
    forcing,
    blocks,
    parameter_vectors,
    process_scales,
    process_covariances,
    observation_std,
    config,
):
    first = blocks[0]
    changed = run_three_stage_switching_validation(
        forcing_blocks=forcing[:1],
        block_ids=(str(first["block_id"]),),
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=str(config["process_noise_source"]["selected_process_id"]),
        scenario=str(config["scenario"]),
        process_noise_seeds=(int(first["process_noise_seed"]),),
        observation_noise_seeds=(int(first["observation_noise_seed"]),),
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_lengths=tuple(int(value) for value in config["stage_lengths"]),
        lead_days=tuple(int(value) for value in config["lead_days"]),
        initial_covariance_fraction=float(config["initial_covariance_fraction"]),
        observation_standard_deviation=float(observation_std),
        factor_transition_stay_probability=float(
            config["factor_transition_stay_probability"]
        ),
        future_observation_replacement=1.0e12,
    )
    probability_error = _maximum_absolute_error(
        changed.method_assimilation_probabilities,
        result.method_assimilation_probabilities[:1],
    )
    prediction_error = _maximum_absolute_error(
        changed.method_predictions, result.method_predictions[:1]
    )
    origin_error = _maximum_absolute_error(
        changed.method_origin_states, result.method_origin_states[:1]
    )
    future_changed = bool(
        np.all(
            changed.observed_discharge[:, :, result.assimilation_days :] == 1.0e12
        )
    )
    return {
        "counterfactual_future_observation_value": 1.0e12,
        "future_observations_changed": future_changed,
        "assimilation_probability_maximum_absolute_change": probability_error,
        "forecast_prediction_maximum_absolute_change": prediction_error,
        "forecast_origin_state_maximum_absolute_change": origin_error,
        "future_discharge_used_by_forecast": not bool(
            future_changed
            and probability_error == 0.0
            and prediction_error == 0.0
            and origin_error == 0.0
        ),
        "passed": bool(
            future_changed
            and probability_error == 0.0
            and prediction_error == 0.0
            and origin_error == 0.0
        ),
    }


def _environment(root: Path, started_at: str) -> dict:
    def git(*arguments):
        completed = subprocess.run(
            ["git", *arguments],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
        )
        return completed.stdout.rstrip() if completed.returncode == 0 else None

    return {
        "started_at_utc": started_at,
        "finished_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "python_version": sys.version,
        "python_executable": sys.executable,
        "operating_system": platform.platform(),
        "numpy_version": np.__version__,
        "pandas_version": pd.__version__,
        "psutil_version": psutil.__version__,
        "git_head": git("rev-parse", "HEAD"),
        "git_branch": git("branch", "--show-current"),
        "git_status_short": git("status", "--short", "--untracked-files=all"),
        "execution_command": subprocess.list2cmdline(sys.argv),
    }


def _source_snapshot(root: Path, destination: Path) -> None:
    sources = (
        "src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_three_stage_switching_validation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_model_probability_validation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_process_noise_identification_validation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_synthetic_truth_validation.py",
        "src/hbv_multilead_joint_uncertainty/methods.py",
        "src/hbv_multilead_joint_uncertainty/forecast.py",
        "src/hbv_multilead_joint_uncertainty/synthetic_truth.py",
        "src/hbv_joint_uncertainty/hbv_adapter.py",
        "src/hbv_joint_uncertainty/imm.py",
        "src/hbv_joint_uncertainty/preflight.py",
        "src/hbv_joint_uncertainty/sigma_filter.py",
        "src/scl_hydro/hbv_lite_numpy.py",
        "test/test_hbv_three_stage_switching_validation.py",
    )
    destination.mkdir(parents=True, exist_ok=False)
    for configured in sources:
        source = (root / configured).resolve()
        if not source.is_file():
            raise FileNotFoundError(f"source snapshot file is missing: {configured}")
        target = destination / configured.replace("/", "__")
        shutil.copy2(source, target)


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    preregistration_path = output.with_name(
        output.name + ".preregistered.json"
    )
    if output.exists() or incomplete.exists() or preregistration_path.exists():
        raise FileExistsError("refusing to overwrite existing evidence")
    config_bytes = config_file.read_bytes()
    config_hash = hashlib.sha256(config_bytes).hexdigest()
    config = json.loads(config_bytes.decode("utf-8"))
    if output.name != str(config["experiment_id"]):
        raise ValueError("output directory name must equal experiment_id")
    blocks = _validated_blocks(config)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    protected_paths = tuple(
        (root / str(value)).resolve()
        for value in config.get("protected_paths", ())
    )
    _validate_output_is_disjoint_from_protected_paths(output, protected_paths)
    _validate_output_is_disjoint_from_protected_paths(incomplete, protected_paths)
    preregistration = {
        "frozen_before_execution": True,
        "experiment_id": config["experiment_id"],
        "scenario": config["scenario"],
        "decision_rules": config["decision_rules"],
        "bootstrap": config["bootstrap"],
        "config_sha256": config_hash,
        "started_at_utc": started_at,
        "output_directory": str(output),
    }
    _atomic_json_write(preregistration_path, preregistration)
    parameter_vectors, parameter_csv, parameter_hash = _load_parameter_vectors(
        root, config
    )
    process_covariances, process_scales, process_csv, process_hash = (
        _load_process_covariances(root, config)
    )
    observation_std, observation_csv, observation_hash = _load_observation_noise(
        root, config
    )
    resource = _resource_preflight(config, root)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))
    forcing = _forcing_blocks(config, blocks)

    result = run_three_stage_switching_validation(
        forcing_blocks=forcing,
        block_ids=tuple(str(value["block_id"]) for value in blocks),
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=str(config["process_noise_source"]["selected_process_id"]),
        scenario=str(config["scenario"]),
        process_noise_seeds=tuple(int(value["process_noise_seed"]) for value in blocks),
        observation_noise_seeds=tuple(
            int(value["observation_noise_seed"]) for value in blocks
        ),
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_lengths=tuple(int(value) for value in config["stage_lengths"]),
        lead_days=tuple(int(value) for value in config["lead_days"]),
        initial_covariance_fraction=float(config["initial_covariance_fraction"]),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=float(
            config["factor_transition_stay_probability"]
        ),
    )
    evaluation = evaluate_three_stage_switching_result(
        result,
        adaptation_days=int(config["decision_rules"]["adaptation_days_excluded_per_stage"]),
        bootstrap_replicates=int(config["bootstrap"]["replicates"]),
        bootstrap_seed=int(config["bootstrap"]["seed"]),
        candidate_accuracy_minimum=float(
            config["decision_rules"]["candidate_argmax_accuracy_minimum"]
        ),
        factor_accuracy_minimum=float(
            config["decision_rules"]["factor_argmax_accuracy_minimum"]
        ),
        median_true_probability_minimum=float(
            config["decision_rules"]["median_true_candidate_probability_minimum"]
        ),
        relative_root_mean_square_error_improvement_percent_minimum=float(
            config["decision_rules"][
                "relative_root_mean_square_error_improvement_percent_minimum"
            ]
        ),
        paired_block_difference_upper_maximum=float(
            config["decision_rules"]["paired_block_difference_upper_maximum"]
        ),
    )
    arrays = _evidence_arrays(
        result, parameter_vectors, process_covariances, observation_std
    )
    integrity = _integrity_checks(
        result, arrays, process_covariances, observation_std, config
    )
    counterfactual = _counterfactual_check(
        result,
        forcing,
        blocks,
        parameter_vectors,
        process_scales,
        process_covariances,
        observation_std,
        config,
    )
    incomplete.mkdir(parents=True, exist_ok=False)
    try:
        (incomplete / "config_snapshot.json").write_bytes(config_bytes)
        (incomplete / "preregistration.json").write_bytes(
            preregistration_path.read_bytes()
        )
        _json_write(incomplete / "resource_preflight.json", resource)
        _json_write(incomplete / "integrity_checks.json", integrity)
        _json_write(incomplete / "future_observation_counterfactual.json", counterfactual)
        _json_write(incomplete / "scientific_evaluation.json", evaluation)
        _json_write(incomplete / "environment.json", _environment(root, started_at))
        (incomplete / "parameter_vectors.csv").write_bytes(parameter_csv)
        (incomplete / "process_noise_covariances.csv").write_bytes(process_csv)
        (incomplete / "observation_noise.csv").write_bytes(observation_csv)
        pd.DataFrame(evaluation["stage_identification"]).to_csv(
            incomplete / "stage_identification.csv", index=False, lineterminator="\n"
        )
        pd.DataFrame(evaluation["method_metrics"]).to_csv(
            incomplete / "method_metrics.csv", index=False, lineterminator="\n"
        )
        pd.DataFrame(evaluation["paired_comparisons"]).to_csv(
            incomplete / "paired_comparisons.csv", index=False, lineterminator="\n"
        )
        np.savez_compressed(incomplete / "evidence.npz", **arrays)
        _source_snapshot(root, incomplete / "source_snapshot")
        protected_after = _protected_hashes(
            root, config.get("protected_paths", ())
        )
        protected_unchanged = protected_before == protected_after
        integrity_passed = bool(
            integrity["integrity_passed"]
            and counterfactual["passed"]
            and protected_unchanged
        )
        summary = {
            "experiment_id": config["experiment_id"],
            "scenario": config["scenario"],
            "integrity_status": "passed" if integrity_passed else "failed",
            "scientific_status": (
                "passed" if evaluation["scientific_success"] else "not_passed"
            ),
            "identification_passed_all_three_stages": evaluation[
                "identification_passed_all_three_stages"
            ],
            "forecast_passed_all_leads": evaluation["forecast_passed_all_leads"],
            "protected_artifacts_unchanged": protected_unchanged,
            "future_discharge_used_by_forecast": counterfactual[
                "future_discharge_used_by_forecast"
            ],
            "parameter_snapshot_sha256": parameter_hash,
            "process_snapshot_sha256": process_hash,
            "observation_snapshot_sha256": observation_hash,
            "config_sha256": config_hash,
            "scope_limit": config["scope_limit"],
        }
        _json_write(incomplete / "summary.json", summary)
        _json_write(
            incomplete / "protected_artifact_integrity.json",
            {
                "configured_paths": config.get("protected_paths", ()),
                "output_paths_proven_disjoint_before_execution": True,
                "before": protected_before,
                "after_evidence_writes": protected_after,
                "status": "unchanged" if protected_unchanged else "changed",
            },
        )
        checksums = {
            path.relative_to(incomplete).as_posix(): _sha256(path)
            for path in sorted(incomplete.rglob("*"))
            if path.is_file() and path.name != "checksums.json"
        }
        _json_write(incomplete / "checksums.json", checksums)
        if not integrity_passed:
            raise RuntimeError("numerical integrity, causal, or protected-artifact gate failed")
        _replace_directory_with_retries(incomplete, output)
    except Exception:
        raise
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    summary = run(arguments.repo_root, arguments.config, arguments.output_dir)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
