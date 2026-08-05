"""Run the HBV state-interaction-only deterministic forecast control."""

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
from hbv_multilead_joint_uncertainty.state_interaction_controlled_forecast import (  # noqa: E402
    CONTROLLED_METHODS,
    DIFFERENCE_DEFINITION,
    summarize_state_interaction_forecasts,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs/"
    "g3_fixed_process_state_interaction_controlled_forecast_v01.json"
)
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    "g3_fixed_process_state_interaction_controlled_forecast_v01"
)
EXPERIMENT_ID = "g3_fixed_process_state_interaction_controlled_forecast_v01"
SEALED_STATE_METHODS = (
    "fully_interacting_multiple_model_global_posterior_state",
    "noninteracting_multiple_filter_global_posterior_state_control",
)
SEALED_INTERACTION_MODES = ("full", "none")
STATE_METHOD_MAPPING = dict(zip(CONTROLLED_METHODS, SEALED_STATE_METHODS))
PARAMETER_IDS = (
    "equifinal_diverse_1",
    "trained_center",
    "equifinal_diverse_2",
)
PARAMETER_CANDIDATES = tuple(f"{name}__process_2" for name in PARAMETER_IDS)
PREFLIGHT_ORIGINS = (0, 179, 180, 359, 360, 539)
SEALED_CONFIG_KEYS = (
    "sealed_state_audit_evidence",
    "sealed_state_audit_summary",
    "sealed_state_audit_independent_verification",
    "sealed_state_audit_config_snapshot",
    "sealed_ideal_evidence",
)
EXPECTED_SEALED_HASHES = {
    "sealed_state_audit_evidence": "22f1b99ee0cf537e1aa7c9b414662c0b390510f2dc0d6b07bf538dd6dda33a04",
    "sealed_state_audit_summary": "b18abfe809839df4ffb870e54f00943a3d846c329e00f6ad474dfe50437de693",
    "sealed_state_audit_independent_verification": "345663c14c5db53b09ca98150d562aeca877c91d8f741fd8e49d3158c84aecff",
    "sealed_state_audit_config_snapshot": "087bc87c00f6a8a25925c3aaa863420587df448e306222a982d11efbc34da1bf",
    "sealed_ideal_evidence": "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67",
}


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


def _validate_config(config: dict) -> None:
    if config.get("experiment_id") != EXPERIMENT_ID:
        raise ValueError("experiment identifier differs from the frozen contract")
    if config.get("model_family") != "HBV":
        raise ValueError("model family must remain HBV")
    if config.get("only_changed_factor") != (
        "assimilation state and covariance interaction"
    ):
        raise ValueError("only changed factor differs from the frozen contract")
    if tuple(config.get("state_methods", ())) != CONTROLLED_METHODS:
        raise ValueError("state method order differs from the frozen contract")
    if config.get("sealed_state_method_mapping") != STATE_METHOD_MAPPING:
        raise ValueError("sealed state method mapping differs from the frozen contract")
    if config.get("fixed_process_id") != "process_2":
        raise ValueError("both assimilation methods must keep process_2 fixed")
    if config.get("fixed_forecast_parameter_id") != "trained_center":
        raise ValueError("both forecasts must use trained_center")
    fixed_boolean_contract = {
        "forecast_state_count": 1,
        "forecast_trajectory_count": 1,
        "forecast_covariance_used": False,
        "candidate_forecast_trajectories_used": False,
        "future_discharge_observations_used": False,
        "matched_block_count": 8,
        "truth_trial_count": 3,
        "assimilation_days": 540,
        "state_count": 15,
    }
    if any(config.get(name) != value for name, value in fixed_boolean_contract.items()):
        raise ValueError("population or single-trajectory contract changed")
    if tuple(config.get("lead_days", ())) != tuple(range(1, 8)):
        raise ValueError("lead days must equal one through seven")
    if config.get("cross_switch_policy") != "exclude_from_primary_metrics":
        raise ValueError("cross-stage targets must be excluded from primary metrics")
    if config.get("primary_grouping") != (
        "all valid daily origins grouped only by forecast lead"
    ):
        raise ValueError("primary grouping differs from the full-stage contract")
    if config.get("bootstrap") != {
        "replicates": 20000,
        "seed": 20260801,
        "unit": "matched_block",
    }:
        raise ValueError("matched-block bootstrap differs from the frozen contract")
    if config.get("decision_rule") != {
        "minimum_relative_rmse_reduction": 0.01,
        "pointwise_confidence_level": 0.95,
        "paired_mse_interval_upper_bound_below_zero": True,
        "difference_definition": DIFFERENCE_DEFINITION,
    }:
        raise ValueError("decision rule differs from the frozen contract")
    if config.get("numerical_tolerance") != 1e-10:
        raise ValueError("numerical tolerance differs from the frozen contract")
    for key in SEALED_CONFIG_KEYS:
        item = config.get(key, {})
        if not item.get("path") or item.get("sha256") != EXPECTED_SEALED_HASHES[key]:
            raise ValueError(f"sealed input identity differs for {key}")


