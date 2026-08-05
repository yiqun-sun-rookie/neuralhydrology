"""Run the no-forecast complete-state one-versus-three parameter audit."""

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

from hbv_joint_uncertainty.hbv_adapter import STATE_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.daily_combined_state_error import (  # noqa: E402
    bootstrap_block_indices,
)
from hbv_multilead_joint_uncertainty.fixed_process_parameter_candidate_forecast import (  # noqa: E402
    validate_controlled_candidate_contract,
)
from hbv_multilead_joint_uncertainty.fixed_process_parameter_candidate_state_audit import (  # noqa: E402
    CONTROLLED_STATE_METHODS,
    STATE_METHOD_ROLES,
    summarize_complete_state_controlled_error,
)


EXPERIMENT_ID = "g3_fixed_process_parameter_candidate_complete_state_audit_v01"
DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs/"
    / f"{EXPERIMENT_ID}.json"
)
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    / EXPERIMENT_ID
)
EXPECTED_SOURCE_MAPPING = {
    CONTROLLED_STATE_METHODS[0]: "fixed_filter",
    CONTROLLED_STATE_METHODS[1]: "parameter_only",
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
    if tuple(config.get("state_methods", ())) != CONTROLLED_STATE_METHODS:
        raise ValueError("state method order differs from the frozen contract")
    if config.get("source_method_mapping") != EXPECTED_SOURCE_MAPPING:
        raise ValueError("source method mapping differs from the frozen contract")
    if config.get("fixed_process_id") != "process_2":
        raise ValueError("both methods must use process_2")
    if config.get("assimilation_days") != 540:
        raise ValueError("assimilation day count must equal 540")
    if (
        config.get("state_count") != 15
        or config.get("hydrologic_state_count") != 5
        or config.get("routing_memory_state_count") != 10
    ):
        raise ValueError("complete-state audit requires all fifteen states")
    if config.get("bootstrap") != {
        "replicates": 20000,
        "seed": 20260801,
        "unit": "matched_block",
    }:
        raise ValueError("bootstrap contract changed")
    rule = config.get("decision_rule", {})
    if (
        rule.get("confidence_level") != 0.95
        or rule.get("improves_if_paired_mse_interval_upper_below_zero") is not True
        or rule.get("worsens_if_paired_mse_interval_lower_above_zero") is not True
    ):
        raise ValueError("decision rule changed")
    sealed = config.get("sealed_ideal_evidence", {})
    if not sealed.get("path") or len(str(sealed.get("sha256", ""))) != 64:
        raise ValueError("sealed evidence identity is incomplete")
    if config.get("numerical_tolerance") != 1e-12:
        raise ValueError("numerical tolerance changed")


def _checksums(directory: Path) -> dict[str, str]:
    return {
        name: _sha256(directory / name)
        for name in (
            "config_snapshot.json",
            "environment.json",
            "evidence.npz",
            "summary.json",
        )
    }


def run(config_path: Path, output_dir: Path) -> dict:
    config_path = config_path.resolve()
    output_dir = output_dir.resolve()
    _require_unused_output(output_dir)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    _validate_config(config)
    source = (PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]).resolve()
    source_hash = _sha256(source)
    if source_hash != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed ideal evidence SHA-256 mismatch")

    started = time.monotonic()
    with np.load(source, allow_pickle=False) as archive:
        contract = validate_controlled_candidate_contract(
            archive["method_names"],
            archive["method_candidate_ids"],
            archive["method_candidate_counts"],
        )
        if contract.fixed_process_id != config["fixed_process_id"]:
            raise ValueError("candidate process identifier differs from the config")
        assimilation_days = int(np.asarray(archive["assimilation_days"]).item())
        if assimilation_days != config["assimilation_days"]:
            raise ValueError("sealed assimilation day count changed")
        all_method_states = np.asarray(
            archive["method_assimilation_states"][:, :, :, :assimilation_days],
            dtype=np.float64,
        )
        truth_states = np.asarray(
            archive["truth_states"][:, :, :assimilation_days], dtype=np.float64
        )
        if all_method_states.shape != (8, 3, 5, 540, 15):
            raise ValueError("sealed method state shape differs from the contract")
        if truth_states.shape != (8, 3, 540, 15):
            raise ValueError("sealed truth state shape differs from the contract")
        selected_states = np.stack(
            tuple(
                all_method_states[:, :, source_index]
                for source_index in contract.source_method_indices
            ),
            axis=2,
        )

    bootstrap = bootstrap_block_indices(
        8,
        int(config["bootstrap"]["replicates"]),
        int(config["bootstrap"]["seed"]),
    )
    result = summarize_complete_state_controlled_error(
        selected_states,
        truth_states,
        CONTROLLED_STATE_METHODS,
        STATE_NAMES,
        bootstrap,
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
            "method_names": np.asarray(result["method_names"]),
            "source_method_names": np.asarray(contract.source_method_names),
            "source_method_indices": np.asarray(
                contract.source_method_indices, dtype=np.int64
            ),
            "fixed_filter_candidate_ids": np.asarray(
                contract.fixed_filter_candidates
            ),
            "three_parameter_candidate_ids": np.asarray(
                contract.parameter_candidates
            ),
            "fixed_process_id": np.asarray(contract.fixed_process_id),
            "state_names": np.asarray(result["state_names"]),
            "state_group_names": np.asarray(result["state_group_names"]),
            "day_indices": result["day_indices"],
            "truth_standard_deviation": result["truth_standard_deviation"],
            "per_state_rmse": result["per_state_rmse"],
            "per_state_standardized_rmse": result[
                "per_state_standardized_rmse"
            ],
            "per_state_block_mse": result["per_state_block_mse"],
            "per_state_block_mse_difference": result[
                "per_state_block_mse_difference"
            ],
            "per_state_mean_mse_difference": result[
                "per_state_mean_mse_difference"
            ],
            "per_state_mse_ci_low": result["per_state_ci_low"],
            "per_state_mse_ci_high": result["per_state_ci_high"],
            "per_state_relative_rmse_fraction": result[
                "per_state_relative_rmse_fraction"
            ],
            "per_state_decision": result["per_state_decision"],
            "group_raw_rmse": result["group_raw_rmse"],
            "group_standardized_rmse": result["group_standardized_rmse"],
            "group_block_standardized_mse": result[
                "group_block_standardized_mse"
            ],
            "group_block_standardized_mse_difference": result[
                "group_block_standardized_mse_difference"
            ],
            "group_standardized_mse_ci_low": result[
                "group_standardized_mse_ci_low"
            ],
            "group_standardized_mse_ci_high": result[
                "group_standardized_mse_ci_high"
            ],
            "group_relative_standardized_rmse_fraction": result[
                "group_relative_standardized_rmse_fraction"
            ],
            "group_decision": result["group_decision"],
            "complete_standardized_rmse": result[
                "complete_standardized_rmse"
            ],
            "complete_block_standardized_mse": result[
                "complete_block_standardized_mse"
            ],
            "complete_block_standardized_mse_difference": result[
                "complete_block_standardized_mse_difference"
            ],
            "complete_standardized_mse_difference": np.asarray(
                result["complete_standardized_mse_difference"]
            ),
            "complete_standardized_mse_ci_low": np.asarray(
                result["complete_standardized_mse_ci_low"]
            ),
            "complete_standardized_mse_ci_high": np.asarray(
                result["complete_standardized_mse_ci_high"]
            ),
            "complete_relative_standardized_rmse_fraction": np.asarray(
                result["complete_relative_standardized_rmse_fraction"]
            ),
            "complete_decision": np.asarray(result["complete_decision"]),
            "bootstrap_indices": bootstrap,
        }
        np.savez_compressed(staging / "evidence.npz", **evidence)

        state_results = {}
        for state_index, state_name in enumerate(STATE_NAMES):
            state_results[state_name] = {
                "single_filter_root_mean_square_error": float(
                    result["per_state_rmse"][0, state_index]
                ),
                "three_parameter_candidates_root_mean_square_error": float(
                    result["per_state_rmse"][1, state_index]
                ),
                "three_minus_single_relative_root_mean_square_error_percent": float(
                    100.0 * result["per_state_relative_rmse_fraction"][state_index]
                ),
                "three_minus_single_mean_squared_error_difference": float(
                    result["per_state_mean_mse_difference"][state_index]
                ),
                "paired_mean_squared_error_difference_95_percent_interval": [
                    float(result["per_state_ci_low"][state_index]),
                    float(result["per_state_ci_high"][state_index]),
                ],
                "decision": str(result["per_state_decision"][state_index]),
            }
        group_results = {}
        for group_index, group_name in enumerate(result["state_group_names"]):
            group_results[group_name] = {
                "single_filter_raw_root_mean_square_error": float(
                    result["group_raw_rmse"][0, group_index]
                ),
                "three_parameter_candidates_raw_root_mean_square_error": float(
                    result["group_raw_rmse"][1, group_index]
                ),
                "single_filter_standardized_root_mean_square_error": float(
                    result["group_standardized_rmse"][0, group_index]
                ),
                "three_parameter_candidates_standardized_root_mean_square_error": float(
                    result["group_standardized_rmse"][1, group_index]
                ),
                "three_minus_single_relative_standardized_root_mean_square_error_percent": float(
                    100.0
                    * result["group_relative_standardized_rmse_fraction"][
                        group_index
                    ]
                ),
                "paired_standardized_mean_squared_error_difference_95_percent_interval": [
                    float(result["group_standardized_mse_ci_low"][group_index]),
                    float(result["group_standardized_mse_ci_high"][group_index]),
                ],
                "decision": str(result["group_decision"][group_index]),
            }
        summary = {
            "experiment_id": config["experiment_id"],
            "classification": config["classification"],
            "status": "complete_pending_independent_verification",
            "question": (
                "Does the unique global posterior from the standard fully "
                "interacting three-parameter-model method improve same-day "
                "complete-state accuracy relative to one fixed-parameter filter "
                "when process_2 is held fixed?"
            ),
            "forecast_executed": False,
            "comparison_factor": (
                "single fixed-parameter filter versus standard fully interacting "
                "three-parameter-model method"
            ),
            "method_roles": STATE_METHOD_ROLES,
            "mechanism_attribution_allowed": False,
            "mechanism_attribution_limit": (
                "This comparison cannot separate the effects of additional fixed "
                "parameter models, state interaction, probability updating, and "
                "global posterior combination."
            ),
            "fixed_factors": {
                "process_covariance_identifier": "process_2",
                "same_observations": True,
                "same_540_days": True,
                "same_fifteen_state_truth": True,
            },
            "candidate_contract": {
                "single_filter_candidates": list(
                    contract.fixed_filter_candidates
                ),
                "three_parameter_candidates": list(contract.parameter_candidates),
            },
            "sample_count": {
                "matched_blocks": 8,
                "truth_trials": 3,
                "assimilation_days": 540,
                "state_count": 15,
            },
            "per_state": state_results,
            "state_groups": group_results,
            "complete_equal_component_standardized_error": {
                CONTROLLED_STATE_METHODS[0]: float(
                    result["complete_standardized_rmse"][0]
                ),
                CONTROLLED_STATE_METHODS[1]: float(
                    result["complete_standardized_rmse"][1]
                ),
                "three_minus_single_relative_percent": float(
                    100.0
                    * result["complete_relative_standardized_rmse_fraction"]
                ),
                "paired_standardized_mean_squared_error_difference_95_percent_interval": [
                    float(result["complete_standardized_mse_ci_low"]),
                    float(result["complete_standardized_mse_ci_high"]),
                ],
                "decision": result["complete_decision"],
            },
            "correctness_gates": {
                "source_sha256_matches": True,
                "candidate_contract_matches": True,
                "complete_fifteen_state_shape_matches": True,
                "forecast_module_used": False,
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
                "sealed_ideal_evidence_sha256": source_hash,
            },
        )
        _write_json(
            staging / "checksums.json",
            {
                "sealed_ideal_evidence_sha256": source_hash,
                **_checksums(staging),
            },
        )
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
