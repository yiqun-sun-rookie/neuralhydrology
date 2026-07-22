"""Run and freeze one no-interaction candidate likelihood diagnostic."""

from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import psutil


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.candidate_likelihood_identifiability import (  # noqa: E402
    evaluate_candidate_likelihood_identifiability,
    run_candidate_likelihood_identifiability,
    score_candidate_log_likelihoods,
)
from hbv_multilead_joint_uncertainty.scripts.run_model_probability_validation import (  # noqa: E402
    _load_parameter_vectors,
    _load_process_covariances,
)
from hbv_multilead_joint_uncertainty.scripts.run_process_noise_identification_validation import (  # noqa: E402
    _load_observation_noise,
    _validated_blocks,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (  # noqa: E402
    _sha256,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _atomic_json_write,
    _replace_directory_with_retries,
    _validate_output_is_disjoint_from_protected_paths,
)


def _json_write(path: Path, value) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _windows_extended_length_path(path: str | Path) -> Path:
    """Return one absolute path with Windows extended-length I/O semantics."""

    candidate = Path(path)
    if os.name != "nt":
        return candidate
    raw = str(candidate)
    if raw.startswith("\\\\?\\"):
        return candidate
    if not candidate.is_absolute():
        raw = str(candidate.absolute())
    if raw.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + raw[2:])
    return Path("\\\\?\\" + raw)


def _protected_hashes(root: Path, configured_paths) -> dict[str, str]:
    """Hash every protected file, including files beyond the Windows path limit."""

    resolved_root = root.resolve()
    canonical_root = _windows_extended_length_path(resolved_root)
    hashes: dict[str, str] = {}
    for configured in configured_paths:
        resolved = (resolved_root / str(configured)).resolve()
        try:
            resolved.relative_to(resolved_root)
        except ValueError as error:
            raise ValueError(
                f"protected path is outside the repository: {configured}"
            ) from error
        canonical = _windows_extended_length_path(resolved)
        if not canonical.exists():
            raise FileNotFoundError(f"protected path does not exist: {configured}")
        files = (
            [canonical]
            if canonical.is_file()
            else sorted(item for item in canonical.rglob("*") if item.is_file())
        )
        for item in files:
            relative = item.relative_to(canonical_root).as_posix()
            hashes[relative] = _sha256(item)
    return hashes


