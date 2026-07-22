"""Run and package fixed-label, physically projected nine-filter validation."""

from __future__ import annotations

import argparse
import datetime as dt
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
from hbv_joint_uncertainty.preflight import (  # noqa: E402
    ForcingTransition,
    RoutedDischargeObservation,
)
from hbv_multilead_joint_uncertainty.joint_method_validation import (  # noqa: E402
    METHOD_NAMES,
    run_stable_joint_method_validation,
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
    _atomic_json_write,
    _environment_manifest,
    _json_write,
    _protected_hashes,
    _sha256,
)


REQUIRED_EVIDENCE_FILES = frozenset(
    {
        "conda_packages.json",
        "condition_decisions.json",
        "config_snapshot.json",
        "environment.json",
        "evidence.npz",
        "git_status.txt",
        "installed_packages.json",
        "joint_method_certificate.json",
        "method_metrics.csv",
        "observation_noise.csv",
        "paired_comparisons.csv",
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
        "source_snapshot/joint_method_validation.py",
        "source_snapshot/methods.py",
        "source_snapshot/preflight.py",
        "source_snapshot/run_joint_method_validation.py",
        "source_snapshot/run_model_probability_validation.py",
        "source_snapshot/run_process_noise_identification_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/sigma_filter.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_joint_method_validation.py",
        "summary.json",
    }
)

TRUTH_CONDITION = (
    "fixed complete parameter label with projected candidate-scale process truth"
)
TRUTH_PROCESS_SCOPE = (
    "The frozen candidate covariance controls only the pre-projection perturbation scale; "
    "the post-projection truth is not an exact additive Gaussian candidate model."
)


def _truth_condition(config: dict) -> str:
    if config.get("truth_switch_period_days") is not None:
        return (
            "periodically switching complete parameter and process-scale labels with "
            "projected candidate-scale process truth"
        )
    return TRUTH_CONDITION


def _forcing_blocks(config: dict, blocks: tuple[dict, ...]) -> np.ndarray:
    forcing = config["forcing"]
    days = (
        int(forcing["warmup_days"])
        + int(config["assimilation_days"])
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
            float(forcing["rain_shape"]), float(forcing["rain_scale"]), size=days
        )
        result[index, :, 1] = np.maximum(0.0, 2.0 + np.sin(angle))
        result[index, :, 2] = 4.0 + 12.0 * np.sin(angle - np.pi / 2.0)
    return result


def _expected_numeric_array_bytes(config: dict) -> int:
    blocks = len(config["matched_blocks"])
    warmup = int(config["forcing"]["warmup_days"])
    assimilation = int(config["assimilation_days"])
    leads = len(config["lead_days"])
    maximum_lead = int(max(config["lead_days"]))
    active = assimilation + maximum_lead
    truth = 9
    methods = 6
    candidates = 9
    states = 15
    float_shapes = [
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
        (blocks, truth, methods, leads),
        (blocks, truth, methods, leads, candidates),
        (blocks, truth, methods, leads, candidates),
        (blocks, truth, methods, states),
        (blocks, truth, methods),
        (blocks, truth, methods, leads),
        (blocks, truth, truth),
        (blocks, truth),
        (blocks, truth),
        (blocks, truth),
        (5,),
    ]
    integer_shapes = [(blocks,), (blocks,), (leads,), (methods,)]
    if config.get("truth_switch_period_days") is not None:
        integer_shapes.append((truth, active))
    return int(
        sum(int(np.prod(shape)) * np.dtype(np.float64).itemsize for shape in float_shapes)
        + sum(int(np.prod(shape)) * np.dtype(np.int64).itemsize for shape in integer_shapes)
    )


