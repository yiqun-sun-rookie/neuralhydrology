"""Independently verify the full-versus-no-interaction state audit."""

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

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, STATE_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    MethodCandidate,
    build_method_bank,
)


EXPERIMENT_ID = "g3_fixed_process_state_interaction_global_posterior_audit_v01"
DEFAULT_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty"
    / EXPERIMENT_ID
)
METHODS = (
    "fully_interacting_multiple_model_global_posterior_state",
    "noninteracting_multiple_filter_global_posterior_state_control",
)
INTERACTION_MODES = ("full", "none")
PARAMETER_IDS = (
    "equifinal_diverse_1",
    "trained_center",
    "equifinal_diverse_2",
)
GROUP_NAMES = ("hydrologic_stores", "routing_memory")
GROUP_SLICES = (slice(0, 5), slice(5, 15))


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
    finite = np.isfinite(left_values) & np.isfinite(right_values)
    return float(
        np.max(np.abs(left_values[finite] - right_values[finite]), initial=0.0)
    )


def _decision(low, high):
    low_values = np.asarray(low, dtype=np.float64)
    high_values = np.asarray(high, dtype=np.float64)
    return np.where(
        high_values < 0.0,
        "improves",
        np.where(low_values > 0.0, "worsens", "inconclusive"),
    )


def _candidates(source, config):
    parameter_ids = tuple(source["parameter_ids"].astype(str))
    process_ids = tuple(source["process_ids"].astype(str))
    if parameter_ids != PARAMETER_IDS or process_ids != (
        "process_0",
        "process_1",
        "process_2",
    ):
        raise ValueError("sealed candidate identifiers changed")
    process_index = process_ids.index("process_2")
    covariance = np.asarray(
        source["process_covariances"][process_index], dtype=np.float64
    )
    result = []
    for parameter_index, parameter_id in enumerate(parameter_ids):
        parameters = {
            name: float(value)
            for name, value in zip(
                PARAMETER_NAMES,
                source["parameter_vectors"][parameter_index],
            )
        }
        result.append(
            MethodCandidate(
                candidate_id=f"{parameter_id}__process_2",
                parameter_id=parameter_id,
                process_id="process_2",
                process_scale=float(config["fixed_process_variance_scale"]),
                parameters=parameters,
                process_covariance=covariance.copy(),
            )
        )
    return tuple(result)


def _reconstruct(source, config):
    candidates = _candidates(source, config)
    block_count = 8
    truth_count = 3
    day_count = 540
    warmup_days = 45
    states = np.empty((8, 3, 2, 540, 15), dtype=np.float64)
    covariance_diagonals = np.empty_like(states)
    probabilities = np.empty((8, 3, 2, 540, 3), dtype=np.float64)
    state_reconstruction_maximum = 0.0
    covariance_reconstruction_maximum = 0.0
    forcing = np.asarray(
        source["forcing_blocks"][:, warmup_days : warmup_days + day_count],
        dtype=np.float64,
    )
    observations = np.asarray(
        source["observed_discharge"][:, :, :day_count], dtype=np.float64
    )
    observation_standard_deviation = float(
        np.asarray(source["observation_standard_deviation"]).item()
    )
    for block in range(block_count):
        initial_states = {
            parameter_id: np.asarray(
                source["initial_parameter_states"][block, parameter_index],
                dtype=np.float64,
            )
            for parameter_index, parameter_id in enumerate(PARAMETER_IDS)
        }
        initial_covariance = np.asarray(
            source["initial_covariances"][block], dtype=np.float64
        )
        for truth_index in range(truth_count):
            for method_index, interaction_mode in enumerate(INTERACTION_MODES):
                bank = build_method_bank(
                    candidates=candidates,
                    initial_states=initial_states,
                    initial_covariance=initial_covariance,
                    observation_standard_deviation=observation_standard_deviation,
                    factor_transition_stay_probability=float(
                        config["factor_transition_stay_probability"]
                    ),
                    interaction_mode=interaction_mode,
                )
                for day in range(day_count):
                    rain, potential_evaporation, temperature = forcing[block, day]
                    for transition in bank.transitions:
                        transition.set_forcing(
                            rain, potential_evaporation, temperature
                        )
                    step = bank.estimator.step(observations[block, truth_index, day])
                    states[block, truth_index, method_index, day] = (
                        step.global_posterior_state
                    )
                    covariance_diagonals[
                        block, truth_index, method_index, day
                    ] = np.diag(step.global_posterior_covariance)
                    probabilities[
                        block, truth_index, method_index, day
                    ] = step.posterior_probabilities
                    state = sum(
                        probability * candidate_result.posterior_state
                        for probability, candidate_result in zip(
                            step.posterior_probabilities, step.candidate_results
                        )
                    )
                    covariance = np.zeros((15, 15), dtype=np.float64)
                    for probability, candidate_result in zip(
                        step.posterior_probabilities, step.candidate_results
                    ):
                        difference = candidate_result.posterior_state - state
                        covariance += probability * (
                            candidate_result.posterior_covariance
                            + np.outer(difference, difference)
                        )
                    state_reconstruction_maximum = max(
                        state_reconstruction_maximum,
                        float(np.max(np.abs(state - step.global_posterior_state))),
                    )
                    covariance_reconstruction_maximum = max(
                        covariance_reconstruction_maximum,
                        float(
                            np.max(
                                np.abs(
                                    covariance - step.global_posterior_covariance
                                )
                            )
                        ),
                    )
    return {
        "global_posterior_states": states,
        "global_posterior_covariance_diagonals": covariance_diagonals,
        "posterior_probabilities": probabilities,
        "global_posterior_state_reconstruction_maximum_absolute_error": np.asarray(
            state_reconstruction_maximum
        ),
        "global_posterior_covariance_reconstruction_maximum_absolute_error": np.asarray(
            covariance_reconstruction_maximum
        ),
    }


