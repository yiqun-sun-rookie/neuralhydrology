"""Run the preregistered post-switch forecast confirmation."""

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

from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    build_method_bank,
    build_method_definitions,
)
from hbv_multilead_joint_uncertainty.post_switch_forecast_confirmation import (  # noqa: E402
    summarize_post_switch_forecasts,
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
)
from hbv_multilead_joint_uncertainty.three_stage_switching_validation import (  # noqa: E402
    run_three_stage_switching_validation,
)
from hbv_multilead_joint_uncertainty.transition_window_forecast import (  # noqa: E402
    collect_forecasts_at_origins,
    post_switch_origins,
)


_FORECAST_CONTRACT = {
    "model_transition_during_forecast": "identity",
    "candidate_probabilities_during_forecast": (
        "fixed_at_origin_assimilation_posterior"
    ),
    "cross_candidate_state_mixing_during_forecast": False,
}
_COMPARISON_METHODS = ("full", "none", "uniform_independent")
_GENERATION = {
    "count": 96,
    "block_id_prefix": "g3_post_switch_confirmation_block_",
    "forcing_seed_start": 8811001,
    "process_noise_seed_start": 8812001,
    "observation_noise_seed_start": 8813001,
}
_SOURCE_FILES = (
    (
        "src/hbv_multilead_joint_uncertainty/"
        "post_switch_forecast_confirmation.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/"
        "transition_window_forecast.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_post_switch_forecast_confirmation.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "verify_g3_post_switch_forecast_confirmation.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/"
        "three_stage_switching_validation.py"
    ),
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_post_switch_forecast_confirmation.py",
    "test/test_hbv_post_switch_forecast_confirmation_runner.py",
    "test/test_hbv_post_switch_forecast_confirmation_verifier.py",
    "test/test_hbv_transition_window_forecast.py",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _generated_blocks(config: dict) -> tuple[dict[str, int | str], ...]:
    generation = config.get("matched_block_generation")
    if not isinstance(generation, dict):
        raise ValueError("matched block generation must be an object")
    required = set(_GENERATION)
    if set(generation) != required:
        raise ValueError(
            "matched block generation fields do not match the contract"
        )
    count = generation["count"]
    if (
        isinstance(count, bool)
        or not isinstance(count, (int, np.integer))
        or int(count) <= 0
    ):
        raise ValueError("matched block count must be a positive integer")
    prefix = generation["block_id_prefix"]
    if not isinstance(prefix, str) or not prefix:
        raise ValueError("matched block prefix must be nonempty")
    starts: dict[str, int] = {}
    for key in (
        "forcing_seed_start",
        "process_noise_seed_start",
        "observation_noise_seed_start",
    ):
        value = generation[key]
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, np.integer))
        ):
            raise ValueError("matched block seed starts must be integers")
        starts[key] = int(value)
    return tuple(
        {
            "block_id": f"{prefix}{offset + 1:03d}",
            "forcing_seed": starts["forcing_seed_start"] + offset,
            "process_noise_seed": (
                starts["process_noise_seed_start"] + offset
            ),
            "observation_noise_seed": (
                starts["observation_noise_seed_start"] + offset
            ),
        }
        for offset in range(int(count))
    )


def _with_generated_blocks(
    config: dict,
    blocks: tuple[dict[str, int | str], ...],
) -> dict:
    expanded = dict(config)
    expanded["matched_blocks"] = [dict(block) for block in blocks]
    return expanded


