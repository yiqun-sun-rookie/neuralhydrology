"""Run the preregistered lead-adaptive posterior-readout confirmation."""

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

from hbv_multilead_joint_uncertainty.interaction_value_comparison import (  # noqa: E402
    compare_interaction_arms,
)
from hbv_multilead_joint_uncertainty.lead_adaptive_readout import (  # noqa: E402
    lead_adaptive_posterior_readout,
    summarize_lead_adaptive_readout,
)
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    build_method_definitions,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _atomic_json_write,
    _environment,
    _forcing_blocks,
    _json_write,
    _load_observation_noise,
    _load_parameter_vectors,
    _load_process_covariances,
    _protected_hashes,
    _replace_directory_with_retries,
    _resource_preflight,
    _validate_output_is_disjoint_from_protected_paths,
    _validated_blocks,
)
from hbv_multilead_joint_uncertainty.three_stage_switching_validation import (  # noqa: E402
    run_three_stage_switching_validation,
)


_FORECAST_CONTRACT = {
    "model_transition_during_forecast": "identity",
    "candidate_probabilities_during_forecast": (
        "fixed_at_final_assimilation_posterior"
    ),
    "cross_candidate_state_mixing_during_forecast": False,
}
_RULE_BY_LEAD = {
    "1": "uniform",
    "3": "highest_posterior",
    "7": "highest_posterior",
}
_COMPARISON_METHODS = (
    "lead_adaptive",
    "full_posterior",
    "none_posterior",
    "uniform",
    "oracle",
)
_SOURCE_FILES = (
    "src/hbv_multilead_joint_uncertainty/lead_adaptive_readout.py",
    "src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py",
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_lead_adaptive_readout.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/"
        "three_stage_switching_validation.py"
    ),
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_lead_adaptive_readout.py",
    "test/test_hbv_lead_adaptive_readout_runner.py",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_config_contract(config: dict) -> None:
    """Reject any drift from the preregistered confirmation contract."""

    if config.get("forecast_contract") != _FORECAST_CONTRACT:
        raise ValueError("forecast contract does not match the frozen identity contract")
    if config.get("readout_rule_by_lead") != _RULE_BY_LEAD:
        raise ValueError("readout rule does not match the frozen lead mapping")
    if tuple(config.get("comparison_methods", ())) != _COMPARISON_METHODS:
        raise ValueError("comparison methods do not match the frozen order")
    if tuple(config.get("lead_days", ())) != (1, 3, 7):
        raise ValueError("lead days must equal 1, 3, and 7")

    blocks = config.get("matched_blocks")
    if not isinstance(blocks, list) or len(blocks) != 32:
        raise ValueError("matched block count must equal 32")
    required_block_fields = {
        "block_id",
        "forcing_seed",
        "process_noise_seed",
        "observation_noise_seed",
    }
    if any(set(block) != required_block_fields for block in blocks):
        raise ValueError("matched block fields do not match the frozen contract")
    block_ids = [str(block["block_id"]) for block in blocks]
    if any(not value for value in block_ids) or len(set(block_ids)) != 32:
        raise ValueError("matched block identifiers must be nonempty and unique")

    all_seeds: list[int] = []
    for key in (
        "forcing_seed",
        "process_noise_seed",
        "observation_noise_seed",
    ):
        values = [block[key] for block in blocks]
        if any(
            isinstance(value, bool)
            or not isinstance(value, (int, np.integer))
            for value in values
        ):
            raise ValueError(f"{key} seed values must be integers")
        if len(set(int(value) for value in values)) != 32:
            raise ValueError(f"{key} seed values must be unique")
        all_seeds.extend(int(value) for value in values)

    bootstrap = config.get("bootstrap", {})
    if bootstrap.get("unit") != "matched_block":
        raise ValueError("bootstrap unit must be matched_block")
    if bootstrap.get("replicates") != 20000:
        raise ValueError("bootstrap must use exactly 20000 replicates")
    bootstrap_seed = bootstrap.get("seed")
    if (
        isinstance(bootstrap_seed, bool)
        or not isinstance(bootstrap_seed, (int, np.integer))
    ):
        raise ValueError("bootstrap seed must be an integer")
    all_seeds.append(int(bootstrap_seed))
    if len(set(all_seeds)) != len(all_seeds):
        raise ValueError("forcing, noise, and bootstrap seed values must be disjoint")

    thresholds = config.get("retention_thresholds", {})
    if thresholds != {
        "minimum_meaningful_rmse_fraction": 0.01,
        "minimum_highest_posterior_selection_accuracy": 0.95,
        "multiday_leads": [3, 7],
    }:
        raise ValueError("retention thresholds do not match the frozen contract")