def _statistics(estimates, truth, bootstrap):
    standard_deviation = np.std(truth, axis=(0, 1, 2))
    squared = np.square(estimates - truth[:, :, None])
    standardized = squared / np.square(
        standard_deviation[None, None, None, None]
    )
    state_rmse = np.sqrt(np.mean(squared, axis=(0, 1, 3)))
    state_standardized_rmse = state_rmse / standard_deviation[None]
    state_block_mse = np.mean(squared, axis=(1, 3))
    state_difference = state_block_mse[:, 0] - state_block_mse[:, 1]
    state_bootstrap = np.mean(state_difference[bootstrap], axis=1)
    state_low = np.quantile(state_bootstrap, 0.025, axis=0)
    state_high = np.quantile(state_bootstrap, 0.975, axis=0)

    group_raw = np.empty((2, 2), dtype=np.float64)
    group_standardized = np.empty((2, 2), dtype=np.float64)
    group_block = np.empty((8, 2, 2), dtype=np.float64)
    for group_index, state_slice in enumerate(GROUP_SLICES):
        group_raw[:, group_index] = np.sqrt(
            np.mean(squared[..., state_slice], axis=(0, 1, 3, 4))
        )
        group_standardized[:, group_index] = np.sqrt(
            np.mean(standardized[..., state_slice], axis=(0, 1, 3, 4))
        )
        group_block[:, :, group_index] = np.mean(
            standardized[..., state_slice], axis=(1, 3, 4)
        )
    group_difference = group_block[:, 0] - group_block[:, 1]
    group_bootstrap = np.mean(group_difference[bootstrap], axis=1)
    group_low = np.quantile(group_bootstrap, 0.025, axis=0)
    group_high = np.quantile(group_bootstrap, 0.975, axis=0)

    complete_rmse = np.sqrt(np.mean(standardized, axis=(0, 1, 3, 4)))
    complete_block = np.mean(standardized, axis=(1, 3, 4))
    complete_difference = complete_block[:, 0] - complete_block[:, 1]
    complete_bootstrap = np.mean(complete_difference[bootstrap], axis=1)
    complete_low = float(np.quantile(complete_bootstrap, 0.025))
    complete_high = float(np.quantile(complete_bootstrap, 0.975))
    return {
        "truth_standard_deviation": standard_deviation,
        "per_state_rmse": state_rmse,
        "per_state_standardized_rmse": state_standardized_rmse,
        "per_state_block_mse": state_block_mse,
        "per_state_block_mse_difference": state_difference,
        "per_state_mean_mse_difference": np.mean(state_difference, axis=0),
        "per_state_mse_ci_low": state_low,
        "per_state_mse_ci_high": state_high,
        "per_state_relative_rmse_fraction": state_rmse[0] / state_rmse[1] - 1.0,
        "per_state_decision": _decision(state_low, state_high),
        "group_raw_rmse": group_raw,
        "group_standardized_rmse": group_standardized,
        "group_block_standardized_mse": group_block,
        "group_block_standardized_mse_difference": group_difference,
        "group_standardized_mse_ci_low": group_low,
        "group_standardized_mse_ci_high": group_high,
        "group_relative_standardized_rmse_fraction": (
            group_standardized[0] / group_standardized[1] - 1.0
        ),
        "group_decision": _decision(group_low, group_high),
        "complete_standardized_rmse": complete_rmse,
        "complete_block_standardized_mse": complete_block,
        "complete_block_standardized_mse_difference": complete_difference,
        "complete_standardized_mse_difference": float(
            np.mean(complete_difference)
        ),
        "complete_standardized_mse_ci_low": complete_low,
        "complete_standardized_mse_ci_high": complete_high,
        "complete_relative_standardized_rmse_fraction": float(
            complete_rmse[0] / complete_rmse[1] - 1.0
        ),
        "complete_decision": str(_decision(complete_low, complete_high).item()),
    }


