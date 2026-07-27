"""Run the sealed post-switch forecast-window development screen."""

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
    post_switch_origins,
)


_FORECAST_CONTRACT = {
    "model_transition_during_forecast": "identity",
    "candidate_probabilities_during_forecast": (
        "fixed_at_origin_assimilation_posterior"
    ),
    "cross_candidate_state_mixing_during_forecast": False,
}
_DEVELOPMENT_GATES = {
    "one_day_maximum_rmse_harm_fraction": 0.01,
    "three_day_minimum_rmse_improvement_fraction": 0.01,
    "seven_day_minimum_rmse_improvement_fraction": 0.01,
}
_SOURCE_FILES = (
    (
        "src/hbv_multilead_joint_uncertainty/"
        "transition_window_forecast.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_post_switch_forecast_development.py"
    ),
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_transition_window_forecast.py",
    "test/test_hbv_post_switch_forecast_development_runner.py",
)


def _validate_config_contract(config: dict) -> None:
    if config.get("classification") != "development_screen":
        raise ValueError("classification must be development_screen")
    if config.get("forecast_contract") != _FORECAST_CONTRACT:
        raise ValueError("forecast contract does not match the fixed contract")
    if tuple(config.get("lead_days", ())) != (1, 3, 7):
        raise ValueError("lead days must equal 1, 3, and 7")
    if tuple(config.get("switch_days", ())) != (180, 360):
        raise ValueError("switch days must equal 180 and 360")
    if tuple(config.get("post_switch_offsets", ())) != tuple(range(7)):
        raise ValueError("post-switch offsets must equal 0 through 6")
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
    if config.get("development_gates") != _DEVELOPMENT_GATES:
        raise ValueError("development gates do not match fixed thresholds")
    for key in (
        "sealed_ideal_input_evidence",
        "sealed_baseline_evidence",
    ):
        source = config.get(key, {})
        if (
            set(source) != {"path", "sha256"}
            or not isinstance(source["path"], str)
            or not source["path"]
            or not isinstance(source["sha256"], str)
            or len(source["sha256"]) != 64
        ):
            raise ValueError(f"{key} source contract is invalid")


