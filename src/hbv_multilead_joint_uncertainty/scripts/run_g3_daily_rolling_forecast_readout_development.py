"""Run the frozen full-stage forecast readout development comparison."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.daily_rolling_forecast import (  # noqa: E402
    build_daily_rolling_index,
)
from hbv_multilead_joint_uncertainty.forecast import (  # noqa: E402
    _assimilation_step,
)
from hbv_multilead_joint_uncertainty.forecast_readout import (  # noqa: E402
    READOUT_METHODS,
    forecast_readout_variants,
    summarize_readout_forecasts,
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


_COMPARISON_CONTROLS = (
    "no_state_interaction_multiple_states",
    "no_state_interaction_uniform_candidates",
)
_ALL_METHODS = READOUT_METHODS + _COMPARISON_CONTROLS
_UNIQUE_METHODS = (
    "posterior_unique_complete_covariance_weighted_parameters",
    "posterior_unique_within_covariance_weighted_parameters",
    "posterior_unique_complete_covariance_maximum_parameters",
    "uniform_unique_complete_covariance_uniform_parameters",
)
_FORECAST_CONTRACT = {
    "assimilation_interaction_mode": "full",
    "model_transition_during_forecast": "identity",
    "candidate_probabilities_during_forecast": (
        "fixed_at_origin_assimilation_posterior"
    ),
    "future_discharge_observations_used": False,
    "maximum_posterior_tie_break": "lowest_frozen_candidate_index",
}
_BOOTSTRAP = {
    "unit": "matched_block",
    "replicates": 20000,
    "reuse_indices_from_sealed_daily_evidence": True,
    "shared_indices_across_all_methods_leads_and_comparisons": True,
}
_DECISION_RULES = {
    "minimum_meaningful_rmse_fraction": 0.01,
    "require_all_seven_leads": True,
    "replacement_baseline": "current_multiple_states",
    "general_repair_baseline": "no_state_interaction_multiple_states",
}
_NUMERICAL_TOLERANCES = {
    "state": 1e-9,
    "covariance": 1e-8,
    "probability": 1e-12,
    "forecast": 1e-9,
    "verification": 1e-9,
}
_SOURCE_FILES = (
    "src/hbv_multilead_joint_uncertainty/forecast_readout.py",
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_daily_rolling_forecast_readout_development.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "verify_g3_daily_rolling_forecast_readout_development.py"
    ),
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_multilead_joint_uncertainty/daily_rolling_forecast.py",
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_joint_uncertainty/preflight.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_forecast_readout.py",
    "test/test_hbv_daily_rolling_forecast_readout_runner.py",
    "test/test_hbv_daily_rolling_forecast_readout_verifier.py",
    (
        "src/hbv_multilead_joint_uncertainty/configs/"
        "g3_daily_rolling_forecast_readout_development_v01.json"
    ),
    "docs/plans/2026-07-28-id23-daily-rolling-forecast-readout-design.md",
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
    if config.get("classification") != "development_mechanism_comparison":
        raise ValueError(
            "classification must be development_mechanism_comparison"
        )
    if tuple(config.get("readout_methods", ())) != READOUT_METHODS:
        raise ValueError("readout methods do not match the frozen order")
    if tuple(config.get("comparison_controls", ())) != _COMPARISON_CONTROLS:
        raise ValueError(
            "comparison controls do not match the frozen order"
        )
    if tuple(config.get("lead_days", ())) != tuple(range(1, 8)):
        raise ValueError("lead days must equal 1 through 7")
    if tuple(config.get("stage_lengths", ())) != (180, 180, 180):
        raise ValueError("stage lengths must equal 180, 180, and 180")
    if tuple(config.get("switch_days", ())) != (180, 360):
        raise ValueError("switch days must equal 180 and 360")
    if (
        config.get("origin_start_day") != 180
        or config.get("origin_end_day") != 539
    ):
        raise ValueError("origin days must equal 180 through 539")
    if config.get("expected_block_count") != 8:
        raise ValueError("block count must equal 8")
    if config.get("expected_truth_count") != 3:
        raise ValueError("truth count must equal 3")
    if config.get("expected_candidate_count") != 3:
        raise ValueError("candidate count must equal 3")
    if config.get("expected_state_count") != 15:
        raise ValueError("state count must equal 15")
    if config.get("primary_candidate_method_name") != "parameter_only":
        raise ValueError("primary candidate method must be parameter_only")
    if config.get("selected_process_id") != "process_2":
        raise ValueError("selected process identifier must be process_2")
    if config.get("process_noise_source", {}).get(
        "selected_process_id"
    ) != config.get("selected_process_id"):
        raise ValueError("selected process identifiers must agree")
    if float(
        config.get("factor_transition_stay_probability", -1.0)
    ) != 0.98:
        raise ValueError("transition stay probability must equal 0.98")
    if config.get("forecast_contract") != _FORECAST_CONTRACT:
        raise ValueError("forecast contract does not match the frozen design")
    if config.get("bootstrap") != _BOOTSTRAP:
        raise ValueError("bootstrap contract does not match the frozen design")
    if config.get("decision_rules") != _DECISION_RULES:
        raise ValueError(
            "decision rules do not match the frozen design"
        )
    if config.get("numerical_tolerances") != _NUMERICAL_TOLERANCES:
        raise ValueError(
            "numerical tolerances do not match the frozen design"
        )
    for key in (
        "sealed_ideal_input_evidence",
        "sealed_daily_rolling_evidence",
        "sealed_factorial_evidence",
    ):
        _validate_source_contract(config, key)


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


def _parameter_matrix(primary) -> np.ndarray:
    return np.asarray(
        [
            [candidate.parameters[name] for name in PARAMETER_NAMES]
            for candidate in primary
        ],
        dtype=np.float64,
    )


def _execute_development(
    root: Path,
    config: dict,
    progress_callback=None,
) -> dict:
    ideal_source = config["sealed_ideal_input_evidence"]
    daily_source = config["sealed_daily_rolling_evidence"]
    factorial_source = config["sealed_factorial_evidence"]
    with _checked_archive(root, ideal_source) as ideal, _checked_archive(
        root, daily_source
    ) as daily, _checked_archive(root, factorial_source) as factorial:
        block_count = int(config["expected_block_count"])
        truth_count = int(config["expected_truth_count"])
        candidate_count = int(config["expected_candidate_count"])
        state_count = int(config["expected_state_count"])
        lead_days = np.asarray(config["lead_days"], dtype=np.int64)
        index = build_daily_rolling_index(
            stage_lengths=config["stage_lengths"],
            switch_days=config["switch_days"],
            lead_days=config["lead_days"],
        )
        origins = index.origin_indices
        origin_count = len(origins)
        lead_count = len(lead_days)
        if (
            origin_count != 360
            or int(origins[0]) != 180
            or int(origins[-1]) != 539
        ):
            raise ValueError("daily rolling origin index is not frozen")

        block_ids = _require_array(
            ideal, "block_ids", (block_count,)
        ).astype(str)
        parameter_ids = _require_array(
            ideal, "parameter_ids", (candidate_count,)
        ).astype(str)
        warmup_days = int(_require_array(ideal, "warmup_days", ()))
        forcing_blocks = _require_array(ideal, "forcing_blocks")
        observations = _require_array(ideal, "observed_discharge")
        initial_states = _require_array(
            ideal,
            "initial_parameter_states",
            (block_count, candidate_count, state_count),
        )
        initial_covariances = _require_array(
            ideal,
            "initial_covariances",
            (block_count, state_count, state_count),
        )
        if (
            forcing_blocks.ndim != 3
            or forcing_blocks.shape[0] != block_count
            or forcing_blocks.shape[2] != 3
            or forcing_blocks.shape[1] - warmup_days < 547
            or observations.shape[:2] != (block_count, truth_count)
            or observations.shape[2] < 540
        ):
            raise ValueError("sealed ideal input shapes are incompatible")

        daily_shape = (
            block_count,
            truth_count,
            origin_count,
            lead_count,
        )
        candidate_forecast_shape = (*daily_shape, candidate_count)
        for name, expected in (
            ("origin_indices", origins),
            ("target_indices", index.target_indices),
            ("lead_days", lead_days),
            ("days_since_switch", index.days_since_switch),
            ("same_stage_mask", index.same_stage_mask),
            ("cross_switch_mask", index.cross_switch_mask),
            ("unavailable_mask", index.unavailable_mask),
        ):
            values = _require_array(daily, name, expected.shape)
            if not np.array_equal(values, expected):
                raise ValueError(f"sealed daily array {name} changed")
        truth_forecasts = _require_array(
            daily, "truth_forecasts", daily_shape
        ).astype(np.float64)
        sealed_current = _require_array(
            daily, "full_forecasts", daily_shape
        ).astype(np.float64)
        sealed_candidates = _require_array(
            daily,
            "full_candidate_forecasts",
            candidate_forecast_shape,
        ).astype(np.float64)
        sealed_probabilities = _require_array(
            daily,
            "full_probabilities",
            candidate_forecast_shape,
        ).astype(np.float64)
        bootstrap_indices = _require_array(
            daily,
            "bootstrap_indices",
            (int(config["bootstrap"]["replicates"]), block_count),
        ).astype(np.int64)

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
        if len(primary) != candidate_count:
            raise ValueError("primary candidate count changed")
        candidate_ids = np.asarray(
            [candidate.candidate_id for candidate in primary]
        )
        if not np.array_equal(
            candidate_ids,
            _require_array(
                factorial,
                "driver__candidate_ids",
                (candidate_count,),
            ).astype(str),
        ):
            raise ValueError("candidate order differs from sealed evidence")
        candidate_parameter_matrix = _parameter_matrix(primary)
        selected_process_covariance = primary[0].process_covariance.copy()
        selected_process_scale = float(primary[0].process_scale)
        if any(
            candidate.process_id != primary[0].process_id
            or candidate.process_scale != selected_process_scale
            or not np.array_equal(
                candidate.process_covariance,
                selected_process_covariance,
            )
            for candidate in primary
        ):
            raise ValueError(
                "parameter-only candidates do not share one process contract"
            )

        forecasts = {
            method: np.empty(daily_shape, dtype=np.float64)
            for method in READOUT_METHODS
        }
        forecasts["no_state_interaction_multiple_states"] = _require_array(
            daily, "none_forecasts", daily_shape
        ).astype(np.float64)
        forecasts["no_state_interaction_uniform_candidates"] = (
            _require_array(
                daily,
                "uniform_independent_forecasts",
                daily_shape,
            ).astype(np.float64)
        )
        current_candidate_forecasts = np.empty(
            candidate_forecast_shape, dtype=np.float64
        )
        origin_probabilities = np.empty(
            (
                block_count,
                truth_count,
                origin_count,
                candidate_count,
            ),
            dtype=np.float64,
        )
        origin_candidate_states = np.empty(
            (
                block_count,
                truth_count,
                origin_count,
                candidate_count,
                state_count,
            ),
            dtype=np.float64,
        )
        origin_candidate_covariances = np.empty(
            (
                block_count,
                truth_count,
                origin_count,
                candidate_count,
                state_count,
                state_count,
            ),
            dtype=np.float64,
        )
        posterior_mean_states = np.empty(
            (block_count, truth_count, origin_count, state_count),
            dtype=np.float64,
        )
        posterior_within_covariances = np.empty(
            (
                block_count,
                truth_count,
                origin_count,
                state_count,
                state_count,
            ),
            dtype=np.float64,
        )
        posterior_between_covariances = np.empty_like(
            posterior_within_covariances
        )
        posterior_complete_covariances = np.empty_like(
            posterior_within_covariances
        )
        uniform_mean_states = np.empty_like(posterior_mean_states)
        uniform_within_covariances = np.empty_like(
            posterior_within_covariances
        )
        uniform_between_covariances = np.empty_like(
            posterior_within_covariances
        )
        uniform_complete_covariances = np.empty_like(
            posterior_within_covariances
        )
        maximum_posterior_indices = np.empty(
            (block_count, truth_count, origin_count),
            dtype=np.int64,
        )
        posterior_weighted_parameter_vectors = np.empty(
            (
                block_count,
                truth_count,
                origin_count,
                len(PARAMETER_NAMES),
            ),
            dtype=np.float64,
        )
        maximum_parameter_vectors = np.empty_like(
            posterior_weighted_parameter_vectors
        )
        uniform_parameter_vectors = np.empty_like(
            posterior_weighted_parameter_vectors
        )
        unique_projected_states = np.empty(
            (
                block_count,
                truth_count,
                origin_count,
                len(_UNIQUE_METHODS),
                state_count,
            ),
            dtype=np.float64,
        )
        projection_displacements = np.empty(
            (
                block_count,
                truth_count,
                origin_count,
                len(_UNIQUE_METHODS),
            ),
            dtype=np.float64,
        )
        future_forcing = np.empty(
            (block_count, origin_count, 7, 3),
            dtype=np.float64,
        )

        started = time.monotonic()
        for block in range(block_count):
            state_map = {
                parameter_id: initial_states[block, position]
                for position, parameter_id in enumerate(parameter_ids)
            }
            active_forcing = forcing_blocks[block, warmup_days:]
            future_forcing[block] = np.asarray(
                [
                    active_forcing[origin + 1 : origin + 8]
                    for origin in origins
                ],
                dtype=np.float64,
            )
            for truth_case in range(truth_count):
                bank = build_method_bank(
                    primary,
                    state_map,
                    initial_covariances[block],
                    observation_std,
                    float(config["factor_transition_stay_probability"]),
                    interaction_mode="full",
                )
                origin_row = 0
                for day in range(540):
                    rain, pet, temperature = active_forcing[day]
                    for transition in bank.transitions:
                        transition.set_forcing(rain, pet, temperature)
                    _assimilation_step(
                        bank,
                        float(observations[block, truth_case, day]),
                        "full",
                    )
                    if day < int(origins[0]):
                        continue
                    if day != int(origins[origin_row]):
                        raise ValueError(
                            "assimilation origin sequence changed"
                        )
                    candidate_states = np.asarray(
                        [
                            candidate.state
                            for candidate in bank.estimator.filters
                        ],
                        dtype=np.float64,
                    )
                    candidate_covariances = np.asarray(
                        [
                            candidate.covariance
                            for candidate in bank.estimator.filters
                        ],
                        dtype=np.float64,
                    )
                    readout = forecast_readout_variants(
                        bank,
                        primary,
                        future_forcing[block, origin_row],
                        lead_days=lead_days,
                    )
                    for method in READOUT_METHODS:
                        forecasts[method][
                            block, truth_case, origin_row
                        ] = readout.predictions[method]
                    current_candidate_forecasts[
                        block, truth_case, origin_row
                    ] = readout.current_forecast.candidate_predictions
                    origin_probabilities[
                        block, truth_case, origin_row
                    ] = bank.estimator.probabilities
                    origin_candidate_states[
                        block, truth_case, origin_row
                    ] = candidate_states
                    origin_candidate_covariances[
                        block, truth_case, origin_row
                    ] = candidate_covariances
                    posterior_mean_states[
                        block, truth_case, origin_row
                    ] = readout.global_posterior_state
                    posterior_within_covariances[
                        block, truth_case, origin_row
                    ] = readout.posterior_within_covariance
                    posterior_between_covariances[
                        block, truth_case, origin_row
                    ] = readout.posterior_between_covariance
                    posterior_complete_covariances[
                        block, truth_case, origin_row
                    ] = readout.posterior_complete_covariance
                    uniform_mean_states[
                        block, truth_case, origin_row
                    ] = readout.uniform_mean_state
                    uniform_within_covariances[
                        block, truth_case, origin_row
                    ] = readout.uniform_within_covariance
                    uniform_between_covariances[
                        block, truth_case, origin_row
                    ] = readout.uniform_between_covariance
                    uniform_complete_covariances[
                        block, truth_case, origin_row
                    ] = readout.uniform_complete_covariance
                    maximum_posterior_indices[
                        block, truth_case, origin_row
                    ] = readout.maximum_posterior_index
                    posterior_weighted_parameter_vectors[
                        block, truth_case, origin_row
                    ] = [
                        readout.posterior_weighted_parameters[name]
                        for name in PARAMETER_NAMES
                    ]
                    maximum_parameter_vectors[
                        block, truth_case, origin_row
                    ] = [
                        readout.maximum_parameters[name]
                        for name in PARAMETER_NAMES
                    ]
                    uniform_parameter_vectors[
                        block, truth_case, origin_row
                    ] = [
                        readout.uniform_parameters[name]
                        for name in PARAMETER_NAMES
                    ]
                    for method_index, method in enumerate(_UNIQUE_METHODS):
                        unique_projected_states[
                            block,
                            truth_case,
                            origin_row,
                            method_index,
                        ] = readout.unique_projected_states[method]
                        projection_displacements[
                            block,
                            truth_case,
                            origin_row,
                            method_index,
                        ] = readout.projection_displacements[method]
                    origin_row += 1
                if origin_row != origin_count:
                    raise ValueError("not every daily origin was forecast")
            if progress_callback is not None:
                progress_callback(
                    block + 1,
                    block_count,
                    time.monotonic() - started,
                )

        statistics = summarize_readout_forecasts(
            forecasts,
            truth_forecasts,
            index.same_stage_mask,
            days_since_switch=index.days_since_switch,
            bootstrap_indices=bootstrap_indices,
            minimum_meaningful_rmse_fraction=float(
                config["decision_rules"][
                    "minimum_meaningful_rmse_fraction"
                ]
            ),
            replacement_baseline=str(
                config["decision_rules"]["replacement_baseline"]
            ),
            general_repair_baseline=str(
                config["decision_rules"]["general_repair_baseline"]
            ),
        )

        sealed_combined_states = _require_array(
            ideal, "method_assimilation_states"
        )[:, :, 2, origins]
        sealed_full_probabilities = _require_array(
            ideal, "method_assimilation_probabilities"
        )[:, :, 2, origins, :candidate_count]
        factorial_final_states = _require_array(
            factorial, "driver__final_candidate_states_full"
        )
        factorial_final_covariances = _require_array(
            factorial, "driver__final_candidate_covariances_full"
        )
        factorial_final_probabilities = _require_array(
            factorial, "driver__final_probabilities_full"
        )
        tolerances = config["numerical_tolerances"]
        cross_checks = {
            "daily_index_matches_sealed": True,
            "same_stage_counts_match_design": bool(
                np.array_equal(
                    np.sum(index.same_stage_mask, axis=0),
                    np.asarray([358, 356, 354, 352, 350, 348, 346]),
                )
            ),
            "all_evidence_finite": bool(
                all(
                    np.all(np.isfinite(values))
                    for values in (
                        truth_forecasts,
                        *forecasts.values(),
                        current_candidate_forecasts,
                        origin_probabilities,
                        origin_candidate_states,
                        origin_candidate_covariances,
                        posterior_mean_states,
                        posterior_within_covariances,
                        posterior_between_covariances,
                        posterior_complete_covariances,
                        posterior_weighted_parameter_vectors,
                        unique_projected_states,
                        projection_displacements,
                    )
                )
            ),
            "future_discharge_observations_used": False,
            "current_forecast_vs_sealed_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    forecasts["current_multiple_states"],
                    sealed_current,
                )
            ),
            "current_candidate_forecast_vs_sealed_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    current_candidate_forecasts,
                    sealed_candidates,
                )
            ),
            "origin_probability_vs_sealed_daily_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    origin_probabilities,
                    sealed_probabilities[..., 0, :],
                )
            ),
            "origin_probability_vs_sealed_assimilation_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    origin_probabilities,
                    sealed_full_probabilities,
                )
            ),
            "posterior_mean_state_vs_sealed_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    posterior_mean_states,
                    sealed_combined_states,
                )
            ),
            "final_candidate_state_vs_factorial_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    origin_candidate_states[:, :, -1],
                    factorial_final_states,
                )
            ),
            "final_candidate_covariance_vs_factorial_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    origin_candidate_covariances[:, :, -1],
                    factorial_final_covariances,
                )
            ),
            "final_probability_vs_factorial_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    origin_probabilities[:, :, -1],
                    factorial_final_probabilities,
                )
            ),
            "current_combination_maximum_absolute_error": (
                _maximum_absolute_difference(
                    forecasts["current_multiple_states"],
                    np.sum(
                        current_candidate_forecasts
                        * origin_probabilities[..., None, :],
                        axis=-1,
                    ),
                )
            ),
            "maximum_candidate_selection_exact": bool(
                np.array_equal(
                    maximum_posterior_indices,
                    np.argmax(origin_probabilities, axis=-1),
                )
            ),
        }
        numerical_requirements = {
            "current_forecast_vs_sealed_maximum_absolute_difference": float(
                tolerances["forecast"]
            ),
            (
                "current_candidate_forecast_vs_sealed_"
                "maximum_absolute_difference"
            ): float(tolerances["forecast"]),
            (
                "origin_probability_vs_sealed_daily_"
                "maximum_absolute_difference"
            ): float(tolerances["probability"]),
            (
                "origin_probability_vs_sealed_assimilation_"
                "maximum_absolute_difference"
            ): float(tolerances["probability"]),
            (
                "posterior_mean_state_vs_sealed_"
                "maximum_absolute_difference"
            ): float(tolerances["state"]),
            (
                "final_candidate_state_vs_factorial_"
                "maximum_absolute_difference"
            ): float(tolerances["state"]),
            (
                "final_candidate_covariance_vs_factorial_"
                "maximum_absolute_difference"
            ): float(tolerances["covariance"]),
            (
                "final_probability_vs_factorial_"
                "maximum_absolute_difference"
            ): float(tolerances["probability"]),
            "current_combination_maximum_absolute_error": float(
                tolerances["forecast"]
            ),
        }
        cross_checks["tolerances"] = numerical_requirements
        cross_checks["passed"] = bool(
            cross_checks["daily_index_matches_sealed"]
            and cross_checks["same_stage_counts_match_design"]
            and cross_checks["all_evidence_finite"]
            and not cross_checks["future_discharge_observations_used"]
            and cross_checks["maximum_candidate_selection_exact"]
            and all(
                float(cross_checks[key]) <= tolerance
                for key, tolerance in numerical_requirements.items()
            )
        )

        return {
            "index": index,
            "statistics": statistics,
            "forecasts": forecasts,
            "truth_forecasts": truth_forecasts,
            "bootstrap_indices": bootstrap_indices,
            "block_ids": block_ids,
            "candidate_ids": candidate_ids,
            "parameter_ids": parameter_ids,
            "candidate_parameter_matrix": candidate_parameter_matrix,
            "selected_process_covariance": selected_process_covariance,
            "selected_process_scale": selected_process_scale,
            "observation_standard_deviation": float(observation_std),
            "future_forcing": future_forcing,
            "current_candidate_forecasts": current_candidate_forecasts,
            "origin_probabilities": origin_probabilities,
            "origin_candidate_states": origin_candidate_states,
            "origin_candidate_covariances": origin_candidate_covariances,
            "posterior_mean_states": posterior_mean_states,
            "posterior_within_covariances": posterior_within_covariances,
            "posterior_between_covariances": posterior_between_covariances,
            "posterior_complete_covariances": (
                posterior_complete_covariances
            ),
            "uniform_mean_states": uniform_mean_states,
            "uniform_within_covariances": uniform_within_covariances,
            "uniform_between_covariances": uniform_between_covariances,
            "uniform_complete_covariances": uniform_complete_covariances,
            "maximum_posterior_indices": maximum_posterior_indices,
            "posterior_weighted_parameter_vectors": (
                posterior_weighted_parameter_vectors
            ),
            "maximum_parameter_vectors": maximum_parameter_vectors,
            "uniform_parameter_vectors": uniform_parameter_vectors,
            "unique_projected_states": unique_projected_states,
            "projection_displacements": projection_displacements,
            "cross_checks": cross_checks,
            "input_hashes": {
                "ideal_input_evidence_sha256": str(
                    ideal_source["sha256"]
                ),
                "daily_rolling_evidence_sha256": str(
                    daily_source["sha256"]
                ),
                "factorial_evidence_sha256": str(
                    factorial_source["sha256"]
                ),
                "parameter_snapshot_sha256": parameter_hash,
                "process_snapshot_sha256": process_hash,
                "observation_snapshot_sha256": observation_hash,
            },
        }


def _json_ready(value):
    if isinstance(value, dict):
        return {
            str(key): _json_ready(item)
            for key, item in value.items()
        }
    if isinstance(value, (tuple, list)):
        return [_json_ready(item) for item in value]
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, (np.bool_, bool)):
        return bool(value)
    if isinstance(value, (np.integer, int)):
        return int(value)
    if isinstance(value, (np.floating, float)):
        return float(value)
    return value


def _result_summary(payload: dict) -> dict:
    statistics = payload["statistics"]
    comparisons = {}
    for method, method_comparisons in statistics["comparisons"].items():
        comparisons[method] = {}
        for comparison, entry in method_comparisons.items():
            comparisons[method][comparison] = {
                field: _json_ready(entry[field])
                for field in (
                    "mean_mse_difference",
                    "ci_low",
                    "ci_high",
                    "baseline_mse",
                    "meaningful_improvement_boundary",
                    "relative_rmse_fraction",
                    "point_estimate_passes",
                    "interval_passes",
                    "all_leads_pass",
                )
            }
    projection = {}
    for method_index, method in enumerate(_UNIQUE_METHODS):
        values = payload["projection_displacements"][..., method_index]
        projection[method] = {
            "fraction_nonzero": float(np.mean(values > 0.0)),
            "median_absolute_displacement": float(np.median(values)),
            "maximum_absolute_displacement": float(np.max(values)),
        }
    selection_counts = np.bincount(
        payload["maximum_posterior_indices"].ravel(),
        minlength=len(payload["candidate_ids"]),
    )
    return {
        "lead_days": _json_ready(payload["index"].lead_days),
        "same_stage_sample_count_per_block_truth": _json_ready(
            statistics["same_stage_sample_count_per_block_truth"]
        ),
        "rmse": {
            method: _json_ready(statistics["rmse"][method])
            for method in _ALL_METHODS
        },
        "comparisons": comparisons,
        "decisions": _json_ready(statistics["decisions"]),
        "time_strata": _json_ready(statistics["time_strata"]),
        "projection_diagnostics": projection,
        "maximum_posterior_candidate_selection_count": {
            str(candidate_id): int(selection_counts[index])
            for index, candidate_id in enumerate(payload["candidate_ids"])
        },
        "complete_minus_within_covariance_trace": {
            "mean": float(
                np.mean(
                    np.trace(
                        payload["posterior_between_covariances"],
                        axis1=-2,
                        axis2=-1,
                    )
                )
            ),
            "median": float(
                np.median(
                    np.trace(
                        payload["posterior_between_covariances"],
                        axis1=-2,
                        axis2=-1,
                    )
                )
            ),
        },
    }


def _evidence_arrays(payload: dict) -> dict[str, np.ndarray]:
    index = payload["index"]
    statistics = payload["statistics"]
    arrays: dict[str, np.ndarray] = {
        "block_ids": payload["block_ids"],
        "candidate_ids": payload["candidate_ids"],
        "parameter_ids": payload["parameter_ids"],
        "parameter_names": np.asarray(PARAMETER_NAMES),
        "candidate_parameter_matrix": payload[
            "candidate_parameter_matrix"
        ],
        "selected_process_covariance": payload[
            "selected_process_covariance"
        ],
        "selected_process_scale": np.asarray(
            payload["selected_process_scale"]
        ),
        "observation_standard_deviation": np.asarray(
            payload["observation_standard_deviation"]
        ),
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
        "bootstrap_indices": payload["bootstrap_indices"],
        "future_forcing": payload["future_forcing"],
        "current_candidate_forecasts": payload[
            "current_candidate_forecasts"
        ],
        "origin_probabilities": payload["origin_probabilities"],
        "origin_candidate_states": payload["origin_candidate_states"],
        "origin_candidate_covariances": payload[
            "origin_candidate_covariances"
        ],
        "posterior_mean_states": payload["posterior_mean_states"],
        "posterior_within_covariances": payload[
            "posterior_within_covariances"
        ],
        "posterior_between_covariances": payload[
            "posterior_between_covariances"
        ],
        "posterior_complete_covariances": payload[
            "posterior_complete_covariances"
        ],
        "uniform_mean_states": payload["uniform_mean_states"],
        "uniform_within_covariances": payload[
            "uniform_within_covariances"
        ],
        "uniform_between_covariances": payload[
            "uniform_between_covariances"
        ],
        "uniform_complete_covariances": payload[
            "uniform_complete_covariances"
        ],
        "maximum_posterior_indices": payload[
            "maximum_posterior_indices"
        ],
        "posterior_weighted_parameter_vectors": payload[
            "posterior_weighted_parameter_vectors"
        ],
        "maximum_parameter_vectors": payload[
            "maximum_parameter_vectors"
        ],
        "uniform_parameter_vectors": payload[
            "uniform_parameter_vectors"
        ],
        "unique_method_names": np.asarray(_UNIQUE_METHODS),
        "unique_projected_states": payload["unique_projected_states"],
        "projection_displacements": payload[
            "projection_displacements"
        ],
    }
    for method in _ALL_METHODS:
        arrays[f"forecast__{method}"] = payload["forecasts"][method]
        arrays[f"squared_error__{method}"] = statistics[
            "squared_errors"
        ][method]
        arrays[f"block_mse__{method}"] = statistics["block_mse"][method]
        arrays[f"rmse__{method}"] = statistics["rmse"][method]
    for method, method_comparisons in statistics["comparisons"].items():
        for comparison, entry in method_comparisons.items():
            for field in (
                "block_mean_mse_difference",
                "mean_mse_difference",
                "ci_low",
                "ci_high",
                "baseline_mse",
                "meaningful_improvement_boundary",
                "relative_rmse_fraction",
                "point_estimate_passes",
                "interval_passes",
            ):
                arrays[
                    f"comparison__{method}__{comparison}__{field}"
                ] = np.asarray(entry[field])
    for stratum, entry in statistics["time_strata"].items():
        arrays[f"stratum__{stratum}__sample_count"] = entry[
            "sample_count_per_block_truth"
        ]
        for method in _ALL_METHODS:
            arrays[f"stratum__{stratum}__rmse__{method}"] = entry[
                "rmse"
            ][method]
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


def run(
    repo_root: Path,
    config_path: Path,
    output_dir: Path,
    progress_callback=None,
) -> dict:
    root = Path(repo_root).resolve()
    config_file = Path(config_path).resolve()
    output = Path(output_dir).resolve()
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
        payload = _execute_development(
            root,
            config,
            progress_callback=progress_callback,
        )
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
            "readout_methods": config["readout_methods"],
            "comparison_controls": config["comparison_controls"],
            "stage_lengths": config["stage_lengths"],
            "switch_days": config["switch_days"],
            "decision_rules": config["decision_rules"],
            "scope_limit": config["scope_limit"],
            **payload["input_hashes"],
            "result": _result_summary(payload),
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

    def progress(completed, total, elapsed):
        print(
            json.dumps(
                {
                    "completed_blocks": completed,
                    "total_blocks": total,
                    "elapsed_seconds": round(float(elapsed), 1),
                }
            ),
            flush=True,
        )

    summary = run(
        arguments.repo_root,
        arguments.config,
        arguments.output_dir,
        progress_callback=progress,
    )
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
