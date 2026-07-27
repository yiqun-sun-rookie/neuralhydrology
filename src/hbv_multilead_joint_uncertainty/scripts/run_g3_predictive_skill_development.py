"""Run the sealed eight-block predictive-skill development screen."""

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
from hbv_multilead_joint_uncertainty.predictive_skill_readout import (  # noqa: E402
    collect_recent_candidate_hindcasts,
    rolling_predictive_skill_readout,
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


_FORECAST_CONTRACT = {
    "model_transition_during_forecast": "identity",
    "candidate_probabilities_during_forecast": (
        "fixed_at_final_assimilation_posterior"
    ),
    "cross_candidate_state_mixing_during_forecast": False,
}
_READOUT_RULE = {
    "1": "final_full_posterior_weighted",
    "3": "minimum_latest_completed_same_lead_mse",
    "7": "minimum_latest_completed_same_lead_mse",
    "window": 30,
    "tie_break": "first_candidate",
}
_DEVELOPMENT_GATES = {
    "one_day_maximum_absolute_difference": 1e-12,
    "three_day_maximum_rmse_harm_fraction": 0.01,
    "seven_day_minimum_rmse_improvement_fraction": 0.01,
}
_SOURCE_FILES = (
    "src/hbv_multilead_joint_uncertainty/predictive_skill_readout.py",
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_predictive_skill_development.py"
    ),
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_predictive_skill_readout.py",
    "test/test_hbv_predictive_skill_development_runner.py",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_config_contract(config: dict) -> None:
    """Reject drift from the result-before-screen development contract."""

    if config.get("classification") != "development_screen":
        raise ValueError("classification must be development_screen")
    if config.get("forecast_contract") != _FORECAST_CONTRACT:
        raise ValueError("forecast contract does not match the fixed identity contract")
    if config.get("readout_rule") != _READOUT_RULE:
        raise ValueError("readout rule does not match the fixed development rule")
    if config.get("development_gates") != _DEVELOPMENT_GATES:
        raise ValueError("development gates do not match the fixed thresholds")
    if tuple(config.get("lead_days", ())) != (1, 3, 7):
        raise ValueError("lead days must equal 1, 3, and 7")
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
    stay = config.get("factor_transition_stay_probability")
    if (
        isinstance(stay, bool)
        or not isinstance(stay, (int, float))
        or float(stay) != 0.98
    ):
        raise ValueError("transition stay probability must equal 0.98")
    for key in (
        "sealed_ideal_input_evidence",
        "sealed_baseline_evidence",
    ):
        source = config.get(key, {})
        if set(source) != {"path", "sha256"}:
            raise ValueError(f"{key} must contain path and sha256")
        if (
            not isinstance(source["path"], str)
            or not source["path"]
            or not isinstance(source["sha256"], str)
            or len(source["sha256"]) != 64
        ):
            raise ValueError(f"{key} source contract is invalid")


def _checked_archive(root: Path, source: dict) -> np.lib.npyio.NpzFile:
    path = (root / str(source["path"])).resolve()
    if not path.is_file():
        raise FileNotFoundError(f"sealed evidence is missing: {source['path']}")
    actual = _sha256(path)
    if actual != str(source["sha256"]):
        raise ValueError(f"sealed evidence checksum mismatch: {source['path']}")
    return np.load(path, allow_pickle=False)


def _maximum_absolute_difference(left, right) -> float:
    left_values = np.asarray(left, dtype=np.float64)
    right_values = np.asarray(right, dtype=np.float64)
    if left_values.shape != right_values.shape:
        return float("inf")
    return float(np.max(np.abs(left_values - right_values), initial=0.0))


def _summarize_development(
    *,
    skill_forecasts: np.ndarray,
    full_forecasts: np.ndarray,
    none_forecasts: np.ndarray,
    truth_forecasts: np.ndarray,
    selected_candidate_indices: np.ndarray,
    predictive_optimum_indices: np.ndarray,
    true_candidate_indices: np.ndarray,
    integrity_cross_checks: dict,
    gates: dict,
) -> tuple[dict, dict[str, np.ndarray]]:
    """Apply the fixed development gates without inferential claims."""

    truth = np.asarray(truth_forecasts, dtype=np.float64)
    forecasts = {
        "predictive_skill": np.asarray(skill_forecasts, dtype=np.float64),
        "full": np.asarray(full_forecasts, dtype=np.float64),
        "none": np.asarray(none_forecasts, dtype=np.float64),
    }
    if truth.ndim != 3 or truth.shape[2] != 3 or any(
        values.shape != truth.shape for values in forecasts.values()
    ):
        raise ValueError("forecast arrays must share [blocks, truths, 3 leads]")
    if not np.all(np.isfinite(truth)) or any(
        not np.all(np.isfinite(values)) for values in forecasts.values()
    ):
        raise ValueError("forecast and truth arrays must be finite")
    selected = np.asarray(selected_candidate_indices)
    optimum = np.asarray(predictive_optimum_indices)
    true_indices = np.asarray(true_candidate_indices)
    if (
        selected.shape != truth.shape
        or optimum.shape != truth.shape
        or true_indices.shape != truth.shape[:2]
        or not np.issubdtype(selected.dtype, np.integer)
        or not np.issubdtype(optimum.dtype, np.integer)
        or not np.issubdtype(true_indices.dtype, np.integer)
    ):
        raise ValueError("candidate index arrays have invalid shapes or types")
    if gates != _DEVELOPMENT_GATES:
        raise ValueError("development gates do not match the fixed thresholds")

    squared_errors = {
        method: np.square(values - truth)
        for method, values in forecasts.items()
    }
    rmse = {
        method: np.sqrt(np.mean(values, axis=(0, 1)))
        for method, values in squared_errors.items()
    }
    if np.any(rmse["full"] <= 0.0) or np.any(rmse["none"] <= 0.0):
        raise ValueError("baseline RMSE must be positive")
    relative_full = rmse["predictive_skill"] / rmse["full"] - 1.0
    relative_none = rmse["predictive_skill"] / rmse["none"] - 1.0
    one_day_difference = _maximum_absolute_difference(
        forecasts["predictive_skill"][..., 0],
        forecasts["full"][..., 0],
    )
    three_harm = float(gates["three_day_maximum_rmse_harm_fraction"])
    seven_improvement = float(
        gates["seven_day_minimum_rmse_improvement_fraction"]
    )
    gate_results = {
        "integrity": bool(integrity_cross_checks.get("passed", False)),
        "one_day_exact": bool(
            one_day_difference
            <= float(gates["one_day_maximum_absolute_difference"])
        ),
        "three_day_no_more_than_one_percent_harm_vs_full": bool(
            relative_full[1] <= three_harm
        ),
        "three_day_no_more_than_one_percent_harm_vs_none": bool(
            relative_none[1] <= three_harm
        ),
        "seven_day_at_least_one_percent_improvement_vs_full": bool(
            relative_full[2] <= -seven_improvement
        ),
        "seven_day_at_least_one_percent_improvement_vs_none": bool(
            relative_none[2] <= -seven_improvement
        ),
    }
    passed = bool(all(gate_results.values()))
    candidate_count = int(
        max(
            np.max(selected, initial=0),
            np.max(optimum, initial=0),
            np.max(true_indices, initial=0),
        )
        + 1
    )
    selection_counts = np.stack(
        [
            np.bincount(
                selected[..., lead][
                    selected[..., lead] >= 0
                ].ravel(),
                minlength=candidate_count,
            )
            for lead in range(3)
        ]
    )
    predictive_match = np.mean(selected == optimum, axis=(0, 1))
    true_match = np.mean(
        selected == true_indices[..., None],
        axis=(0, 1),
    )
    summary = {
        "classification": "development_screen",
        "development_decision": (
            "advance_to_new_formal_design"
            if passed
            else "stop_no_formal_experiment"
        ),
        "lead_days": [1, 3, 7],
        "rmse": {
            method: [float(value) for value in values]
            for method, values in rmse.items()
        },
        "relative_rmse_percent": {
            "predictive_skill_minus_full": [
                float(value * 100.0) for value in relative_full
            ],
            "predictive_skill_minus_none": [
                float(value * 100.0) for value in relative_none
            ],
        },
        "one_day_maximum_absolute_difference": one_day_difference,
        "selected_is_predictive_optimum_fraction": [
            float(value) for value in predictive_match
        ],
        "selected_is_true_parameter_fraction": [
            float(value) for value in true_match
        ],
        "selection_counts_by_lead_and_candidate": selection_counts.tolist(),
        "gates": gate_results,
    }
    evidence = {
        "forecast_predictive_skill": forecasts["predictive_skill"],
        "forecast_full": forecasts["full"],
        "forecast_none": forecasts["none"],
        "truth_forecasts": truth,
        "squared_error_predictive_skill": squared_errors[
            "predictive_skill"
        ],
        "squared_error_full": squared_errors["full"],
        "squared_error_none": squared_errors["none"],
        "selected_candidate_indices": selected.astype(np.int64, copy=False),
        "predictive_optimum_indices": optimum.astype(np.int64, copy=False),
        "true_candidate_indices": true_indices.astype(np.int64, copy=False),
        "selection_counts": selection_counts,
    }
    return summary, evidence


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
    """Replay only the primary full-interaction bank on sealed old inputs."""

    ideal_source = config["sealed_ideal_input_evidence"]
    baseline_source = config["sealed_baseline_evidence"]
    with _checked_archive(root, ideal_source) as ideal, _checked_archive(
        root, baseline_source
    ) as baseline:
        block_count = int(config["expected_block_count"])
        truth_count = int(config["expected_truth_count"])
        lead_days = np.asarray(config["lead_days"], dtype=np.int64)
        block_ids = _require_array(ideal, "block_ids", (block_count,)).astype(str)
        baseline_block_ids = _require_array(
            baseline, "driver__block_ids", (block_count,)
        ).astype(str)
        if not np.array_equal(block_ids, baseline_block_ids):
            raise ValueError("sealed block identifiers do not agree")
        if not np.array_equal(
            _require_array(ideal, "forecast_lead_days", (3,)),
            lead_days,
        ) or not np.array_equal(
            _require_array(baseline, "driver__forecast_lead_days", (3,)),
            lead_days,
        ):
            raise ValueError("sealed lead days do not agree")
        if not bool(_require_array(baseline, "cross_checks__passed", ())):
            raise ValueError("sealed baseline cross-check did not pass")

        assimilation_days = int(
            _require_array(ideal, "assimilation_days", ())
        )
        warmup_days = int(_require_array(ideal, "warmup_days", ()))
        forcing_blocks = _require_array(ideal, "forcing_blocks")
        observations = _require_array(ideal, "observed_discharge")
        initial_states = _require_array(ideal, "initial_parameter_states")
        initial_covariances = _require_array(ideal, "initial_covariances")
        parameter_ids = _require_array(ideal, "parameter_ids", (3,)).astype(str)
        if (
            forcing_blocks.ndim != 3
            or forcing_blocks.shape[0] != block_count
            or forcing_blocks.shape[2] != 3
            or observations.shape
            != (block_count, truth_count, forcing_blocks.shape[1] - warmup_days)
            or initial_states.shape != (block_count, 3, 15)
            or initial_covariances.shape != (block_count, 15, 15)
            or forcing_blocks.shape[1] - warmup_days
            < assimilation_days + int(lead_days[-1])
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
        sealed_candidate_ids = _require_array(
            baseline, "driver__candidate_ids", (len(primary),)
        ).astype(str)
        if not np.array_equal(candidate_ids, sealed_candidate_ids):
            raise ValueError("candidate order does not match sealed baseline")

        full_forecasts = _require_array(
            baseline,
            "driver__full_states_full_weights",
            (block_count, truth_count, 3),
        ).astype(np.float64)
        none_forecasts = _require_array(
            baseline,
            "driver__none_states_none_weights",
            (block_count, truth_count, 3),
        ).astype(np.float64)
        truth_forecasts = _require_array(
            baseline,
            "driver__truth_forecasts",
            (block_count, truth_count, 3),
        ).astype(np.float64)
        sealed_candidates = _require_array(
            baseline,
            "driver__candidate_forecasts_full",
            (block_count, truth_count, 3, len(primary)),
        ).astype(np.float64)
        sealed_probabilities = _require_array(
            baseline,
            "driver__final_probabilities_full",
            (block_count, truth_count, len(primary)),
        ).astype(np.float64)
        truth_indices_by_case = _require_array(
            baseline,
            "driver__final_true_candidate_indices",
            (truth_count,),
        ).astype(np.int64)
        truth_indices = np.broadcast_to(
            truth_indices_by_case,
            (block_count, truth_count),
        ).copy()

        origin_count = 35
        candidate_count = len(primary)
        skill_forecasts = np.empty(
            (block_count, truth_count, 3), dtype=np.float64
        )
        final_candidates = np.empty(
            (block_count, truth_count, 3, candidate_count),
            dtype=np.float64,
        )
        final_probabilities = np.empty(
            (block_count, truth_count, candidate_count),
            dtype=np.float64,
        )
        weights = np.empty_like(final_candidates)
        scores = np.empty_like(final_candidates)
        selected = np.empty(
            (block_count, truth_count, 3), dtype=np.int64
        )
        history_origins = np.empty(
            (
                block_count,
                truth_count,
                3,
                int(config["readout_rule"]["window"]),
            ),
            dtype=np.int64,
        )
        recent_origins = np.empty(
            (block_count, truth_count, origin_count),
            dtype=np.int64,
        )
        recent_targets = np.empty(
            (block_count, truth_count, origin_count, 3),
            dtype=np.int64,
        )
        recent_candidates = np.empty(
            (
                block_count,
                truth_count,
                origin_count,
                3,
                candidate_count,
            ),
            dtype=np.float64,
        )
        final_origin = assimilation_days - 1
        window = int(config["readout_rule"]["window"])
        for block in range(block_count):
            state_map = {
                parameter_id: initial_states[block, index]
                for index, parameter_id in enumerate(parameter_ids)
            }
            active_forcing = forcing_blocks[block, warmup_days:]
            for truth_case in range(truth_count):
                bank = build_method_bank(
                    primary,
                    state_map,
                    initial_covariances[block],
                    observation_std,
                    float(config["factor_transition_stay_probability"]),
                    interaction_mode="full",
                )
                recent = collect_recent_candidate_hindcasts(
                    forcing=active_forcing,
                    observations=observations[block, truth_case],
                    bank=bank,
                    final_origin_index=final_origin,
                    lead_days=lead_days,
                    window=window,
                    interaction_mode="full",
                )
                if len(recent.origin_indices) != origin_count:
                    raise ValueError("unexpected recent-origin count")
                final_rows = np.flatnonzero(
                    recent.origin_indices == final_origin
                )
                if len(final_rows) != 1:
                    raise ValueError("final origin is missing or duplicated")
                final_row = int(final_rows[0])
                readout = rolling_predictive_skill_readout(
                    origin_indices=recent.origin_indices,
                    target_indices=recent.target_indices,
                    historical_candidate_predictions=(
                        recent.candidate_predictions
                    ),
                    observations=observations[block, truth_case],
                    final_candidate_predictions=(
                        recent.candidate_predictions[final_row]
                    ),
                    final_probabilities=recent.final_probabilities,
                    final_origin_index=final_origin,
                    lead_days=lead_days,
                    window=window,
                )
                skill_forecasts[block, truth_case] = readout.predictions
                final_candidates[block, truth_case] = (
                    recent.candidate_predictions[final_row]
                )
                final_probabilities[block, truth_case] = (
                    recent.final_probabilities
                )
                weights[block, truth_case] = readout.weights
                scores[block, truth_case] = (
                    readout.historical_mean_squared_errors
                )
                selected[block, truth_case] = (
                    readout.selected_candidate_indices
                )
                history_origins[block, truth_case] = (
                    readout.history_origin_indices
                )
                recent_origins[block, truth_case] = recent.origin_indices
                recent_targets[block, truth_case] = recent.target_indices
                recent_candidates[block, truth_case] = (
                    recent.candidate_predictions
                )

        reconstructed_full = np.sum(
            final_probabilities[:, :, None, :] * final_candidates,
            axis=-1,
        )
        cross_checks = {
            "sealed_baseline_cross_checks_passed": True,
            "final_candidate_forecasts_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    final_candidates,
                    sealed_candidates,
                )
            ),
            "final_probabilities_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    final_probabilities,
                    sealed_probabilities,
                )
            ),
            "full_forecast_reconstruction_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    reconstructed_full,
                    full_forecasts,
                )
            ),
            "one_day_readout_maximum_absolute_difference": (
                _maximum_absolute_difference(
                    skill_forecasts[..., 0],
                    full_forecasts[..., 0],
                )
            ),
            "all_evidence_finite": bool(
                all(
                    np.all(np.isfinite(values))
                    for values in (
                        skill_forecasts,
                        final_candidates,
                        final_probabilities,
                        recent_candidates,
                    )
                )
            ),
            "history_target_indices_completed": bool(
                np.all(
                    np.where(
                        history_origins[:, :, 1:, :] >= 0,
                        history_origins[:, :, 1:, :]
                        + lead_days[None, None, 1:, None]
                        <= final_origin,
                        True,
                    )
                )
            ),
        }
        cross_checks["passed"] = bool(
            cross_checks["sealed_baseline_cross_checks_passed"]
            and cross_checks["all_evidence_finite"]
            and cross_checks["history_target_indices_completed"]
            and cross_checks[
                "final_candidate_forecasts_maximum_absolute_difference"
            ]
            <= 1e-12
            and cross_checks[
                "final_probabilities_maximum_absolute_difference"
            ]
            <= 1e-12
            and cross_checks[
                "full_forecast_reconstruction_maximum_absolute_difference"
            ]
            <= 1e-12
            and cross_checks[
                "one_day_readout_maximum_absolute_difference"
            ]
            <= 1e-12
        )
        predictive_optimum = np.argmin(
            np.square(final_candidates - truth_forecasts[..., None]),
            axis=-1,
        )
        result_summary, summary_arrays = _summarize_development(
            skill_forecasts=skill_forecasts,
            full_forecasts=full_forecasts,
            none_forecasts=none_forecasts,
            truth_forecasts=truth_forecasts,
            selected_candidate_indices=selected,
            predictive_optimum_indices=predictive_optimum,
            true_candidate_indices=truth_indices,
            integrity_cross_checks=cross_checks,
            gates=config["development_gates"],
        )
        evidence = {
            "block_ids": block_ids,
            "lead_days": lead_days,
            "candidate_ids": candidate_ids,
            "recent_origin_indices": recent_origins,
            "recent_target_indices": recent_targets,
            "recent_candidate_forecasts": recent_candidates,
            "final_candidate_forecasts": final_candidates,
            "final_probabilities": final_probabilities,
            "predictive_skill_weights": weights,
            "historical_mean_squared_errors": scores,
            "history_origin_indices": history_origins,
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
    """Execute one immutable development screen and package its evidence."""

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
            "readout_rule": config["readout_rule"],
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