def _sealed_paths_and_hashes(config: dict) -> tuple[dict[str, Path], dict[str, str]]:
    paths: dict[str, Path] = {}
    hashes: dict[str, str] = {}
    for key in SEALED_CONFIG_KEYS:
        path = (PROJECT_ROOT / config[key]["path"]).resolve()
        actual = _sha256(path)
        if actual != config[key]["sha256"]:
            raise ValueError(f"sealed input SHA-256 mismatch: {key}")
        paths[key] = path
        hashes[key] = actual
    verification = json.loads(
        paths["sealed_state_audit_independent_verification"].read_text(
            encoding="utf-8"
        )
    )
    if (
        verification.get("status") != "passed"
        or verification.get("evidence_sha256")
        != hashes["sealed_state_audit_evidence"]
        or verification.get("sealed_ideal_evidence_sha256")
        != hashes["sealed_ideal_evidence"]
    ):
        raise ValueError("sealed state audit is not independently verified")
    return paths, hashes


def _select_source_states(method_names, global_states):
    names = tuple(str(value) for value in np.asarray(method_names).tolist())
    values = np.asarray(global_states, dtype=np.float64)
    if names != SEALED_STATE_METHODS:
        raise ValueError("sealed state method names changed")
    if values.ndim != 5 or values.shape[2] != len(names):
        raise ValueError("sealed global posterior state axes changed")
    if not np.all(np.isfinite(values)):
        raise ValueError("sealed global posterior states must be finite")
    indices = tuple(names.index(STATE_METHOD_MAPPING[method]) for method in CONTROLLED_METHODS)
    selected = {
        method: values[:, :, index].copy()
        for method, index in zip(CONTROLLED_METHODS, indices)
    }
    return selected, indices


def _select_fixed_parameter(parameter_ids, parameter_vectors) -> np.ndarray:
    names = tuple(str(value) for value in np.asarray(parameter_ids).tolist())
    vectors = np.asarray(parameter_vectors, dtype=np.float64)
    if names != PARAMETER_IDS or vectors.shape != (3, len(PARAMETER_NAMES)):
        raise ValueError("sealed parameter vectors differ from the frozen contract")
    if not np.all(np.isfinite(vectors)):
        raise ValueError("sealed parameter vectors must be finite")
    return vectors[names.index("trained_center")].copy()


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


def _run_preflight(states, parameter_vector, active_forcing, lead_days, tolerance):
    maximum = 0.0
    comparison_count = 0
    for method in CONTROLLED_METHODS:
        for block in range(8):
            for truth in range(3):
                for origin in PREFLIGHT_ORIGINS:
                    future = active_forcing[block, origin + 1 : origin + 8]
                    production = forecast_deterministic_state(
                        states[method][block, truth, origin],
                        parameter_vector,
                        future,
                        lead_days,
                    ).discharge
                    reference = _reference_forecast(
                        states[method][block, truth, origin],
                        parameter_vector,
                        future,
                        lead_days,
                    )
                    maximum = max(
                        maximum,
                        float(np.max(np.abs(production - reference), initial=0.0)),
                    )
                    comparison_count += 1
    if maximum > tolerance:
        raise RuntimeError("production-reference deterministic preflight failed")
    return comparison_count, maximum


def _forecast_all(states, parameter_vector, active_forcing, lead_days):
    forecasts: dict[str, np.ndarray] = {}
    for method_number, method in enumerate(CONTROLLED_METHODS, start=1):
        values = np.empty((8, 3, 540, 7), dtype=np.float64)
        for block in range(8):
            for truth in range(3):
                for origin in range(540):
                    values[block, truth, origin] = forecast_deterministic_state(
                        states[method][block, truth, origin],
                        parameter_vector,
                        active_forcing[block, origin + 1 : origin + 8],
                        lead_days,
                    ).discharge
        forecasts[method] = values
        print(
            f"state-interaction forecast method {method_number}/{len(CONTROLLED_METHODS)}",
            flush=True,
        )
    return forecasts