def _validate_config_contract(config: dict) -> None:
    if config.get("forecast_contract") != _FORECAST_CONTRACT:
        raise ValueError("forecast contract does not match the frozen contract")
    if tuple(config.get("comparison_methods", ())) != _COMPARISON_METHODS:
        raise ValueError("comparison methods do not match the frozen order")
    if tuple(config.get("lead_days", ())) != (1, 3, 7):
        raise ValueError("lead days must equal 1, 3, and 7")
    if tuple(config.get("switch_days", ())) != (180, 360):
        raise ValueError("switch days must equal 180 and 360")
    if tuple(config.get("post_switch_offsets", ())) != tuple(range(7)):
        raise ValueError("post-switch offsets must equal 0 through 6")
    if config.get("crosscheck_origin") != 539:
        raise ValueError("cross-check origin must equal 539")
    generation = config.get("matched_block_generation")
    if generation != _GENERATION:
        if isinstance(generation, dict) and generation.get("count") != 96:
            raise ValueError("matched block count must equal 96")
        raise ValueError(
            "matched block generation does not match the frozen seed contract"
        )
    blocks = _generated_blocks(config)
    all_seeds = [
        int(block[key])
        for block in blocks
        for key in (
            "forcing_seed",
            "process_noise_seed",
            "observation_noise_seed",
        )
    ]
    bootstrap = config.get("bootstrap", {})
    if bootstrap.get("unit") != "matched_block":
        raise ValueError("bootstrap unit must be matched_block")
    if bootstrap.get("replicates") != 20000:
        raise ValueError("bootstrap must use exactly 20000 replicates")
    if bootstrap.get("shared_resample_indices_across_leads") is not True:
        raise ValueError("bootstrap indices must be shared across leads")
    bootstrap_seed = bootstrap.get("seed")
    if (
        isinstance(bootstrap_seed, bool)
        or not isinstance(bootstrap_seed, (int, np.integer))
        or int(bootstrap_seed) != 8814001
    ):
        raise ValueError("bootstrap seed must equal 8814001")
    all_seeds.append(int(bootstrap_seed))
    if len(all_seeds) != len(set(all_seeds)):
        raise ValueError("forcing, noise, and bootstrap seeds must be disjoint")
    if config.get("retention_thresholds") != {
        "minimum_meaningful_rmse_fraction": 0.01,
    }:
        raise ValueError("retention thresholds do not match the frozen contract")


def _maximum_absolute_difference(left, right) -> float:
    left_values = np.asarray(left, dtype=np.float64)
    right_values = np.asarray(right, dtype=np.float64)
    if left_values.shape != right_values.shape:
        return float("inf")
    return float(
        np.max(np.abs(left_values - right_values), initial=0.0)
    )


