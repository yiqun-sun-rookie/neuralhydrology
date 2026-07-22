"""Run auditable HBV-lite origin-state correction diagnostics."""

from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import pandas as pd

from hbv_joint_uncertainty.candidates import sha256_file
from hbv_joint_uncertainty.hbv_adapter import STATE_NAMES, simulate_adapter

from hbv_multilead_joint_uncertainty.experiment import calculate_metrics
from hbv_multilead_joint_uncertainty.methods import build_method_bank, build_method_definitions
from hbv_multilead_joint_uncertainty.orchestrator import collect_contract_snapshot_files
from hbv_multilead_joint_uncertainty.preparation import (
    _load_complete_period,
    _load_forcing_only_period,
    _method_contract_parts,
)
from hbv_multilead_joint_uncertainty.registry import RunRegistry
from hbv_multilead_joint_uncertainty.resource_monitor import (
    ResourceRecorder,
    verify_resource_history_rows,
)
from hbv_multilead_joint_uncertainty.state_correction_diagnostic import (
    diagnostic_result_arrays,
    evaluate_continuation_gate,
    hbv_water_balance_residual,
    load_diagnostic_checkpoint,
    run_state_diagnostic_assimilation,
    save_diagnostic_checkpoint,
    validate_replay_arrays,
)
from hbv_joint_uncertainty.resource_monitor import ResourceGateError


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def verify_checksum_package(directory: Path, expected_checksum_table_hash: str) -> dict:
    """Verify a checksum table and every file it declares."""
    root = Path(directory).resolve()
    checksum_path = root / "checksums.json"
    expected_table_hash = str(expected_checksum_table_hash).lower()
    actual_table_hash = sha256_file(checksum_path)
    if actual_table_hash != expected_table_hash:
        raise ValueError(
            f"checksum table mismatch for {root}: expected {expected_table_hash}, got {actual_table_hash}"
        )
    declared = json.loads(checksum_path.read_text(encoding="utf-8"))
    if not isinstance(declared, dict) or not declared:
        raise ValueError(f"checksum table for {root} must be a nonempty object")
    verified = 0
    for relative, expected_hash in declared.items():
        path = (root / str(relative)).resolve()
        try:
            path.relative_to(root)
        except ValueError as error:
            raise ValueError(f"checksum path escapes package: {relative}") from error
        if not path.is_file():
            raise ValueError(f"checksum file is missing: {relative}")
        actual_hash = sha256_file(path)
        if actual_hash != str(expected_hash).lower():
            raise ValueError(
                f"checksum mismatch for {relative}: expected {expected_hash}, got {actual_hash}"
            )
        verified += 1
    return {
        "passed": True,
        "package": str(root),
        "checksum_table_sha256": actual_table_hash,
        "declared_file_count": len(declared),
        "verified_file_count": verified,
    }


def finalize_output_checksums(
    directory: Path,
    *,
    stable_hashes: Mapping[str, str],
    refresh_relatives: set[str],
) -> dict:
    """Write the final table after mutable monitor files have received their last sample.

    ``stable_hashes`` must have been computed and verified immediately before the
    resource recorder was stopped. Only ``refresh_relatives`` are rehashed here;
    this keeps the unmonitored finalization shorter than one monitoring interval.
    """
    root = Path(directory).resolve()
    refresh = {Path(value).as_posix() for value in refresh_relatives}
    stable = {Path(key).as_posix(): str(value).lower() for key, value in stable_hashes.items()}
    if set(stable).intersection(refresh):
        raise ValueError("stable and refreshed output checksum paths must be disjoint")
    actual_files = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    declared_files = set(stable).union(refresh)
    if actual_files != declared_files:
        missing = sorted(actual_files - declared_files)
        extra = sorted(declared_files - actual_files)
        raise ValueError(f"output checksum file set mismatch: unlisted={missing}, absent={extra}")
    output_hashes = dict(stable)
    for relative in sorted(refresh):
        path = (root / relative).resolve()
        try:
            path.relative_to(root)
        except ValueError as error:
            raise ValueError(f"output checksum path escapes package: {relative}") from error
        output_hashes[relative] = sha256_file(path)
    output_hashes = dict(sorted(output_hashes.items()))
    _write_json(root / "checksums.json", output_hashes)
    for relative in sorted(refresh):
        if sha256_file(root / relative) != output_hashes[relative]:
            raise ValueError(f"new output checksum mismatch after finalization: {relative}")
    return {
        "passed": True,
        "checksum_table_sha256": sha256_file(root / "checksums.json"),
        "declared_file_count": len(output_hashes),
        "verified_file_count": len(output_hashes),
        "refreshed_file_count": len(refresh),
    }


