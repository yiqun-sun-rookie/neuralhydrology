"""Run the registered H16 long-history generation and contract preflight."""

from __future__ import annotations

import argparse
from dataclasses import fields
import inspect
import json
import math
import os
import platform
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping

import numpy as np
import torch

from hbv_multilead_joint_uncertainty.synthetic_truth import generate_reference_truth

from hbv_history_conditioned_imm.hbv import (
    forecast_global_state_weighted_parameters,
)
from hbv_history_conditioned_imm.long_history import (
    LongHistoryParameterSwitchBatch,
    ObservableAssimilationBatch,
    duration_dependent_switch_hazard,
    duration_distribution_summary,
    generate_long_history_parameter_switch_batch,
    generate_long_history_schedule,
    transition_hazard_output_bounds,
)
from hbv_history_conditioned_imm.network import build_history_features
from hbv_history_conditioned_imm.parameter_switch import (
    audit_parameter_signal,
    build_parameter_candidates,
)
from hbv_history_conditioned_imm.scripts.run_h01_end_to_end_smoke import (
    _git_head,
    _sha256,
    _write_json,
    load_registry_row,
)
from hbv_history_conditioned_imm.scripts.verify_h16_long_history_contract_preflight import (
    verify_h16_result,
)
from hbv_history_conditioned_imm.synthetic import (
    _forcing,
    _random_schedule,
    make_block_seeds,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = (
    PACKAGE_ROOT / "configs/h16_long_history_contract_preflight_v02.json"
)


def load_h16_config(path: str | Path) -> dict[str, Any]:
    """Load and validate the immutable H16 preflight identity."""

    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    required = {
        "experiment_id",
        "result_relative_path",
        "source_h05_config",
        "legacy_h05_daily_arrays",
        "base_parameters",
        "parameter_candidates",
        "data",
        "duration_hazard",
        "seeds",
        "filter",
        "network_output_contract",
        "future_training_contract",
        "forecast",
        "execution",
        "capability_gates",
        "required_result_files",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"H16 configuration is missing fields: {sorted(missing)}")
    if config["experiment_id"] not in {
        "h16_long_history_contract_preflight_v01",
        "h16_long_history_contract_preflight_v02",
    }:
        raise ValueError("unexpected H16 experiment identifier")
    if config["execution"] != {
        "training_started": False,
        "checkpoint_created": False,
        "optimizer_created": False,
    }:
        raise ValueError("H16 must remain a data-only preflight")
    required_files = tuple(str(name) for name in config["required_result_files"])
    if not required_files or len(required_files) != len(set(required_files)):
        raise ValueError("required H16 result files must be nonempty and unique")
    if any(name.endswith(".pt") or "checkpoint" in name for name in required_files):
        raise ValueError("H16 must not declare a checkpoint artifact")
    return config


def _parameter_candidates(
    config: Mapping[str, Any],
) -> dict[str, dict[str, float]]:
    candidates = build_parameter_candidates(
        config["base_parameters"], config["parameter_candidates"]["values"]
    )
    if tuple(candidates) != tuple(config["parameter_candidates"]["ids"]):
        raise ValueError("H16 candidate identifiers differ from implementation order")
    return candidates


def _process_state_index(config: Mapping[str, Any]) -> int:
    name = str(config["data"]["fixed_process_state_name"])
    indices = {"SUZ": 3, "SLZ": 4}
    if name not in indices:
        raise ValueError("H16 process state must be SUZ or SLZ")
    return indices[name]


def _generate_splits(
    config: Mapping[str, Any],
    candidates: Mapping[str, Mapping[str, float]],
) -> dict[str, LongHistoryParameterSwitchBatch]:
    data = config["data"]
    seeds = config["seeds"]
    definitions = (
        ("training", int(data["training_blocks"]), int(seeds["training_split_offset"])),
        (
            "validation",
            int(data["validation_blocks"]),
            int(seeds["validation_split_offset"]),
        ),
        ("test", int(data["test_blocks"]), int(seeds["test_split_offset"])),
    )
    result: dict[str, LongHistoryParameterSwitchBatch] = {}
    for split, count, offset in definitions:
        specifications = make_block_seeds(
            split=split,
            count=count,
            forcing_prefix=int(seeds["forcing_prefix"]),
            process_prefix=int(seeds["process_prefix"]),
            observation_prefix=int(seeds["observation_prefix"]),
            schedule_prefix=int(seeds["schedule_prefix"]),
            split_offset=offset,
        )
        result[split] = generate_long_history_parameter_switch_batch(
            block_seeds=specifications,
            parameter_candidates=candidates,
            warmup_parameter_id=str(data["warmup_parameter_id"]),
            assimilation_days=int(data["assimilation_days"]),
            maximum_forecast_lead=int(data["maximum_forecast_lead"]),
            warmup_days=int(data["warmup_days"]),
            hazard=config["duration_hazard"],
            process_standard_deviation=float(
                data["fixed_process_standard_deviation"]
            ),
            observation_standard_deviation=float(
                data["observation_standard_deviation"]
            ),
            process_state_index=_process_state_index(config),
            require_zero_projection=bool(data["require_zero_projection"]),
            initial_covariance_fraction=float(data["initial_covariance_fraction"]),
            maximum_process_resamples=int(data["maximum_process_resamples"]),
        )
    return result


def _event_coverage_audit(
    config: Mapping[str, Any],
    batches: Mapping[str, LongHistoryParameterSwitchBatch],
) -> dict[str, Any]:
    identifiers = tuple(config["parameter_candidates"]["ids"])
    directed = {
        f"{identifiers[source]}->{identifiers[destination]}": 0
        for source in range(3)
        for destination in range(3)
        if source != destination
    }
    split_counts: dict[str, dict[str, Any]] = {}
    total_events = 0
    maximum_row_sum_error = 0.0
    schedules_reproducible = True
    assimilation_days = int(config["data"]["assimilation_days"])
    total_days = assimilation_days + int(config["data"]["maximum_forecast_lead"])
    for split, batch in batches.items():
        split_directed = {name: 0 for name in directed}
        split_events = int(
            torch.count_nonzero(batch.switch_event_mask[:, :assimilation_days])
        )
        total_events += split_events
        for block in range(len(batch.block_ids)):
            for day in torch.nonzero(
                batch.switch_event_mask[block, :assimilation_days], as_tuple=False
            ).flatten():
                day_index = int(day)
                source = int(batch.active_source_indices[block, day_index])
                destination = int(batch.true_parameter_indices[block, day_index])
                name = f"{identifiers[source]}->{identifiers[destination]}"
                directed[name] += 1
                split_directed[name] += 1
            repeated = generate_long_history_schedule(
                seed=batch.block_seeds[block].schedule_seed,
                total_days=total_days,
                hazard=config["duration_hazard"],
            )
            schedules_reproducible = schedules_reproducible and all(
                np.array_equal(
                    repeated_value,
                    getattr(batch, batch_name)[block].detach().cpu().numpy(),
                )
                for repeated_value, batch_name in (
                    (repeated.mode_indices, "true_parameter_indices"),
                    (repeated.active_source_indices, "active_source_indices"),
                    (
                        repeated.regime_age_before_transition,
                        "regime_age_before_transition",
                    ),
                    (
                        repeated.oracle_active_row_probabilities,
                        "oracle_active_row_probabilities",
                    ),
                    (
                        repeated.transition_evaluation_mask,
                        "transition_evaluation_mask",
                    ),
                    (repeated.switch_event_mask, "switch_event_mask"),
                )
            )
        evaluated_rows = batch.oracle_active_row_probabilities[
            batch.transition_evaluation_mask
        ]
        maximum_row_sum_error = max(
            maximum_row_sum_error,
            float(torch.max(torch.abs(evaluated_rows.sum(dim=-1) - 1.0))),
        )
        split_counts[split] = {
            "block_count": len(batch.block_ids),
            "switch_events": split_events,
            "directed_transition_counts": split_directed,
        }
    return {
        "assimilation_days_per_block": assimilation_days,
        "total_switch_events": total_events,
        "directed_transition_counts": directed,
        "minimum_directed_transition_count": min(directed.values()),
        "split_counts": split_counts,
        "maximum_oracle_active_row_sum_error": maximum_row_sum_error,
        "schedules_reproducible": bool(schedules_reproducible),
    }


def _initial_covariance(state: np.ndarray, fraction: float) -> np.ndarray:
    scales = np.maximum(np.abs(np.asarray(state, dtype=np.float64)), 1.0)
    return np.diag(np.square(float(fraction) * scales))


def _initialization_audit(
    config: Mapping[str, Any],
    batches: Mapping[str, LongHistoryParameterSwitchBatch],
    candidates: Mapping[str, Mapping[str, float]],
) -> tuple[dict[str, Any], dict[str, np.ndarray]]:
    data = config["data"]
    total_days = int(data["assimilation_days"]) + int(
        data["maximum_forecast_lead"]
    )
    reference_states: list[np.ndarray] = []
    counterfactual_states: list[np.ndarray] = []
    reference_covariances: list[np.ndarray] = []
    counterfactual_covariances: list[np.ndarray] = []
    reference_modes: list[int] = []
    counterfactual_modes: list[int] = []
    reference_schedule_seeds: list[int] = []
    counterfactual_schedule_seeds: list[int] = []
    warmup_parameters = candidates[str(data["warmup_parameter_id"])]
    for split, batch in batches.items():
        specification = batch.block_seeds[0]
        reference_mode = int(batch.true_parameter_indices[0, 0])
        counter_seed = int(specification.schedule_seed) + 1
        while True:
            counter_schedule = generate_long_history_schedule(
                seed=counter_seed,
                total_days=total_days,
                hazard=config["duration_hazard"],
            )
            if int(counter_schedule.mode_indices[0]) != reference_mode:
                break
            counter_seed += 1
        complete_forcing = _forcing(
            specification.forcing_seed, int(data["warmup_days"]) + total_days
        )
        independently_recomputed = generate_reference_truth(
            complete_forcing[: int(data["warmup_days"])], warmup_parameters
        ).states[-1]
        reference_state = batch.initial_states[0].detach().cpu().numpy()
        counterfactual_state = generate_reference_truth(
            complete_forcing[: int(data["warmup_days"])], warmup_parameters
        ).states[-1]
        reference_covariance = batch.initial_covariances[0].detach().cpu().numpy()
        counterfactual_covariance = _initial_covariance(
            counterfactual_state, float(data["initial_covariance_fraction"])
        )
        if not np.array_equal(reference_state, independently_recomputed):
            raise ValueError(f"{split} initial state does not match central warmup")
        reference_states.append(reference_state)
        counterfactual_states.append(counterfactual_state)
        reference_covariances.append(reference_covariance)
        counterfactual_covariances.append(counterfactual_covariance)
        reference_modes.append(reference_mode)
        counterfactual_modes.append(int(counter_schedule.mode_indices[0]))
        reference_schedule_seeds.append(int(specification.schedule_seed))
        counterfactual_schedule_seeds.append(counter_seed)
    state_values = np.stack(reference_states)
    counter_state_values = np.stack(counterfactual_states)
    covariance_values = np.stack(reference_covariances)
    counter_covariance_values = np.stack(counterfactual_covariances)
    state_difference = float(np.max(np.abs(state_values - counter_state_values)))
    covariance_difference = float(
        np.max(np.abs(covariance_values - counter_covariance_values))
    )
    audit = {
        "warmup_parameter_id": str(data["warmup_parameter_id"]),
        "warmup_depends_on_schedule_seed": False,
        "counterfactual_pair_count": len(reference_states),
        "counterfactual_first_modes_all_differ": bool(
            np.all(np.asarray(reference_modes) != np.asarray(counterfactual_modes))
        ),
        "maximum_initial_state_counterfactual_difference": state_difference,
        "maximum_initial_covariance_counterfactual_difference": covariance_difference,
        "schedule_conditioned_initialization_channel_removed_by_construction": (
            state_difference == 0.0 and covariance_difference == 0.0
        ),
        "reference_schedule_seeds": reference_schedule_seeds,
        "counterfactual_schedule_seeds": counterfactual_schedule_seeds,
    }
    arrays = {
        "initialization_reference_states": state_values,
        "initialization_counterfactual_states": counter_state_values,
        "initialization_reference_covariances": covariance_values,
        "initialization_counterfactual_covariances": counter_covariance_values,
        "initialization_reference_first_modes": np.asarray(
            reference_modes, dtype=np.int64
        ),
        "initialization_counterfactual_first_modes": np.asarray(
            counterfactual_modes, dtype=np.int64
        ),
    }
    return audit, arrays


def _legacy_initialization_channel_audit(
    config: Mapping[str, Any], *, project_root: Path
) -> dict[str, Any]:
    h05_path = project_root / str(config["source_h05_config"]["path"])
    h05 = json.loads(h05_path.read_text("utf-8"))
    arrays_path = project_root / str(config["legacy_h05_daily_arrays"]["path"])
    saved = np.load(arrays_path, allow_pickle=False)
    truth_modes = np.asarray(saved["truth_parameter_indices"], dtype=np.int64)
    transition_day_zero = np.asarray(
        saved["history_conditioned_transition_matrices"][:, 0], dtype=np.float64
    )
    posterior_day_zero = np.asarray(
        saved["history_conditioned_posterior_probabilities"][:, 0],
        dtype=np.float64,
    )
    h05_candidates = build_parameter_candidates(
        h05["base_parameters"], h05["parameter_candidates"]["values"]
    )
    identifiers = tuple(h05_candidates)
    data = h05["data"]
    seeds = h05["seeds"]
    test_seeds = make_block_seeds(
        split="test",
        count=int(data["test_blocks"]),
        forcing_prefix=int(seeds["forcing_prefix"]),
        process_prefix=int(seeds["process_prefix"]),
        observation_prefix=int(seeds["observation_prefix"]),
        schedule_prefix=int(seeds["schedule_prefix"]),
        split_offset=int(seeds["test_split_offset"]),
    )
    total_days = int(data["assimilation_days"]) + int(
        data["maximum_forecast_lead"]
    )
    maximum_difference = 0.0
    noncentral_count = 0
    schedule_matches_saved = True
    central_identifier = "calibrated_recession"
    for block, specification in enumerate(test_seeds):
        schedule, _ = _random_schedule(
            seed=specification.schedule_seed,
            assimilation_days=int(data["assimilation_days"]),
            total_days=total_days,
            minimum_duration=int(data["minimum_regime_duration_days"]),
            maximum_duration=int(data["maximum_regime_duration_days"]),
        )
        first_mode = int(schedule[0])
        schedule_matches_saved = schedule_matches_saved and first_mode == int(
            truth_modes[block, 0]
        )
        complete_forcing = _forcing(
            specification.forcing_seed, int(data["warmup_days"]) + total_days
        )
        legacy_state = generate_reference_truth(
            complete_forcing[: int(data["warmup_days"])],
            h05_candidates[identifiers[first_mode]],
        ).states[-1]
        central_state = generate_reference_truth(
            complete_forcing[: int(data["warmup_days"])],
            h05_candidates[central_identifier],
        ).states[-1]
        maximum_difference = max(
            maximum_difference, float(np.max(np.abs(legacy_state - central_state)))
        )
        noncentral_count += int(identifiers[first_mode] != central_identifier)

    uniform = np.full((len(test_seeds), 3), 1.0 / 3.0, dtype=np.float64)
    transition_prior = np.einsum("bi,bij->bj", uniform, transition_day_zero)
    labels = truth_modes[:, 0]
    prior_accuracy = float(np.mean(transition_prior.argmax(axis=-1) == labels))
    posterior_accuracy = float(np.mean(posterior_day_zero.argmax(axis=-1) == labels))
    majority_accuracy = float(np.max(np.bincount(labels, minlength=3)) / len(labels))
    coordinate_range = float(
        np.max(np.ptp(transition_day_zero.reshape(len(labels), -1), axis=0))
    )
    construction_dependency = maximum_difference > 0.0 and noncentral_count > 0
    leakage_established = bool(
        construction_dependency
        and coordinate_range > 0.0
        and prior_accuracy > majority_accuracy
    )
    return {
        "legacy_experiment_id": h05["experiment_id"],
        "evaluation_block_count": len(labels),
        "legacy_initial_states_saved_in_daily_arrays": False,
        "legacy_schedule_first_modes_match_saved_truth": bool(schedule_matches_saved),
        "noncentral_first_mode_block_count": noncentral_count,
        "maximum_mode_conditioned_vs_central_initial_state_difference": maximum_difference,
        "legacy_initialization_depends_on_first_true_mode": construction_dependency,
        "maximum_day_0_transition_coordinate_range": coordinate_range,
        "trained_history_network_day_0_prior_top_label_accuracy": prior_accuracy,
        "trained_history_network_day_0_posterior_top_label_accuracy": posterior_accuracy,
        "majority_class_accuracy": majority_accuracy,
        "above_majority_day_0_prior_label_identification": prior_accuracy
        > majority_accuracy,
        "legacy_initial_state_leakage_established": leakage_established,
        "conclusion": (
            "not established: construction depends on the first mode, but the frozen "
            "trained history network does not identify that label above the balanced "
            "majority baseline from its day-0 transition prior"
            if not leakage_established
            else "established under the preregistered construction-and-identification rule"
        ),
    }


def _interface_audit(config: Mapping[str, Any]) -> dict[str, Any]:
    observable_names = [field.name for field in fields(ObservableAssimilationBatch)]
    forbidden = [
        "truth_states",
        "truth_discharge",
        "true_parameter_indices",
        "oracle_active_row_probabilities",
        "active_source_indices",
        "regime_age_before_transition",
        "switch_event_mask",
        "block_ids",
        "block_seeds",
    ]
    overlap = sorted(set(observable_names) & set(forbidden))
    feature_arguments = list(inspect.signature(build_history_features).parameters)
    current_observation_input = any(
        "observation" in name or "innovation" in name for name in feature_arguments
    )
    return {
        "observable_field_names": observable_names,
        "forbidden_truth_fields": forbidden,
        "forbidden_observable_truth_fields": overlap,
        "forbidden_observable_truth_field_count": len(overlap),
        "transition_feature_builder_arguments": feature_arguments,
        "current_observation_is_transition_input": current_observation_input,
        "current_innovation_is_transition_input": current_observation_input,
        "block_identifiers_available": "block_ids" in observable_names,
        "random_seeds_available": "block_seeds" in observable_names,
        "transition_day_t_information_cutoff": config["future_training_contract"][
            "transition_day_t_information_cutoff"
        ],
        "strict_observation_only_interface_passed": (
            not overlap
            and not current_observation_input
            and config["future_training_contract"]["true_labels_available"] is False
            and config["future_training_contract"].get(
                "block_identifiers_available", False
            )
            is False
            and config["future_training_contract"].get(
                "random_seeds_available", False
            )
            is False
        ),
    }


def _forecast_contract_audit(config: Mapping[str, Any]) -> dict[str, Any]:
    forecast = config["forecast"]
    signature = list(
        inspect.signature(forecast_global_state_weighted_parameters).parameters
    )
    passed = (
        forecast["origin_state"]
        == "one posterior-probability-weighted global posterior fifteen-state mean"
        and forecast["parameter_readout"]
        == "one posterior-probability-weighted parameter vector frozen at the forecast origin"
        and forecast["candidate_trajectories_used"] is False
        and forecast["future_observations_used"] is False
        and signature
        == [
            "initial_state",
            "future_forcing",
            "candidate_parameters",
            "posterior_probabilities",
            "leads",
        ]
    )
    return {
        **dict(forecast),
        "implementation": (
            "hbv_history_conditioned_imm.hbv."
            "forecast_global_state_weighted_parameters"
        ),
        "implementation_arguments": signature,
        "primary_readout_contract_passed": passed,
    }


def _concatenated_arrays(
    batches: Mapping[str, LongHistoryParameterSwitchBatch],
    initialization_arrays: Mapping[str, np.ndarray],
) -> dict[str, np.ndarray]:
    ordered = tuple(batches.items())

    def concatenate(name: str) -> np.ndarray:
        return torch.cat(
            [getattr(batch, name) for _, batch in ordered], dim=0
        ).detach().cpu().numpy()

    values = {
        name: concatenate(name)
        for name in (
            "forcing",
            "observations",
            "truth_states",
            "truth_discharge",
            "true_parameter_indices",
            "active_source_indices",
            "regime_age_before_transition",
            "oracle_active_row_probabilities",
            "transition_evaluation_mask",
            "switch_event_mask",
            "projection_adjustments",
            "process_perturbations",
            "initial_states",
            "initial_covariances",
        )
    }
    values["split_labels"] = np.asarray(
        [split for split, batch in ordered for _ in batch.block_ids], dtype=np.str_
    )
    values["block_ids"] = np.asarray(
        [identifier for _, batch in ordered for identifier in batch.block_ids],
        dtype=np.str_,
    )
    values["block_seeds"] = np.asarray(
        [
            specification.all_seeds
            for _, batch in ordered
            for specification in batch.block_seeds
        ],
        dtype=np.int64,
    )
    values["accepted_process_seeds"] = np.asarray(
        [seed for _, batch in ordered for seed in batch.accepted_process_seeds],
        dtype=np.int64,
    )
    values["rejected_process_seeds"] = np.asarray(
        [seed for _, batch in ordered for seed in batch.rejected_process_seeds],
        dtype=np.int64,
    )
    values["parameter_ids"] = np.asarray(
        next(iter(batches.values())).parameter_ids, dtype=np.str_
    )
    values.update(initialization_arrays)
    return values


def _write_arrays(path: Path, values: Mapping[str, np.ndarray]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("wb") as handle:
        np.savez_compressed(handle, **values)
    temporary.replace(path)


def _all_finite(value: Any) -> bool:
    if isinstance(value, Mapping):
        return all(_all_finite(item) for item in value.values())
    if isinstance(value, (list, tuple)):
        return all(_all_finite(item) for item in value)
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return True
    if isinstance(value, (int, float)):
        return math.isfinite(float(value))
    return True


def run_long_history_contract_preflight(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    result_directory_override: str | Path | None = None,
) -> Path:
    """Generate, gate, independently verify, and atomically publish H16."""

    root = Path(project_root).resolve()
    final_directory = (
        Path(result_directory_override).resolve()
        if result_directory_override is not None
        else (root / str(config["result_relative_path"])).resolve()
    )
    if final_directory.exists():
        raise FileExistsError(f"result directory already exists: {final_directory}")
    final_directory.parent.mkdir(parents=True, exist_ok=True)
    registry_row = load_registry_row(str(config["experiment_id"]))
    if registry_row["run_dir"] != str(config["result_relative_path"]):
        raise ValueError("H16 registry and config output roots differ")
    for source_name in ("source_h05_config", "legacy_h05_daily_arrays"):
        source = (root / str(config[source_name]["path"])).resolve()
        if _sha256(source) != str(config[source_name]["sha256"]):
            raise ValueError(f"H16 source hash mismatch: {source_name}")

    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{config['experiment_id']}.staging-",
            dir=final_directory.parent,
        )
    )
    try:
        candidates = _parameter_candidates(config)
        batches = _generate_splits(config, candidates)
        hazard_audit = duration_distribution_summary(config["duration_hazard"])
        hazard_audit["anchor_hazards"] = {
            str(age): duration_dependent_switch_hazard(age, config["duration_hazard"])
            for age in (1, 29, 30, 40, 50, 51)
        }
        configured_stay = float(config["filter"]["base_transition_stay_probability"])
        hazard_audit["configured_base_stay_probability"] = configured_stay
        hazard_audit["base_stay_probability_absolute_error"] = abs(
            configured_stay - float(hazard_audit["long_run_stay_probability"])
        )

        event_audit = _event_coverage_audit(config, batches)
        bounds = transition_hazard_output_bounds(
            configured_stay,
            float(config["network_output_contract"]["maximum_logit_correction"]),
        )
        truth_minimum = float(
            config["network_output_contract"]["truth_total_hazard_minimum"]
        )
        truth_maximum = float(
            config["network_output_contract"]["truth_total_hazard_maximum"]
        )
        lower_margin = truth_minimum - bounds["minimum_total_switch_hazard"]
        upper_margin = bounds["maximum_total_switch_hazard"] - truth_maximum
        probability_audit = {
            **bounds,
            "truth_total_switch_hazard_minimum": truth_minimum,
            "truth_total_switch_hazard_maximum": truth_maximum,
            "lower_range_margin": lower_margin,
            "upper_range_margin": upper_margin,
            "minimum_range_margin": min(lower_margin, upper_margin),
            "truth_hazard_inside_output_range": lower_margin >= 0.0
            and upper_margin >= 0.0,
            "output_layer_mathematical_reachability_established": True,
            "recurrent_history_capacity_established": False,
            "claim_boundary": config["network_output_contract"]["claim"],
        }

        initialization_audit, initialization_arrays = _initialization_audit(
            config, batches, candidates
        )
        legacy_audit = _legacy_initialization_channel_audit(
            config, project_root=root
        )
        signal_audit = audit_parameter_signal(
            batches["training"],
            candidates,
            observation_standard_deviation=float(
                config["data"]["observation_standard_deviation"]
            ),
            leads=tuple(int(value) for value in config["forecast"]["leads_days"]),
        )
        maximum_projection = max(
            float(batch.projection_adjustments.abs().max())
            for batch in batches.values()
        )
        signal_audit["maximum_absolute_projection_adjustment_all_splits"] = (
            maximum_projection
        )
        interface_audit = _interface_audit(config)
        forecast_audit = _forecast_contract_audit(config)
        thresholds = config["capability_gates"]
        minimum_directed = int(event_audit["minimum_directed_transition_count"])
        gates = {
            "duration_law_matches_fixed_base_probability": {
                "value": float(
                    hazard_audit["base_stay_probability_absolute_error"]
                ),
                "threshold_maximum": 1e-15,
                "passed": float(
                    hazard_audit["base_stay_probability_absolute_error"]
                )
                <= 1e-15,
            },
            "total_switch_event_coverage": {
                "value": int(event_audit["total_switch_events"]),
                "threshold_minimum": int(thresholds["minimum_total_switch_events"]),
                "passed": int(event_audit["total_switch_events"])
                >= int(thresholds["minimum_total_switch_events"]),
            },
            "each_directed_transition_event_coverage": {
                "value": minimum_directed,
                "threshold_minimum": int(
                    thresholds["minimum_each_directed_transition_events"]
                ),
                "passed": minimum_directed
                >= int(thresholds["minimum_each_directed_transition_events"]),
            },
            "oracle_active_row_legality": {
                "value": float(
                    event_audit["maximum_oracle_active_row_sum_error"]
                ),
                "threshold_maximum": float(
                    thresholds["maximum_oracle_active_row_sum_error"]
                ),
                "passed": float(
                    event_audit["maximum_oracle_active_row_sum_error"]
                )
                <= float(thresholds["maximum_oracle_active_row_sum_error"]),
            },
            "schedule_reproducibility": {
                "value": bool(event_audit["schedules_reproducible"]),
                "passed": bool(event_audit["schedules_reproducible"]),
            },
            "output_probability_range_contains_truth": {
                "value": float(probability_audit["minimum_range_margin"]),
                "threshold_minimum": float(
                    thresholds["minimum_output_probability_range_margin"]
                ),
                "passed": float(probability_audit["minimum_range_margin"])
                >= float(thresholds["minimum_output_probability_range_margin"]),
            },
            "schedule_independent_initial_state": {
                "value": float(
                    initialization_audit[
                        "maximum_initial_state_counterfactual_difference"
                    ]
                ),
                "threshold_maximum": float(
                    thresholds["maximum_initial_state_counterfactual_difference"]
                ),
                "passed": float(
                    initialization_audit[
                        "maximum_initial_state_counterfactual_difference"
                    ]
                )
                <= float(
                    thresholds["maximum_initial_state_counterfactual_difference"]
                ),
            },
            "schedule_independent_initial_covariance": {
                "value": float(
                    initialization_audit[
                        "maximum_initial_covariance_counterfactual_difference"
                    ]
                ),
                "threshold_maximum": float(
                    thresholds[
                        "maximum_initial_covariance_counterfactual_difference"
                    ]
                ),
                "passed": float(
                    initialization_audit[
                        "maximum_initial_covariance_counterfactual_difference"
                    ]
                )
                <= float(
                    thresholds[
                        "maximum_initial_covariance_counterfactual_difference"
                    ]
                ),
            },
            "zero_physical_projection": {
                "value": maximum_projection,
                "threshold_maximum": float(
                    thresholds["maximum_absolute_projection_adjustment"]
                ),
                "passed": maximum_projection
                <= float(thresholds["maximum_absolute_projection_adjustment"]),
            },
            "filter_free_parameter_signal": {
                "value": float(
                    signal_audit["minimum_pairwise_rmse_to_observation_sd_ratio"]
                ),
                "threshold_minimum": float(
                    thresholds["minimum_pairwise_rmse_to_observation_sd_ratio"]
                ),
                "passed": float(
                    signal_audit["minimum_pairwise_rmse_to_observation_sd_ratio"]
                )
                >= float(thresholds["minimum_pairwise_rmse_to_observation_sd_ratio"]),
            },
            "observation_only_future_training_interface": {
                "value": int(
                    interface_audit["forbidden_observable_truth_field_count"]
                ),
                "threshold_maximum": int(
                    thresholds["forbidden_observable_truth_field_count"]
                ),
                "passed": bool(
                    interface_audit["strict_observation_only_interface_passed"]
                )
                and int(interface_audit["forbidden_observable_truth_field_count"])
                <= int(thresholds["forbidden_observable_truth_field_count"]),
            },
            "single_global_state_forecast_readout": {
                "value": bool(forecast_audit["primary_readout_contract_passed"]),
                "passed": bool(forecast_audit["primary_readout_contract_passed"]),
            },
            "data_only_execution": {
                "value": dict(config["execution"]),
                "passed": config["execution"]
                == {
                    "training_started": False,
                    "checkpoint_created": False,
                    "optimizer_created": False,
                },
            },
        }
        preflight_passed = all(bool(values["passed"]) for values in gates.values())
        report = {
            "experiment_id": config["experiment_id"],
            "preflight_passed": preflight_passed,
            "decision": (
                "GO_FOR_SEPARATELY_AUTHORIZED_H17_IMPLEMENTATION"
                if preflight_passed
                else "HOLD_BEFORE_H17_IMPLEMENTATION"
            ),
            "gates": gates,
            "execution": dict(config["execution"]),
            "legacy_initial_state_leakage_established": bool(
                legacy_audit["legacy_initial_state_leakage_established"]
            ),
            "learned_probability_recovery_established": False,
            "recurrent_history_capacity_established": False,
            "mode_identification_established": False,
            "state_superiority_established": False,
            "forecast_value_established": False,
            "real_basin_claim_established": False,
            "h17_registered_or_run": False,
            "h18_registered_or_run": False,
        }
        if not all(
            _all_finite(value)
            for value in (
                hazard_audit,
                event_audit,
                probability_audit,
                initialization_audit,
                legacy_audit,
                signal_audit,
                interface_audit,
                forecast_audit,
                report,
            )
        ):
            raise ValueError("H16 preflight contains non-finite values")

        _write_json(staging / "config_snapshot.json", dict(config))
        _write_json(staging / "registry_entry.json", registry_row)
        _write_arrays(
            staging / "preflight_arrays.npz",
            _concatenated_arrays(batches, initialization_arrays),
        )
        _write_json(staging / "hazard_audit.json", hazard_audit)
        _write_json(staging / "event_coverage_audit.json", event_audit)
        _write_json(staging / "probability_range_audit.json", probability_audit)
        _write_json(staging / "initialization_audit.json", initialization_audit)
        _write_json(
            staging / "legacy_initialization_channel_audit.json", legacy_audit
        )
        _write_json(staging / "signal_audit.json", signal_audit)
        _write_json(staging / "interface_audit.json", interface_audit)
        _write_json(staging / "forecast_contract_audit.json", forecast_audit)
        _write_json(staging / "preflight_report.json", report)
        _write_json(
            staging / "environment.json",
            {
                "python": sys.version,
                "platform": platform.platform(),
                "torch": torch.__version__,
                "numpy": np.__version__,
                "git_head": _git_head(root),
                "process_id": os.getpid(),
            },
        )

        required = set(str(name) for name in config["required_result_files"])
        expected_before_verification = required - {
            "independent_verification.json",
            "checksums.json",
        }
        found_before_verification = {
            path.name for path in staging.iterdir() if path.is_file()
        }
        if found_before_verification != expected_before_verification:
            raise RuntimeError("H16 staging output is incomplete before verification")
        independent = verify_h16_result(staging, verify_checksums=False)
        if independent["verified"] is not True:
            raise ValueError("H16 independent staging verification failed")
        _write_json(staging / "independent_verification.json", independent)
        checksums = {
            name: _sha256(staging / name)
            for name in sorted(required - {"checksums.json"})
        }
        _write_json(staging / "checksums.json", checksums)
        found = {path.name for path in staging.iterdir() if path.is_file()}
        if found != required:
            raise RuntimeError("H16 staging output does not match the required file set")
        published_verification = verify_h16_result(staging)
        if published_verification["verified"] is not True:
            raise ValueError("H16 checksum verification failed before publication")
        staging.replace(final_directory)
        return final_directory
    except Exception:
        if staging.exists() and staging.parent == final_directory.parent:
            shutil.rmtree(staging)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PACKAGE_ROOT.parents[1]))
    arguments = parser.parse_args()
    config = load_h16_config(arguments.config)
    output = run_long_history_contract_preflight(
        config, project_root=arguments.project_root
    )
    print(output)


if __name__ == "__main__":
    main()
