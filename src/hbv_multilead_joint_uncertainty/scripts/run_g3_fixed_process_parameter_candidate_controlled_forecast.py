"""Run the fixed-process one-versus-three parameter-candidate forecast audit."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import sys
import tempfile
import time
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.daily_combined_state_error import (  # noqa: E402
    bootstrap_block_indices,
)
from hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast import (  # noqa: E402
    build_all_stage_daily_index,
    forecast_deterministic_state,
)
from hbv_multilead_joint_uncertainty.fixed_process_parameter_candidate_forecast import (  # noqa: E402
    CONTROLLED_METHOD_ROLES,
    CONTROLLED_METHODS,
    FIXED_FORECAST_PARAMETER_ID,
    FIXED_PROCESS_ID,
    SEALED_METHODS,
    select_fixed_forecast_parameter,
    summarize_controlled_forecasts,
    validate_common_forecast_parameters,
    validate_controlled_candidate_contract,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs/"
    "g3_fixed_process_parameter_candidate_controlled_forecast_v01.json"
)
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    "g3_fixed_process_parameter_candidate_controlled_forecast_v01"
)
EXPECTED_EXPERIMENT_ID = "g3_fixed_process_parameter_candidate_controlled_forecast_v01"
EXPECTED_SOURCE_MAPPING = {
    CONTROLLED_METHODS[0]: "fixed_filter",
    CONTROLLED_METHODS[1]: "parameter_only",
}
PREFLIGHT_ORIGINS = (0, 179, 180, 359, 360, 539)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_json(path: Path, payload) -> None:
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _require_unused_output(output_dir: Path) -> None:
    if output_dir.exists():
        raise FileExistsError(f"output directory already exists: {output_dir}")


def _validate_frozen_config(config: dict) -> None:
    if config.get("experiment_id") != EXPECTED_EXPERIMENT_ID:
        raise ValueError("experiment identifier differs from the frozen contract")
    if tuple(config.get("state_methods", ())) != CONTROLLED_METHODS:
        raise ValueError("state method order differs from the frozen contract")
    if config.get("source_method_mapping") != EXPECTED_SOURCE_MAPPING:
        raise ValueError("source method mapping differs from the frozen contract")
    if config.get("fixed_process_id") != FIXED_PROCESS_ID:
        raise ValueError("both methods must keep process_2 fixed")
    if config.get("fixed_forecast_parameter_id") != FIXED_FORECAST_PARAMETER_ID:
        raise ValueError("both methods must forecast with trained_center")
    if config.get("assimilation_days") != 540:
        raise ValueError("assimilation days must equal 540")
    if tuple(config.get("lead_days", ())) != tuple(range(1, 8)):
        raise ValueError("lead days must equal 1 through 7")
    if config.get("cross_switch_policy") != "exclude_from_primary_metrics":
        raise ValueError("cross-switch targets must be excluded from primary metrics")
    bootstrap = config.get("bootstrap", {})
    if bootstrap != {
        "replicates": 20000,
        "seed": 20260801,
        "unit": "matched_block",
    }:
        raise ValueError("matched-block bootstrap differs from the frozen contract")
    rule = config.get("decision_rule", {})
    if (
        rule.get("minimum_relative_rmse_reduction") != 0.01
        or rule.get("pointwise_confidence_level") != 0.95
        or rule.get("paired_mse_interval_upper_bound_below_zero") is not True
    ):
        raise ValueError("decision rule differs from the frozen contract")
    tolerance = config.get("numerical_tolerance")
    if not isinstance(tolerance, (int, float)) or tolerance <= 0.0:
        raise ValueError("numerical tolerance must be positive")
    sealed = config.get("sealed_ideal_evidence", {})
    if not sealed.get("path") or len(str(sealed.get("sha256", ""))) != 64:
        raise ValueError("sealed evidence identity is incomplete")


def _build_truth_forecasts(truth_discharge, target_indices) -> np.ndarray:
    truth = np.asarray(truth_discharge, dtype=np.float64)
    targets = np.asarray(target_indices)
    if truth.ndim != 3 or not np.all(np.isfinite(truth)):
        raise ValueError("truth discharge must be finite [blocks, truths, days]")
    if (
        targets.ndim != 2
        or not np.issubdtype(targets.dtype, np.integer)
        or np.any(targets < 0)
        or np.any(targets >= truth.shape[-1])
    ):
        raise ValueError("target indices are invalid for truth discharge")
    return truth[:, :, targets]


def _parameter_mapping(vector) -> dict[str, float]:
    values = np.asarray(vector, dtype=np.float64)
    if values.shape != (len(PARAMETER_NAMES),):
        raise ValueError("forecast parameter vector has the wrong length")
    return {name: float(value) for name, value in zip(PARAMETER_NAMES, values)}


def _reference_forecast(state, parameter_vector, forcing, lead_days) -> np.ndarray:
    parameters = _parameter_mapping(parameter_vector)
    current = np.asarray(state, dtype=np.float64).copy()
    leads = np.asarray(lead_days, dtype=np.int64)
    result = np.empty(len(leads), dtype=np.float64)
    lead_to_row = {int(value): row for row, value in enumerate(leads)}
    for step in range(1, int(leads[-1]) + 1):
        current = advance_reference_state(current, *forcing[step - 1], parameters)
        if step in lead_to_row:
            result[lead_to_row[step]] = reference_routed_discharge(
                current, parameters["lag_time"]
            )
    return result


def _validate_source_shapes(
    method_states,
    forcing,
    truth_discharge,
    truth_parameter_indices,
    *,
    assimilation_days: int,
    maximum_lead: int,
) -> None:
    if method_states.shape != (8, 3, len(SEALED_METHODS), assimilation_days, 15):
        raise ValueError("sealed combined-state array shape differs from the contract")
    if forcing.ndim != 3 or forcing.shape[0] != 8 or forcing.shape[2] != 3:
        raise ValueError("sealed forcing array shape differs from the contract")
    if truth_discharge.shape[0:2] != (8, 3):
        raise ValueError("sealed truth discharge shape differs from the contract")
    if truth_parameter_indices.shape[0] != 3:
        raise ValueError("sealed truth parameter schedule differs from the contract")
    required_days = assimilation_days + maximum_lead
    if truth_discharge.shape[-1] < required_days or truth_parameter_indices.shape[-1] < required_days:
        raise ValueError("sealed truth arrays do not cover all forecast targets")
    if not all(
        np.all(np.isfinite(values))
        for values in (method_states, forcing, truth_discharge)
    ):
        raise ValueError("sealed forecast inputs must be finite")


def _run_preflight(states, parameter_vector, active_forcing, lead_days, tolerance):
    maximum = 0.0
    count = 0
    for method in CONTROLLED_METHODS:
        method_states = states[method]
        for block in range(method_states.shape[0]):
            for truth in range(method_states.shape[1]):
                for origin in PREFLIGHT_ORIGINS:
                    future = active_forcing[
                        block, origin + 1 : origin + 1 + int(lead_days[-1])
                    ]
                    production = forecast_deterministic_state(
                        method_states[block, truth, origin],
                        parameter_vector,
                        future,
                        lead_days,
                    ).discharge
                    reference = _reference_forecast(
                        method_states[block, truth, origin],
                        parameter_vector,
                        future,
                        lead_days,
                    )
                    maximum = max(
                        maximum,
                        float(np.max(np.abs(production - reference), initial=0.0)),
                    )
                    count += 1
    if maximum > tolerance:
        raise RuntimeError("production-reference deterministic preflight failed")
    return count, maximum


def _forecast_all(states, parameter_vector, active_forcing, lead_days):
    result = {}
    origin_count = next(iter(states.values())).shape[2]
    maximum_lead = int(lead_days[-1])
    for method_number, method in enumerate(CONTROLLED_METHODS, start=1):
        method_states = states[method]
        values = np.empty(
            (method_states.shape[0], method_states.shape[1], origin_count, len(lead_days)),
            dtype=np.float64,
        )
        for block in range(method_states.shape[0]):
            for truth in range(method_states.shape[1]):
                for origin in range(origin_count):
                    values[block, truth, origin] = forecast_deterministic_state(
                        method_states[block, truth, origin],
                        parameter_vector,
                        active_forcing[
                            block, origin + 1 : origin + 1 + maximum_lead
                        ],
                        lead_days,
                    ).discharge
        result[method] = values
        print(
            f"controlled state methods {method_number}/{len(CONTROLLED_METHODS)}",
            flush=True,
        )
    return result


def _artifact_checksums(directory: Path) -> dict[str, str]:
    names = ("config_snapshot.json", "environment.json", "evidence.npz", "summary.json")
    return {name: _sha256(directory / name) for name in names}


def run(config_path: Path, output_dir: Path) -> dict:
    config_path = config_path.resolve()
    output_dir = output_dir.resolve()
    _require_unused_output(output_dir)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    _validate_frozen_config(config)
    source = (PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]).resolve()
    source_sha = _sha256(source)
    if source_sha != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed ideal evidence SHA-256 mismatch")

    started = time.monotonic()
    with np.load(source, allow_pickle=False) as evidence:
        contract = validate_controlled_candidate_contract(
            evidence["method_names"],
            evidence["method_candidate_ids"],
            evidence["method_candidate_counts"],
        )
        if contract.fixed_process_id != config["fixed_process_id"]:
            raise ValueError("sealed process candidate differs from the frozen config")
        parameter_ids = tuple(str(value) for value in evidence["parameter_ids"])
        process_ids = tuple(str(value) for value in evidence["process_ids"])
        if parameter_ids != (
            "equifinal_diverse_1",
            "trained_center",
            "equifinal_diverse_2",
        ):
            raise ValueError("sealed parameter identifier order changed")
        if process_ids != ("process_0", "process_1", "process_2"):
            raise ValueError("sealed process identifier order changed")
        fixed_parameter = select_fixed_forecast_parameter(
            evidence["parameter_ids"],
            evidence["parameter_vectors"],
            config["fixed_forecast_parameter_id"],
        )
        common_parameter = validate_common_forecast_parameters(
            fixed_parameter, fixed_parameter, fixed_parameter
        )
        assimilation_days = int(np.asarray(evidence["assimilation_days"]).item())
        if assimilation_days != config["assimilation_days"]:
            raise ValueError("sealed assimilation day count differs from the config")
        schedule = np.asarray(evidence["truth_parameter_indices"], dtype=np.int64)
        index = build_all_stage_daily_index(
            schedule,
            assimilation_days=assimilation_days,
            lead_days=config["lead_days"],
        )
        all_method_states = np.asarray(
            evidence["method_assimilation_states"][:, :, :, :assimilation_days],
            dtype=np.float64,
        )
        forcing = np.asarray(evidence["forcing_blocks"], dtype=np.float64)
        truth_discharge = np.asarray(evidence["truth_discharge"], dtype=np.float64)
        _validate_source_shapes(
            all_method_states,
            forcing,
            truth_discharge,
            schedule,
            assimilation_days=assimilation_days,
            maximum_lead=int(index.lead_days[-1]),
        )
        states = {
            method: all_method_states[:, :, source_index].copy()
            for method, source_index in zip(
                CONTROLLED_METHODS, contract.source_method_indices
            )
        }
        warmup_days = int(np.asarray(evidence["warmup_days"]).item())
        active_forcing = forcing[:, warmup_days:]
        if active_forcing.shape[1] < assimilation_days + int(index.lead_days[-1]):
            raise ValueError("active forcing does not cover every forecast target")
        truth_forecasts = _build_truth_forecasts(
            truth_discharge, index.target_indices
        )
        preflight_count, preflight_maximum = _run_preflight(
            states,
            common_parameter,
            active_forcing,
            index.lead_days,
            float(config["numerical_tolerance"]),
        )
        forecasts = _forecast_all(
            states, common_parameter, active_forcing, index.lead_days
        )

    bootstrap = bootstrap_block_indices(
        truth_forecasts.shape[0],
        int(config["bootstrap"]["replicates"]),
        int(config["bootstrap"]["seed"]),
    )
    statistics = summarize_controlled_forecasts(
        forecasts,
        truth_forecasts,
        index.same_stage_mask,
        index.origin_parameter_indices,
        parameter_ids,
        bootstrap,
        minimum_relative_rmse_reduction=float(
            config["decision_rule"]["minimum_relative_rmse_reduction"]
        ),
    )

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{output_dir.name}.incomplete.", dir=str(output_dir.parent)
        )
    )
    published = False
    try:
        shutil.copy2(config_path, staging / "config_snapshot.json")
        npz = {
            "method_names": np.asarray(CONTROLLED_METHODS),
            "source_method_names": np.asarray(contract.source_method_names),
            "source_method_indices": np.asarray(contract.source_method_indices, dtype=np.int64),
            "fixed_filter_candidate_ids": np.asarray(contract.fixed_filter_candidates),
            "three_parameter_candidate_ids": np.asarray(contract.parameter_candidates),
            "fixed_process_id": np.asarray(contract.fixed_process_id),
            "fixed_forecast_parameter_id": np.asarray(contract.fixed_forecast_parameter_id),
            "fixed_forecast_parameter_vector": common_parameter,
            "parameter_ids": np.asarray(parameter_ids),
            "lead_days": index.lead_days,
            "origin_indices": index.origin_indices,
            "target_indices": index.target_indices,
            "origin_parameter_indices": index.origin_parameter_indices,
            "target_parameter_indices": index.target_parameter_indices,
            "same_stage_mask": index.same_stage_mask,
            "truth_forecasts": truth_forecasts,
            "bootstrap_indices": bootstrap,
            "same_stage_sample_count_per_block": statistics["same_stage_sample_count_per_block"],
            "same_stage_sample_count_all_blocks": statistics["same_stage_sample_count_all_blocks"],
            "stage_sample_count_per_block": statistics["stage_sample_count_per_block"],
            "stage_rmse": statistics["stage_rmse"],
            "block_mse_difference": statistics["block_mse_difference"],
            "mean_mse_difference": statistics["mean_mse_difference"],
            "paired_mse_ci_low": statistics["ci_low"],
            "paired_mse_ci_high": statistics["ci_high"],
            "relative_rmse_fraction": statistics["relative_rmse_fraction"],
            "improvement_decision": statistics["improvement_decision"],
        }
        for method in CONTROLLED_METHODS:
            npz[f"forecast__{method}"] = forecasts[method]
            npz[f"rmse__{method}"] = statistics["rmse"][method]
            npz[f"block_mse__{method}"] = statistics["block_mse"][method]
        np.savez_compressed(staging / "evidence.npz", **npz)

        relative_percent = 100.0 * statistics["relative_rmse_fraction"]
        summary = {
            "experiment_id": config["experiment_id"],
            "classification": config["classification"],
            "status": "complete_pending_independent_verification",
            "controlled_question": (
                "With process_2 fixed during assimilation and trained_center fixed "
                "during forecast, does the standard fully interacting "
                "three-parameter-model global posterior improve deterministic "
                "forecasts relative to one fixed-parameter filter posterior?"
            ),
            "comparison_factor": (
                "single fixed-parameter filter versus standard fully interacting "
                "three-parameter-model method"
            ),
            "method_roles": CONTROLLED_METHOD_ROLES,
            "mechanism_attribution_allowed": False,
            "mechanism_attribution_limit": (
                "The forecast readout is controlled, but the source-state "
                "comparison does not separate additional models from the "
                "interaction and probability-combination mechanisms."
            ),
            "fixed_factors": {
                "process_covariance_identifier": FIXED_PROCESS_ID,
                "forecast_parameter_identifier": FIXED_FORECAST_PARAMETER_ID,
                "forecast_state_count": 1,
                "forecast_trajectory_count": 1,
                "forecast_covariance_used": False,
                "candidate_forecast_trajectories_used": False,
                "future_discharge_observations_used": False,
            },
            "candidate_contract": {
                "single_filter_candidates": list(contract.fixed_filter_candidates),
                "three_parameter_candidates": list(contract.parameter_candidates),
            },
            "lead_days": index.lead_days.tolist(),
            "same_stage_sample_count_per_block": statistics[
                "same_stage_sample_count_per_block"
            ].tolist(),
            "same_stage_sample_count_all_blocks": statistics[
                "same_stage_sample_count_all_blocks"
            ].tolist(),
            "all_stage_primary": {
                "single_filter_root_mean_square_error": statistics["rmse"][
                    CONTROLLED_METHODS[0]
                ].tolist(),
                "three_parameter_candidates_root_mean_square_error": statistics[
                    "rmse"
                ][CONTROLLED_METHODS[1]].tolist(),
                "three_minus_single_relative_root_mean_square_error_percent": relative_percent.tolist(),
                "three_minus_single_mean_squared_error_difference": statistics[
                    "mean_mse_difference"
                ].tolist(),
                "paired_mean_squared_error_difference_95_percent_interval_low": statistics[
                    "ci_low"
                ].tolist(),
                "paired_mean_squared_error_difference_95_percent_interval_high": statistics[
                    "ci_high"
                ].tolist(),
                "three_parameter_candidates_improves": statistics[
                    "improvement_decision"
                ].tolist(),
            },
            "true_parameter_group_diagnostics": {
                name: {
                    CONTROLLED_METHODS[method_index]: statistics["stage_rmse"][
                        method_index, stage_index
                    ].tolist()
                    for method_index in range(len(CONTROLLED_METHODS))
                }
                for stage_index, name in enumerate(parameter_ids)
            },
            "correctness_gates": {
                "source_sha256_matches": True,
                "candidate_structure_matches": True,
                "common_forecast_parameter_matches": True,
                "production_reference_comparisons": preflight_count,
                "production_reference_maximum_absolute_difference": preflight_maximum,
                "numerical_tolerance": float(config["numerical_tolerance"]),
                "passed": True,
            },
            "elapsed_seconds": time.monotonic() - started,
            "scope_limit": config["scope_limit"],
        }
        _write_json(staging / "summary.json", summary)
        _write_json(
            staging / "environment.json",
            {
                "python": sys.version,
                "platform": platform.platform(),
                "numpy": np.__version__,
                "sealed_ideal_evidence": str(source),
                "sealed_ideal_evidence_sha256": source_sha,
            },
        )
        checksums = {
            "sealed_ideal_evidence_sha256": source_sha,
            **_artifact_checksums(staging),
        }
        _write_json(staging / "checksums.json", checksums)
        _require_unused_output(output_dir)
        os.replace(staging, output_dir)
        published = True
    finally:
        if not published and staging.exists():
            shutil.rmtree(staging)

    print(json.dumps(summary, indent=2, ensure_ascii=False), flush=True)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    run(args.config, args.output_dir)


if __name__ == "__main__":
    main()
