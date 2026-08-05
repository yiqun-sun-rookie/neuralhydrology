"""Independently verify the HBV state-interaction forecast control."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


EXPERIMENT_ID = (
    "g3_fixed_process_" "state_interaction_" "controlled_forecast_v01"
)
DEFAULT_RESULT = (
    PROJECT_ROOT / "results/23_hbv_multilead_joint_uncertainty" / EXPERIMENT_ID
)
CONTROLLED_METHODS = (
    "fully_interacting_global_posterior_state",
    "noninteracting_global_posterior_state",
)
SEALED_STATE_METHODS = (
    "fully_interacting_multiple_model_global_posterior_state",
    "noninteracting_multiple_filter_global_posterior_state_control",
)
PARAMETER_IDS = (
    "equifinal_diverse_1",
    "trained_center",
    "equifinal_diverse_2",
)
DIFFERENCE_DEFINITION = "full_interaction_minus_no_interaction"
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


def _maximum_difference(left, right) -> float:
    left_values = np.asarray(left, dtype=np.float64)
    right_values = np.asarray(right, dtype=np.float64)
    if left_values.shape != right_values.shape:
        return float("inf")
    if not np.array_equal(np.isnan(left_values), np.isnan(right_values)):
        return float("inf")
    if not np.array_equal(np.isinf(left_values), np.isinf(right_values)):
        return float("inf")
    finite = np.isfinite(left_values) & np.isfinite(right_values)
    return float(
        np.max(np.abs(left_values[finite] - right_values[finite]), initial=0.0)
    )


def _reference_forecast(state, parameter_vector, forcing) -> np.ndarray:
    parameters = {
        name: float(value)
        for name, value in zip(
            PARAMETER_NAMES, np.asarray(parameter_vector, dtype=np.float64)
        )
    }
    current = np.asarray(state, dtype=np.float64).copy()
    result = np.empty(7, dtype=np.float64)
    for lead in range(7):
        current = advance_reference_state(current, *forcing[lead], parameters)
        result[lead] = reference_routed_discharge(
            current, parameters["lag_time"]
        )
    return result


def _recompute_statistics(forecasts, truth, same_stage, bootstrap):
    block_count, _, _, lead_count = truth.shape
    rmse = np.empty((2, lead_count), dtype=np.float64)
    block_mse = np.empty((2, block_count, lead_count), dtype=np.float64)
    for method_index, method in enumerate(CONTROLLED_METHODS):
        squared = np.square(forecasts[method] - truth)
        for lead in range(lead_count):
            selected = squared[..., lead][:, same_stage[..., lead]]
            rmse[method_index, lead] = np.sqrt(np.mean(selected))
            block_mse[method_index, :, lead] = np.mean(selected, axis=1)
    difference = block_mse[0] - block_mse[1]
    bootstrap_means = np.mean(difference[bootstrap], axis=1)
    mean_difference = np.mean(difference, axis=0)
    ci_low = np.quantile(bootstrap_means, 0.025, axis=0)
    ci_high = np.quantile(bootstrap_means, 0.975, axis=0)
    relative = rmse[0] / rmse[1] - 1.0
    decision = (relative <= -0.01) & (ci_high < 0.0)
    return {
        "rmse": rmse,
        "block_mse": block_mse,
        "difference": difference,
        "mean_difference": mean_difference,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "relative": relative,
        "decision": decision,
    }


def _validate_result_config(config: dict) -> None:
    if (
        config.get("experiment_id") != EXPERIMENT_ID
        or config.get("model_family") != "HBV"
        or tuple(config.get("state_methods", ())) != CONTROLLED_METHODS
        or config.get("only_changed_factor")
        != "assimilation state and covariance interaction"
        or config.get("fixed_process_id") != "process_2"
        or config.get("fixed_forecast_parameter_id") != "trained_center"
        or tuple(config.get("lead_days", ())) != tuple(range(1, 8))
        or config.get("assimilation_days") != 540
        or config.get("matched_block_count") != 8
        or config.get("truth_trial_count") != 3
        or config.get("state_count") != 15
        or config.get("cross_switch_policy") != "exclude_from_primary_metrics"
        or config.get("future_discharge_observations_used") is not False
        or config.get("forecast_covariance_used") is not False
        or config.get("candidate_forecast_trajectories_used") is not False
        or config.get("forecast_state_count") != 1
        or config.get("forecast_trajectory_count") != 1
        or config.get("bootstrap")
        != {"replicates": 20000, "seed": 20260801, "unit": "matched_block"}
        or config.get("numerical_tolerance") != 1e-10
    ):
        raise ValueError("result config does not match the frozen forecast contract")
    for key in SEALED_CONFIG_KEYS:
        if config.get(key, {}).get("sha256") != EXPECTED_SEALED_HASHES[key]:
            raise ValueError(f"result config sealed hash differs for {key}")


def verify(result_dir: Path) -> dict:
    result_dir = result_dir.resolve()
    report_path = result_dir / "independent_verification.json"
    if report_path.exists():
        raise FileExistsError(f"independent verification already exists: {report_path}")
    config = json.loads(
        (result_dir / "config_snapshot.json").read_text(encoding="utf-8")
    )
    _validate_result_config(config)

    sealed_paths: dict[str, Path] = {}
    sealed_hashes: dict[str, str] = {}
    for key in SEALED_CONFIG_KEYS:
        path = (PROJECT_ROOT / config[key]["path"]).resolve()
        actual = _sha256(path)
        if actual != config[key]["sha256"]:
            raise ValueError(f"sealed input SHA-256 mismatch: {key}")
        sealed_paths[key] = path
        sealed_hashes[key] = actual
    prior_verification = json.loads(
        sealed_paths["sealed_state_audit_independent_verification"].read_text(
            encoding="utf-8"
        )
    )
    if (
        prior_verification.get("status") != "passed"
        or prior_verification.get("evidence_sha256")
        != sealed_hashes["sealed_state_audit_evidence"]
    ):
        raise ValueError("sealed state audit independent verification changed")

    checksums = json.loads(
        (result_dir / "checksums.json").read_text(encoding="utf-8")
    )
    checksum_checks = {
        name: checksums.get(name) == _sha256(result_dir / name)
        for name in (
            "config_snapshot.json",
            "environment.json",
            "evidence.npz",
            "summary.json",
        )
    }
    checksum_checks["sealed_inputs"] = checksums.get("sealed_inputs") == sealed_hashes

    with np.load(result_dir / "evidence.npz", allow_pickle=False) as archive:
        saved = {name: archive[name].copy() for name in archive.files}
    with np.load(
        sealed_paths["sealed_state_audit_evidence"], allow_pickle=False
    ) as state_archive:
        source_names = tuple(state_archive["method_names"].astype(str))
        if source_names != SEALED_STATE_METHODS:
            raise ValueError("sealed state method names changed")
        all_states = np.asarray(
            state_archive["global_posterior_states"], dtype=np.float64
        )
        states = {
            method: all_states[:, :, source_names.index(source_name)].copy()
            for method, source_name in zip(CONTROLLED_METHODS, SEALED_STATE_METHODS)
        }
        sealed_truth_states = np.asarray(state_archive["truth_states"], dtype=np.float64)

    with np.load(sealed_paths["sealed_ideal_evidence"], allow_pickle=False) as ideal:
        parameter_ids = tuple(ideal["parameter_ids"].astype(str))
        if parameter_ids != PARAMETER_IDS:
            raise ValueError("sealed parameter identifier order changed")
        parameter_vectors = np.asarray(ideal["parameter_vectors"], dtype=np.float64)
        fixed_parameter = parameter_vectors[parameter_ids.index("trained_center")].copy()
        assimilation_days = int(np.asarray(ideal["assimilation_days"]).item())
        schedule = np.asarray(ideal["truth_parameter_indices"], dtype=np.int64)
        origins = np.arange(assimilation_days, dtype=np.int64)
        leads = np.arange(1, 8, dtype=np.int64)
        targets = origins[:, None] + leads[None, :]
        origin_parameters = schedule[:, origins]
        target_parameters = schedule[:, targets]
        same_stage = target_parameters == origin_parameters[:, :, None]
        warmup = int(np.asarray(ideal["warmup_days"]).item())
        forcing = np.asarray(ideal["forcing_blocks"], dtype=np.float64)[:, warmup:]
        truth_discharge = np.asarray(ideal["truth_discharge"], dtype=np.float64)
        truth_forecasts = truth_discharge[:, :, targets]
        ideal_truth_states = np.asarray(ideal["truth_states"][:, :, :540], dtype=np.float64)

    if assimilation_days != 540 or not np.array_equal(sealed_truth_states, ideal_truth_states):
        raise ValueError("sealed state and ideal truth alignment changed")
    forecasts: dict[str, np.ndarray] = {}
    for method_number, method in enumerate(CONTROLLED_METHODS, start=1):
        values = np.empty((8, 3, 540, 7), dtype=np.float64)
        for block in range(8):
            for truth in range(3):
                for origin in range(540):
                    values[block, truth, origin] = _reference_forecast(
                        states[method][block, truth, origin],
                        fixed_parameter,
                        forcing[block, origin + 1 : origin + 8],
                    )
        forecasts[method] = values
        print(
            f"independent state-interaction forecast method {method_number}/{len(CONTROLLED_METHODS)}",
            flush=True,
        )

    bootstrap = np.random.default_rng(int(config["bootstrap"]["seed"])).integers(
        0,
        8,
        size=(int(config["bootstrap"]["replicates"]), 8),
        dtype=np.int64,
    )
    statistics = _recompute_statistics(
        forecasts, truth_forecasts, same_stage, bootstrap
    )
    expected_numeric = {
        "sealed_source_method_indices": np.asarray((0, 1), dtype=np.int64),
        "fixed_forecast_parameter_vector": fixed_parameter,
        "lead_days": leads,
        "origin_indices": origins,
        "target_indices": targets,
        "origin_parameter_indices": origin_parameters,
        "target_parameter_indices": target_parameters,
        "same_stage_mask": same_stage,
        "truth_forecasts": truth_forecasts,
        "bootstrap_indices": bootstrap,
        "same_stage_sample_count_per_block": np.sum(same_stage, axis=(0, 1)),
        "same_stage_sample_count_all_blocks": 8 * np.sum(same_stage, axis=(0, 1)),
        "block_mse_difference": statistics["difference"],
        "mean_mse_difference": statistics["mean_difference"],
        "paired_mse_ci_low": statistics["ci_low"],
        "paired_mse_ci_high": statistics["ci_high"],
        "relative_rmse_fraction": statistics["relative"],
    }
    for method_index, method in enumerate(CONTROLLED_METHODS):
        expected_numeric[f"origin_states__{method}"] = states[method]
        expected_numeric[f"forecast__{method}"] = forecasts[method]
        expected_numeric[f"rmse__{method}"] = statistics["rmse"][method_index]
        expected_numeric[f"block_mse__{method}"] = statistics["block_mse"][
            method_index
        ]
    differences = {
        name: _maximum_difference(saved[name], value)
        for name, value in expected_numeric.items()
    }
    label_checks = {
        "method_names": tuple(saved["method_names"].astype(str))
        == CONTROLLED_METHODS,
        "sealed_source_method_names": tuple(
            saved["sealed_source_method_names"].astype(str)
        )
        == SEALED_STATE_METHODS,
        "interaction_modes": tuple(saved["interaction_modes"].astype(str))
        == ("full", "none"),
        "difference_definition": str(saved["difference_definition"].item())
        == DIFFERENCE_DEFINITION,
        "fixed_process_id": str(saved["fixed_process_id"].item())
        == "process_2",
        "fixed_forecast_parameter_id": str(
            saved["fixed_forecast_parameter_id"].item()
        )
        == "trained_center",
        "improvement_decision": np.array_equal(
            saved["improvement_decision"], statistics["decision"]
        ),
    }

    summary = json.loads((result_dir / "summary.json").read_text(encoding="utf-8"))
    primary = summary["all_stage_primary"]
    summary_differences = {
        "fully_interacting_root_mean_square_error": _maximum_difference(
            primary["fully_interacting_root_mean_square_error"], statistics["rmse"][0]
        ),
        "noninteracting_root_mean_square_error": _maximum_difference(
            primary["noninteracting_root_mean_square_error"], statistics["rmse"][1]
        ),
        "relative_root_mean_square_error_percent": _maximum_difference(
            primary["full_minus_none_relative_root_mean_square_error_percent"],
            100.0 * statistics["relative"],
        ),
        "mean_squared_error_difference": _maximum_difference(
            primary["full_minus_none_mean_squared_error_difference"],
            statistics["mean_difference"],
        ),
        "interval_low": _maximum_difference(
            primary["paired_mean_squared_error_difference_95_percent_interval_low"],
            statistics["ci_low"],
        ),
        "interval_high": _maximum_difference(
            primary["paired_mean_squared_error_difference_95_percent_interval_high"],
            statistics["ci_high"],
        ),
    }
    expected_decisions = [
        "improves" if value else "does_not_meet_improvement_criteria"
        for value in statistics["decision"]
    ]
    fixed = summary.get("fixed_factors", {})
    summary_checks = {
        "status_pending_before_verification": summary.get("status")
        == "complete_pending_independent_verification",
        "only_changed_factor": summary.get("only_changed_factor")
        == "assimilation state and covariance interaction",
        "difference_definition": summary.get("difference_definition")
        == DIFFERENCE_DEFINITION,
        "decision_boolean": primary.get("full_interaction_improves")
        == statistics["decision"].tolist(),
        "decision_label": primary.get("decision") == expected_decisions,
        "one_state": fixed.get("forecast_state_count") == 1,
        "one_trajectory": fixed.get("forecast_trajectory_count") == 1,
        "no_covariance": fixed.get("forecast_covariance_used") is False,
        "no_candidate_trajectories": fixed.get(
            "candidate_forecast_trajectories_used"
        )
        is False,
        "no_future_observations": fixed.get("future_discharge_observations_used")
        is False,
        "scope_is_hbv_synthetic_only": summary.get("scope_limit")
        == config["scope_limit"],
    }
    tolerance = float(config["numerical_tolerance"])
    passed = (
        all(value <= tolerance for value in differences.values())
        and all(value <= tolerance for value in summary_differences.values())
        and all(label_checks.values())
        and all(summary_checks.values())
        and all(checksum_checks.values())
    )
    if not passed:
        raise RuntimeError("independent verification failed; no report was published")

    report = {
        "status": "passed",
        "independent_reference_model": True,
        "production_runner_imported": False,
        "production_summary_module_imported": False,
        "production_deterministic_module_imported": False,
        "tolerance": tolerance,
        "maximum_absolute_differences": differences,
        "maximum_summary_differences": summary_differences,
        "maximum_absolute_difference_overall": max(
            list(differences.values()) + list(summary_differences.values())
        ),
        "label_checks": label_checks,
        "summary_checks": summary_checks,
        "checksum_checks": checksum_checks,
        "trajectory_checks": {
            method: differences[f"forecast__{method}"] <= tolerance
            for method in CONTROLLED_METHODS
        },
        "metric_interval_and_decision_checks_passed": True,
        "no_future_observation_reconstruction": True,
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
        "sealed_input_sha256": sealed_hashes,
    }
    temporary = result_dir / ".independent_verification.json.incomplete"
    if temporary.exists():
        raise FileExistsError(f"verification staging file already exists: {temporary}")
    temporary.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.replace(temporary, report_path)
    print(json.dumps(report, indent=2), flush=True)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    verify(args.result_dir)


if __name__ == "__main__":
    main()