def _derive_confirmation(
    result,
    definitions: dict,
    observation_std: float,
    config: dict,
) -> dict:
    """Collect fixed-origin forecasts and derive the three comparisons."""

    lead_days = np.asarray(config["lead_days"], dtype=np.int64)
    origins = post_switch_origins(
        config["switch_days"],
        config["post_switch_offsets"],
        crosscheck_origin=int(config["crosscheck_origin"]),
    )
    scoring_mask = origins != int(config["crosscheck_origin"])
    target_indices = origins[:, None] + lead_days[None, :]
    block_count = len(result.block_ids)
    truth_count = result.truth_discharge.shape[1]
    primary_name = str(result.schedule.primary_method_name)
    primary_index = list(result.method_names).index(primary_name)
    primary = definitions[primary_name]
    candidate_count = len(primary)
    origin_count = len(origins)
    forecasts = {
        mode: np.empty(
            (block_count, truth_count, origin_count, 3),
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
                3,
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
    truth_window = np.empty(
        (block_count, truth_count, int(np.sum(scoring_mask)), 3),
        dtype=np.float64,
    )
    parameter_ids = tuple(str(value) for value in result.parameter_ids)
    for block in range(block_count):
        initial_states = {
            parameter_id: result.initial_parameter_states[block, index]
            for index, parameter_id in enumerate(parameter_ids)
        }
        active_forcing = result.forcing_blocks[
            block, int(result.warmup_days) :
        ]
        for truth_case in range(truth_count):
            truth_window[block, truth_case] = result.truth_discharge[
                block,
                truth_case,
                target_indices[scoring_mask],
            ]
            for mode in ("full", "none"):
                bank = build_method_bank(
                    primary,
                    initial_states,
                    result.initial_covariances[block],
                    observation_std,
                    float(config["factor_transition_stay_probability"]),
                    interaction_mode=mode,
                )
                collected = collect_forecasts_at_origins(
                    forcing=active_forcing,
                    observations=result.observed_discharge[
                        block, truth_case
                    ],
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

    scoring_forecasts = {
        "full": forecasts["full"][:, :, scoring_mask],
        "none": forecasts["none"][:, :, scoring_mask],
        "uniform_independent": np.mean(
            candidates["none"][:, :, scoring_mask],
            axis=-1,
        ),
    }
    statistics = summarize_post_switch_forecasts(
        forecasts=scoring_forecasts,
        truth_forecasts=truth_window,
        lead_days=lead_days,
        bootstrap_replicates=int(config["bootstrap"]["replicates"]),
        bootstrap_seed=int(config["bootstrap"]["seed"]),
        minimum_meaningful_rmse_fraction=float(
            config["retention_thresholds"][
                "minimum_meaningful_rmse_fraction"
            ]
        ),
    )
    crosscheck_row = int(
        np.flatnonzero(
            origins == int(config["crosscheck_origin"])
        )[0]
    )
    stored_full_candidates = result.method_candidate_predictions[
        :, :, primary_index, :, :candidate_count
    ]
    stored_full_probabilities = (
        result.method_assimilation_probabilities[
            :, :, primary_index, -1, :candidate_count
        ]
    )
    reconstructed = {
        mode: np.sum(
            probabilities[mode] * candidates[mode],
            axis=-1,
        )
        for mode in ("full", "none")
    }
    probability_spread = {
        mode: float(
            np.max(
                np.abs(
                    probabilities[mode]
                    - probabilities[mode][..., :1, :]
                ),
                initial=0.0,
            )
        )
        for mode in ("full", "none")
    }
    probability_sum_error = {
        mode: float(
            np.max(
                np.abs(np.sum(probabilities[mode], axis=-1) - 1.0),
                initial=0.0,
            )
        )
        for mode in ("full", "none")
    }
    cross_checks = {
        "full_final_forecast_maximum_absolute_difference": (
            _maximum_absolute_difference(
                forecasts["full"][:, :, crosscheck_row],
                result.method_predictions[:, :, primary_index],
            )
        ),
        "full_final_candidate_maximum_absolute_difference": (
            _maximum_absolute_difference(
                candidates["full"][:, :, crosscheck_row],
                stored_full_candidates,
            )
        ),
        "full_final_probability_maximum_absolute_difference": (
            _maximum_absolute_difference(
                probabilities["full"][:, :, crosscheck_row, 0],
                stored_full_probabilities,
            )
        ),
        "full_combination_maximum_absolute_difference": (
            _maximum_absolute_difference(
                reconstructed["full"],
                forecasts["full"],
            )
        ),
        "none_combination_maximum_absolute_difference": (
            _maximum_absolute_difference(
                reconstructed["none"],
                forecasts["none"],
            )
        ),
        "full_forecast_probability_spread_across_leads": (
            probability_spread["full"]
        ),
        "none_forecast_probability_spread_across_leads": (
            probability_spread["none"]
        ),
        "full_probability_sum_maximum_absolute_error": (
            probability_sum_error["full"]
        ),
        "none_probability_sum_maximum_absolute_error": (
            probability_sum_error["none"]
        ),
        "target_indices_within_truth": bool(
            np.all(target_indices[scoring_mask] < result.truth_discharge.shape[2])
        ),
        "all_evidence_finite": bool(
            all(
                np.all(np.isfinite(values))
                for values in (
                    truth_window,
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
        cross_checks["target_indices_within_truth"]
        and cross_checks["all_evidence_finite"]
        and not cross_checks["future_observations_used_for_forecast"]
        and all(
            float(cross_checks[key]) <= 1e-12
            for key in numerical_keys
        )
    )
    return {
        "origin_indices": origins,
        "target_indices": target_indices,
        "scoring_origin_mask": scoring_mask,
        "truth_forecasts": truth_window,
        "forecasts": scoring_forecasts,
        "all_origin_forecasts": forecasts,
        "candidate_forecasts": candidates,
        "probabilities": probabilities,
        "statistics": statistics,
        "cross_checks": cross_checks,
    }


def _result_summary(statistics: dict) -> dict:
    def values(array) -> list:
        return [float(value) for value in np.asarray(array)]

    paired = {}
    for comparison, entry in statistics["paired"].items():
        paired[comparison] = {
            key: values(entry[key])
            for key in (
                "mean",
                "ci_low",
                "ci_high",
                "baseline_mse",
                "meaningful_improvement_boundary",
            )
        }
        paired[comparison]["materially_improves"] = [
            bool(value) for value in entry["materially_improves"]
        ]
    return {
        "lead_days": [
            int(value) for value in np.asarray(statistics["lead_days"])
        ],
        "rmse": {
            method: values(statistics["rmse"][method])
            for method in _COMPARISON_METHODS
        },
        "per_origin_rmse": {
            method: [
                values(row)
                for row in statistics["per_origin_rmse"][method]
            ]
            for method in _COMPARISON_METHODS
        },
        "paired": paired,
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
        "origin_indices": derived["origin_indices"],
        "target_indices": derived["target_indices"],
        "scoring_origin_mask": derived["scoring_origin_mask"],
        "truth_forecasts": derived["truth_forecasts"],
        "full_forecasts": derived["forecasts"]["full"],
        "none_forecasts": derived["forecasts"]["none"],
        "uniform_independent_forecasts": derived["forecasts"][
            "uniform_independent"
        ],
        "full_all_origin_forecasts": derived["all_origin_forecasts"][
            "full"
        ],
        "none_all_origin_forecasts": derived["all_origin_forecasts"][
            "none"
        ],
        "full_candidate_forecasts": derived["candidate_forecasts"][
            "full"
        ],
        "none_candidate_forecasts": derived["candidate_forecasts"][
            "none"
        ],
        "full_probabilities": derived["probabilities"]["full"],
        "none_probabilities": derived["probabilities"]["none"],
        "bootstrap_indices": statistics["bootstrap_indices"],
    }
    for method in _COMPARISON_METHODS:
        arrays[f"squared_error_{method}"] = statistics["squared_errors"][
            method
        ]
        arrays[f"rmse_{method}"] = statistics["rmse"][method]
        arrays[f"per_origin_rmse_{method}"] = statistics[
            "per_origin_rmse"
        ][method]
    for comparison, entry in statistics["paired"].items():
        for field in (
            "squared_error_difference",
            "block_mean",
            "mean",
            "ci_low",
            "ci_high",
            "baseline_mse",
            "meaningful_improvement_boundary",
        ):
            arrays[f"{comparison}_{field}"] = np.asarray(entry[field])
    return arrays


def _execute_confirmation(
    root: Path,
    config: dict,
    blocks: tuple[dict, ...],
) -> dict:
    parameter_vectors, parameter_csv, parameter_hash = _load_parameter_vectors(
        root, config
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
    resource = _resource_preflight(
        _with_generated_blocks(config, blocks),
        root,
    )
    forcing = _forcing_blocks(config, blocks)
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
        factor_transition_stay_probability=float(
            config["factor_transition_stay_probability"]
        ),
    )
    derived = _derive_confirmation(
        result,
        definitions,
        observation_std,
        config,
    )
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
            raise FileNotFoundError(f"source snapshot is missing: {configured}")
        if source.name in seen:
            raise ValueError(f"duplicate source snapshot basename: {source.name}")
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
    preregistration_path = output.with_name(
        output.name + ".preregistered.json"
    )
    preregistration_incomplete = preregistration_path.with_name(
        preregistration_path.name + ".incomplete"
    )
    if any(
        path.exists()
        for path in (
            output,
            incomplete,
            preregistration_path,
            preregistration_incomplete,
        )
    ):
        raise FileExistsError("refusing to overwrite existing evidence")
    config_bytes = config_file.read_bytes()
    config_hash = hashlib.sha256(config_bytes).hexdigest()
    config = json.loads(config_bytes.decode("utf-8"))
    _validate_config_contract(config)
    if output.name != str(config.get("experiment_id")):
        raise ValueError("output directory name must equal experiment_id")
    blocks = _generated_blocks(config)
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
            candidate, protected_paths
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
        "comparison_methods": config["comparison_methods"],
        "switch_days": config["switch_days"],
        "post_switch_offsets": config["post_switch_offsets"],
        "matched_block_generation": config["matched_block_generation"],
        "bootstrap": config["bootstrap"],
        "retention_thresholds": config["retention_thresholds"],
        "retention_gates": config["retention_gates"],
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
        root, config.get("protected_paths", ())
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
            root, config.get("protected_paths", ())
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
            "integrity_status": (
                "passed" if integrity_passed else "failed"
            ),
            "retention_decision": "retain" if retained else "reject",
            "protected_artifacts_unchanged": protected_unchanged,
            "cross_checks_passed": cross_checks_passed,
            "forecast_contract": config["forecast_contract"],
            "comparison_methods": config["comparison_methods"],
            "switch_days": config["switch_days"],
            "post_switch_offsets": config["post_switch_offsets"],
            "matched_block_count": len(blocks),
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