def _derive_confirmation(result, driver: dict, config: dict) -> dict:
    """Derive all readouts from stored final probabilities and candidate paths."""

    primary_name = str(result.schedule.primary_method_name)
    primary_index = list(result.method_names).index(primary_name)
    candidate_count = int(result.method_candidate_counts[primary_index])
    lead_days = np.asarray(config["lead_days"], dtype=np.int64)
    candidate_forecasts = np.asarray(
        result.method_candidate_predictions[
            :, :, primary_index, :, :candidate_count
        ],
        dtype=np.float64,
    )
    final_probabilities = np.asarray(
        result.method_assimilation_probabilities[
            :, :, primary_index, -1, :candidate_count
        ],
        dtype=np.float64,
    )
    full_forecasts = np.asarray(driver["forecasts"]["full"], dtype=np.float64)
    reconstructed_full = np.einsum(
        "btc,btlc->btl",
        final_probabilities,
        candidate_forecasts,
    )
    full_reconstruction_error = float(
        np.max(np.abs(reconstructed_full - full_forecasts))
    )

    block_count, truth_count, lead_count, _ = candidate_forecasts.shape
    readout_forecasts = np.empty(
        (block_count, truth_count, lead_count),
        dtype=np.float64,
    )
    readout_weights = np.empty_like(candidate_forecasts)
    selected_indices = np.empty((block_count, truth_count), dtype=np.int64)
    rules = {
        int(lead): rule
        for lead, rule in config["readout_rule_by_lead"].items()
    }
    for block in range(block_count):
        for truth in range(truth_count):
            readout = lead_adaptive_posterior_readout(
                final_probabilities[block, truth],
                candidate_forecasts[block, truth],
                lead_days,
                rules,
            )
            readout_forecasts[block, truth] = readout.predictions
            readout_weights[block, truth] = readout.weights
            selected_indices[block, truth] = (
                readout.selected_candidate_index
            )

    reconstructed_readout = np.sum(
        readout_weights * candidate_forecasts,
        axis=-1,
    )
    readout_reconstruction_error = float(
        np.max(np.abs(reconstructed_readout - readout_forecasts))
    )
    uniform_forecasts = np.mean(candidate_forecasts, axis=-1)
    truth_forecasts = np.asarray(driver["truth_forecasts"], dtype=np.float64)
    true_candidate_indices = np.asarray(
        driver["true_candidate_labels"][:, -1],
        dtype=np.int64,
    )
    true_candidate_indices = np.broadcast_to(
        true_candidate_indices,
        (block_count, truth_count),
    ).copy()
    forecasts = {
        "lead_adaptive": readout_forecasts,
        "full_posterior": full_forecasts,
        "none_posterior": np.asarray(
            driver["forecasts"]["none"],
            dtype=np.float64,
        ),
        "uniform": uniform_forecasts,
        "oracle": np.asarray(driver["forecasts"]["oracle"], dtype=np.float64),
    }
    statistics = summarize_lead_adaptive_readout(
        forecasts=forecasts,
        truth_forecasts=truth_forecasts,
        final_probabilities=final_probabilities,
        final_true_candidate_indices=true_candidate_indices,
        lead_days=lead_days,
        bootstrap_replicates=int(config["bootstrap"]["replicates"]),
        bootstrap_seed=int(config["bootstrap"]["seed"]),
        minimum_meaningful_rmse_fraction=float(
            config["retention_thresholds"][
                "minimum_meaningful_rmse_fraction"
            ]
        ),
    )
    selection_matches = np.array_equal(
        selected_indices,
        statistics["selected_candidate_indices"],
    )
    cross_checks = {
        "full_baseline_reconstruction_max_abs": full_reconstruction_error,
        "readout_reconstruction_max_abs": readout_reconstruction_error,
        "selected_candidate_indices_match_argmax": bool(selection_matches),
        "readout_uses_future_observations": False,
    }
    cross_checks["passed"] = bool(
        full_reconstruction_error <= 1e-12
        and readout_reconstruction_error <= 1e-12
        and selection_matches
    )
    return {
        "forecasts": forecasts,
        "truth_forecasts": truth_forecasts,
        "full_candidate_forecasts": candidate_forecasts,
        "full_final_probabilities": final_probabilities,
        "lead_adaptive_weights": readout_weights,
        "selected_candidate_indices": selected_indices,
        "true_candidate_indices": true_candidate_indices,
        "statistics": statistics,
        "cross_checks": cross_checks,
    }