def verify(result_dir: Path) -> dict:
    result_dir = result_dir.resolve()
    report_path = result_dir / "independent_verification.json"
    if report_path.exists():
        raise FileExistsError(f"independent verification already exists: {report_path}")
    config = json.loads(
        (result_dir / "config_snapshot.json").read_text(encoding="utf-8")
    )
    if (
        config.get("experiment_id") != EXPERIMENT_ID
        or tuple(config.get("state_methods", ())) != METHODS
        or config.get("assimilation_days") != 540
        or config.get("state_count") != 15
        or config.get("forecast_executed") is not False
    ):
        raise ValueError("result config differs from the frozen contract")
    source_path = (PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]).resolve()
    source_hash = _sha256(source_path)
    if source_hash != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed ideal evidence SHA-256 mismatch")
    checksums = json.loads((result_dir / "checksums.json").read_text(encoding="utf-8"))
    checksum_checks = {
        name: checksums.get(name) == _sha256(result_dir / name)
        for name in (
            "config_snapshot.json",
            "environment.json",
            "evidence.npz",
            "summary.json",
        )
    }
    checksum_checks["sealed_source"] = (
        checksums.get("sealed_ideal_evidence_sha256") == source_hash
    )

    with np.load(result_dir / "evidence.npz", allow_pickle=False) as archive:
        saved = {name: archive[name].copy() for name in archive.files}
    with np.load(source_path, allow_pickle=False) as archive:
        source = {name: archive[name].copy() for name in archive.files}
    reconstructed = _reconstruct(source, config)
    truth = np.asarray(source["truth_states"][:, :, :540], dtype=np.float64)
    bootstrap = np.random.default_rng(int(config["bootstrap"]["seed"])).integers(
        0,
        8,
        size=(int(config["bootstrap"]["replicates"]), 8),
        dtype=np.int64,
    )
    statistics = _statistics(
        reconstructed["global_posterior_states"], truth, bootstrap
    )
    expected_numeric = {
        "day_indices": np.arange(540, dtype=np.int64),
        "truth_standard_deviation": statistics["truth_standard_deviation"],
        "global_posterior_states": reconstructed["global_posterior_states"],
        "global_posterior_covariance_diagonals": reconstructed[
            "global_posterior_covariance_diagonals"
        ],
        "posterior_probabilities": reconstructed["posterior_probabilities"],
        "truth_states": truth,
        "bootstrap_indices": bootstrap,
        "global_posterior_state_reconstruction_maximum_absolute_error": reconstructed[
            "global_posterior_state_reconstruction_maximum_absolute_error"
        ],
        "global_posterior_covariance_reconstruction_maximum_absolute_error": reconstructed[
            "global_posterior_covariance_reconstruction_maximum_absolute_error"
        ],
        **{
            name: value
            for name, value in statistics.items()
            if name
            not in {"per_state_decision", "group_decision", "complete_decision"}
        },
    }
    differences = {
        name: _maximum_difference(saved[name], value)
        for name, value in expected_numeric.items()
    }
    label_checks = {
        "method_names": tuple(saved["method_names"].astype(str)) == METHODS,
        "interaction_modes": tuple(saved["interaction_modes"].astype(str))
        == INTERACTION_MODES,
        "difference_definition": str(saved["difference_definition"].item())
        == "full_interaction_minus_no_interaction",
        "parameter_candidate_ids": tuple(
            saved["parameter_candidate_ids"].astype(str)
        )
        == tuple(config["parameter_candidate_ids"]),
        "fixed_process_id": str(saved["fixed_process_id"].item()) == "process_2",
        "state_names": tuple(saved["state_names"].astype(str))
        == tuple(STATE_NAMES),
        "state_group_names": tuple(saved["state_group_names"].astype(str))
        == GROUP_NAMES,
        "per_state_decision": np.array_equal(
            saved["per_state_decision"].astype(str),
            statistics["per_state_decision"],
        ),
        "group_decision": np.array_equal(
            saved["group_decision"].astype(str), statistics["group_decision"]
        ),
        "complete_decision": str(saved["complete_decision"].item())
        == statistics["complete_decision"],
    }

    summary = json.loads((result_dir / "summary.json").read_text(encoding="utf-8"))
    summary_differences = {}
    for state_index, state_name in enumerate(STATE_NAMES):
        values = summary["per_state"][state_name]
        summary_differences[f"{state_name}_full_rmse"] = _maximum_difference(
            values["fully_interacting_root_mean_square_error"],
            statistics["per_state_rmse"][0, state_index],
        )
        summary_differences[f"{state_name}_none_rmse"] = _maximum_difference(
            values["no_interaction_root_mean_square_error"],
            statistics["per_state_rmse"][1, state_index],
        )
        summary_differences[f"{state_name}_relative_percent"] = _maximum_difference(
            values["full_minus_none_relative_root_mean_square_error_percent"],
            100.0 * statistics["per_state_relative_rmse_fraction"][state_index],
        )
    for group_index, group_name in enumerate(GROUP_NAMES):
        values = summary["state_groups"][group_name]
        summary_differences[f"{group_name}_full"] = _maximum_difference(
            values["fully_interacting_standardized_root_mean_square_error"],
            statistics["group_standardized_rmse"][0, group_index],
        )
        summary_differences[f"{group_name}_none"] = _maximum_difference(
            values["no_interaction_standardized_root_mean_square_error"],
            statistics["group_standardized_rmse"][1, group_index],
        )
    complete = summary["complete_equal_component_standardized_error"]
    summary_differences["complete_full"] = _maximum_difference(
        complete[METHODS[0]], statistics["complete_standardized_rmse"][0]
    )
    summary_differences["complete_none"] = _maximum_difference(
        complete[METHODS[1]], statistics["complete_standardized_rmse"][1]
    )
    summary_differences["complete_relative_percent"] = _maximum_difference(
        complete["full_minus_none_relative_root_mean_square_error_percent"],
        100.0 * statistics["complete_relative_standardized_rmse_fraction"],
    )
    summary_checks = {
        "pending_status": summary.get("status")
        == "complete_pending_independent_verification",
        "only_changed_factor": summary.get("only_changed_factor")
        == config["only_changed_factor"],
        "forecast_not_executed": summary.get("forecast_executed") is False,
        "time_since_switch_not_grouped": summary.get(
            "time_since_truth_switch_grouping_used"
        )
        is False,
        "complete_decision": complete.get("decision")
        == statistics["complete_decision"],
    }

    tolerance = float(config["numerical_tolerance"])
    passed = (
        all(value <= tolerance for value in differences.values())
        and all(value <= tolerance for value in summary_differences.values())
        and all(label_checks.values())
        and all(summary_checks.values())
        and all(checksum_checks.values())
    )
    report = {
        "status": "passed" if passed else "failed",
        "forecast_module_imported": False,
        "production_runner_imported": False,
        "production_summary_module_imported": False,
        "tolerance": tolerance,
        "maximum_absolute_differences": differences,
        "maximum_summary_differences": summary_differences,
        "maximum_absolute_difference_overall": max(
            list(differences.values()) + list(summary_differences.values())
        ),
        "label_checks": label_checks,
        "summary_checks": summary_checks,
        "checksum_checks": checksum_checks,
        "sealed_ideal_evidence_sha256": source_hash,
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
    }
    temporary = result_dir / ".independent_verification.json.incomplete"
    if temporary.exists():
        raise FileExistsError(f"verification staging file already exists: {temporary}")
    temporary.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, report_path)
    print(json.dumps(report, indent=2), flush=True)
    if not passed:
        raise SystemExit(1)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    verify(args.result_dir)


if __name__ == "__main__":
    main()