def _artifact_checksums(directory: Path) -> dict[str, str]:
    names = ("config_snapshot.json", "environment.json", "evidence.npz", "summary.json")
    return {name: _sha256(directory / name) for name in names}


def run(config_path: Path, output_dir: Path) -> dict:
    config_path = config_path.resolve()
    output_dir = output_dir.resolve()
    _require_unused_output(output_dir)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    _validate_config(config)
    sealed_paths, sealed_hashes = _sealed_paths_and_hashes(config)

    started = time.monotonic()
    with np.load(
        sealed_paths["sealed_state_audit_evidence"], allow_pickle=False
    ) as state_archive:
        state_arrays = {name: state_archive[name].copy() for name in state_archive.files}
    with np.load(sealed_paths["sealed_ideal_evidence"], allow_pickle=False) as ideal:
        if int(np.asarray(ideal["assimilation_days"]).item()) != 540:
            raise ValueError("sealed assimilation day count changed")
        parameter_vector = _select_fixed_parameter(
            ideal["parameter_ids"], ideal["parameter_vectors"]
        )
        schedule = np.asarray(ideal["truth_parameter_indices"], dtype=np.int64)
        forcing = np.asarray(ideal["forcing_blocks"], dtype=np.float64)
        warmup_days = int(np.asarray(ideal["warmup_days"]).item())
        active_forcing = forcing[:, warmup_days:]
        truth_discharge = np.asarray(ideal["truth_discharge"], dtype=np.float64)
        ideal_truth_states = np.asarray(ideal["truth_states"][:, :, :540], dtype=np.float64)

    if tuple(state_arrays["interaction_modes"].astype(str)) != SEALED_INTERACTION_MODES:
        raise ValueError("sealed interaction modes changed")
    if str(state_arrays["fixed_process_id"].item()) != "process_2":
        raise ValueError("sealed state process identifier changed")
    if tuple(state_arrays["parameter_candidate_ids"].astype(str)) != PARAMETER_CANDIDATES:
        raise ValueError("sealed parameter candidate identifiers changed")
    if not np.array_equal(state_arrays["day_indices"], np.arange(540)):
        raise ValueError("sealed daily state indices changed")
    if not np.array_equal(state_arrays["truth_states"], ideal_truth_states):
        raise ValueError("state-audit truth states do not match ideal evidence")
    states, source_indices = _select_source_states(
        state_arrays["method_names"], state_arrays["global_posterior_states"]
    )
    expected_shape = (8, 3, 540, 15)
    if any(values.shape != expected_shape for values in states.values()):
        raise ValueError("selected origin-state shape differs from the frozen contract")
    if active_forcing.shape != (8, 547, 3):
        raise ValueError("active forcing shape differs from the frozen contract")
    if truth_discharge.shape != (8, 3, 547) or schedule.shape != (3, 547):
        raise ValueError("truth target arrays differ from the frozen contract")

    index = build_all_stage_daily_index(
        schedule, assimilation_days=540, lead_days=config["lead_days"]
    )
    truth_forecasts = _build_truth_forecasts(truth_discharge, index.target_indices)
    preflight_count, preflight_maximum = _run_preflight(
        states,
        parameter_vector,
        active_forcing,
        index.lead_days,
        float(config["numerical_tolerance"]),
    )
    forecasts = _forecast_all(
        states, parameter_vector, active_forcing, index.lead_days
    )
    bootstrap = bootstrap_block_indices(
        8,
        int(config["bootstrap"]["replicates"]),
        int(config["bootstrap"]["seed"]),
    )
    statistics = summarize_state_interaction_forecasts(
        forecasts,
        truth_forecasts,
        index.same_stage_mask,
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
        evidence = {
            "method_names": np.asarray(CONTROLLED_METHODS),
            "sealed_source_method_names": np.asarray(SEALED_STATE_METHODS),
            "sealed_source_method_indices": np.asarray(source_indices, dtype=np.int64),
            "interaction_modes": np.asarray(SEALED_INTERACTION_MODES),
            "difference_definition": np.asarray(DIFFERENCE_DEFINITION),
            "fixed_process_id": np.asarray("process_2"),
            "fixed_forecast_parameter_id": np.asarray("trained_center"),
            "fixed_forecast_parameter_vector": parameter_vector,
            "lead_days": index.lead_days,
            "origin_indices": index.origin_indices,
            "target_indices": index.target_indices,
            "origin_parameter_indices": index.origin_parameter_indices,
            "target_parameter_indices": index.target_parameter_indices,
            "same_stage_mask": index.same_stage_mask,
            "truth_forecasts": truth_forecasts,
            "bootstrap_indices": bootstrap,
            "same_stage_sample_count_per_block": statistics[
                "same_stage_sample_count_per_block"
            ],
            "same_stage_sample_count_all_blocks": statistics[
                "same_stage_sample_count_all_blocks"
            ],
            "block_mse_difference": statistics["block_mse_difference"],
            "mean_mse_difference": statistics["mean_mse_difference"],
            "paired_mse_ci_low": statistics["ci_low"],
            "paired_mse_ci_high": statistics["ci_high"],
            "relative_rmse_fraction": statistics["relative_rmse_fraction"],
            "improvement_decision": statistics["improvement_decision"],
        }
        for method in CONTROLLED_METHODS:
            evidence[f"origin_states__{method}"] = states[method]
            evidence[f"forecast__{method}"] = forecasts[method]
            evidence[f"rmse__{method}"] = statistics["rmse"][method]
            evidence[f"block_mse__{method}"] = statistics["block_mse"][method]
        np.savez_compressed(staging / "evidence.npz", **evidence)

        relative_percent = 100.0 * statistics["relative_rmse_fraction"]
        decisions = [
            "improves" if value else "does_not_meet_improvement_criteria"
            for value in statistics["improvement_decision"]
        ]
        summary = {
            "experiment_id": EXPERIMENT_ID,
            "classification": config["classification"],
            "status": "complete_pending_independent_verification",
            "question": (
                "Does full state-and-covariance interaction improve one-through-seven-day "
                "deterministic HBV forecasts relative to no state interaction?"
            ),
            "only_changed_factor": config["only_changed_factor"],
            "difference_definition": DIFFERENCE_DEFINITION,
            "method_roles": {
                CONTROLLED_METHODS[0]: "one global posterior state after full interaction",
                CONTROLLED_METHODS[1]: "one global posterior state without interaction",
            },
            "fixed_factors": {
                "same_three_fixed_parameter_models_during_assimilation": True,
                "process_covariance_identifier": "process_2",
                "forecast_parameter_identifier": "trained_center",
                "forcing_and_targets_identical": True,
                "forecast_state_count": 1,
                "forecast_trajectory_count": 1,
                "forecast_covariance_used": False,
                "candidate_forecast_trajectories_used": False,
                "future_discharge_observations_used": False,
            },
            "population": {
                "matched_blocks": 8,
                "truth_scenarios_per_block": 3,
                "daily_origins": 540,
                "state_count": 15,
                "lead_days": index.lead_days.tolist(),
                "cross_stage_targets_excluded": True,
            },
            "same_stage_sample_count_per_block": statistics[
                "same_stage_sample_count_per_block"
            ].tolist(),
            "same_stage_sample_count_all_blocks": statistics[
                "same_stage_sample_count_all_blocks"
            ].tolist(),
            "all_stage_primary": {
                "fully_interacting_root_mean_square_error": statistics["rmse"][
                    CONTROLLED_METHODS[0]
                ].tolist(),
                "noninteracting_root_mean_square_error": statistics["rmse"][
                    CONTROLLED_METHODS[1]
                ].tolist(),
                "full_minus_none_relative_root_mean_square_error_percent": relative_percent.tolist(),
                "full_minus_none_mean_squared_error_difference": statistics[
                    "mean_mse_difference"
                ].tolist(),
                "paired_mean_squared_error_difference_95_percent_interval_low": statistics[
                    "ci_low"
                ].tolist(),
                "paired_mean_squared_error_difference_95_percent_interval_high": statistics[
                    "ci_high"
                ].tolist(),
                "full_interaction_improves": statistics[
                    "improvement_decision"
                ].tolist(),
                "decision": decisions,
            },
            "correctness_gates": {
                "all_sealed_hashes_match": True,
                "sealed_state_audit_independent_verification_passed": True,
                "source_method_indices": list(source_indices),
                "state_audit_truth_matches_ideal_truth": True,
                "common_forecast_parameter_matches": True,
                "time_alignment_and_same_stage_mask_valid": True,
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
                "sealed_input_paths": {
                    key: str(path) for key, path in sealed_paths.items()
                },
                "sealed_input_sha256": sealed_hashes,
            },
        )
        checksums = {
            "sealed_inputs": sealed_hashes,
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