def _forcing_blocks(config: dict, blocks: tuple[dict, ...]) -> np.ndarray:
    forcing = config["forcing"]
    days = int(forcing["warmup_days"]) + sum(
        int(value) for value in config["stage_lengths"]
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


def _truth_and_candidate_count(config: dict) -> tuple[int, int]:
    joint = config["scenario"] == "parameter_process_noise_switch"
    return (9, 9) if joint else (3, 3)


def _expected_saved_numeric_bytes(config: dict) -> int:
    blocks = len(config["matched_blocks"])
    truths, candidates = _truth_and_candidate_count(config)
    warmup = int(config["forcing"]["warmup_days"])
    assimilation = sum(int(value) for value in config["stage_lengths"])
    stages = 3
    scored_days = int(config["stage_lengths"][0]) - int(
        config["adaptation_days_excluded_per_stage"]
    )
    state = 15
    float_shapes = (
        (blocks, warmup + assimilation, 3),
        (3, len(PARAMETER_NAMES)),
        (3, state, state),
        (),
        (blocks, 3, state),
        (blocks, state, state),
        (blocks, assimilation, state),
        (blocks, assimilation),
        *((blocks, truths, assimilation, state),) * 4,
        *((blocks, truths, assimilation),) * 2,
        *((blocks, truths, assimilation, candidates),) * 4,
        *((blocks, truths, stages, scored_days, candidates),) * 2,
        *((blocks, truths, stages, scored_days),) * 2,
    )
    integer_shapes = (
        (blocks,),
        (blocks,),
        (3,),
        (candidates,),
        (candidates,),
        (truths, assimilation),
        *((blocks, truths, stages, scored_days),) * 2,
        *((blocks, truths, stages),) * 2,
    )
    boolean_shapes = ((blocks, truths, stages),)
    return int(
        sum(np.prod(shape, dtype=np.int64) * 8 for shape in float_shapes)
        + sum(np.prod(shape, dtype=np.int64) * 8 for shape in integer_shapes)
        + sum(np.prod(shape, dtype=np.int64) for shape in boolean_shapes)
    )


def _commit_memory() -> dict[str, int | None]:
    if platform.system() != "Windows":
        return {
            "commit_limit_bytes": None,
            "committed_bytes": None,
            "available_commit_memory_bytes": None,
        }

    class MemoryStatusEx(ctypes.Structure):
        _fields_ = [
            ("dwLength", ctypes.c_ulong),
            ("dwMemoryLoad", ctypes.c_ulong),
            ("ullTotalPhys", ctypes.c_ulonglong),
            ("ullAvailPhys", ctypes.c_ulonglong),
            ("ullTotalPageFile", ctypes.c_ulonglong),
            ("ullAvailPageFile", ctypes.c_ulonglong),
            ("ullTotalVirtual", ctypes.c_ulonglong),
            ("ullAvailVirtual", ctypes.c_ulonglong),
            ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
        ]

    status = MemoryStatusEx()
    status.dwLength = ctypes.sizeof(status)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
        raise OSError("GlobalMemoryStatusEx failed")
    limit = int(status.ullTotalPageFile)
    available = int(status.ullAvailPageFile)
    return {
        "commit_limit_bytes": limit,
        "committed_bytes": limit - available,
        "available_commit_memory_bytes": available,
    }


def _resource_preflight(config: dict) -> dict:
    expected = _expected_saved_numeric_bytes(config)
    truths, candidates = _truth_and_candidate_count(config)
    filter_work = int(
        candidates
        * (15 + 15 * 15 + 2 * (2 * 15 + 1) * 15)
        * np.dtype(np.float64).itemsize
    )
    compression_work = expected
    estimated_peak = int(2 * expected + filter_work + compression_work)
    current_process = int(psutil.Process().memory_info().rss)
    task_specific_reserve = int(max(estimated_peak // 2, current_process // 4))
    required = estimated_peak + task_specific_reserve
    available_physical = int(psutil.virtual_memory().available)
    commit = _commit_memory()
    available_commit = commit["available_commit_memory_bytes"]
    safe = available_physical >= required and (
        available_commit is None or available_commit >= required
    )
    result = {
        "checked_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "scenario": config["scenario"],
        "dataset_role": config["dataset_role"],
        "matched_block_count": len(config["matched_blocks"]),
        "truth_trial_count_per_block": truths,
        "candidate_count": candidates,
        "state_dimension": 15,
        "execution_parallelism": 1,
        "expected_saved_numeric_array_bytes": expected,
        "estimated_filter_work_bytes": filter_work,
        "estimated_compression_work_bytes": compression_work,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "current_process_resident_memory_bytes": current_process,
        "task_specific_reserve_bytes": task_specific_reserve,
        "task_specific_required_available_bytes": required,
        "available_physical_memory_bytes": available_physical,
        "available_physical_after_estimated_peak_bytes": (
            available_physical - estimated_peak
        ),
        **commit,
        "safe_to_run": bool(safe),
        "universal_memory_threshold_used": False,
        "execution_adjustment_if_unsafe": (
            "Keep the scientific block count fixed, run one scenario in a fresh process, "
            "and write its immutable output before starting the next scenario."
        ),
        "estimation_basis": (
            "Exact configured numeric-array shapes, two live result copies, one compressed-output "
            "workspace, candidate sigma-point and covariance work, and a task-specific reserve "
            "equal to the larger of half the estimated peak or one quarter of current process memory."
        ),
    }
    if not safe:
        raise MemoryError(
            "task-specific physical or committed-memory estimate lacks a safe current margin"
        )
    return result


def _validate_fixed_decision_contract(
    config: dict, scoring_days: int = 10
) -> None:
    expected_stable_days = min(5, int(scoring_days))
    rules = config["decision_rules"]
    if (
        int(config["stable_final_scoring_days"]) != expected_stable_days
        or list(rules["switching_stage_numbers"]) != [2, 3]
        or bool(rules.get("stage_one_decides_scientific_status", False))
    ):
        raise ValueError(
            "configuration disagrees with the fixed decision contract"
        )


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
    return {
        "scenario": np.asarray(result.scenario),
        "block_ids": np.asarray(result.block_ids),
        "process_noise_seeds": result.process_noise_seeds,
        "observation_noise_seeds": result.observation_noise_seeds,
        "forcing_blocks": result.forcing_blocks,
        "warmup_days": np.asarray(result.warmup_days, dtype=np.int64),
        "stage_lengths": result.stage_lengths,
        "adaptation_days": np.asarray(result.adaptation_days, dtype=np.int64),
        "assimilation_days": np.asarray(result.assimilation_days, dtype=np.int64),
        "candidate_ids": np.asarray(result.candidate_ids),
        "candidate_parameter_indices": result.candidate_parameter_indices,
        "candidate_process_indices": result.candidate_process_indices,
        "truth_candidate_indices": result.truth_candidate_indices,
        "truth_joint_candidate_indices": result.schedule.joint_candidate_indices[
            :, : result.assimilation_days
        ],
        "truth_parameter_indices": result.schedule.parameter_indices[
            :, : result.assimilation_days
        ],
        "truth_process_indices": result.schedule.process_indices[
            :, : result.assimilation_days
        ],
        "stage_start_days": result.schedule.stage_start_days,
        "stage_end_days": result.schedule.stage_end_days,
        "parameter_ids": np.asarray(result.parameter_ids),
        "process_ids": np.asarray(result.process_ids),
        "parameter_vectors": parameter_values,
        "process_covariances": covariance_values,
        "observation_standard_deviation": np.asarray(observation_std),
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
        "candidate_prior_observations": result.candidate_prior_observations,
        "candidate_innovations": result.candidate_innovations,
        "candidate_innovation_variances": result.candidate_innovation_variances,
        "candidate_daily_log_likelihoods": result.candidate_daily_log_likelihoods,
        "scored_daily_log_likelihoods": result.scored_daily_log_likelihoods,
        "cumulative_log_likelihoods": result.cumulative_log_likelihoods,
        "true_candidate_daily_ranks": result.true_candidate_daily_ranks,
        "true_candidate_cumulative_ranks": result.true_candidate_cumulative_ranks,
        "true_candidate_daily_margins": result.true_candidate_daily_margins,
        "true_candidate_cumulative_margins": result.true_candidate_cumulative_margins,
        "first_cumulative_rank_one_day": result.first_cumulative_rank_one_day,
        "first_stable_cumulative_rank_one_day": (
            result.first_stable_cumulative_rank_one_day
        ),
        "stable_cumulative_identifiable": result.stable_cumulative_identifiable,
    }


def _maximum_absolute_error(left, right) -> float:
    return float(
        np.max(np.abs(np.asarray(left) - np.asarray(right)), initial=0.0)
    )


def _stage_truth_indices(result) -> np.ndarray:
    return np.stack(
        [
            result.truth_candidate_indices[
                :, int(start) + result.adaptation_days
            ]
            for start in result.schedule.stage_start_days
        ],
        axis=1,
    )


def _integrity_checks(result, arrays, process_covariances, observation_std, config):
    covariance_stack = np.stack(
        [process_covariances[key] for key in result.process_ids]
    )
    process_standard_deviations = np.sqrt(
        np.diagonal(covariance_stack, axis1=1, axis2=2)
    )
    scheduled_scales = process_standard_deviations[
        result.schedule.process_indices[:, : result.assimilation_days]
    ]
    expected_perturbations = (
        result.process_standard_normals[:, None, :, :]
        * scheduled_scales[None, :, :, :]
    )
    expected_observations = (
        result.truth_discharge
        + float(observation_std) * result.observation_standard_normals[:, None, :]
    )
    expected_innovations = (
        result.observed_discharge[..., None] - result.candidate_prior_observations
    )
    expected_log_likelihoods = -0.5 * (
        np.log(2.0 * np.pi * result.candidate_innovation_variances)
        + np.square(result.candidate_innovations)
        / result.candidate_innovation_variances
    )
    expected_scored = []
    for start, end in zip(
        result.schedule.stage_start_days, result.schedule.stage_end_days
    ):
        expected_scored.append(
            result.candidate_daily_log_likelihoods[
                ...,
                int(start) + result.adaptation_days : int(end),
                :,
            ]
        )
    expected_scored = np.stack(expected_scored, axis=-3)
    rescored = score_candidate_log_likelihoods(
        expected_scored,
        _stage_truth_indices(result),
        stable_final_days=int(config["stable_final_scoring_days"]),
    )
    score_errors = (
        _maximum_absolute_error(
            result.scored_daily_log_likelihoods, expected_scored
        ),
        _maximum_absolute_error(
            result.cumulative_log_likelihoods,
            rescored.cumulative_log_likelihoods,
        ),
        _maximum_absolute_error(
            result.true_candidate_daily_margins,
            rescored.true_candidate_daily_margins,
        ),
        _maximum_absolute_error(
            result.true_candidate_cumulative_margins,
            rescored.true_candidate_cumulative_margins,
        ),
    )
    ranks_match = bool(
        np.array_equal(
            result.true_candidate_daily_ranks,
            rescored.true_candidate_daily_ranks,
        )
        and np.array_equal(
            result.true_candidate_cumulative_ranks,
            rescored.true_candidate_cumulative_ranks,
        )
        and np.array_equal(
            result.first_cumulative_rank_one_day,
            rescored.first_cumulative_rank_one_day,
        )
        and np.array_equal(
            result.first_stable_cumulative_rank_one_day,
            rescored.first_stable_cumulative_rank_one_day,
        )
        and np.array_equal(
            result.stable_cumulative_identifiable,
            rescored.stable_cumulative_identifiable,
        )
    )
    finite_array_failures = [
        name
        for name, value in arrays.items()
        if np.issubdtype(np.asarray(value).dtype, np.number)
        and not np.all(np.isfinite(value))
    ]
    values = {
        "truth_process_perturbation_reconstruction_maximum_absolute_error": (
            _maximum_absolute_error(
                result.truth_process_perturbations, expected_perturbations
            )
        ),
        "observation_reconstruction_maximum_absolute_error": (
            _maximum_absolute_error(result.observed_discharge, expected_observations)
        ),
        "innovation_reconstruction_maximum_absolute_error": (
            _maximum_absolute_error(result.candidate_innovations, expected_innovations)
        ),
        "log_likelihood_reconstruction_maximum_absolute_error": (
            _maximum_absolute_error(
                result.candidate_daily_log_likelihoods, expected_log_likelihoods
            )
        ),
        "score_reconstruction_maximum_absolute_error": max(score_errors),
        "integer_and_boolean_score_arrays_match": ranks_match,
        "minimum_innovation_variance": float(
            np.min(result.candidate_innovation_variances)
        ),
        "nonfinite_numeric_array_names": finite_array_failures,
        "candidate_filter_update_mode": "independent_filter_step",
        "interacting_multiple_model_step_called": False,
    }
    gates = config["integrity_gates"]
    passed = bool(
        values[
            "truth_process_perturbation_reconstruction_maximum_absolute_error"
        ]
        <= float(
            gates[
                "truth_process_perturbation_reconstruction_maximum_absolute_error"
            ]
        )
        and values["observation_reconstruction_maximum_absolute_error"]
        <= float(gates["observation_reconstruction_maximum_absolute_error"])
        and values["innovation_reconstruction_maximum_absolute_error"]
        <= float(gates["innovation_reconstruction_maximum_absolute_error"])
        and values["log_likelihood_reconstruction_maximum_absolute_error"]
        <= float(gates["log_likelihood_reconstruction_maximum_absolute_error"])
        and values["score_reconstruction_maximum_absolute_error"]
        <= float(gates["score_reconstruction_maximum_absolute_error"])
        and values["integer_and_boolean_score_arrays_match"]
        and values["minimum_innovation_variance"] > 0.0
        and not finite_array_failures
    )
    return {
        **values,
        "integrity_passed": passed,
        "configured_gates": gates,
    }


def _trial_stage_rows(result) -> list[dict]:
    rows = []
    for block_index, block_id in enumerate(result.block_ids):
        for truth_index in range(result.truth_candidate_indices.shape[0]):
            for stage_index in range(3):
                rows.append(
                    {
                        "scenario": result.scenario,
                        "block_id": block_id,
                        "truth_trial_index": truth_index,
                        "stage_number": stage_index + 1,
                        "is_switching_stage": stage_index > 0,
                        "true_candidate_id": result.candidate_ids[
                            int(_stage_truth_indices(result)[truth_index, stage_index])
                        ],
                        "first_cumulative_rank_one_scoring_day": int(
                            result.first_cumulative_rank_one_day[
                                block_index, truth_index, stage_index
                            ]
                        ),
                        "first_stable_cumulative_rank_one_scoring_day": int(
                            result.first_stable_cumulative_rank_one_day[
                                block_index, truth_index, stage_index
                            ]
                        ),
                        "final_cumulative_true_candidate_rank": int(
                            result.true_candidate_cumulative_ranks[
                                block_index, truth_index, stage_index, -1
                            ]
                        ),
                        "final_true_vs_best_wrong_cumulative_log_likelihood_margin": float(
                            result.true_candidate_cumulative_margins[
                                block_index, truth_index, stage_index, -1
                            ]
                        ),
                        "stable_cumulative_identifiable": bool(
                            result.stable_cumulative_identifiable[
                                block_index, truth_index, stage_index
                            ]
                        ),
                    }
                )
    return rows


def _daily_candidate_rows(result) -> list[dict]:
    rows = []
    stage_truth = _stage_truth_indices(result)
    for block_index, block_id in enumerate(result.block_ids):
        for truth_index in range(result.truth_candidate_indices.shape[0]):
            for stage_index, (start, end) in enumerate(
                zip(result.schedule.stage_start_days, result.schedule.stage_end_days)
            ):
                scoring_start = int(start) + result.adaptation_days
                for day in range(int(start), int(end)):
                    scoring_day = day - scoring_start + 1 if day >= scoring_start else 0
                    for candidate_index, candidate_id in enumerate(result.candidate_ids):
                        row = {
                            "scenario": result.scenario,
                            "block_id": block_id,
                            "truth_trial_index": truth_index,
                            "stage_number": stage_index + 1,
                            "assimilation_day_one_based": day + 1,
                            "is_scoring_day": day >= scoring_start,
                            "scoring_day_number": scoring_day,
                            "candidate_id": candidate_id,
                            "is_true_candidate": candidate_index
                            == int(stage_truth[truth_index, stage_index]),
                            "prior_observation": float(
                                result.candidate_prior_observations[
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "innovation": float(
                                result.candidate_innovations[
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "innovation_variance": float(
                                result.candidate_innovation_variances[
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "daily_log_likelihood": float(
                                result.candidate_daily_log_likelihoods[
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "stage_cumulative_log_likelihood": None,
                        }
                        if scoring_day > 0:
                            row["stage_cumulative_log_likelihood"] = float(
                                result.cumulative_log_likelihoods[
                                    block_index,
                                    truth_index,
                                    stage_index,
                                    scoring_day - 1,
                                    candidate_index,
                                ]
                            )
                        rows.append(row)
    return rows


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


def _snapshot_source_paths() -> tuple[str, ...]:
    return (
        "src/hbv_multilead_joint_uncertainty/candidate_likelihood_identifiability.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_candidate_likelihood_identifiability.py",
        "src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_three_stage_switching_validation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_model_probability_validation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_process_noise_identification_validation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_synthetic_truth_validation.py",
        "src/hbv_multilead_joint_uncertainty/methods.py",
        "src/hbv_multilead_joint_uncertainty/synthetic_truth.py",
        "src/hbv_joint_uncertainty/hbv_adapter.py",
        "src/hbv_joint_uncertainty/imm.py",
        "src/hbv_joint_uncertainty/preflight.py",
        "src/hbv_joint_uncertainty/sigma_filter.py",
        "src/scl_hydro/hbv_lite_numpy.py",
        "test/test_hbv_candidate_likelihood_identifiability.py",
    )


def _source_snapshot(root: Path, destination: Path) -> None:
    canonical_destination = _windows_extended_length_path(destination)
    canonical_destination.mkdir(parents=True, exist_ok=False)
    for configured in _snapshot_source_paths():
        source = (root / configured).resolve()
        if not source.is_file():
            raise FileNotFoundError(f"source snapshot file is missing: {configured}")
        target = canonical_destination / configured.replace("/", "__")
        shutil.copy2(_windows_extended_length_path(source), target)


def _checksums_for_directory(directory: Path) -> dict[str, str]:
    """Hash every file through the same extended-length path namespace."""

    canonical = _windows_extended_length_path(directory)
    return {
        path.relative_to(canonical).as_posix(): _sha256(path)
        for path in sorted(canonical.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    preregistration_path = output.with_name(output.name + ".preregistered.json")
    if output.exists() or incomplete.exists() or preregistration_path.exists():
        raise FileExistsError("refusing to overwrite existing evidence")
    config_bytes = config_file.read_bytes()
    config_hash = hashlib.sha256(config_bytes).hexdigest()
    config = json.loads(config_bytes.decode("utf-8"))
    if output.name != str(config["experiment_id"]):
        raise ValueError("output directory name must equal experiment_id")
    if config.get("dataset_role") not in {"development", "confirmation"}:
        raise ValueError("dataset_role must be development or confirmation")
    blocks = _validated_blocks(config)
    lengths = tuple(int(value) for value in config["stage_lengths"])
    scoring_days = {
        value - int(config["adaptation_days_excluded_per_stage"])
        for value in lengths
    }
    if len(scoring_days) != 1 or next(iter(scoring_days)) <= 0:
        raise ValueError("all stages must leave the same positive scoring-day count")
    if int(config["stable_final_scoring_days"]) > next(iter(scoring_days)):
        raise ValueError("stable_final_scoring_days exceeds the scoring window")
    _validate_fixed_decision_contract(config, next(iter(scoring_days)))

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
        "dataset_role": config["dataset_role"],
        "scenario": config["scenario"],
        "decision_rules": config["decision_rules"],
        "bootstrap": config["bootstrap"],
        "adaptation_days_excluded_per_stage": config[
            "adaptation_days_excluded_per_stage"
        ],
        "stable_final_scoring_days": config["stable_final_scoring_days"],
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
    resource = _resource_preflight(config)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))
    forcing = _forcing_blocks(config, blocks)
    result = run_candidate_likelihood_identifiability(
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
        stage_lengths=lengths,
        adaptation_days=int(config["adaptation_days_excluded_per_stage"]),
        initial_covariance_fraction=float(config["initial_covariance_fraction"]),
        observation_standard_deviation=observation_std,
    )
    evaluation = evaluate_candidate_likelihood_identifiability(
        result,
        bootstrap_replicates=int(config["bootstrap"]["replicates"]),
        bootstrap_seed=int(config["bootstrap"]["seed"]),
        stable_fraction_minimum=float(
            config["decision_rules"]["stable_identifiable_fraction_minimum"]
        ),
        bootstrap_lower_minimum=float(
            config["decision_rules"][
                "stable_fraction_block_bootstrap_lower_strict_minimum"
            ]
        ),
        median_final_margin_minimum=float(
            config["decision_rules"]["median_final_margin_strict_minimum"]
        ),
    )
    arrays = _evidence_arrays(
        result, parameter_vectors, process_covariances, observation_std
    )
    integrity = _integrity_checks(
        result, arrays, process_covariances, observation_std, config
    )

    incomplete.mkdir(parents=True, exist_ok=False)
    try:
        (incomplete / "config_snapshot.json").write_bytes(config_bytes)
        (incomplete / "preregistration.json").write_bytes(
            preregistration_path.read_bytes()
        )
        _json_write(incomplete / "resource_preflight.json", resource)
        _json_write(incomplete / "integrity_checks.json", integrity)
        _json_write(incomplete / "scientific_evaluation.json", evaluation)
        _json_write(incomplete / "environment.json", _environment(root, started_at))
        (incomplete / "parameter_vectors.csv").write_bytes(parameter_csv)
        (incomplete / "process_noise_covariances.csv").write_bytes(process_csv)
        (incomplete / "observation_noise.csv").write_bytes(observation_csv)
        pd.DataFrame(_daily_candidate_rows(result)).to_csv(
            incomplete / "candidate_daily_log_likelihood.csv",
            index=False,
            lineterminator="\n",
        )
        pd.DataFrame(_trial_stage_rows(result)).to_csv(
            incomplete / "trial_stage_identifiability.csv",
            index=False,
            lineterminator="\n",
        )
        pd.DataFrame(evaluation["stage_results"]).to_csv(
            incomplete / "stage_identifiability.csv",
            index=False,
            lineterminator="\n",
        )
        np.savez_compressed(incomplete / "evidence.npz", **arrays)
        _source_snapshot(root, incomplete / "source_snapshot")
        protected_after = _protected_hashes(
            root, config.get("protected_paths", ())
        )
        protected_unchanged = protected_before == protected_after
        integrity_passed = bool(
            integrity["integrity_passed"] and protected_unchanged
        )
        summary = {
            "experiment_id": config["experiment_id"],
            "dataset_role": config["dataset_role"],
            "scenario": config["scenario"],
            "integrity_status": "passed" if integrity_passed else "failed",
            "scientific_status": evaluation["scientific_status"],
            "switching_stages_passed": evaluation["switching_stages_passed"],
            "protected_artifacts_unchanged": protected_unchanged,
            "candidate_state_interaction_used": False,
            "candidate_weight_transition_or_update_used": False,
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
        checksums = _checksums_for_directory(incomplete)
        _json_write(incomplete / "checksums.json", checksums)
        if not integrity_passed:
            raise RuntimeError("numerical or protected-artifact integrity gate failed")
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
