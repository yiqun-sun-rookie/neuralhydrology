"""Run the formal full-versus-no-interaction same-day state audit."""

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

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, STATE_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    MethodCandidate,
    build_method_bank,
)
from hbv_multilead_joint_uncertainty.state_interaction_global_posterior_audit import (  # noqa: E402
    DIFFERENCE_DEFINITION,
    INTERACTION_STATE_METHODS,
    summarize_state_interaction_global_posterior_error,
)


EXPERIMENT_ID = "g3_fixed_process_state_interaction_global_posterior_audit_v01"
DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs"
    / f"{EXPERIMENT_ID}.json"
)
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty"
    / EXPERIMENT_ID
)
EXPECTED_INTERACTION_MODES = {
    INTERACTION_STATE_METHODS[0]: "full",
    INTERACTION_STATE_METHODS[1]: "none",
}
EXPECTED_FIXED_FACTORS = {
    "parameter_candidates": "identical three fixed vectors",
    "process_covariance_identifier": "process_2 for every model",
    "initial_model_conditioned_states": "identical",
    "initial_covariances": "identical",
    "observations": "identical",
    "meteorological_forcing": "identical",
    "transition_probability_matrix": "identical",
    "probability_prediction": "identical",
    "likelihood_probability_update": "identical",
    "global_posterior_combination": "posterior-probability weighted in both methods",
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
    if config.get("status") != "frozen_before_run":
        raise ValueError("config status must be frozen_before_run")
    if tuple(config.get("state_methods", ())) != INTERACTION_STATE_METHODS:
        raise ValueError("state method order differs from the frozen contract")
    if config.get("interaction_modes") != EXPECTED_INTERACTION_MODES:
        raise ValueError("interaction modes differ from full versus none")
    if config.get("only_changed_factor") != (
        "state and covariance interaction mixing before each observation update: "
        "full versus none"
    ):
        raise ValueError("only changed factor differs from the frozen contract")
    if config.get("fixed_factors") != EXPECTED_FIXED_FACTORS:
        raise ValueError("fixed factors differ from the frozen contract")
    expected_scalars = {
        "assimilation_days": 540,
        "warmup_days": 45,
        "matched_block_count": 8,
        "truth_trial_count": 3,
        "candidate_count": 3,
        "state_count": 15,
        "hydrologic_state_count": 5,
        "routing_memory_state_count": 10,
    }
    if any(config.get(name) != value for name, value in expected_scalars.items()):
        raise ValueError("population dimensions differ from the frozen contract")
    if config.get("fixed_process_id") != "process_2":
        raise ValueError("all candidates must use process_2")
    if config.get("fixed_process_variance_scale") != 0.01:
        raise ValueError("process_2 variance scale changed")
    if config.get("factor_transition_stay_probability") != 0.98:
        raise ValueError("transition probability changed")
    if config.get("forecast_executed") is not False:
        raise ValueError("forecast must not be executed")
    if config.get("time_since_truth_switch_grouping_used") is not False:
        raise ValueError("time-since-switch grouping must not be used")
    if config.get("bootstrap") != {
        "replicates": 20000,
        "seed": 20260801,
        "unit": "matched_block",
    }:
        raise ValueError("bootstrap contract changed")
    rule = config.get("decision_rule", {})
    if (
        rule.get("confidence_level") != 0.95
        or rule.get(
            "improves_if_full_minus_none_paired_mse_interval_upper_below_zero"
        )
        is not True
        or rule.get(
            "worsens_if_full_minus_none_paired_mse_interval_lower_above_zero"
        )
        is not True
    ):
        raise ValueError("decision rule changed")
    sealed = config.get("sealed_ideal_evidence", {})
    if not sealed.get("path") or len(str(sealed.get("sha256", ""))) != 64:
        raise ValueError("sealed evidence identity is incomplete")
    if config.get("numerical_tolerance") != 1e-12:
        raise ValueError("numerical tolerance changed")


def _source_arrays(source: Path, config: dict) -> dict[str, np.ndarray]:
    with np.load(source, allow_pickle=False) as archive:
        arrays = {name: archive[name].copy() for name in archive.files}
    expected_shapes = {
        name: tuple(int(value) for value in shape)
        for name, shape in config["expected_source_shapes"].items()
    }
    for name, shape in expected_shapes.items():
        if name not in arrays or arrays[name].shape != shape:
            raise ValueError(f"sealed source shape changed for {name}")
    if int(np.asarray(arrays["assimilation_days"]).item()) != 540:
        raise ValueError("sealed assimilation day count changed")
    if int(np.asarray(arrays["warmup_days"]).item()) != 45:
        raise ValueError("sealed warmup day count changed")
    parameter_ids = tuple(arrays["parameter_ids"].astype(str))
    if parameter_ids != (
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    ):
        raise ValueError("sealed parameter identifiers changed")
    process_ids = tuple(arrays["process_ids"].astype(str))
    if process_ids != ("process_0", "process_1", "process_2"):
        raise ValueError("sealed process identifiers changed")
    candidate_ids = tuple(str(value) for value in config["parameter_candidate_ids"])
    expected_candidates = tuple(f"{value}__process_2" for value in parameter_ids)
    if candidate_ids != expected_candidates:
        raise ValueError("parameter candidate identifiers changed")
    return arrays


def _parameter_candidates(arrays: dict, config: dict) -> tuple[MethodCandidate, ...]:
    parameter_ids = tuple(arrays["parameter_ids"].astype(str))
    process_ids = tuple(arrays["process_ids"].astype(str))
    process_index = process_ids.index(config["fixed_process_id"])
    covariance = np.asarray(
        arrays["process_covariances"][process_index], dtype=np.float64
    )
    candidates = []
    for parameter_index, parameter_id in enumerate(parameter_ids):
        parameters = {
            name: float(value)
            for name, value in zip(
                PARAMETER_NAMES,
                arrays["parameter_vectors"][parameter_index],
            )
        }
        candidates.append(
            MethodCandidate(
                candidate_id=f"{parameter_id}__{config['fixed_process_id']}",
                parameter_id=parameter_id,
                process_id=config["fixed_process_id"],
                process_scale=float(config["fixed_process_variance_scale"]),
                parameters=parameters,
                process_covariance=covariance.copy(),
            )
        )
    return tuple(candidates)


def reconstruct_global_posterior_histories(
    arrays: dict[str, np.ndarray], config: dict
) -> dict[str, np.ndarray]:
    """Re-run both methods and retain only their one final state per day."""

    candidates = _parameter_candidates(arrays, config)
    parameter_ids = tuple(arrays["parameter_ids"].astype(str))
    block_count = int(config["matched_block_count"])
    truth_count = int(config["truth_trial_count"])
    day_count = int(config["assimilation_days"])
    method_count = len(INTERACTION_STATE_METHODS)
    states = np.empty(
        (block_count, truth_count, method_count, day_count, 15),
        dtype=np.float64,
    )
    covariance_diagonals = np.empty_like(states)
    probabilities = np.empty(
        (block_count, truth_count, method_count, day_count, len(candidates)),
        dtype=np.float64,
    )
    state_reconstruction_maximum = 0.0
    covariance_reconstruction_maximum = 0.0
    warmup_days = int(config["warmup_days"])
    active_forcing = np.asarray(
        arrays["forcing_blocks"][:, warmup_days : warmup_days + day_count],
        dtype=np.float64,
    )
    observations = np.asarray(
        arrays["observed_discharge"][:, :, :day_count], dtype=np.float64
    )
    observation_standard_deviation = float(
        np.asarray(arrays["observation_standard_deviation"]).item()
    )

    for block in range(block_count):
        initial_states = {
            parameter_id: np.asarray(
                arrays["initial_parameter_states"][block, parameter_index],
                dtype=np.float64,
            )
            for parameter_index, parameter_id in enumerate(parameter_ids)
        }
        initial_covariance = np.asarray(
            arrays["initial_covariances"][block], dtype=np.float64
        )
        for truth_index in range(truth_count):
            for method_index, method_name in enumerate(INTERACTION_STATE_METHODS):
                interaction_mode = EXPECTED_INTERACTION_MODES[method_name]
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
                    rain, potential_evaporation, temperature = active_forcing[
                        block, day
                    ]
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
                    reconstructed_state = sum(
                        probability * result.posterior_state
                        for probability, result in zip(
                            step.posterior_probabilities, step.candidate_results
                        )
                    )
                    reconstructed_covariance = np.zeros((15, 15), dtype=np.float64)
                    for probability, result in zip(
                        step.posterior_probabilities, step.candidate_results
                    ):
                        difference = result.posterior_state - reconstructed_state
                        reconstructed_covariance += probability * (
                            result.posterior_covariance
                            + np.outer(difference, difference)
                        )
                    state_reconstruction_maximum = max(
                        state_reconstruction_maximum,
                        float(
                            np.max(
                                np.abs(
                                    reconstructed_state
                                    - step.global_posterior_state
                                )
                            )
                        ),
                    )
                    covariance_reconstruction_maximum = max(
                        covariance_reconstruction_maximum,
                        float(
                            np.max(
                                np.abs(
                                    reconstructed_covariance
                                    - step.global_posterior_covariance
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
    arrays = _source_arrays(source, config)

    started = time.monotonic()
    reconstructed = reconstruct_global_posterior_histories(arrays, config)
    bootstrap = np.random.default_rng(int(config["bootstrap"]["seed"])).integers(
        0,
        int(config["matched_block_count"]),
        size=(
            int(config["bootstrap"]["replicates"]),
            int(config["matched_block_count"]),
        ),
        dtype=np.int64,
    )
    truth_states = np.asarray(
        arrays["truth_states"][:, :, : int(config["assimilation_days"])],
        dtype=np.float64,
    )
    result = summarize_state_interaction_global_posterior_error(
        reconstructed["global_posterior_states"],
        truth_states,
        INTERACTION_STATE_METHODS,
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
            "method_names": np.asarray(INTERACTION_STATE_METHODS),
            "interaction_modes": np.asarray(
                tuple(EXPECTED_INTERACTION_MODES[name] for name in INTERACTION_STATE_METHODS)
            ),
            "difference_definition": np.asarray(DIFFERENCE_DEFINITION),
            "parameter_candidate_ids": np.asarray(config["parameter_candidate_ids"]),
            "fixed_process_id": np.asarray(config["fixed_process_id"]),
            "state_names": np.asarray(STATE_NAMES),
            "state_group_names": np.asarray(result["state_group_names"]),
            "day_indices": result["day_indices"],
            "truth_standard_deviation": result["truth_standard_deviation"],
            "global_posterior_states": reconstructed["global_posterior_states"],
            "global_posterior_covariance_diagonals": reconstructed[
                "global_posterior_covariance_diagonals"
            ],
            "posterior_probabilities": reconstructed["posterior_probabilities"],
            "truth_states": truth_states,
            "per_state_rmse": result["per_state_rmse"],
            "per_state_standardized_rmse": result["per_state_standardized_rmse"],
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
            "global_posterior_state_reconstruction_maximum_absolute_error": reconstructed[
                "global_posterior_state_reconstruction_maximum_absolute_error"
            ],
            "global_posterior_covariance_reconstruction_maximum_absolute_error": reconstructed[
                "global_posterior_covariance_reconstruction_maximum_absolute_error"
            ],
        }
        np.savez_compressed(staging / "evidence.npz", **evidence)

        per_state = {}
        for state_index, state_name in enumerate(STATE_NAMES):
            per_state[state_name] = {
                "fully_interacting_root_mean_square_error": float(
                    result["per_state_rmse"][0, state_index]
                ),
                "no_interaction_root_mean_square_error": float(
                    result["per_state_rmse"][1, state_index]
                ),
                "full_minus_none_relative_root_mean_square_error_percent": float(
                    100.0 * result["per_state_relative_rmse_fraction"][state_index]
                ),
                "full_minus_none_mean_squared_error_difference": float(
                    result["per_state_mean_mse_difference"][state_index]
                ),
                "paired_mean_squared_error_difference_95_percent_interval": [
                    float(result["per_state_ci_low"][state_index]),
                    float(result["per_state_ci_high"][state_index]),
                ],
                "decision": str(result["per_state_decision"][state_index]),
            }
        groups = {}
        for group_index, group_name in enumerate(result["state_group_names"]):
            groups[group_name] = {
                "fully_interacting_standardized_root_mean_square_error": float(
                    result["group_standardized_rmse"][0, group_index]
                ),
                "no_interaction_standardized_root_mean_square_error": float(
                    result["group_standardized_rmse"][1, group_index]
                ),
                "full_minus_none_relative_standardized_root_mean_square_error_percent": float(
                    100.0
                    * result["group_relative_standardized_rmse_fraction"][group_index]
                ),
                "paired_standardized_mean_squared_error_difference_95_percent_interval": [
                    float(result["group_standardized_mse_ci_low"][group_index]),
                    float(result["group_standardized_mse_ci_high"][group_index]),
                ],
                "decision": str(result["group_decision"][group_index]),
            }
        summary = {
            "experiment_id": EXPERIMENT_ID,
            "status": "complete_pending_independent_verification",
            "question": (
                "Does full state-and-covariance interaction improve the daily "
                "global posterior relative to the same three filters without "
                "state interaction?"
            ),
            "only_changed_factor": config["only_changed_factor"],
            "difference_definition": DIFFERENCE_DEFINITION,
            "forecast_executed": False,
            "time_since_truth_switch_grouping_used": False,
            "population": {
                "matched_blocks": int(config["matched_block_count"]),
                "truth_trials_per_block": int(config["truth_trial_count"]),
                "assimilation_days": int(config["assimilation_days"]),
                "state_count": int(config["state_count"]),
            },
            "per_state": per_state,
            "state_groups": groups,
            "complete_equal_component_standardized_error": {
                INTERACTION_STATE_METHODS[0]: float(
                    result["complete_standardized_rmse"][0]
                ),
                INTERACTION_STATE_METHODS[1]: float(
                    result["complete_standardized_rmse"][1]
                ),
                "full_minus_none_relative_root_mean_square_error_percent": float(
                    100.0 * result["complete_relative_standardized_rmse_fraction"]
                ),
                "full_minus_none_mean_squared_error_difference": float(
                    result["complete_standardized_mse_difference"]
                ),
                "paired_mean_squared_error_difference_95_percent_interval": [
                    float(result["complete_standardized_mse_ci_low"]),
                    float(result["complete_standardized_mse_ci_high"]),
                ],
                "decision": result["complete_decision"],
            },
            "global_posterior_reconstruction": {
                "state_maximum_absolute_error": float(
                    reconstructed[
                        "global_posterior_state_reconstruction_maximum_absolute_error"
                    ]
                ),
                "covariance_maximum_absolute_error": float(
                    reconstructed[
                        "global_posterior_covariance_reconstruction_maximum_absolute_error"
                    ]
                ),
            },
            "scope_limit": config["scope_limit"],
        }
        _write_json(staging / "summary.json", summary)
        _write_json(
            staging / "environment.json",
            {
                "python": sys.version,
                "platform": platform.platform(),
                "numpy": np.__version__,
                "elapsed_seconds": time.monotonic() - started,
                "sealed_ideal_evidence": str(source),
                "sealed_ideal_evidence_sha256": source_hash,
            },
        )
        checksums = _checksums(staging)
        checksums["sealed_ideal_evidence_sha256"] = source_hash
        _write_json(staging / "checksums.json", checksums)
        os.replace(staging, output_dir)
        published = True
    finally:
        if not published and staging.exists():
            shutil.rmtree(staging)
    print(json.dumps(summary, indent=2), flush=True)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    run(args.config, args.output_dir)


if __name__ == "__main__":
    main()