def _resource_preflight(config: dict) -> dict:
    expected = _expected_numeric_array_bytes(config)
    pilot = config["resource_pilot"]
    pilot_growth = int(pilot["observed_resident_memory_growth_bytes"])
    estimated_peak = int(4 * expected + 2 * pilot_growth + 128 * 1024 * 1024)
    available = int(psutil.virtual_memory().available)
    reserve = int(max(estimated_peak // 2, 256 * 1024 * 1024))
    required = estimated_peak + reserve
    safe = available >= required
    pilot_active = int(pilot["assimilation_days"]) + int(pilot["maximum_lead_days"])
    formal_active = int(config["assimilation_days"]) + int(max(config["lead_days"]))
    runtime_estimate = float(pilot["elapsed_seconds"]) * len(config["matched_blocks"]) * (
        formal_active / pilot_active
    )
    result = {
        "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "matched_block_count": len(config["matched_blocks"]),
        "truth_candidate_count_per_block": 9,
        "method_count": 6,
        "joint_candidate_count": 9,
        "state_dimension": 15,
        "assimilation_days": int(config["assimilation_days"]),
        "maximum_lead_days": int(max(config["lead_days"])),
        "execution_parallelism": 1,
        "expected_saved_numeric_array_bytes": expected,
        "pilot_observed_resident_memory_growth_bytes": pilot_growth,
        "estimated_additional_peak_memory_bytes": estimated_peak,
        "available_physical_memory_bytes": available,
        "task_specific_reserve_bytes": reserve,
        "task_specific_required_available_bytes": required,
        "available_after_estimated_peak_bytes": available - estimated_peak,
        "estimated_runtime_seconds_from_pilot": runtime_estimate,
        "safe_to_run": safe,
        "estimation_basis": (
            "four copies of every saved numeric array, twice the measured one-block pilot "
            "resident-memory growth and 128 MiB for sequential filter and compressed-output work; "
            "the task reserve is the larger of half the estimate and 256 MiB"
        ),
        "universal_memory_threshold_used": False,
        "resource_pilot": pilot,
    }
    if not safe:
        raise MemoryError("stable joint-method validation lacks its task-specific memory margin")
    return result


def _maximum_error(left, right) -> float:
    return float(np.max(np.abs(np.asarray(left) - np.asarray(right)), initial=0.0))


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


def _bootstrap_mean_interval(
    values: np.ndarray, replicates: int, seed: int
) -> tuple[float, float]:
    if values.ndim != 1 or len(values) == 0 or replicates <= 0:
        raise ValueError("bootstrap values and replicates must be nonempty")
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(replicates, len(values)))
    statistics = np.mean(values[indices], axis=1)
    lower, upper = np.quantile(statistics, [0.025, 0.975])
    return float(lower), float(upper)


def _metric_tables(result, config: dict) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    method_index = {name: index for index, name in enumerate(result.method_names)}
    block_count = len(result.block_ids)
    block_forecast_rmse = np.sqrt(
        np.mean(np.square(result.method_absolute_errors), axis=1)
    )
    rows = []
    for method, index in method_index.items():
        for lead_index, lead in enumerate(result.forecast_lead_days):
            errors = result.method_absolute_errors[:, :, index, lead_index]
            rows.append(
                {
                    "metric": "forecast_discharge",
                    "method": method,
                    "lead_days": int(lead),
                    "root_mean_square_error": float(np.sqrt(np.mean(np.square(errors)))),
                    "median_absolute_error": float(np.median(errors)),
                    "matched_block_count": block_count,
                    "truth_condition_count_per_block": 9,
                }
            )
        state_errors = result.method_origin_state_normalized_root_mean_square_errors[
            :, :, index
        ]
        rows.append(
            {
                "metric": "origin_hydrologic_state",
                "method": method,
                "lead_days": 0,
                "root_mean_square_error": float(
                    np.sqrt(np.mean(np.square(state_errors)))
                ),
                "median_absolute_error": float(np.median(state_errors)),
                "matched_block_count": block_count,
                "truth_condition_count_per_block": 9,
            }
        )
    method_metrics = pd.DataFrame(rows)

    bootstrap = config["bootstrap"]
    replicates = int(bootstrap["replicates"])
    seed = int(bootstrap["seed"])
    joint = method_index["joint"]
    controls = ("open_loop", "fixed_filter", "parameter_only", "noise_only", "oracle_filter")
    comparison_rows = []
    for lead_index, lead in enumerate(result.forecast_lead_days):
        joint_global = float(
            np.sqrt(np.mean(np.square(result.method_absolute_errors[:, :, joint, lead_index])))
        )
        for comparison_index, control in enumerate(controls):
            control_index = method_index[control]
            control_global = float(
                np.sqrt(
                    np.mean(
                        np.square(
                            result.method_absolute_errors[:, :, control_index, lead_index]
                        )
                    )
                )
            )
            differences = (
                block_forecast_rmse[:, joint, lead_index]
                - block_forecast_rmse[:, control_index, lead_index]
            )
            lower, upper = _bootstrap_mean_interval(
                differences,
                replicates,
                seed + 100 * lead_index + comparison_index,
            )
            comparison_rows.append(
                {
                    "metric": "forecast_discharge",
                    "lead_days": int(lead),
                    "control_method": control,
                    "joint_root_mean_square_error": joint_global,
                    "control_root_mean_square_error": control_global,
                    "joint_relative_improvement_percent": (
                        100.0 * (control_global - joint_global) / control_global
                    ),
                    "mean_paired_block_root_mean_square_error_difference": float(
                        np.mean(differences)
                    ),
                    "paired_block_difference_bootstrap_lower": lower,
                    "paired_block_difference_bootstrap_upper": upper,
                    "joint_better_block_count": int(np.count_nonzero(differences < 0.0)),
                    "matched_block_count": block_count,
                }
            )
    state_block_rmse = np.sqrt(
        np.mean(
            np.square(result.method_origin_state_normalized_root_mean_square_errors),
            axis=1,
        )
    )
    joint_state_global = float(
        np.sqrt(
            np.mean(
                np.square(
                    result.method_origin_state_normalized_root_mean_square_errors[
                        :, :, joint
                    ]
                )
            )
        )
    )
    for comparison_index, control in enumerate(controls):
        control_index = method_index[control]
        control_global = float(
            np.sqrt(
                np.mean(
                    np.square(
                        result.method_origin_state_normalized_root_mean_square_errors[
                            :, :, control_index
                        ]
                    )
                )
            )
        )
        differences = state_block_rmse[:, joint] - state_block_rmse[:, control_index]
        lower, upper = _bootstrap_mean_interval(
            differences, replicates, seed + 1000 + comparison_index
        )
        comparison_rows.append(
            {
                "metric": "origin_hydrologic_state",
                "lead_days": 0,
                "control_method": control,
                "joint_root_mean_square_error": joint_state_global,
                "control_root_mean_square_error": control_global,
                "joint_relative_improvement_percent": (
                    100.0 * (control_global - joint_state_global) / control_global
                ),
                "mean_paired_block_root_mean_square_error_difference": float(
                    np.mean(differences)
                ),
                "paired_block_difference_bootstrap_lower": lower,
                "paired_block_difference_bootstrap_upper": upper,
                "joint_better_block_count": int(np.count_nonzero(differences < 0.0)),
                "matched_block_count": block_count,
            }
        )
    paired = pd.DataFrame(comparison_rows)

    probability_grid = result.joint_origin_probabilities.reshape(
        block_count, 9, 3, 3
    )
    candidate_truth = np.arange(9)[None, :]
    parameter_truth = np.repeat(np.arange(3), 3)[None, :]
    process_truth = np.tile(np.arange(3), 3)[None, :]
    identification = {
        "joint_candidate_argmax_accuracy": float(
            np.mean(np.argmax(result.joint_origin_probabilities, axis=2) == candidate_truth)
        ),
        "joint_parameter_argmax_accuracy": float(
            np.mean(np.argmax(probability_grid.sum(axis=3), axis=2) == parameter_truth)
        ),
        "joint_process_argmax_accuracy": float(
            np.mean(np.argmax(probability_grid.sum(axis=2), axis=2) == process_truth)
        ),
        "median_joint_true_candidate_probability": float(
            np.median(result.joint_origin_true_probabilities)
        ),
        "median_joint_true_parameter_probability": float(
            np.median(result.joint_origin_true_parameter_probabilities)
        ),
        "median_joint_true_process_probability": float(
            np.median(result.joint_origin_true_process_probabilities)
        ),
    }
    decisions = config["decision_rules"]
    minimum_improvement = float(
        decisions["practical_relative_root_mean_square_error_improvement_percent_minimum"]
    )
    maximum_upper = float(
        decisions["paired_block_root_mean_square_error_difference_upper_maximum"]
    )
    lead_decisions = []
    for lead in result.forecast_lead_days:
        selected = paired.loc[
            (paired["metric"] == "forecast_discharge")
            & (paired["lead_days"] == int(lead))
        ].set_index("control_method")
        fixed_effect = bool(
            selected.loc["fixed_filter", "joint_relative_improvement_percent"]
            >= minimum_improvement
            and selected.loc[
                "fixed_filter", "paired_block_difference_bootstrap_upper"
            ]
            < maximum_upper
        )
        added = bool(
            fixed_effect
            and selected.loc[
                "parameter_only", "paired_block_difference_bootstrap_upper"
            ]
            < maximum_upper
            and selected.loc[
                "noise_only", "paired_block_difference_bootstrap_upper"
            ]
            < maximum_upper
        )
        lead_decisions.append(
            {
                "lead_days": int(lead),
                "effective_against_fixed_filter": fixed_effect,
                "added_value_beyond_both_single_factor_methods": added,
            }
        )
    state_selected = paired.loc[
        paired["metric"] == "origin_hydrologic_state"
    ].set_index("control_method")
    state_fixed_effect = bool(
        state_selected.loc["fixed_filter", "joint_relative_improvement_percent"]
        >= minimum_improvement
        and state_selected.loc[
            "fixed_filter", "paired_block_difference_bootstrap_upper"
        ]
        < maximum_upper
    )
    origin_state_decision = {
        "effective_against_fixed_filter": state_fixed_effect,
        "added_value_beyond_both_single_factor_methods": bool(
            state_fixed_effect
            and state_selected.loc[
                "parameter_only", "paired_block_difference_bootstrap_upper"
            ]
            < maximum_upper
            and state_selected.loc[
                "noise_only", "paired_block_difference_bootstrap_upper"
            ]
            < maximum_upper
        ),
    }
    identification_effective = bool(
        identification["joint_candidate_argmax_accuracy"]
        >= float(decisions["joint_candidate_argmax_accuracy_minimum"])
        and identification["joint_parameter_argmax_accuracy"]
        >= float(decisions["joint_parameter_argmax_accuracy_minimum"])
        and identification["joint_process_argmax_accuracy"]
        >= float(decisions["joint_process_argmax_accuracy_minimum"])
        and identification["median_joint_true_candidate_probability"]
        >= float(decisions["median_joint_true_candidate_probability_minimum"])
    )
    projection_events = np.any(
        result.truth_projection_adjustments != 0.0,
        axis=-1,
    )
    truth_process_interpretation = {
        "pre_projection_covariance_uses_frozen_candidate": True,
        "post_projection_distribution_matches_additive_gaussian_candidate": False,
        "projection_event_count": int(np.count_nonzero(projection_events)),
        "projection_event_total": int(projection_events.size),
        "projection_event_fraction": float(np.mean(projection_events)),
        "interpretation": TRUTH_PROCESS_SCOPE,
    }
    condition_decisions = {
        "condition": _truth_condition(config),
        "lead_decisions": lead_decisions,
        "origin_state_decision": origin_state_decision,
        "truth_process_interpretation": truth_process_interpretation,
        "identification": identification,
        "joint_identification_effective": identification_effective,
        "oracle_filter_interpretation": {
            "dynamic_oracle": False,
            "interpretation": (
                "For switching truth, this diagnostic uses the candidate that is true at the "
                "forecast origin for the entire assimilation history; it is not a dynamically "
                "switching oracle and is excluded from scientific control decisions."
                if config.get("truth_switch_period_days") is not None
                else "For fixed truth, this diagnostic uses the fixed true candidate and is excluded from scientific control decisions."
            ),
        },
        "decision_rules": decisions,
        "interpretation_rule": (
            "These scientific decisions are reported whether positive or negative and do not "
            "determine the numerical-integrity status of the experiment."
        ),
    }
    return method_metrics, paired, condition_decisions


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
            raise RuntimeError(f"joint-method validation failed; see {output / 'summary.json'}")
        return summary
    if incomplete.exists() or registry.exists() or preregistry.exists():
        raise FileExistsError("refusing to overwrite incomplete evidence or registry")

    blocks = _validated_blocks(config)
    vectors, parameter_csv, parameter_snapshot_hash = _load_parameter_vectors(root, config)
    covariances, scales, process_csv, process_snapshot_hash = _load_process_covariances(
        root, config
    )
    observation_std, observation_csv, observation_snapshot_hash = _load_observation_noise(
        root, config
    )
    if not np.isclose(
        observation_std,
        float(config["observation_noise_source"]["standard_deviation_mm_day"]),
        rtol=0.0,
        atol=1e-15,
    ):
        raise ValueError("loaded observation standard deviation differs from the frozen config")
    forcing = _forcing_blocks(config, blocks)
    registered_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "experiment_id": config["experiment_id"],
        "status": "preregistered",
        "registered_at": registered_at,
        "config_sha256": _sha256(config_file),
        "matched_blocks": [dict(value) for value in blocks],
        "truth_candidate_count_per_block": 9,
        "method_names": list(METHOD_NAMES),
        "assimilation_days": int(config["assimilation_days"]),
        "lead_days": list(config["lead_days"]),
        "truth_switch_period_days": config.get("truth_switch_period_days"),
        "truth_switch_candidate_step": config.get("truth_switch_candidate_step"),
        "decision_rules": config["decision_rules"],
        "integrity_gates": config["integrity_gates"],
    }
    _atomic_json_write(preregistry, preregistration)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    resource = _resource_preflight(config)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))
    result = run_stable_joint_method_validation(
        forcing_blocks=forcing,
        block_ids=tuple(str(value["block_id"]) for value in blocks),
        parameter_vectors=vectors,
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id=str(config["process_noise_source"]["selected_process_id"]),
        process_noise_seeds=tuple(int(value["process_noise_seed"]) for value in blocks),
        observation_noise_seeds=tuple(int(value["observation_noise_seed"]) for value in blocks),
        warmup_days=int(config["forcing"]["warmup_days"]),
        assimilation_days=int(config["assimilation_days"]),
        lead_days=tuple(int(value) for value in config["lead_days"]),
        initial_covariance_fraction=float(config["initial_covariance_fraction"]),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=float(config["factor_transition_stay_probability"]),
        truth_switch_period_days=config.get("truth_switch_period_days"),
        truth_switch_candidate_step=int(config.get("truth_switch_candidate_step", 4)),
        state_normalization_scales=config["state_normalization_scales"],
    )
    parameter_vectors = np.asarray(
        [[vectors[key][name] for name in PARAMETER_NAMES] for key in result.parameter_ids],
        dtype=np.float64,
    )
    process_covariances = np.stack([covariances[key] for key in result.process_ids])
    evidence_arrays = {
        "block_ids": np.asarray(result.block_ids),
        "process_noise_seeds": result.process_noise_seeds,
        "observation_noise_seeds": result.observation_noise_seeds,
        "forcing_blocks": result.forcing_blocks,
        "parameter_ids": np.asarray(result.parameter_ids),
        "process_ids": np.asarray(result.process_ids),
        "truth_candidate_ids": np.asarray(result.truth_candidate_ids),
        "truth_candidate_factors": np.asarray(result.truth_candidate_factors),
        "method_names": np.asarray(result.method_names),
        "method_candidate_ids": np.asarray(
            [values + ("",) * (9 - len(values)) for values in result.method_candidate_ids]
        ),
        "parameter_vectors": parameter_vectors,
        "process_covariances": process_covariances,
        "observation_standard_deviation": np.asarray(observation_std),
        "forecast_lead_days": result.forecast_lead_days,
        "method_candidate_counts": result.method_candidate_counts,
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
        "method_predictions": result.method_predictions,
        "method_candidate_predictions": result.method_candidate_predictions,
        "method_probabilities": result.method_probabilities,
        "method_origin_states": result.method_origin_states,
        "method_origin_state_normalized_root_mean_square_errors": result.method_origin_state_normalized_root_mean_square_errors,
        "method_absolute_errors": result.method_absolute_errors,
        "joint_origin_probabilities": result.joint_origin_probabilities,
        "joint_origin_true_probabilities": result.joint_origin_true_probabilities,
        "joint_origin_true_parameter_probabilities": result.joint_origin_true_parameter_probabilities,
        "joint_origin_true_process_probabilities": result.joint_origin_true_process_probabilities,
        "state_normalization_scales": result.state_normalization_scales,
    }
    if config.get("truth_switch_period_days") is not None:
        evidence_arrays["truth_candidate_schedules"] = result.truth_candidate_schedules
    finiteness = _numeric_finiteness(evidence_arrays)

    transition_error = 0.0
    observation_error = 0.0
    active_forcing = result.forcing_blocks[:, result.warmup_days :]
    parameter_lookup = {key: vectors[key] for key in result.parameter_ids}
    parameter_state_index = {key: index for index, key in enumerate(result.parameter_ids)}
    for block in range(len(result.block_ids)):
        for truth_index in range(len(result.truth_candidate_factors)):
            initial_candidate_index = int(result.truth_candidate_schedules[truth_index, 0])
            initial_parameter_id = result.truth_candidate_factors[
                initial_candidate_index
            ][0]
            previous = result.initial_parameter_states[
                block, parameter_state_index[initial_parameter_id]
            ]
            for day, (rain, potential_evaporation, temperature) in enumerate(
                active_forcing[block]
            ):
                candidate_index = int(result.truth_candidate_schedules[truth_index, day])
                parameter_id = result.truth_candidate_factors[candidate_index][0]
                transition = ForcingTransition(parameter_lookup[parameter_id])
                observation = RoutedDischargeObservation(parameter_lookup[parameter_id])
                transition.set_forcing(rain, potential_evaporation, temperature)
                transition_error = max(
                    transition_error,
                    _maximum_error(
                        transition(previous),
                        result.truth_deterministic_states[block, truth_index, day],
                    ),
                )
                observation_error = max(
                    observation_error,
                    abs(
                        float(observation(result.truth_states[block, truth_index, day])[0])
                        - float(result.truth_discharge[block, truth_index, day])
                    ),
                )
                previous = result.truth_states[block, truth_index, day]
    expected_perturbations = np.empty_like(result.truth_process_perturbations)
    for truth_index in range(len(result.truth_candidate_factors)):
        for day, candidate_index in enumerate(result.truth_candidate_schedules[truth_index]):
            process_id = result.truth_candidate_factors[int(candidate_index)][1]
            expected_perturbations[:, truth_index, day] = (
                result.process_standard_normals[:, day]
                * np.sqrt(np.diag(covariances[process_id]))[None, :]
            )
    perturbation_error = _maximum_error(
        result.truth_process_perturbations, expected_perturbations
    )
    observation_reconstruction_error = _maximum_error(
        result.observed_discharge,
        result.truth_discharge
        + observation_std * result.observation_standard_normals[:, None, :],
    )
    mixture_errors = []
    probability_sum_errors = []
    minimum_probability = np.inf
    for method_index, count in enumerate(result.method_candidate_counts):
        active = slice(0, int(count))
        reconstructed = np.sum(
            result.method_probabilities[:, :, method_index, :, active]
            * result.method_candidate_predictions[:, :, method_index, :, active],
            axis=-1,
        )
        mixture_errors.append(
            _maximum_error(result.method_predictions[:, :, method_index], reconstructed)
        )
        probability_sum_errors.append(
            _maximum_error(
                result.method_probabilities[:, :, method_index, :, active].sum(axis=-1),
                1.0,
            )
        )
        minimum_probability = min(
            minimum_probability,
            float(
                np.min(result.method_probabilities[:, :, method_index, :, active])
            ),
        )
    mixture_error = max(mixture_errors)
    probability_sum_error = max(probability_sum_errors)
    gate_values = {
        "independent_truth_transition_maximum_absolute_error": transition_error,
        "independent_truth_observation_maximum_absolute_error": observation_error,
        "truth_process_perturbation_reconstruction_maximum_absolute_error": perturbation_error,
        "observation_reconstruction_maximum_absolute_error": observation_reconstruction_error,
        "method_mixture_reconstruction_maximum_absolute_error": mixture_error,
        "method_probability_sum_maximum_absolute_error": probability_sum_error,
        "minimum_method_probability": minimum_probability,
        "all_saved_numeric_arrays_finite": finiteness["all_numeric_arrays_finite"],
    }
    gates = config["integrity_gates"]
    integrity_gate_pass = bool(
        transition_error <= float(gates["independent_truth_transition_maximum_absolute_error"])
        and observation_error <= float(gates["independent_truth_observation_maximum_absolute_error"])
        and perturbation_error <= float(gates["truth_process_perturbation_reconstruction_maximum_absolute_error"])
        and observation_reconstruction_error <= float(gates["observation_reconstruction_maximum_absolute_error"])
        and mixture_error <= float(gates["method_mixture_reconstruction_maximum_absolute_error"])
        and probability_sum_error <= float(gates["method_probability_sum_maximum_absolute_error"])
        and minimum_probability >= float(gates["minimum_method_probability"])
        and finiteness["all_numeric_arrays_finite"]
    )
    method_metrics, paired_comparisons, decisions = _metric_tables(result, config)
    projection_event_count = int(
        np.count_nonzero(np.any(result.truth_projection_adjustments != 0.0, axis=-1))
    )
    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    protected_unchanged = protected_before == protected_after
    passed = bool(integrity_gate_pass and protected_unchanged)
    finished_at = dt.datetime.now(dt.timezone.utc).isoformat()
    truth_condition = _truth_condition(config)
    switching_truth = config.get("truth_switch_period_days") is not None
    certificate = {
        "experiment_id": config["experiment_id"],
        "check_type": f"complete nine-filter joint-method validation under {truth_condition}",
        "truth_process_scope": TRUTH_PROCESS_SCOPE,
        "truth_switch_period_days": config.get("truth_switch_period_days"),
        "truth_switch_candidate_step": config.get("truth_switch_candidate_step"),
        "matched_block_count": len(blocks),
        "truth_candidate_count_per_block": 9,
        "method_names": list(result.method_names),
        "lead_days": result.forecast_lead_days.tolist(),
        "gate_values": gate_values,
        "integrity_gates": gates,
        "saved_numeric_array_names": finiteness["numeric_array_names"],
        "nonfinite_saved_numeric_array_names": finiteness["nonfinite_numeric_array_names"],
        "integrity_gate_pass": integrity_gate_pass,
        "scientific_decisions": decisions,
        "scope_limit": config["scope_limit"],
    }
    summary = {
        "experiment_id": config["experiment_id"],
        "status": "passed" if passed else "failed",
        "started_at": started_at,
        "finished_at": finished_at,
        "matched_block_count": len(blocks),
        "trial_count": len(blocks) * 9,
        "truth_candidate_count_per_block": 9,
        "method_count": len(result.method_names),
        "method_names": list(result.method_names),
        "method_candidate_counts": result.method_candidate_counts.tolist(),
        "assimilation_days": result.assimilation_days,
        "lead_days": result.forecast_lead_days.tolist(),
        "state_dimension": 15,
        "truth_condition": truth_condition,
        "truth_process_scope": TRUTH_PROCESS_SCOPE,
        "truth_switch_period_days": config.get("truth_switch_period_days"),
        "truth_switch_candidate_step": config.get("truth_switch_candidate_step"),
        "projection_event_count": projection_event_count,
        "projection_event_total": int(len(blocks) * 9 * result.truth_states.shape[2]),
        "gate_values": gate_values,
        "integrity_gates": gates,
        "integrity_gate_pass": integrity_gate_pass,
        "scientific_decisions": decisions,
        "saved_numeric_array_count": len(finiteness["numeric_array_names"]),
        "nonfinite_saved_numeric_array_names": finiteness["nonfinite_numeric_array_names"],
        "parameter_source_sha256": config["parameter_source"]["sha256"],
        "process_noise_source_sha256": config["process_noise_source"]["sha256"],
        "observation_noise_source_sha256": config["observation_noise_source"]["sha256"],
        "selected_parameter_snapshot_sha256": parameter_snapshot_hash,
        "selected_process_noise_snapshot_sha256": process_snapshot_hash,
        "selected_observation_noise_snapshot_sha256": observation_snapshot_hash,
        "protected_artifacts_unchanged": protected_unchanged,
        "scope_limit": config["scope_limit"],
    }
    registry_entry = {
        "experiment_id": config["experiment_id"],
        "type": (
            "closed_truth_periodic_switching_nine_filter_joint_method"
            if switching_truth
            else "closed_truth_stable_nine_filter_joint_method"
        ),
        "hypothesis": (
            "the complete joint method retains identification and forecast value when complete "
            "parameter and process-scale labels switch periodically"
            if switching_truth
            else "the complete joint method adds value under a fixed complete parameter label and physically projected candidate-scale pre-projection perturbations"
        ),
        "base_config": str(config_file),
        "changed_factor": (
            "the periodically switching complete parameter and process-scale truth schedule"
            if switching_truth
            else "which frozen complete parameter label and pre-projection covariance scale generate physically projected truth"
        ),
        "fixed_factors": (
            f"matched forcing and random draws, {result.assimilation_days} assimilation "
            "days, full interaction and one-, three-, seven-day leads"
        ),
        "seeds": [dict(value) for value in blocks],
        "status": summary["status"],
        "run_dir": str(output),
        "metrics_path": str(output / "method_metrics.csv"),
        "paper_name": f"{truth_condition} condition",
        "truth_condition": truth_condition,
        "truth_process_scope": TRUTH_PROCESS_SCOPE,
        "truth_switch_period_days": config.get("truth_switch_period_days"),
        "truth_switch_candidate_step": config.get("truth_switch_candidate_step"),
        "notes": config["scope_limit"],
    }
    environment, git_status, installed_packages, conda_packages, pip_freeze = (
        _environment_manifest(root, started_at)
    )
    protected_integrity = {
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
        (incomplete / "observation_noise.csv").write_bytes(observation_csv)
        _json_write(incomplete / "preregistration.json", preregistration)
        _json_write(incomplete / "summary.json", summary)
        _json_write(incomplete / "joint_method_certificate.json", certificate)
        _json_write(incomplete / "condition_decisions.json", decisions)
        _json_write(incomplete / "registry_entry.json", registry_entry)
        _json_write(incomplete / "resource_preflight.json", resource)
        _json_write(incomplete / "environment.json", environment)
        _json_write(incomplete / "installed_packages.json", installed_packages)
        _json_write(incomplete / "conda_packages.json", conda_packages)
        _json_write(incomplete / "protected_artifact_integrity.json", protected_integrity)
        (incomplete / "git_status.txt").write_text(git_status + "\n", encoding="utf-8")
        (incomplete / "pip_freeze.txt").write_text(pip_freeze, encoding="utf-8")
        method_metrics.to_csv(incomplete / "method_metrics.csv", index=False)
        paired_comparisons.to_csv(incomplete / "paired_comparisons.csv", index=False)
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
            "joint_method_validation.py": root / "src" / "hbv_multilead_joint_uncertainty" / "joint_method_validation.py",
            "methods.py": root / "src" / "hbv_multilead_joint_uncertainty" / "methods.py",
            "synthetic_truth.py": root / "src" / "hbv_multilead_joint_uncertainty" / "synthetic_truth.py",
            "run_joint_method_validation.py": Path(__file__).resolve(),
            "run_model_probability_validation.py": root / "src" / "hbv_multilead_joint_uncertainty" / "scripts" / "run_model_probability_validation.py",
            "run_process_noise_identification_validation.py": root / "src" / "hbv_multilead_joint_uncertainty" / "scripts" / "run_process_noise_identification_validation.py",
            "run_synthetic_truth_validation.py": root / "src" / "hbv_multilead_joint_uncertainty" / "scripts" / "run_synthetic_truth_validation.py",
            "hbv_adapter.py": root / "src" / "hbv_joint_uncertainty" / "hbv_adapter.py",
            "preflight.py": root / "src" / "hbv_joint_uncertainty" / "preflight.py",
            "imm.py": root / "src" / "hbv_joint_uncertainty" / "imm.py",
            "sigma_filter.py": root / "src" / "hbv_joint_uncertainty" / "sigma_filter.py",
            "hbv_lite_numpy.py": root / "src" / "scl_hydro" / "hbv_lite_numpy.py",
            "test_hbv_joint_method_validation.py": root / "test" / "test_hbv_joint_method_validation.py",
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
        raise RuntimeError(f"joint-method validation failed; see {output / 'summary.json'}")
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