def _summarize_development(
    *,
    full_forecasts: np.ndarray,
    none_forecasts: np.ndarray,
    truth_forecasts: np.ndarray,
    integrity_cross_checks: dict,
    gates: dict,
) -> tuple[dict, dict[str, np.ndarray]]:
    truth = np.asarray(truth_forecasts, dtype=np.float64)
    full = np.asarray(full_forecasts, dtype=np.float64)
    none = np.asarray(none_forecasts, dtype=np.float64)
    if (
        truth.ndim != 4
        or truth.shape[-1] != 3
        or full.shape != truth.shape
        or none.shape != truth.shape
    ):
        raise ValueError(
            "arrays must share [blocks, truths, origins, 3 leads]"
        )
    if not all(np.all(np.isfinite(values)) for values in (truth, full, none)):
        raise ValueError("forecast and truth arrays must be finite")
    if gates != _DEVELOPMENT_GATES:
        raise ValueError("development gates do not match fixed thresholds")
    squared_full = np.square(full - truth)
    squared_none = np.square(none - truth)
    rmse_full = np.sqrt(np.mean(squared_full, axis=(0, 1, 2)))
    rmse_none = np.sqrt(np.mean(squared_none, axis=(0, 1, 2)))
    if np.any(rmse_none <= 0.0):
        raise ValueError("no-interaction RMSE must be positive")
    relative = rmse_full / rmse_none - 1.0
    gate_results = {
        "integrity": bool(integrity_cross_checks.get("passed", False)),
        "one_day_no_more_than_one_percent_harm": bool(
            relative[0]
            <= float(gates["one_day_maximum_rmse_harm_fraction"])
        ),
        "three_day_at_least_one_percent_improvement": bool(
            relative[1]
            <= -float(
                gates["three_day_minimum_rmse_improvement_fraction"]
            )
        ),
        "seven_day_at_least_one_percent_improvement": bool(
            relative[2]
            <= -float(
                gates["seven_day_minimum_rmse_improvement_fraction"]
            )
        ),
    }
    passed = bool(all(gate_results.values()))
    summary = {
        "classification": "development_screen",
        "development_decision": (
            "advance_to_new_formal_design"
            if passed
            else "stop_no_formal_experiment"
        ),
        "lead_days": [1, 3, 7],
        "rmse": {
            "full": [float(value) for value in rmse_full],
            "none": [float(value) for value in rmse_none],
        },
        "relative_full_minus_none_rmse_percent": [
            float(value * 100.0) for value in relative
        ],
        "gates": gate_results,
    }
    return summary, {
        "forecast_full": full,
        "forecast_none": none,
        "truth_forecasts": truth,
        "squared_error_full": squared_full,
        "squared_error_none": squared_none,
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
        block_ids = _require_array(ideal, "block_ids", (block_count,)).astype(str)
        if not np.array_equal(
            block_ids,
            _require_array(
                baseline, "driver__block_ids", (block_count,)
            ).astype(str),
        ):
            raise ValueError("sealed block identifiers do not agree")
        if not np.array_equal(
            _require_array(ideal, "forecast_lead_days", (3,)),
            lead_days,
        ) or not np.array_equal(
            _require_array(baseline, "driver__forecast_lead_days", (3,)),
            lead_days,
        ):
            raise ValueError("sealed lead days do not agree")
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
        initial_states = _require_array(ideal, "initial_parameter_states")
        initial_covariances = _require_array(ideal, "initial_covariances")
        parameter_ids = _require_array(ideal, "parameter_ids", (3,)).astype(str)
        if (
            forcing_blocks.ndim != 3
            or forcing_blocks.shape[0] != block_count
            or forcing_blocks.shape[2] != 3
            or observations.shape != truth_discharge.shape
            or observations.shape[:2] != (block_count, truth_count)
            or observations.shape[2]
            != forcing_blocks.shape[1] - warmup_days
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
        primary = definitions[str(config["primary_candidate_method_name"])]
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

        origins = post_switch_origins(
            config["switch_days"],
            config["post_switch_offsets"],
            crosscheck_origin=int(config["crosscheck_origin"]),
        )
        scoring_mask = origins != int(config["crosscheck_origin"])
        origin_count = len(origins)
        scoring_count = int(np.sum(scoring_mask))
        candidate_count = len(primary)
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
        target_indices = origins[:, None] + lead_days[None, :]
        truth_window = np.empty(
            (block_count, truth_count, scoring_count, 3),
            dtype=np.float64,
        )
        for block in range(block_count):
            state_map = {
                parameter_id: initial_states[block, index]
                for index, parameter_id in enumerate(parameter_ids)
            }
            active_forcing = forcing_blocks[block, warmup_days:]
            for truth_case in range(truth_count):
                truth_window[block, truth_case] = truth_discharge[
                    block,
                    truth_case,
                    target_indices[scoring_mask],
                ]
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

        crosscheck_row = int(
            np.flatnonzero(
                origins == int(config["crosscheck_origin"])
            )[0]
        )
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
            "sealed_baseline_cross_checks_passed": True,
            "full_final_forecast_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    forecasts["full"][:, :, crosscheck_row],
                    sealed["full"]["forecast"],
                )
            ),
            "none_final_forecast_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    forecasts["none"][:, :, crosscheck_row],
                    sealed["none"]["forecast"],
                )
            ),
            "full_final_candidate_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    candidates["full"][:, :, crosscheck_row],
                    sealed["full"]["candidate"],
                )
            ),
            "none_final_candidate_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    candidates["none"][:, :, crosscheck_row],
                    sealed["none"]["candidate"],
                )
            ),
            "full_final_probability_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    probabilities["full"][:, :, crosscheck_row, 0],
                    sealed["full"]["probability"],
                )
            ),
            "none_final_probability_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    probabilities["none"][:, :, crosscheck_row, 0],
                    sealed["none"]["probability"],
                )
            ),
            "target_indices_within_truth": bool(
                np.all(target_indices[scoring_mask] < truth_discharge.shape[2])
            ),
            "all_evidence_finite": bool(
                all(
                    np.all(np.isfinite(values))
                    for values in (
                        forecasts["full"],
                        forecasts["none"],
                        candidates["full"],
                        candidates["none"],
                        probabilities["full"],
                        probabilities["none"],
                        truth_window,
                    )
                )
            ),
            "future_observation_isolation_unit_tested": True,
        }
        exact_keys = [
            key
            for key in cross_checks
            if key.endswith("maximum_absolute_difference")
        ]
        cross_checks["passed"] = bool(
            cross_checks["sealed_baseline_cross_checks_passed"]
            and cross_checks["target_indices_within_truth"]
            and cross_checks["all_evidence_finite"]
            and cross_checks["future_observation_isolation_unit_tested"]
            and all(float(cross_checks[key]) <= 1e-12 for key in exact_keys)
        )
        result_summary, summary_arrays = _summarize_development(
            full_forecasts=forecasts["full"][:, :, scoring_mask],
            none_forecasts=forecasts["none"][:, :, scoring_mask],
            truth_forecasts=truth_window,
            integrity_cross_checks=cross_checks,
            gates=config["development_gates"],
        )
        evidence = {
            "block_ids": block_ids,
            "lead_days": lead_days,
            "candidate_ids": candidate_ids,
            "origin_indices": origins,
            "target_indices": target_indices,
            "scoring_origin_mask": scoring_mask,
            "forecast_full_all_origins": forecasts["full"],
            "forecast_none_all_origins": forecasts["none"],
            "candidate_forecast_full_all_origins": candidates["full"],
            "candidate_forecast_none_all_origins": candidates["none"],
            "probabilities_full_all_origins": probabilities["full"],
            "probabilities_none_all_origins": probabilities["none"],
            **summary_arrays,
        }
        return {
            "summary": result_summary,
            "evidence": evidence,
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
    _validate_output_is_disjoint_from_protected_paths(output, protected_paths)
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
            **payload["evidence"],
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
            "switch_days": config["switch_days"],
            "post_switch_offsets": config["post_switch_offsets"],
            "development_gates": config["development_gates"],
            "scope_limit": config["scope_limit"],
            **payload["input_hashes"],
            "result": payload["summary"],
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
