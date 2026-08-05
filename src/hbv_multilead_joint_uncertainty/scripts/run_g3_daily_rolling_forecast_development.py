"""Run the frozen full-stage daily rolling forecast development screen."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.daily_rolling_forecast import (  # noqa: E402
    build_daily_rolling_index,
    summarize_daily_rolling_forecasts,
)
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    build_method_bank,
    build_method_definitions,
)
from hbv_multilead_joint_uncertainty.scripts.run_g3_predictive_skill_development import (  # noqa: E402
    _checked_archive,
    _maximum_absolute_difference,
    _sha256,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _environment,
    _json_write,
    _load_observation_noise,
    _load_parameter_vectors,
    _load_process_covariances,
    _protected_hashes,
    _replace_directory_with_retries,
    _validate_output_is_disjoint_from_protected_paths,
)
from hbv_multilead_joint_uncertainty.transition_window_forecast import (  # noqa: E402
    collect_forecasts_at_origins,
)


_FORECAST_CONTRACT = {
    "model_transition_during_forecast": "identity",
    "candidate_probabilities_during_forecast": (
        "fixed_at_origin_assimilation_posterior"
    ),
    "cross_candidate_state_mixing_during_forecast": False,
}
_COMPARISON_METHODS = ("full", "none", "uniform_independent")
_BOOTSTRAP = {
    "unit": "matched_block",
    "replicates": 20000,
    "seed": 8820001,
    "shared_resample_indices_across_leads_and_comparisons": True,
}
_DEVELOPMENT_GATES = {
    "minimum_full_stage_rmse_improvement_fraction": 0.01,
    "require_all_seven_leads_against_both_controls": True,
}
_SOURCE_FILES = (
    "src/hbv_multilead_joint_uncertainty/daily_rolling_forecast.py",
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_daily_rolling_forecast_development.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "verify_g3_daily_rolling_forecast_development.py"
    ),
    "src/hbv_multilead_joint_uncertainty/transition_window_forecast.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_daily_rolling_forecast.py",
    "test/test_hbv_daily_rolling_forecast_development_runner.py",
    "test/test_hbv_daily_rolling_forecast_development_verifier.py",
)


def _validate_source_contract(config: dict, key: str) -> None:
    source = config.get(key, {})
    if (
        set(source) != {"path", "sha256"}
        or not isinstance(source["path"], str)
        or not source["path"]
        or not isinstance(source["sha256"], str)
        or len(source["sha256"]) != 64
    ):
        raise ValueError(f"{key} source contract is invalid")


def _validate_config_contract(config: dict) -> None:
    if config.get("classification") != "development_screen":
        raise ValueError("classification must be development_screen")
    if config.get("forecast_contract") != _FORECAST_CONTRACT:
        raise ValueError("forecast contract does not match the frozen contract")
    if tuple(config.get("comparison_methods", ())) != _COMPARISON_METHODS:
        raise ValueError("comparison methods do not match the frozen order")
    if tuple(config.get("lead_days", ())) != tuple(range(1, 8)):
        raise ValueError("lead days must equal 1 through 7")
    if tuple(config.get("stage_lengths", ())) != (180, 180, 180):
        raise ValueError("stage lengths must equal 180, 180, and 180")
    if tuple(config.get("switch_days", ())) != (180, 360):
        raise ValueError("switch days must equal 180 and 360")
    if config.get("origin_start_day") != 180:
        raise ValueError("origin start day must equal 180")
    if config.get("crosscheck_origin") != 539:
        raise ValueError("cross-check origin must equal 539")
    if config.get("expected_block_count") != 8:
        raise ValueError("expected block count must equal 8")
    if config.get("expected_truth_count") != 3:
        raise ValueError("expected truth count must equal 3")
    if config.get("primary_candidate_method_name") != "parameter_only":
        raise ValueError("primary candidate method must be parameter_only")
    if config.get("selected_process_id") != "process_2":
        raise ValueError("selected process identifier must be process_2")
    if config.get("process_noise_source", {}).get(
        "selected_process_id"
    ) != config.get("selected_process_id"):
        raise ValueError("selected process identifiers must agree")
    if float(config.get("factor_transition_stay_probability", -1.0)) != 0.98:
        raise ValueError("transition stay probability must equal 0.98")
    if config.get("bootstrap") != _BOOTSTRAP:
        raise ValueError("bootstrap contract does not match the frozen design")
    if config.get("development_gates") != _DEVELOPMENT_GATES:
        raise ValueError("development gates do not match the frozen design")
    _validate_source_contract(config, "sealed_ideal_input_evidence")
    _validate_source_contract(config, "sealed_baseline_evidence")


def _development_decision(
    rmse: dict[str, np.ndarray],
    gates: dict,
    *,
    integrity_passed: bool,
) -> dict[str, object]:
    if gates != _DEVELOPMENT_GATES:
        raise ValueError("development gates do not match the frozen design")
    if set(rmse) != set(_COMPARISON_METHODS):
        raise ValueError("root mean square error methods are incomplete")
    values = {
        method: np.asarray(rmse[method], dtype=np.float64)
        for method in _COMPARISON_METHODS
    }
    if any(
        array.shape != (7,) or not np.all(np.isfinite(array))
        for array in values.values()
    ):
        raise ValueError("each method must provide seven finite errors")
    if np.any(values["none"] <= 0.0) or np.any(
        values["uniform_independent"] <= 0.0
    ):
        raise ValueError("control errors must be positive")
    threshold = float(
        gates["minimum_full_stage_rmse_improvement_fraction"]
    )
    relative_none = values["full"] / values["none"] - 1.0
    relative_uniform = (
        values["full"] / values["uniform_independent"] - 1.0
    )
    passes_none = relative_none <= -threshold
    passes_uniform = relative_uniform <= -threshold
    advance = bool(
        integrity_passed
        and np.all(passes_none)
        and np.all(passes_uniform)
    )
    return {
        "integrity_passed": bool(integrity_passed),
        "relative_full_minus_none": relative_none,
        "relative_full_minus_uniform_independent": relative_uniform,
        "full_vs_none_passes": passes_none,
        "full_vs_uniform_independent_passes": passes_uniform,
        "advance_to_formal_confirmation": advance,
        "decision": (
            "advance_to_fresh_formal_design"
            if advance
            else "stop_no_formal_confirmation"
        ),
    }


def _require_array(
    archive: np.lib.npyio.NpzFile,
    name: str,
    shape: tuple[int, ...] | None = None,
) -> np.ndarray:
    if name not in archive.files:
        raise ValueError(f"sealed evidence is missing array {name}")
    values = np.asarray(archive[name])
    if shape is not None and values.shape != shape:
        raise ValueError(
            f"sealed array {name} has shape {values.shape}, expected {shape}"
        )
    return values


def _execute_development(root: Path, config: dict) -> dict:
    ideal_source = config["sealed_ideal_input_evidence"]
    baseline_source = config["sealed_baseline_evidence"]
    with _checked_archive(root, ideal_source) as ideal, _checked_archive(
        root, baseline_source
    ) as baseline:
        block_count = int(config["expected_block_count"])
        truth_count = int(config["expected_truth_count"])
        lead_days = np.asarray(config["lead_days"], dtype=np.int64)
        index = build_daily_rolling_index(
            stage_lengths=config["stage_lengths"],
            switch_days=config["switch_days"],
            lead_days=config["lead_days"],
        )
        block_ids = _require_array(
            ideal, "block_ids", (block_count,)
        ).astype(str)
        if not np.array_equal(
            block_ids,
            _require_array(
                baseline, "driver__block_ids", (block_count,)
            ).astype(str),
        ):
            raise ValueError("sealed block identifiers do not agree")
        sealed_leads = np.asarray([1, 3, 7], dtype=np.int64)
        if not np.array_equal(
            _require_array(ideal, "forecast_lead_days", (3,)),
            sealed_leads,
        ) or not np.array_equal(
            _require_array(
                baseline, "driver__forecast_lead_days", (3,)
            ),
            sealed_leads,
        ):
            raise ValueError("sealed cross-check lead days do not agree")
        if not np.array_equal(
            _require_array(ideal, "stage_start_days", (3,))[1:],
            np.asarray(config["switch_days"], dtype=np.int64),
        ):
            raise ValueError("sealed stage starts do not match switch days")
        if not bool(_require_array(baseline, "cross_checks__passed", ())):
            raise ValueError("sealed baseline cross-check did not pass")

        warmup_days = int(_require_array(ideal, "warmup_days", ()))
        forcing_blocks = _require_array(ideal, "forcing_blocks")
        observations = _require_array(ideal, "observed_discharge")
        truth_discharge = _require_array(ideal, "truth_discharge")
        initial_states = _require_array(
            ideal, "initial_parameter_states"
        )
        initial_covariances = _require_array(
            ideal, "initial_covariances"
        )
        parameter_ids = _require_array(
            ideal, "parameter_ids", (3,)
        ).astype(str)
        if (
            forcing_blocks.ndim != 3
            or forcing_blocks.shape[0] != block_count
            or forcing_blocks.shape[2] != 3
            or observations.shape != truth_discharge.shape
            or observations.shape[:2] != (block_count, truth_count)
            or observations.shape[2] < 540
            or forcing_blocks.shape[1] - warmup_days < 547
            or initial_states.shape != (block_count, 3, 15)
            or initial_covariances.shape != (block_count, 15, 15)
        ):
            raise ValueError("sealed ideal input shapes are incompatible")

        parameter_vectors, _, parameter_hash = _load_parameter_vectors(
            root, config
        )
        (
            process_covariances,
            process_scales,
            _,
            process_hash,
        ) = _load_process_covariances(root, config)
        observation_std, _, observation_hash = _load_observation_noise(
            root, config
        )
        definitions = build_method_definitions(
            parameter_vectors,
            process_scales,
            process_covariances,
            str(config["selected_process_id"]),
        )
        primary = definitions[
            str(config["primary_candidate_method_name"])
        ]
        candidate_ids = np.asarray(
            [definition.candidate_id for definition in primary]
        )
        if not np.array_equal(
            candidate_ids,
            _require_array(
                baseline,
                "driver__candidate_ids",
                (len(primary),),
            ).astype(str),
        ):
            raise ValueError("candidate order does not match sealed baseline")

        origins = index.origin_indices
        origin_count = len(origins)
        lead_count = len(lead_days)
        candidate_count = len(primary)
        forecasts = {
            mode: np.empty(
                (
                    block_count,
                    truth_count,
                    origin_count,
                    lead_count,
                ),
                dtype=np.float64,
            )
            for mode in ("full", "none")
        }
        candidates = {
            mode: np.empty(
                (
                    block_count,
                    truth_count,
                    origin_count,
                    lead_count,
                    candidate_count,
                ),
                dtype=np.float64,
            )
            for mode in ("full", "none")
        }
        probabilities = {
            mode: np.empty_like(candidates[mode])
            for mode in ("full", "none")
        }
        truth_targets = np.zeros(
            (
                block_count,
                truth_count,
                origin_count,
                lead_count,
            ),
            dtype=np.float64,
        )
        available = ~index.unavailable_mask
        for block in range(block_count):
            state_map = {
                parameter_id: initial_states[block, position]
                for position, parameter_id in enumerate(parameter_ids)
            }
            active_forcing = forcing_blocks[block, warmup_days:]
            for truth_case in range(truth_count):
                truth_targets[block, truth_case][available] = (
                    truth_discharge[block, truth_case][
                        index.target_indices[available]
                    ]
                )
                for mode in ("full", "none"):
                    bank = build_method_bank(
                        primary,
                        state_map,
                        initial_covariances[block],
                        observation_std,
                        float(
                            config[
                                "factor_transition_stay_probability"
                            ]
                        ),
                        interaction_mode=mode,
                    )
                    collected = collect_forecasts_at_origins(
                        forcing=active_forcing,
                        observations=observations[block, truth_case],
                        bank=bank,
                        origin_indices=origins,
                        lead_days=lead_days,
                        interaction_mode=mode,
                    )
                    forecasts[mode][block, truth_case] = (
                        collected.predictions
                    )
                    candidates[mode][block, truth_case] = (
                        collected.candidate_predictions
                    )
                    probabilities[mode][block, truth_case] = (
                        collected.probabilities
                    )

        comparison_forecasts = {
            "full": forecasts["full"],
            "none": forecasts["none"],
            "uniform_independent": np.mean(candidates["none"], axis=-1),
        }
        statistics = summarize_daily_rolling_forecasts(
            comparison_forecasts,
            truth_targets,
            index,
            bootstrap_replicates=int(
                config["bootstrap"]["replicates"]
            ),
            bootstrap_seed=int(config["bootstrap"]["seed"]),
            minimum_meaningful_rmse_fraction=float(
                config["development_gates"][
                    "minimum_full_stage_rmse_improvement_fraction"
                ]
            ),
        )

        crosscheck_row = int(
            np.flatnonzero(
                origins == int(config["crosscheck_origin"])
            )[0]
        )
        crosscheck_lead_rows = np.asarray([0, 2, 6], dtype=np.int64)
        sealed = {
            "full": {
                "forecast": _require_array(
                    baseline,
                    "driver__full_states_full_weights",
                    (block_count, truth_count, 3),
                ),
                "candidate": _require_array(
                    baseline,
                    "driver__candidate_forecasts_full",
                    (block_count, truth_count, 3, candidate_count),
                ),
                "probability": _require_array(
                    baseline,
                    "driver__final_probabilities_full",
                    (block_count, truth_count, candidate_count),
                ),
            },
            "none": {
                "forecast": _require_array(
                    baseline,
                    "driver__none_states_none_weights",
                    (block_count, truth_count, 3),
                ),
                "candidate": _require_array(
                    baseline,
                    "driver__candidate_forecasts_none",
                    (block_count, truth_count, 3, candidate_count),
                ),
                "probability": _require_array(
                    baseline,
                    "driver__final_probabilities_none",
                    (block_count, truth_count, candidate_count),
                ),
            },
        }
        cross_checks = {
            "same_stage_counts_match_design": bool(
                np.array_equal(
                    np.sum(index.same_stage_mask, axis=0),
                    np.asarray(
                        [358, 356, 354, 352, 350, 348, 346]
                    ),
                )
            ),
            "cross_switch_counts_match_design": bool(
                np.array_equal(
                    np.sum(index.cross_switch_mask, axis=0),
                    np.arange(1, 8),
                )
            ),
            "unavailable_counts_match_design": bool(
                np.array_equal(
                    np.sum(index.unavailable_mask, axis=0),
                    np.arange(1, 8),
                )
            ),
            "masks_are_mutually_exclusive_and_exhaustive": bool(
                np.array_equal(
                    (
                        index.same_stage_mask.astype(np.int8)
                        + index.cross_switch_mask.astype(np.int8)
                        + index.unavailable_mask.astype(np.int8)
                    ),
                    np.ones_like(index.same_stage_mask, dtype=np.int8),
                )
            ),
            "target_indices_within_forcing": bool(
                np.all(
                    index.target_indices
                    < forcing_blocks.shape[1] - warmup_days
                )
            ),
            "all_evidence_finite": bool(
                all(
                    np.all(np.isfinite(values))
                    for values in (
                        truth_targets,
                        forecasts["full"],
                        forecasts["none"],
                        candidates["full"],
                        candidates["none"],
                        probabilities["full"],
                        probabilities["none"],
                    )
                )
            ),
            "future_observations_used_for_forecast": False,
        }
        for mode in ("full", "none"):
            cross_checks[
                f"{mode}_final_forecast_maximum_absolute_difference"
            ] = _maximum_absolute_difference(
                forecasts[mode][
                    :,
                    :,
                    crosscheck_row,
                    crosscheck_lead_rows,
                ],
                sealed[mode]["forecast"],
            )
            cross_checks[
                f"{mode}_final_candidate_maximum_absolute_difference"
            ] = _maximum_absolute_difference(
                candidates[mode][
                    :,
                    :,
                    crosscheck_row,
                    crosscheck_lead_rows,
                ],
                sealed[mode]["candidate"],
            )
            cross_checks[
                f"{mode}_final_probability_maximum_absolute_difference"
            ] = _maximum_absolute_difference(
                probabilities[mode][:, :, crosscheck_row, 0],
                sealed[mode]["probability"],
            )
            cross_checks[
                f"{mode}_probability_spread_across_leads"
            ] = float(
                np.max(
                    np.abs(
                        probabilities[mode]
                        - probabilities[mode][..., :1, :]
                    ),
                    initial=0.0,
                )
            )
            cross_checks[
                f"{mode}_combination_maximum_absolute_error"
            ] = _maximum_absolute_difference(
                forecasts[mode],
                np.sum(
                    candidates[mode] * probabilities[mode],
                    axis=-1,
                ),
            )
        numerical_keys = [
            key
            for key in cross_checks
            if (
                key.endswith("maximum_absolute_difference")
                or key.endswith("spread_across_leads")
                or key.endswith("maximum_absolute_error")
            )
        ]
        cross_checks["passed"] = bool(
            cross_checks["same_stage_counts_match_design"]
            and cross_checks["cross_switch_counts_match_design"]
            and cross_checks["unavailable_counts_match_design"]
            and cross_checks[
                "masks_are_mutually_exclusive_and_exhaustive"
            ]
            and cross_checks["target_indices_within_forcing"]
            and cross_checks["all_evidence_finite"]
            and not cross_checks["future_observations_used_for_forecast"]
            and all(
                float(cross_checks[key]) <= 1e-12
                for key in numerical_keys
            )
        )
        decision = _development_decision(
            statistics["rmse"],
            config["development_gates"],
            integrity_passed=bool(cross_checks["passed"]),
        )
        return {
            "index": index,
            "statistics": statistics,
            "decision": decision,
            "truth_forecasts": truth_targets,
            "forecasts": comparison_forecasts,
            "candidate_forecasts": candidates,
            "probabilities": probabilities,
            "block_ids": block_ids,
            "candidate_ids": candidate_ids,
            "cross_checks": cross_checks,
            "input_hashes": {
                "ideal_input_evidence_sha256": str(
                    ideal_source["sha256"]
                ),
                "baseline_evidence_sha256": str(
                    baseline_source["sha256"]
                ),
                "parameter_snapshot_sha256": parameter_hash,
                "process_snapshot_sha256": process_hash,
                "observation_snapshot_sha256": observation_hash,
            },
        }


def _json_values(values) -> list:
    return [
        bool(value) if isinstance(value, (bool, np.bool_)) else float(value)
        for value in np.asarray(values)
    ]


def _result_summary(payload: dict) -> dict:
    statistics = payload["statistics"]
    decision = payload["decision"]
    paired = {}
    for name, entry in statistics["paired"].items():
        paired[name] = {
            field: _json_values(entry[field])
            for field in (
                "mean",
                "ci_low",
                "ci_high",
                "baseline_mse",
                "meaningful_improvement_boundary",
                "materially_improves",
            )
        }
    strata = {
        name: {
            "minimum_offset": int(entry["minimum_offset"]),
            "maximum_offset": int(entry["maximum_offset"]),
            "sample_count_per_block_truth": [
                int(value)
                for value in entry["sample_count_per_block_truth"]
            ],
            "rmse": {
                method: _json_values(entry["rmse"][method])
                for method in _COMPARISON_METHODS
            },
        }
        for name, entry in statistics["time_strata"].items()
    }
    return {
        "lead_days": [
            int(value) for value in statistics["lead_days"]
        ],
        "same_stage_sample_count_per_block_truth": [
            int(value)
            for value in statistics[
                "same_stage_sample_count_per_block_truth"
            ]
        ],
        "cross_switch_sample_count_per_block_truth": [
            int(value)
            for value in statistics[
                "cross_switch_sample_count_per_block_truth"
            ]
        ],
        "unavailable_sample_count_per_block_truth": [
            int(value)
            for value in statistics[
                "unavailable_sample_count_per_block_truth"
            ]
        ],
        "rmse": {
            method: _json_values(statistics["rmse"][method])
            for method in _COMPARISON_METHODS
        },
        "relative_full_minus_none_rmse_percent": _json_values(
            100.0
            * np.asarray(
                decision["relative_full_minus_none"],
                dtype=np.float64,
            )
        ),
        (
            "relative_full_minus_uniform_independent_"
            "rmse_percent"
        ): _json_values(
            100.0
            * np.asarray(
                decision[
                    "relative_full_minus_uniform_independent"
                ],
                dtype=np.float64,
            )
        ),
        "development_gate": {
            "integrity_passed": bool(decision["integrity_passed"]),
            "full_vs_none_passes": _json_values(
                decision["full_vs_none_passes"]
            ),
            "full_vs_uniform_independent_passes": _json_values(
                decision["full_vs_uniform_independent_passes"]
            ),
            "advance_to_formal_confirmation": bool(
                decision["advance_to_formal_confirmation"]
            ),
            "decision": str(decision["decision"]),
        },
        "paired_descriptive_intervals": paired,
        "time_strata": strata,
        "cross_switch_rmse": {
            method: _json_values(
                statistics["cross_switch_rmse"][method]
            )
            for method in _COMPARISON_METHODS
        },
    }


def _evidence_arrays(payload: dict) -> dict[str, np.ndarray]:
    index = payload["index"]
    statistics = payload["statistics"]
    arrays: dict[str, np.ndarray] = {
        "block_ids": payload["block_ids"],
        "candidate_ids": payload["candidate_ids"],
        "lead_days": index.lead_days,
        "origin_indices": index.origin_indices,
        "target_indices": index.target_indices,
        "origin_stage_indices": index.origin_stage_indices,
        "target_stage_indices": index.target_stage_indices,
        "days_since_switch": index.days_since_switch,
        "same_stage_mask": index.same_stage_mask,
        "cross_switch_mask": index.cross_switch_mask,
        "unavailable_mask": index.unavailable_mask,
        "truth_forecasts": payload["truth_forecasts"],
        "full_forecasts": payload["forecasts"]["full"],
        "none_forecasts": payload["forecasts"]["none"],
        "uniform_independent_forecasts": payload["forecasts"][
            "uniform_independent"
        ],
        "full_candidate_forecasts": payload["candidate_forecasts"][
            "full"
        ],
        "none_candidate_forecasts": payload["candidate_forecasts"][
            "none"
        ],
        "full_probabilities": payload["probabilities"]["full"],
        "none_probabilities": payload["probabilities"]["none"],
        "bootstrap_indices": statistics["bootstrap_indices"],
        "daily_offset_days": statistics["daily_offset"]["offset_days"],
    }
    for method in _COMPARISON_METHODS:
        arrays[f"squared_error_{method}"] = statistics[
            "squared_errors"
        ][method]
        arrays[f"block_mse_{method}"] = statistics["block_mse"][method]
        arrays[f"rmse_{method}"] = statistics["rmse"][method]
        arrays[f"cross_switch_rmse_{method}"] = statistics[
            "cross_switch_rmse"
        ][method]
        arrays[f"daily_offset_rmse_{method}"] = statistics[
            "daily_offset"
        ]["rmse"][method]
        arrays[f"daily_offset_sample_count_{method}"] = statistics[
            "daily_offset"
        ]["sample_count"][method]
    for stratum, entry in statistics["time_strata"].items():
        arrays[f"{stratum}_sample_count"] = entry[
            "sample_count_per_block_truth"
        ]
        for method in _COMPARISON_METHODS:
            arrays[f"{stratum}_rmse_{method}"] = entry["rmse"][method]
    for comparison, entry in statistics["paired"].items():
        for field in (
            "block_mean",
            "mean",
            "ci_low",
            "ci_high",
            "baseline_mse",
            "meaningful_improvement_boundary",
            "materially_improves",
        ):
            arrays[f"{comparison}_{field}"] = np.asarray(entry[field])
    return arrays


def _source_snapshot(root: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    seen: set[str] = set()
    for configured in _SOURCE_FILES:
        source = (root / configured).resolve()
        if not source.is_file():
            raise FileNotFoundError(
                f"source snapshot is missing: {configured}"
            )
        if source.name in seen:
            raise ValueError(
                f"duplicate source snapshot basename: {source.name}"
            )
        seen.add(source.name)
        shutil.copy2(source, destination / source.name)


def _checksums(directory: Path) -> dict[str, str]:
    return {
        path.relative_to(directory).as_posix(): _sha256(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    if output.exists() or incomplete.exists():
        raise FileExistsError("refusing to overwrite existing evidence")
    config_bytes = config_file.read_bytes()
    config_hash = hashlib.sha256(config_bytes).hexdigest()
    config = json.loads(config_bytes.decode("utf-8"))
    _validate_config_contract(config)
    if output.name != str(config.get("experiment_id")):
        raise ValueError("output directory name must equal experiment_id")
    protected_paths = tuple(
        (root / str(value)).resolve()
        for value in config.get("protected_paths", ())
    )
    _validate_output_is_disjoint_from_protected_paths(
        output, protected_paths
    )
    _validate_output_is_disjoint_from_protected_paths(
        incomplete, protected_paths
    )
    protected_before = _protected_hashes(
        root, config.get("protected_paths", ())
    )
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    incomplete.mkdir(parents=True, exist_ok=False)
    (incomplete / "config_snapshot.json").write_bytes(config_bytes)
    try:
        payload = _execute_development(root, config)
        np.savez_compressed(
            incomplete / "evidence.npz",
            **_evidence_arrays(payload),
        )
        _json_write(
            incomplete / "cross_checks.json",
            payload["cross_checks"],
        )
        _json_write(
            incomplete / "environment.json",
            _environment(root, started_at),
        )
        _source_snapshot(root, incomplete / "source_snapshot")
        protected_after = _protected_hashes(
            root, config.get("protected_paths", ())
        )
        protected_unchanged = protected_before == protected_after
        integrity_passed = bool(
            protected_unchanged
            and payload["cross_checks"].get("passed", False)
        )
        result = _result_summary(payload)
        if not integrity_passed:
            result["development_gate"][
                "advance_to_formal_confirmation"
            ] = False
            result["development_gate"][
                "decision"
            ] = "stop_integrity_failure"
        summary = {
            "experiment_id": config["experiment_id"],
            "classification": config["classification"],
            "scenario": config["scenario"],
            "integrity_status": (
                "passed" if integrity_passed else "failed"
            ),
            "protected_artifacts_unchanged": protected_unchanged,
            "config_sha256": config_hash,
            "forecast_contract": config["forecast_contract"],
            "comparison_methods": config["comparison_methods"],
            "stage_lengths": config["stage_lengths"],
            "switch_days": config["switch_days"],
            "development_gates": config["development_gates"],
            "scope_limit": config["scope_limit"],
            **payload["input_hashes"],
            "result": result,
        }
        _json_write(incomplete / "summary.json", summary)
        _json_write(
            incomplete / "protected_artifact_integrity.json",
            {
                "configured_paths": config.get("protected_paths", ()),
                "before": protected_before,
                "after_evidence_writes": protected_after,
                "status": (
                    "unchanged" if protected_unchanged else "changed"
                ),
            },
        )
        _json_write(incomplete / "checksums.json", _checksums(incomplete))
        if not integrity_passed:
            raise RuntimeError(
                "protected-artifact or numerical cross-check failed"
            )
        _replace_directory_with_retries(incomplete, output)
        return summary
    except Exception as error:
        if incomplete.exists():
            _json_write(
                incomplete / "failure.json",
                {
                    "exception_type": type(error).__name__,
                    "message": str(error),
                    "failed_at_utc": dt.datetime.now(
                        dt.timezone.utc
                    ).isoformat(),
                },
            )
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    summary = run(
        arguments.repo_root,
        arguments.config,
        arguments.output_dir,
    )
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