def _result_summary(statistics: dict) -> dict:
    def values(array) -> list:
        return [float(value) for value in np.asarray(array)]

    paired = {}
    for name, entry in statistics["paired"].items():
        paired[name] = {
            key: values(entry[key])
            for key in (
                "mean",
                "ci_low",
                "ci_high",
                "baseline_mse",
                "meaningful_improvement_boundary",
                "meaningful_harm_boundary",
                "materially_improves",
                "no_material_harm",
            )
        }
    composite = statistics["multiday_normalized_mse_composite"]
    return {
        "lead_days": [
            int(value) for value in np.asarray(statistics["lead_days"])
        ],
        "rmse": {
            method: values(statistics["rmse"][method])
            for method in _COMPARISON_METHODS
        },
        "paired": paired,
        "multiday_normalized_mse_composite": {
            "mean": float(composite["mean"]),
            "ci_low": float(composite["ci_low"]),
            "ci_high": float(composite["ci_high"]),
        },
        "selection_accuracy": float(statistics["selection_accuracy"]),
        "retention_gates": {
            key: bool(value)
            for key, value in statistics["retention_gates"].items()
        },
    }


def _evidence_arrays(
    derived: dict,
    blocks: tuple[dict, ...],
    lead_days: np.ndarray,
) -> dict[str, np.ndarray]:
    statistics = derived["statistics"]
    arrays: dict[str, np.ndarray] = {
        "block_ids": np.asarray(
            [str(block["block_id"]) for block in blocks]
        ),
        "forcing_seeds": np.asarray(
            [int(block["forcing_seed"]) for block in blocks],
            dtype=np.int64,
        ),
        "process_noise_seeds": np.asarray(
            [int(block["process_noise_seed"]) for block in blocks],
            dtype=np.int64,
        ),
        "observation_noise_seeds": np.asarray(
            [int(block["observation_noise_seed"]) for block in blocks],
            dtype=np.int64,
        ),
        "lead_days": np.asarray(lead_days, dtype=np.int64),
        "truth_forecasts": derived["truth_forecasts"],
        "full_posterior_forecasts": derived["forecasts"]["full_posterior"],
        "full_candidate_forecasts": derived["full_candidate_forecasts"],
        "full_final_probabilities": derived["full_final_probabilities"],
        "none_posterior_forecasts": derived["forecasts"]["none_posterior"],
        "uniform_forecasts": derived["forecasts"]["uniform"],
        "oracle_forecasts": derived["forecasts"]["oracle"],
        "lead_adaptive_forecasts": derived["forecasts"]["lead_adaptive"],
        "lead_adaptive_weights": derived["lead_adaptive_weights"],
        "selected_candidate_indices": derived["selected_candidate_indices"],
        "true_candidate_indices": derived["true_candidate_indices"],
        "bootstrap_indices": statistics["bootstrap_indices"],
        "multiday_lead_mask": statistics[
            "multiday_normalized_mse_composite"
        ]["lead_mask"],
        "multiday_normalized_squared_error_difference": statistics[
            "multiday_normalized_mse_composite"
        ]["normalized_squared_error_difference"],
        "multiday_composite_block_mean": statistics[
            "multiday_normalized_mse_composite"
        ]["block_mean"],
    }
    for method in _COMPARISON_METHODS:
        arrays[f"squared_error_{method}"] = statistics["squared_errors"][
            method
        ]
        arrays[f"rmse_{method}"] = statistics["rmse"][method]
    for comparison, entry in statistics["paired"].items():
        for field in (
            "squared_error_difference",
            "block_mean",
            "mean",
            "ci_low",
            "ci_high",
            "baseline_mse",
            "meaningful_improvement_boundary",
            "meaningful_harm_boundary",
        ):
            arrays[f"{comparison}_{field}"] = np.asarray(entry[field])
    return arrays