def load_verified_resume_checkpoint(
    checkpoint_path: Path,
    current_identity: Mapping[str, str],
):
    """Verify the external manifest and file checksum before loading arrays."""
    source_path = Path(checkpoint_path).resolve()
    manifest_path = source_path.with_suffix(".json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected_hash = str(manifest.get("checkpoint_sha256", "")).lower()
    if len(expected_hash) != 64 or any(character not in "0123456789abcdef" for character in expected_hash):
        raise ValueError("resume checkpoint manifest has an invalid checkpoint checksum")
    actual_hash = sha256_file(source_path)
    if actual_hash != expected_hash:
        raise ValueError(
            f"resume checkpoint checksum mismatch: expected {expected_hash}, got {actual_hash}"
        )
    saved_identity = {str(key): str(value) for key, value in manifest["identity"].items()}
    current = {str(key): str(value) for key, value in current_identity.items()}
    for key in ("experiment_family", "config_sha256", "input_sha256", "source_sha256"):
        if saved_identity.get(key) != current.get(key):
            raise ValueError(f"resume checkpoint {key} does not match the current run")
    return load_diagnostic_checkpoint(source_path, saved_identity)


def write_resource_history_verification(
    history_path: Path,
    resource_config: Mapping,
    report_path: Path,
) -> dict:
    """Require a complete, gate-compliant start-to-finish resource history."""
    history = json.loads(Path(history_path).read_text(encoding="utf-8"))
    report = verify_resource_history_rows(
        history,
        resource_config,
        require_finish=True,
    )
    _write_json(Path(report_path), report)
    return report


def load_effective_config(config_path: Path) -> tuple[dict, dict]:
    """Load a full config or a checksum-bound resource-only overlay."""
    path = Path(config_path).resolve()
    overlay = json.loads(path.read_text(encoding="utf-8"))
    inherited = overlay.get("inherits")
    if inherited is None:
        return dict(overlay), overlay
    base_path = (path.parent / str(inherited)).resolve()
    expected_hash = str(overlay.get("inherited_config_sha256", "")).lower()
    if sha256_file(base_path) != expected_hash:
        raise ValueError("inherited state-correction config checksum mismatch")
    base = json.loads(base_path.read_text(encoding="utf-8"))
    effective = dict(base)
    effective["experiment_family"] = overlay["experiment_family"]
    effective["resource"] = dict(overlay["resource"])
    for key in overlay.get("override_keys", []):
        if key in {"experiment_family", "resource"} or key not in overlay:
            raise ValueError(f"invalid state-correction config override key: {key}")
        effective[str(key)] = overlay[key]
    effective["resource_revision"] = {
        key: value for key, value in overlay.items() if key != "resource"
    }
    return effective, overlay


def control_metric_rows(
    basin_id: str,
    lead_days,
    target_observations,
    predictions: Mapping[str, np.ndarray],
) -> list[dict]:
    """Compute one metric row per control and lead against exact targets."""
    leads = np.asarray(lead_days, dtype=np.int64)
    observed = np.asarray(target_observations, dtype=np.float64)
    if observed.ndim != 2 or observed.shape[1] != len(leads):
        raise ValueError("target observations must have one column per lead")
    rows = []
    for control_id, values in predictions.items():
        predicted = np.asarray(values, dtype=np.float64)
        if predicted.shape != observed.shape:
            raise ValueError(f"control {control_id} predictions do not match target observations")
        for lead_index, lead in enumerate(leads):
            metrics = calculate_metrics(observed[:, lead_index], predicted[:, lead_index])
            rows.append(
                {
                    "basin_id": str(basin_id).zfill(8),
                    "control_id": str(control_id),
                    "lead_days": int(lead),
                    "n_origins": len(observed),
                    **metrics,
                }
            )
    return rows


def _state_update_masks(config: Mapping) -> dict[str, np.ndarray]:
    controls = {row["control_id"]: row for row in config["controls"]}
    required = (
        "current_joint_all_fifteen_states",
        "hydrologic_five_states_only",
        "runoff_two_states_only",
    )
    masks = {}
    for control_id in required:
        indices = tuple(int(value) for value in controls[control_id]["allowed_state_indices"])
        if len(indices) != len(set(indices)) or any(value < 0 or value >= len(STATE_NAMES) for value in indices):
            raise ValueError(f"control {control_id} has invalid state indices")
        mask = np.zeros(len(STATE_NAMES), dtype=np.float64)
        mask[list(indices)] = 1.0
        masks[control_id] = mask
    return masks


def _replay_report(result, formal_arrays, config: Mapping) -> dict:
    reference = result.controls["current_joint_all_fifteen_states"]
    replayed = {
        "joint_predictions": reference.predictions,
        "joint_candidate_predictions": reference.candidate_predictions,
        "joint_probabilities": reference.probabilities,
        "joint_candidate_covariance_diagonals": reference.candidate_covariance_diagonals,
        "joint_combined_covariance_diagonals": reference.combined_covariance_diagonals,
    }
    saved = {
        "joint_predictions": formal_arrays["joint__predictions"],
        "joint_candidate_predictions": formal_arrays["joint__candidate_predictions"],
        "joint_probabilities": formal_arrays["joint__probabilities"],
        "joint_candidate_covariance_diagonals": formal_arrays[
            "joint__candidate_covariance_diagonals"
        ],
        "joint_combined_covariance_diagonals": formal_arrays[
            "joint__combined_covariance_diagonals"
        ],
    }
    tolerances = config["formal_replay_validation"]
    report = validate_replay_arrays(
        replayed,
        saved,
        maximum_absolute_error=tolerances["maximum_absolute_error"],
        maximum_relative_error=tolerances["maximum_relative_error"],
        relative_error_denominator_floor=tolerances["relative_error_denominator_floor"],
    )
    common = {
        "lead_days_equal": bool(np.array_equal(result.lead_days, formal_arrays["lead_days"])),
        "origin_indices_equal": bool(
            np.array_equal(result.origin_indices, formal_arrays["origin_indices"])
        ),
        "target_indices_equal": bool(
            np.array_equal(result.target_indices, formal_arrays["target_indices"])
        ),
    }
    report["common_indices"] = common
    report["passed"] = bool(report["passed"] and all(common.values()))
    return report


def _state_summary_rows(basin_id: str, result, definitions) -> list[dict]:
    rows = []
    for control_id in result.state_update_masks:
        corrections = (
            result.control_origin_candidate_posterior_states[control_id]
            - result.control_origin_candidate_prior_states[control_id]
        )
        for state_index, state_name in enumerate(STATE_NAMES):
            values = corrections[:, :, state_index]
            absolute = np.abs(values)
            unit = "mm" if state_index < 5 else "mm/day"
            relative_values = []
            normalization = "none"
            for candidate_index, definition in enumerate(definitions):
                if state_name == "SM":
                    denominator = float(definition.parameters["parFC"])
                    normalization = "parFC"
                elif state_name == "SUZ":
                    denominator = float(definition.parameters["parUZL"])
                    normalization = "parUZL_threshold"
                else:
                    continue
                if denominator > 0.0:
                    relative_values.extend((absolute[:, candidate_index] / denominator).tolist())
            rows.append(
                {
                    "basin_id": basin_id,
                    "diagnostic": "origin_candidate_correction",
                    "control_id": control_id,
                    "lead_days": 0,
                    "state_index": state_index,
                    "state_name": state_name,
                    "unit": unit,
                    "mean_signed": float(np.mean(values)),
                    "median_signed": float(np.median(values)),
                    "median_absolute": float(np.median(absolute)),
                    "p95_absolute": float(np.quantile(absolute, 0.95)),
                    "relative_normalization": normalization,
                    "median_absolute_relative": (
                        None if not relative_values else float(np.median(relative_values))
                    ),
                }
            )

    removed = result.controls["origin_mean_correction_removed"].combined_states
    for control_id in (
        "current_joint_all_fifteen_states",
        "three_day_half_life_additional_mean_taper_sensitivity",
    ):
        propagated = result.controls[control_id].combined_states - removed
        for lead_index, lead in enumerate(result.lead_days):
            for state_index, state_name in enumerate(STATE_NAMES):
                values = propagated[:, lead_index, state_index]
                rows.append(
                    {
                        "basin_id": basin_id,
                        "diagnostic": "propagated_combined_state_difference_vs_removed_mean",
                        "control_id": control_id,
                        "lead_days": int(lead),
                        "state_index": state_index,
                        "state_name": state_name,
                        "unit": "mm" if state_index < 5 else "mm/day",
                        "mean_signed": float(np.mean(values)),
                        "median_signed": float(np.median(values)),
                        "median_absolute": float(np.median(np.abs(values))),
                        "p95_absolute": float(np.quantile(np.abs(values), 0.95)),
                        "relative_normalization": "none",
                        "median_absolute_relative": None,
                    }
                )
    return rows


def _physical_checks(result, definitions, forcing) -> dict:
    tolerance = 1e-10
    violations = 0
    minimum_state = float("inf")
    maximum_soil_excess = 0.0
    maximum_meltwater_excess = 0.0
    for control in result.controls.values():
        states = control.candidate_states
        minimum_state = min(minimum_state, float(np.min(states)))
        violations += int(np.count_nonzero(states < -tolerance))
        for candidate_index, definition in enumerate(definitions):
            parameter = definition.parameters
            candidate_states = states[:, :, candidate_index]
            soil_excess = candidate_states[:, :, 2] - float(parameter["parFC"])
            meltwater_excess = (
                candidate_states[:, :, 1]
                - float(parameter["parCWH"]) * candidate_states[:, :, 0]
            )
            maximum_soil_excess = max(maximum_soil_excess, float(np.max(soil_excess)))
            maximum_meltwater_excess = max(
                maximum_meltwater_excess, float(np.max(meltwater_excess))
            )
            violations += int(np.count_nonzero(soil_excess > tolerance))
            violations += int(np.count_nonzero(meltwater_excess > tolerance))

    balance_residuals = []
    for origin_row, origin in enumerate(result.origin_indices):
        rain, pet, temperature = forcing[int(origin) + 1]
        for candidate_index, definition in enumerate(definitions):
            balance = hbv_water_balance_residual(
                result.origin_candidate_posterior_states[origin_row, candidate_index],
                rain,
                pet,
                temperature,
                definition.parameters,
            )
            balance_residuals.append(balance["absolute_residual_mm"])
    maximum_balance_residual = float(max(balance_residuals, default=0.0))
    return {
        "passed": bool(violations == 0 and maximum_balance_residual <= 1e-10),
        "physical_boundary_violation_count": violations,
        "minimum_saved_state_value": minimum_state,
        "maximum_soil_capacity_excess_mm": maximum_soil_excess,
        "maximum_meltwater_holding_excess_mm": maximum_meltwater_excess,
        "maximum_deterministic_water_balance_residual_mm": maximum_balance_residual,
        "water_storage_and_routing_memory_summed": False,
    }


def _causal_perturbation_check(forcing, observations, bank, masks, interaction_mode) -> dict:
    short_forcing = np.asarray(forcing[:8], dtype=np.float64)
    original = np.asarray(observations[:8], dtype=np.float64)
    perturbed = original.copy()
    perturbed[1:] += 1000.0
    first = run_state_diagnostic_assimilation(
        short_forcing,
        original,
        bank,
        masks,
        lead_days=(1, 3, 7),
        interaction_mode=interaction_mode,
    )
    second = run_state_diagnostic_assimilation(
        short_forcing,
        perturbed,
        bank,
        masks,
        lead_days=(1, 3, 7),
        interaction_mode=interaction_mode,
    )
    maximum_difference = 0.0
    for control_id in first.controls:
        maximum_difference = max(
            maximum_difference,
            float(
                np.max(
                    np.abs(
                        first.controls[control_id].predictions
                        - second.controls[control_id].predictions
                    )
                )
            ),
        )
    return {
        "passed": maximum_difference == 0.0,
        "future_discharge_perturbation_mm_day": 1000.0,
        "maximum_issued_prediction_difference": maximum_difference,
        "future_discharge_after_origin_read": False,
    }


def _copy_source_snapshot(root: Path, output: Path, source_files: Sequence[Path]) -> dict[str, str]:
    hashes = {}
    for source in sorted({Path(value).resolve() for value in source_files}):
        relative = source.relative_to(root)
        destination = output / "source_snapshot" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        hashes[relative.as_posix()] = sha256_file(source)
    return hashes


def _hash_paths(root: Path, paths: Sequence[Path]) -> dict[str, str]:
    result = {}
    for path in sorted({Path(value).resolve() for value in paths}):
        result[path.relative_to(root).as_posix()] = sha256_file(path)
    return result


def _run_basin(
    root: Path,
    basin_id: str,
    config: Mapping,
    formal_config: Mapping,
    contract_directory: Path,
    formal_result_directory: Path,
    output: Path,
    recorder: ResourceRecorder,
    checkpoint_identity: Mapping[str, str],
    resume_checkpoint_path: Path | None = None,
) -> tuple[list[dict], list[dict], dict]:
    basin_contract = json.loads(
        (contract_directory / "basin_contracts" / f"{basin_id}.json").read_text(
            encoding="utf-8"
        )
    )
    warmup = _load_forcing_only_period(
        root,
        basin_id,
        formal_config,
        formal_config["evaluation_warmup_start"],
        formal_config["evaluation_warmup_end"],
    )
    forcing, observations = _load_complete_period(
        root,
        basin_id,
        formal_config,
        formal_config["evaluation_start"],
        formal_config["evaluation_end"],
    )
    parameter_vectors, process_scales, process_covariances = _method_contract_parts(basin_contract)
    initial_states = {}
    for parameter_id, parameters in parameter_vectors.items():
        _, states = simulate_adapter(
            warmup[:, 0], warmup[:, 1], warmup[:, 2], parameters
        )
        initial_states[parameter_id] = states[-1]
    center_state = initial_states["trained_center"]
    initial_covariance = np.diag(
        (
            float(formal_config["initial_covariance_fraction"])
            * np.maximum(np.abs(center_state), 1.0)
        )
        ** 2
    )
    definitions = build_method_definitions(
        parameter_vectors,
        process_scales,
        process_covariances,
        basin_contract["process_noise"]["selected_process_id"],
    )["joint"]
    bank = build_method_bank(
        candidates=definitions,
        initial_states=initial_states,
        initial_covariance=initial_covariance,
        observation_standard_deviation=basin_contract["observation_noise"][
            "selected_standard_deviation_mm_day"
        ],
        factor_transition_stay_probability=float(
            formal_config["factor_transition_stay_probability"]
        ),
        interaction_mode=formal_config["formal_interaction_mode"],
    )
    masks = _state_update_masks(config)
    causal_check = _causal_perturbation_check(
        forcing,
        observations,
        bank,
        masks,
        formal_config["formal_interaction_mode"],
    )
    if not causal_check["passed"]:
        raise ValueError(f"basin {basin_id} failed the future-discharge perturbation check")
    checkpoint_path = output / "checkpoints" / f"{basin_id}.npz"
    checkpoint_manifest_path = output / "checkpoints" / f"{basin_id}.json"
    resume_checkpoint = None
    if resume_checkpoint_path is not None:
        resume_checkpoint = load_verified_resume_checkpoint(
            Path(resume_checkpoint_path),
            checkpoint_identity,
        )

    interval = int(config["checkpoint"]["interval_completed_origins"])
    if interval <= 0:
        raise ValueError("checkpoint interval must be positive")

    def checkpoint_progress(completed, total, checkpoint):
        saved = False
        if completed % interval == 0 or completed == total:
            save_diagnostic_checkpoint(checkpoint_path, checkpoint, checkpoint_identity)
            _write_json(
                checkpoint_manifest_path,
                {
                    "basin_id": basin_id,
                    "completed_origin_count": completed,
                    "total_origin_count": total,
                    "identity": dict(checkpoint_identity),
                    "checkpoint_sha256": sha256_file(checkpoint_path),
                    "atomic": True,
                },
            )
            saved = True
        try:
            recorder.checkpoint(
                "origin_complete",
                basin_id=basin_id,
                completed=completed,
                total=total,
            )
        except ResourceGateError:
            if not saved:
                save_diagnostic_checkpoint(checkpoint_path, checkpoint, checkpoint_identity)
                _write_json(
                    checkpoint_manifest_path,
                    {
                        "basin_id": basin_id,
                        "completed_origin_count": completed,
                        "total_origin_count": total,
                        "identity": dict(checkpoint_identity),
                        "checkpoint_sha256": sha256_file(checkpoint_path),
                        "atomic": True,
                        "saved_on_resource_gate_failure": True,
                    },
                )
            raise

    result = run_state_diagnostic_assimilation(
        forcing,
        observations,
        bank,
        masks,
        lead_days=tuple(config["lead_days"]),
        interaction_mode=formal_config["formal_interaction_mode"],
        checkpoint_callback=checkpoint_progress,
        resume_checkpoint=resume_checkpoint,
    )
    formal_path = formal_result_directory / "basins" / f"{basin_id}.npz"
    with np.load(formal_path, allow_pickle=False) as loaded:
        formal_arrays = {name: loaded[name].copy() for name in loaded.files}
    replay = _replay_report(result, formal_arrays, config)
    if not replay["passed"]:
        raise ValueError(f"basin {basin_id} failed frozen formal-array replay validation")
    physical_checks = _physical_checks(result, definitions, forcing)
    if not physical_checks["passed"]:
        raise ValueError(f"basin {basin_id} failed physical-state or mass-balance checks")

    arrays = {f"formal__{name}": values for name, values in formal_arrays.items()}
    arrays.update(diagnostic_result_arrays(result))
    arrays["forcing_historical_observed_meteorology"] = forcing
    arrays["observations"] = observations
    arrays["target_observations"] = formal_arrays["target_observations"]
    arrays["state_names"] = np.asarray(STATE_NAMES, dtype="U32")
    arrays["candidate_ids"] = np.asarray(
        [definition.candidate_id for definition in definitions], dtype="U128"
    )
    np.savez_compressed(output / "basins" / f"{basin_id}.npz", **arrays)

    predictions = {
        "open_loop": formal_arrays["open_loop__predictions"],
        **{control_id: control.predictions for control_id, control in result.controls.items()},
    }
    metrics = control_metric_rows(
        basin_id,
        result.lead_days,
        formal_arrays["target_observations"],
        predictions,
    )
    state_summary = _state_summary_rows(basin_id, result, definitions)
    basin_report = {
        "basin_id": basin_id,
        "replay_validation": replay,
        "physical_checks": physical_checks,
        "shared_origin_prior_validation": result.shared_origin_prior_validation,
        "causal_perturbation_check": causal_check,
        "origin_count": len(result.origin_indices),
        "lead_days": result.lead_days.tolist(),
        "historical_meteorology_description": config["future_meteorology_description"],
    }
    _write_json(output / "basin_reports" / f"{basin_id}.json", basin_report)
    return metrics, state_summary, basin_report


def run_experiment(
    repo_root: Path,
    config_path: Path,
    experiment_id: str,
    basin_ids: Sequence[str],
    resume_checkpoint_path: Path | None = None,
) -> dict:
    root = Path(repo_root).resolve()
    config, overlay = load_effective_config(config_path)
    frozen_basins = tuple(str(value).zfill(8) for value in config["frozen_basins"])
    requested = tuple(str(value).zfill(8) for value in basin_ids)
    if not requested or len(requested) != len(set(requested)):
        raise ValueError("requested basins must be nonempty and unique")
    if any(basin_id not in frozen_basins for basin_id in requested):
        raise ValueError("requested basin is outside the frozen sixteen")
    if requested != tuple(value for value in frozen_basins if value in requested):
        raise ValueError("requested basins must retain frozen contract order")
    if len(requested) not in {1, 16}:
        raise ValueError("state-correction runs are limited to one smoke basin or all frozen sixteen")
    if len(requested) == 1 and requested[0] != str(config["smoke_basin"]):
        raise ValueError("the one-basin run must use the preregistered smoke basin")

    results_root = root / config["results_root"]
    output = results_root / experiment_id
    incomplete = results_root / f".{experiment_id}.incomplete"
    failed = results_root / f"{experiment_id}.failed"
    if any(path.exists() for path in (output, incomplete, failed)):
        raise FileExistsError(f"refusing to overwrite state-correction run {experiment_id}")
    registry = RunRegistry(results_root, experiment_id)
    registry.reserve(
        "state_correction_diagnostic",
        basin_count=len(requested),
        config=str(Path(config_path).resolve()),
    )
    recorder = None
    try:
        incomplete.mkdir(parents=True)
        (incomplete / "basins").mkdir()
        (incomplete / "basin_reports").mkdir()
        recorder = ResourceRecorder(
            probe_path=results_root,
            resource_config=config["resource"],
            history_path=incomplete / "resource_history.json",
        )
        run_kind = "smoke" if len(requested) == 1 else "formal"
        recorder.start(
            estimated_peak_gib=config["resource"][f"{run_kind}_estimated_peak_gib"],
            estimated_output_gib=config["resource"][f"{run_kind}_estimated_output_gib"],
            experiment_id=experiment_id,
        )
        contract_directory = (root / config["formal_contract"]["path"]).resolve()
        formal_result_directory = (root / config["formal_result"]["path"]).resolve()
        contract_verification = verify_checksum_package(
            contract_directory,
            config["formal_contract"]["checksums_sha256"],
        )
        result_verification = verify_checksum_package(
            formal_result_directory,
            config["formal_result"]["checksums_sha256"],
        )
        recorder.checkpoint("formal_packages_verified", force=True)
        formal_config = json.loads(
            (contract_directory / "config_snapshot.json").read_text(encoding="utf-8")
        )
        contract_basins = pd.read_csv(
            contract_directory / "basins.csv", dtype={"gauge_id": str}
        )["gauge_id"].str.zfill(8).tolist()
        if tuple(contract_basins) != frozen_basins:
            raise ValueError("frozen basin order differs from the formal contract")

        source_files, input_files = collect_contract_snapshot_files(
            root,
            list(requested),
            formal_config,
            include_evaluation_discharge=True,
        )
        extra_sources = [
            root / "src" / "hbv_multilead_joint_uncertainty" / "state_correction_diagnostic.py",
            root
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "scripts"
            / "run_state_correction_diagnostic.py",
            Path(config_path).resolve(),
            Path(config_path).resolve().parent / str(overlay["inherits"]),
            root / "test" / "test_hbv_state_correction_diagnostic.py",
        ]
        source_hashes = _copy_source_snapshot(root, incomplete, [*source_files, *extra_sources])
        input_hashes = _hash_paths(
            root,
            [
                *input_files,
                contract_directory / "checksums.json",
                formal_result_directory / "checksums.json",
                *(formal_result_directory / "basins" / f"{basin_id}.npz" for basin_id in requested),
            ],
        )
        _write_json(incomplete / "source_checksums.json", source_hashes)
        _write_json(incomplete / "input_checksums.json", input_hashes)
        _write_json(incomplete / "config_snapshot.json", config)
        _write_json(incomplete / "config_overlay_snapshot.json", overlay)
        _write_json(
            incomplete / "formal_package_verification.json",
            {"contract": contract_verification, "result": result_verification},
        )
        checkpoint_identity = {
            "experiment_family": str(config["experiment_family"]),
            "config_sha256": sha256_file(Path(config_path).resolve()),
            "input_sha256": sha256_file(incomplete / "input_checksums.json"),
            "source_sha256": sha256_file(incomplete / "source_checksums.json"),
            "checkpoint_experiment_id": str(experiment_id),
        }
        resume_path = None if resume_checkpoint_path is None else Path(resume_checkpoint_path).resolve()
        if resume_path is not None and resume_path.stem not in requested:
            raise ValueError("resume checkpoint basin is outside the requested frozen basin list")

        metric_rows = []
        state_rows = []
        basin_reports = []
        for basin_index, basin_id in enumerate(requested):
            metrics, states, report = _run_basin(
                root,
                basin_id,
                config,
                formal_config,
                contract_directory,
                formal_result_directory,
                incomplete,
                recorder,
                checkpoint_identity,
                resume_checkpoint_path=(
                    resume_path if resume_path is not None and resume_path.stem == basin_id else None
                ),
            )
            metric_rows.extend(metrics)
            state_rows.extend(states)
            basin_reports.append(report)
            recorder.checkpoint(
                "basin_complete",
                force=True,
                basin_id=basin_id,
                basin_index=basin_index + 1,
                basin_count=len(requested),
            )
        metrics_frame = pd.DataFrame(metric_rows)
        state_frame = pd.DataFrame(state_rows)
        metrics_frame.to_csv(incomplete / "control_metrics.csv", index=False)
        state_frame.to_csv(incomplete / "state_diagnostics.csv", index=False)
        if len(requested) == 16:
            decision = evaluate_continuation_gate(
                metric_rows,
                expected_basin_count=16,
                gate_control_id=config["continuation_gate"]["control_id"],
            )
        else:
            decision = {
                "status": "not_evaluated_on_smoke",
                "recommend_larger_sample": False,
                "run_531_automatically": False,
            }
        _write_json(incomplete / "continuation_decision.json", decision)
        _write_json(
            incomplete / "result_manifest.json",
            {
                "experiment_id": experiment_id,
                "status": "verified",
                "basins": list(requested),
                "basin_count": len(requested),
                "common_origin_count": config["common_origin_count"],
                "lead_days": config["lead_days"],
                "controls": [row["control_id"] for row in config["controls"]],
                "formal_artifacts_modified": False,
                "run_531": False,
                "basin_reports_passed": all(
                    report["replay_validation"]["passed"]
                    and report["physical_checks"]["passed"]
                    and report["causal_perturbation_check"]["passed"]
                    for report in basin_reports
                ),
            },
        )
        recorder.checkpoint("before_output_checksums", force=True)
        stable_output_hashes = {}
        for path in sorted(incomplete.rglob("*")):
            relative = path.relative_to(incomplete).as_posix()
            if path.is_file() and path.name != "checksums.json" and relative != "resource_history.json":
                stable_output_hashes[relative] = sha256_file(path)
        for relative, expected in stable_output_hashes.items():
            if sha256_file(incomplete / relative) != expected:
                raise ValueError(f"new output checksum mismatch: {relative}")
        recorder.finish(experiment_id=experiment_id)
        resource_verification_path = incomplete / "resource_history_verification.json"
        write_resource_history_verification(
            incomplete / "resource_history.json",
            config["resource"],
            resource_verification_path,
        )
        stable_output_hashes["resource_history_verification.json"] = sha256_file(
            resource_verification_path
        )
        finalize_output_checksums(
            incomplete,
            stable_hashes=stable_output_hashes,
            refresh_relatives={"resource_history.json"},
        )
        os.replace(incomplete, output)
        registry.update("verified", output_directory=str(output))
        return {
            "status": "verified",
            "experiment_id": experiment_id,
            "output_directory": str(output),
            "basins": list(requested),
            "continuation_decision": decision,
        }
    except Exception as error:
        if recorder is not None:
            try:
                recorder.abort()
            except Exception:
                pass
        if incomplete.exists():
            _write_json(
                incomplete / "failure.json",
                {
                    "status": "failed",
                    "error_type": type(error).__name__,
                    "message": str(error),
                    "formal_artifacts_modified": False,
                },
            )
            if not failed.exists():
                os.replace(incomplete, failed)
        try:
            registry.update("failed", error_type=type(error).__name__, message=str(error))
        except Exception:
            pass
        raise


def _parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(
            "src/hbv_multilead_joint_uncertainty/configs/state_correction_propagation_v07.json"
        ),
    )
    parser.add_argument("--experiment-id", required=True)
    parser.add_argument("--basins", required=True, help="Comma-separated frozen basin identifiers")
    parser.add_argument("--resume-checkpoint", type=Path, default=None)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = _parse_args(argv)
    root = args.repo_root.resolve()
    config_path = args.config if args.config.is_absolute() else root / args.config
    basin_ids = tuple(value.strip() for value in args.basins.split(",") if value.strip())
    resume_checkpoint = args.resume_checkpoint
    if resume_checkpoint is not None and not resume_checkpoint.is_absolute():
        resume_checkpoint = root / resume_checkpoint
    result = run_experiment(
        root,
        config_path,
        args.experiment_id,
        basin_ids,
        resume_checkpoint_path=resume_checkpoint,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