def _execute_confirmation(
    root: Path,
    config: dict,
    blocks: tuple[dict, ...],
) -> dict:
    """Run truth generation, existing comparisons, and the new pure readout."""

    parameter_vectors, parameter_csv, parameter_hash = _load_parameter_vectors(
        root,
        config,
    )
    (
        process_covariances,
        process_scales,
        process_csv,
        process_hash,
    ) = _load_process_covariances(root, config)
    observation_std, observation_csv, observation_hash = (
        _load_observation_noise(root, config)
    )
    resource = _resource_preflight(config, root)
    forcing = _forcing_blocks(config, blocks)
    stay_probability = float(
        config["factor_transition_stay_probability"]
    )
    selected_process = str(
        config["process_noise_source"]["selected_process_id"]
    )
    definitions = build_method_definitions(
        parameter_vectors,
        process_scales,
        process_covariances,
        selected_process,
    )
    result = run_three_stage_switching_validation(
        forcing_blocks=forcing,
        block_ids=tuple(str(block["block_id"]) for block in blocks),
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=selected_process,
        scenario=str(config["scenario"]),
        process_noise_seeds=tuple(
            int(block["process_noise_seed"]) for block in blocks
        ),
        observation_noise_seeds=tuple(
            int(block["observation_noise_seed"]) for block in blocks
        ),
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_lengths=tuple(int(value) for value in config["stage_lengths"]),
        lead_days=tuple(int(value) for value in config["lead_days"]),
        initial_covariance_fraction=float(
            config["initial_covariance_fraction"]
        ),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=stay_probability,
    )
    driver = compare_interaction_arms(
        result,
        definitions,
        observation_std,
        stay_probability,
    )
    derived = _derive_confirmation(result, driver, config)
    return {
        "evidence": _evidence_arrays(
            derived,
            blocks,
            np.asarray(config["lead_days"], dtype=np.int64),
        ),
        "result_summary": _result_summary(derived["statistics"]),
        "cross_checks": derived["cross_checks"],
        "resource_preflight": resource,
        "input_snapshots": {
            "parameter_vectors.csv": parameter_csv,
            "process_noise_covariances.csv": process_csv,
            "observation_noise.csv": observation_csv,
        },
        "input_hashes": {
            "parameter_snapshot_sha256": parameter_hash,
            "process_snapshot_sha256": process_hash,
            "observation_snapshot_sha256": observation_hash,
        },
    }


def _source_snapshot(root: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    seen: set[str] = set()
    for configured in _SOURCE_FILES:
        source = (root / configured).resolve()
        if not source.is_file():
            raise FileNotFoundError(
                f"source snapshot file is missing: {configured}"
            )
        if source.name in seen:
            raise ValueError(f"duplicate source snapshot basename: {source.name}")
        seen.add(source.name)
        shutil.copy2(source, destination / source.name)


def _checksums_for_directory(directory: Path) -> dict[str, str]:
    return {
        path.relative_to(directory).as_posix(): _sha256(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
    """Execute one immutable confirmation and package its audit evidence."""

    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    preregistration_path = output.with_name(
        output.name + ".preregistered.json"
    )
    preregistration_incomplete = preregistration_path.with_name(
        preregistration_path.name + ".incomplete"
    )
    existing = (
        output,
        incomplete,
        preregistration_path,
        preregistration_incomplete,
    )
    if any(path.exists() for path in existing):
        raise FileExistsError("refusing to overwrite existing evidence")

    config_bytes = config_file.read_bytes()
    config_hash = hashlib.sha256(config_bytes).hexdigest()
    config = json.loads(config_bytes.decode("utf-8"))
    _validate_config_contract(config)
    if output.name != str(config.get("experiment_id")):
        raise ValueError("output directory name must equal experiment_id")
    blocks = _validated_blocks(config)

    protected_paths = tuple(
        (root / str(value)).resolve()
        for value in config.get("protected_paths", ())
    )
    for candidate in (
        output,
        incomplete,
        preregistration_path,
        preregistration_incomplete,
    ):
        _validate_output_is_disjoint_from_protected_paths(
            candidate,
            protected_paths,
        )

    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "frozen_before_execution": True,
        "experiment_id": config["experiment_id"],
        "scenario": config["scenario"],
        "purpose": config["purpose"],
        "design_doc": config["design_doc"],
        "implementation_plan": config["implementation_plan"],
        "forecast_contract": config["forecast_contract"],
        "readout_rule_by_lead": config["readout_rule_by_lead"],
        "comparison_methods": config["comparison_methods"],
        "matched_block_count": len(blocks),
        "lead_days": config["lead_days"],
        "bootstrap": config["bootstrap"],
        "retention_thresholds": config["retention_thresholds"],
        "config_sha256": config_hash,
        "started_at_utc": started_at,
        "output_directory": str(output),
    }
    _atomic_json_write(preregistration_path, preregistration)
    incomplete.mkdir(parents=True, exist_ok=False)
    (incomplete / "config_snapshot.json").write_bytes(config_bytes)
    (incomplete / "preregistration.json").write_bytes(
        preregistration_path.read_bytes()
    )

    protected_before = _protected_hashes(
        root,
        config.get("protected_paths", ()),
    )
    try:
        payload = _execute_confirmation(root, config, blocks)
        _json_write(
            incomplete / "resource_preflight.json",
            payload["resource_preflight"],
        )
        _json_write(
            incomplete / "cross_checks.json",
            payload["cross_checks"],
        )
        _json_write(
            incomplete / "environment.json",
            _environment(root, started_at),
        )
        for name, content in payload["input_snapshots"].items():
            (incomplete / name).write_bytes(content)
        np.savez_compressed(
            incomplete / "evidence.npz",
            **payload["evidence"],
        )
        _source_snapshot(root, incomplete / "source_snapshot")

        protected_after = _protected_hashes(
            root,
            config.get("protected_paths", ()),
        )
        protected_unchanged = protected_before == protected_after
        cross_checks_passed = bool(payload["cross_checks"]["passed"])
        integrity_passed = bool(
            protected_unchanged and cross_checks_passed
        )
        retained = bool(
            payload["result_summary"]["retention_gates"]["retain"]
        )
        summary = {
            "experiment_id": config["experiment_id"],
            "scenario": config["scenario"],
            "integrity_status": "passed" if integrity_passed else "failed",
            "retention_decision": "retain" if retained else "reject",
            "protected_artifacts_unchanged": protected_unchanged,
            "cross_checks_passed": cross_checks_passed,
            "forecast_contract": config["forecast_contract"],
            "readout_rule_by_lead": config["readout_rule_by_lead"],
            "comparison_methods": config["comparison_methods"],
            "config_sha256": config_hash,
            "scope_limit": config["scope_limit"],
            **payload["input_hashes"],
            "result": payload["result_summary"],
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
        _json_write(
            incomplete / "checksums.json",
            _checksums_for_directory(incomplete),
        )
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
