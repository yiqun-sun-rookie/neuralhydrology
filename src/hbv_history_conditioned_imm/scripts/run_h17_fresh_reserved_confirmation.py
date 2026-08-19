"""Run the single-use H17F fresh-reserve confirmation."""

from __future__ import annotations

import argparse
import csv
from dataclasses import replace
from datetime import datetime, timezone
import hashlib
import io
import json
import math
import os
import platform
import shutil
import subprocess
import sys
import traceback
import zipfile
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

import numpy as np
import torch

from hbv_history_conditioned_imm.causal_duration import (
    CausalSemiMarkovTransitionModule,
)
from hbv_history_conditioned_imm.long_history import (
    LongHistoryParameterSwitchBatch,
    ObservableAssimilationBatch,
    generate_long_history_parameter_switch_batch,
    generate_long_history_schedule,
)
from hbv_history_conditioned_imm.scripts.run_h17_supervised_probability_upper_bound import (
    H17DataSplit,
    _base_transition,
    _causality_audit,
    _estimator,
    _parameter_candidates,
    _static_network,
)
from hbv_history_conditioned_imm.supervised_probability import (
    ActiveRowSupervision,
    ProbabilityRolloutResult,
    rollout_semi_markov_probability,
    rollout_static_probability,
)
from hbv_history_conditioned_imm.synthetic import BlockSeeds


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = PACKAGE_ROOT / "configs" / (
    "h17r_monotone_piecewise_age_risk_learning_rate_0p075_"
    "fresh_reserved_confirmation_v01.json"
)
DEFAULT_REGISTRY_PATH = PACKAGE_ROOT / "configs/experiment_registry.csv"
EXPECTED_EXPERIMENT_ID = (
    "h17r_monotone_piecewise_age_risk_learning_rate_0p075_"
    "fresh_reserved_confirmation_v01"
)
RESERVE_OPEN_TOMBSTONE_DIRECTORY = Path("src/hbv_history_conditioned_imm/configs")
TENSOR_BATCH_FIELDS = (
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


class NamespacedProcessExhaustion(RuntimeError):
    """All frozen process seeds failed for one already opened reserve block."""

    def __init__(self, requested: BlockSeeds, rejected: Sequence[int]) -> None:
        super().__init__(
            f"no namespaced admissible process seed for {requested.block_id}"
        )
        self.requested = requested
        self.rejected = tuple(int(value) for value in rejected)


class ProcessLayerExhaustion(RuntimeError):
    """Carry a complete frozen attempt trail into the terminal HOLD package."""

    def __init__(
        self,
        *,
        layer: str,
        rank: int,
        schedule_ordinal: int,
        failure: NamespacedProcessExhaustion,
        completed_attempts: Sequence[Mapping[str, Any]],
    ) -> None:
        super().__init__(str(failure))
        self.layer = str(layer)
        self.rank = int(rank)
        self.schedule_ordinal = int(schedule_ordinal)
        self.requested = failure.requested
        self.rejected = failure.rejected
        self.completed_attempts = tuple(dict(value) for value in completed_attempts)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _lexists(path: Path) -> bool:
    return os.path.lexists(os.fspath(path))


def _write_json(path: Path, values: Mapping[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(_json_bytes(values))
    temporary.replace(path)


def _json_bytes(values: Mapping[str, Any]) -> bytes:
    return (
        json.dumps(values, indent=2, sort_keys=True, allow_nan=False) + "\n"
    ).encode("utf-8")


def _mapping_sha256(values: Mapping[str, Any]) -> str:
    data = json.dumps(values, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def _require_approved_preregistration_sha256(value: str) -> str:
    normalized = str(value).strip().lower()
    if len(normalized) != 64 or any(
        character not in "0123456789abcdef" for character in normalized
    ):
        raise ValueError("an exact externally approved preregistration SHA-256 is required")
    return normalized


def _write_npz(path: Path, values: Mapping[str, np.ndarray]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("wb") as handle:
        np.savez_compressed(handle, **values)
    temporary.replace(path)


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_h17r_config(path: str | Path = DEFAULT_CONFIG_PATH) -> dict[str, Any]:
    config = _read_json(Path(path))
    required = {
        "experiment_id",
        "status",
        "result_relative_path",
        "repository_contract",
        "eligibility_contract",
        "source_h16",
        "source_h17p",
        "source_h17f",
        "static_reference",
        "base_parameters",
        "parameter_candidates",
        "data",
        "duration_hazard",
        "seed_namespace",
        "coverage_selection",
        "coverage_thresholds",
        "evaluation_contract",
        "one_read_contract",
        "model_input_contract",
        "source_dependency_contract",
        "decision_contract",
        "registry_contract",
        "preregistration_manifest",
        "external_approval_contract",
        "source_snapshot",
        "required_result_files",
        "coverage_hold_result_files",
        "process_exhaustion_hold_result_files",
        "h18_registered_or_run",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"H17R configuration is missing fields: {sorted(missing)}")
    if config["experiment_id"] != EXPECTED_EXPERIMENT_ID:
        raise ValueError("unexpected H17R experiment identifier")
    data = config["data"]
    evaluation = config["evaluation_contract"]
    namespace = config["seed_namespace"]
    if (
        int(data["assimilation_days"]) != 300
        or int(data["scored_transition_days_per_block"]) != 299
        or int(data["natural_core_blocks"]) != 120
        or int(data["natural_core_scored_transition_count"]) != 35880
        or int(data["maximum_candidate_schedules"]) != 20000
        or int(data["maximum_accepted_coverage_blocks"]) != 256
        or float(evaluation["minimum_relative_reduction"]) != 0.5
        or int(evaluation["required_total_performance_conditions"]) != 42
        or int(evaluation["required_natural_performance_conditions"]) != 6
        or int(evaluation["required_coverage_performance_conditions"]) != 36
        or bool(evaluation["seed_averaging_for_decision"])
        or bool(evaluation["coverage_and_natural_scores_merged"])
        or namespace["stage"] != "final_reserve"
        or int(namespace["maximum_total_process_attempts"]) != 100
        or int(namespace["maximum_process_resample_attempt"]) != 99
        or int(namespace["maximum_total_process_attempts"])
        != 1 + int(namespace["maximum_process_resample_attempt"])
        or int(config["coverage_selection"]["maximum_candidate_schedules"])
        != int(data["maximum_candidate_schedules"])
        or int(config["coverage_selection"]["maximum_accepted_coverage_blocks"])
        != int(data["maximum_accepted_coverage_blocks"])
        or config["external_approval_contract"].get("required") is not True
        or bool(config["h18_registered_or_run"])
    ):
        raise ValueError("H17R frozen dimensions, gates, or authorization changed")
    if dict(config["coverage_thresholds"]) != {
        "minimum_40_to_49_days_per_source": 200,
        "minimum_50_plus_days_per_source": 40,
        "minimum_segments_reaching_50_per_source": 20,
        "minimum_distinct_50_plus_blocks_per_source": 15,
    }:
        raise ValueError("H17R rare-duration coverage thresholds changed")
    checkpoints = config["source_h17f"]["checkpoints"]
    if [int(item["initialization_seed"]) for item in checkpoints] != [
        1710101,
        1710102,
        1710103,
    ]:
        raise ValueError("H17R checkpoint seeds changed")
    files = tuple(str(value) for value in config["required_result_files"])
    if len(files) != len(set(files)) or not files:
        raise ValueError("H17R required result files must be unique")
    hold_files = tuple(str(value) for value in config["coverage_hold_result_files"])
    if len(hold_files) != len(set(hold_files)) or not hold_files:
        raise ValueError("H17R coverage-HOLD result files must be unique")
    process_hold_files = tuple(
        str(value) for value in config["process_exhaustion_hold_result_files"]
    )
    if len(process_hold_files) != len(set(process_hold_files)) or not process_hold_files:
        raise ValueError("H17R process-exhaustion result files must be unique")
    return config


def _registry_rows(project_root: Path) -> list[dict[str, str]]:
    path = project_root / "src/hbv_history_conditioned_imm/configs/experiment_registry.csv"
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def _git_branch(project_root: Path) -> str:
    result = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=project_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _git_head_local(project_root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=project_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _registry_row(project_root: Path, experiment_id: str) -> dict[str, str]:
    rows = [row for row in _registry_rows(project_root) if row["exp_id"] == experiment_id]
    if len(rows) != 1:
        raise ValueError(f"registry must contain exactly one row for {experiment_id}")
    return rows[0]


def _immutable_registry_fields(row: Mapping[str, str]) -> dict[str, str]:
    return {
        str(name): str(value)
        for name, value in row.items()
        if name not in {"status", "notes"}
    }


def _verify_preregistration_manifest(
    config: Mapping[str, Any],
    root: Path,
    registry_row: Mapping[str, str],
    *,
    approved_preregistration_sha256: str,
) -> dict[str, Any]:
    specification = config["preregistration_manifest"]
    path = root / str(specification["path"])
    if not path.is_file():
        raise FileNotFoundError("H17R preregistration manifest is missing")
    manifest_hash = _sha256(path)
    approved_hash = _require_approved_preregistration_sha256(
        approved_preregistration_sha256
    )
    if manifest_hash != approved_hash:
        raise ValueError(
            "the preregistration manifest does not match the externally approved SHA-256"
        )
    token = f"{specification['registry_note_token']}{manifest_hash}"
    if token not in str(registry_row["notes"]):
        raise ValueError("live registry does not anchor the H17R preregistration manifest")
    manifest = _read_json(path)
    if manifest.get("experiment_id") != config["experiment_id"]:
        raise ValueError("H17R preregistration manifest identity changed")
    files = manifest.get("files")
    if not isinstance(files, Mapping) or not files:
        raise ValueError("H17R preregistration manifest has no frozen files")
    expected_files = set(
        str(value) for value in config["source_snapshot"]["files"]
    ) - {str(specification["path"])}
    if set(str(value) for value in files) != expected_files:
        raise ValueError("H17R preregistration manifest does not freeze the full closure")
    observed = {}
    for relative, expected in files.items():
        source = root / str(relative)
        digest = _sha256(source)
        observed[str(relative)] = digest
        if digest != str(expected):
            raise ValueError(f"H17R preregistered file changed: {relative}")
    immutable = _immutable_registry_fields(registry_row)
    if immutable != manifest.get("registry_immutable_fields"):
        raise ValueError("an immutable H17R registry field changed after preregistration")
    return {
        "path": str(specification["path"]),
        "sha256": manifest_hash,
        "externally_approved_sha256": approved_hash,
        "live_config_sha256": observed[
            "src/hbv_history_conditioned_imm/configs/"
            "h17r_monotone_piecewise_age_risk_learning_rate_0p075_"
            "fresh_reserved_confirmation_v01.json"
        ],
        "file_count": len(observed),
        "all_file_hashes_verified": True,
        "immutable_registry_fields_sha256": _mapping_sha256(immutable),
    }


def seed_for(
    config: Mapping[str, Any], *, layer: str, stream: str, ordinal: int
) -> int:
    namespace = config["seed_namespace"]
    integer_ordinal = int(ordinal)
    if integer_ordinal != ordinal or not 1 <= integer_ordinal <= int(
        namespace["maximum_ordinal"]
    ):
        raise ValueError("final-reserve seed ordinal is outside the frozen namespace")
    if layer not in namespace["layer_codes"] or stream not in namespace["stream_codes"]:
        raise ValueError("unknown final-reserve seed layer or stream")
    result = (
        int(namespace["base"])
        + int(namespace["stage_codes"]["final_reserve"])
        * int(namespace["stage_multiplier"])
        + int(namespace["layer_codes"][layer]) * int(namespace["layer_multiplier"])
        + int(namespace["stream_codes"][stream])
        * int(namespace["stream_multiplier"])
        + integer_ordinal
    )
    if not int(namespace["expected_final_reserve_namespace_minimum_seed"]) <= result <= int(
        namespace["expected_final_reserve_namespace_maximum_seed"]
    ):
        raise ValueError("seed escaped the frozen final-reserve namespace")
    return result


def _schedule_counts(schedule: Any) -> dict[str, np.ndarray]:
    sources = np.asarray(schedule.active_source_indices, dtype=np.int64)
    ages = np.asarray(schedule.regime_age_before_transition, dtype=np.int64)
    evaluated = np.asarray(schedule.transition_evaluation_mask, dtype=np.bool_)
    result = {
        name: np.zeros(3, dtype=np.int64)
        for name in (
            "days_40_to_49",
            "days_50_plus",
            "segments_reaching_50",
            "distinct_50_plus_blocks",
        )
    }
    for source in range(3):
        active = evaluated & (sources == source)
        result["days_40_to_49"][source] = np.count_nonzero(
            active & (ages >= 40) & (ages <= 49)
        )
        result["days_50_plus"][source] = np.count_nonzero(active & (ages >= 50))
        result["segments_reaching_50"][source] = np.count_nonzero(
            active & (ages == 50)
        )
        result["distinct_50_plus_blocks"][source] = int(
            result["days_50_plus"][source] > 0
        )
    return result


def _thresholds(config: Mapping[str, Any]) -> dict[str, np.ndarray]:
    values = config["coverage_thresholds"]
    return {
        "days_40_to_49": np.full(
            3, int(values["minimum_40_to_49_days_per_source"]), dtype=np.int64
        ),
        "days_50_plus": np.full(
            3, int(values["minimum_50_plus_days_per_source"]), dtype=np.int64
        ),
        "segments_reaching_50": np.full(
            3, int(values["minimum_segments_reaching_50_per_source"]), dtype=np.int64
        ),
        "distinct_50_plus_blocks": np.full(
            3,
            int(values["minimum_distinct_50_plus_blocks_per_source"]),
            dtype=np.int64,
        ),
    }


def _coverage_complete(
    counts: Mapping[str, np.ndarray], thresholds: Mapping[str, np.ndarray]
) -> bool:
    return all(np.all(counts[name] >= thresholds[name]) for name in thresholds)


def _reduces_gap(
    candidate: Mapping[str, np.ndarray],
    counts: Mapping[str, np.ndarray],
    thresholds: Mapping[str, np.ndarray],
    names: Sequence[str],
) -> bool:
    return any(
        np.any((counts[name] < thresholds[name]) & (candidate[name] > 0))
        for name in names
    )


def select_final_coverage_schedules(
    config: Mapping[str, Any],
    *,
    schedule_generator: Callable[..., Any] = generate_long_history_schedule,
) -> tuple[list[int], list[Any], dict[str, np.ndarray], int, list[Any]]:
    maximum_candidates = int(config["coverage_selection"]["maximum_candidate_schedules"])
    maximum_accepted = int(
        config["coverage_selection"]["maximum_accepted_coverage_blocks"]
    )
    counts = {name: np.zeros(3, dtype=np.int64) for name in _thresholds(config)}
    thresholds = _thresholds(config)
    accepted_indices: list[int] = []
    accepted_schedules: list[Any] = []
    inspected_schedules: list[Any] = []
    inspected = 0
    for candidate_index in range(1, maximum_candidates + 1):
        if len(accepted_indices) >= maximum_accepted:
            break
        schedule = schedule_generator(
            seed=seed_for(
                config, layer="coverage", stream="schedule", ordinal=candidate_index
            ),
            total_days=int(config["data"]["assimilation_days"]),
            hazard=config["duration_hazard"],
        )
        inspected_schedules.append(schedule)
        inspected = candidate_index
        candidate = _schedule_counts(schedule)
        accept = _reduces_gap(
            candidate,
            counts,
            thresholds,
            ("days_50_plus", "segments_reaching_50", "distinct_50_plus_blocks"),
        ) or _reduces_gap(candidate, counts, thresholds, ("days_40_to_49",))
        if accept:
            accepted_indices.append(candidate_index)
            accepted_schedules.append(schedule)
            for name in counts:
                counts[name] += candidate[name]
        if _coverage_complete(counts, thresholds):
            break
    return accepted_indices, accepted_schedules, counts, inspected, inspected_schedules


def _natural_schedules(config: Mapping[str, Any]) -> list[Any]:
    return [
        generate_long_history_schedule(
            seed=seed_for(config, layer="natural_core", stream="schedule", ordinal=i),
            total_days=int(config["data"]["assimilation_days"]),
            hazard=config["duration_hazard"],
        )
        for i in range(1, int(config["data"]["natural_core_blocks"]) + 1)
    ]


def _stack_schedules(
    schedules: Sequence[Any], prefix: str, *, days: int
) -> dict[str, np.ndarray]:
    result: dict[str, np.ndarray] = {}
    for name in (
        "mode_indices",
        "active_source_indices",
        "regime_age_before_transition",
        "oracle_active_row_probabilities",
        "transition_evaluation_mask",
        "switch_event_mask",
    ):
        if schedules:
            value = np.stack([np.asarray(getattr(item, name)) for item in schedules])
        else:
            shape = (0, days, 3) if name == "oracle_active_row_probabilities" else (0, days)
            if name in ("transition_evaluation_mask", "switch_event_mask"):
                dtype = np.bool_
            elif name == "oracle_active_row_probabilities":
                dtype = np.float64
            else:
                dtype = np.int64
            value = np.empty(shape, dtype=dtype)
        result[f"{prefix}_{name}"] = value
    return result


def _requested_block_seeds(
    config: Mapping[str, Any], *, layer: str, schedule_ordinals: Sequence[int]
) -> tuple[BlockSeeds, ...]:
    return tuple(
        BlockSeeds(
            block_id=f"final_reserve_{layer}_block_{rank:03d}",
            forcing_seed=seed_for(config, layer=layer, stream="forcing", ordinal=rank),
            process_seed=seed_for(config, layer=layer, stream="process", ordinal=rank),
            observation_seed=seed_for(
                config, layer=layer, stream="observation", ordinal=rank
            ),
            schedule_seed=seed_for(
                config, layer=layer, stream="schedule", ordinal=schedule_ordinal
            ),
        )
        for rank, schedule_ordinal in enumerate(schedule_ordinals, start=1)
    )


def generate_one_namespaced_block(
    *,
    requested: BlockSeeds,
    process_resample_seeds: Sequence[int],
    generation_kwargs: Mapping[str, Any],
    generator: Callable[..., LongHistoryParameterSwitchBatch] = (
        generate_long_history_parameter_switch_batch
    ),
) -> LongHistoryParameterSwitchBatch:
    rejected: list[int] = []
    exact_failure = f"no admissible long-history truth found for {requested.block_id}"
    for candidate_seed in (requested.process_seed, *map(int, process_resample_seeds)):
        attempted = replace(requested, process_seed=int(candidate_seed))
        try:
            result = generator(
                block_seeds=(attempted,),
                maximum_process_resamples=1,
                **generation_kwargs,
            )
        except RuntimeError as error:
            if str(error) != exact_failure:
                raise
            rejected.append(int(candidate_seed))
            continue
        return replace(
            result,
            block_seeds=(requested,),
            accepted_process_seeds=(int(candidate_seed),),
            rejected_process_seeds=tuple(rejected),
        )
    raise NamespacedProcessExhaustion(requested, rejected)


def concatenate_batches(
    batches: Sequence[LongHistoryParameterSwitchBatch],
) -> LongHistoryParameterSwitchBatch:
    if not batches:
        raise ValueError("cannot concatenate an empty batch list")
    first = batches[0]
    for item in batches:
        if (
            item.parameter_ids != first.parameter_ids
            or item.warmup_parameter_id != first.warmup_parameter_id
            or item.assimilation_days != first.assimilation_days
        ):
            raise ValueError("long-history batches do not share one frozen contract")
    tensors = {
        name: torch.cat([getattr(item, name) for item in batches], dim=0)
        for name in TENSOR_BATCH_FIELDS
    }
    return LongHistoryParameterSwitchBatch(
        **tensors,
        block_ids=tuple(value for item in batches for value in item.block_ids),
        block_seeds=tuple(value for item in batches for value in item.block_seeds),
        accepted_process_seeds=tuple(
            value for item in batches for value in item.accepted_process_seeds
        ),
        rejected_process_seeds=tuple(
            value for item in batches for value in item.rejected_process_seeds
        ),
        parameter_ids=first.parameter_ids,
        warmup_parameter_id=first.warmup_parameter_id,
        assimilation_days=first.assimilation_days,
    )


def _generate_layer(
    config: Mapping[str, Any],
    h17_config: Mapping[str, Any],
    *,
    layer: str,
    schedule_ordinals: Sequence[int],
    expected_schedules: Sequence[Any],
) -> tuple[LongHistoryParameterSwitchBatch, list[dict[str, Any]]]:
    requested = _requested_block_seeds(
        config, layer=layer, schedule_ordinals=schedule_ordinals
    )
    generation_kwargs = {
        "parameter_candidates": _parameter_candidates(h17_config),
        "warmup_parameter_id": str(config["data"]["warmup_parameter_id"]),
        "assimilation_days": int(config["data"]["assimilation_days"]),
        "maximum_forecast_lead": int(config["data"]["maximum_forecast_lead"]),
        "warmup_days": int(config["data"]["warmup_days"]),
        "hazard": config["duration_hazard"],
        "process_standard_deviation": float(
            config["data"]["fixed_process_standard_deviation"]
        ),
        "observation_standard_deviation": float(
            config["data"]["observation_standard_deviation"]
        ),
        "process_state_index": int(config["data"]["fixed_process_state_index"]),
        "require_zero_projection": bool(config["data"]["require_zero_projection"]),
        "initial_covariance_fraction": float(
            config["data"]["initial_covariance_fraction"]
        ),
    }
    results: list[LongHistoryParameterSwitchBatch] = []
    process_attempts: list[dict[str, Any]] = []
    maximum_resamples = int(config["seed_namespace"]["maximum_process_resample_attempt"])
    for rank, specification in enumerate(requested, start=1):
        resamples = [
            seed_for(
                config,
                layer=layer,
                stream="process_resample",
                ordinal=rank * 1000 + attempt,
            )
            for attempt in range(1, maximum_resamples + 1)
        ]
        try:
            result = generate_one_namespaced_block(
                requested=specification,
                process_resample_seeds=resamples,
                generation_kwargs=generation_kwargs,
            )
        except NamespacedProcessExhaustion as error:
            raise ProcessLayerExhaustion(
                layer=layer,
                rank=rank,
                schedule_ordinal=int(schedule_ordinals[rank - 1]),
                failure=error,
                completed_attempts=process_attempts,
            ) from None
        process_attempts.append(
            {
                "block_id": specification.block_id,
                "requested_process_seed": int(specification.process_seed),
                "accepted_process_seed": int(result.accepted_process_seeds[0]),
                "rejected_process_seeds": [
                    int(value) for value in result.rejected_process_seeds
                ],
                "total_attempt_count": 1 + len(result.rejected_process_seeds),
            }
        )
        days = int(config["data"]["assimilation_days"])
        expected = expected_schedules[rank - 1]
        comparisons = (
            (result.true_parameter_indices[0, :days], expected.mode_indices),
            (result.active_source_indices[0, :days], expected.active_source_indices),
            (
                result.regime_age_before_transition[0, :days],
                expected.regime_age_before_transition,
            ),
            (
                result.transition_evaluation_mask[0, :days],
                expected.transition_evaluation_mask,
            ),
            (
                result.oracle_active_row_probabilities[0, :days],
                expected.oracle_active_row_probabilities,
            ),
            (
                result.switch_event_mask[0, :days],
                expected.switch_event_mask,
            ),
        )
        if any(
            not np.array_equal(left.detach().cpu().numpy(), np.asarray(right))
            for left, right in comparisons
        ):
            raise ValueError("physical generation changed a preselected schedule")
        results.append(result)
        if rank % 20 == 0 or rank == len(requested):
            print(f"{layer}: generated {rank}/{len(requested)} blocks", flush=True)
    return concatenate_batches(results), process_attempts


def evaluation_split(
    name: str, batch: LongHistoryParameterSwitchBatch, *, days: int
) -> H17DataSplit:
    return H17DataSplit(
        name=name,
        observable=ObservableAssimilationBatch(
            forcing=batch.forcing[:, :days].clone(),
            observations=batch.observations[:, :days].clone(),
            initial_states=batch.initial_states.clone(),
            initial_covariances=batch.initial_covariances.clone(),
            assimilation_days=days,
        ),
        supervision=ActiveRowSupervision(
            source_indices=batch.active_source_indices[:, :days].clone(),
            target_probabilities=batch.oracle_active_row_probabilities[:, :days].clone(),
            evaluation_mask=batch.transition_evaluation_mask[:, :days].clone(),
            switch_event_mask=batch.switch_event_mask[:, :days].clone(),
            regime_age_before_transition=batch.regime_age_before_transition[
                :, :days
            ].clone(),
        ),
    )


def _slice_split(split: H17DataSplit, count: int) -> H17DataSplit:
    observable = split.observable
    supervision = split.supervision
    return H17DataSplit(
        name=f"{split.name}_audit",
        observable=replace(
            observable,
            forcing=observable.forcing[:count].clone(),
            observations=observable.observations[:count].clone(),
            initial_states=observable.initial_states[:count].clone(),
            initial_covariances=observable.initial_covariances[:count].clone(),
        ),
        supervision=replace(
            supervision,
            source_indices=supervision.source_indices[:count].clone(),
            target_probabilities=supervision.target_probabilities[:count].clone(),
            evaluation_mask=supervision.evaluation_mask[:count].clone(),
            switch_event_mask=supervision.switch_event_mask[:count].clone(),
            regime_age_before_transition=supervision.regime_age_before_transition[
                :count
            ].clone(),
        ),
    )


def _duration_network(
    h17_config: Mapping[str, Any], base_transition: torch.Tensor
) -> CausalSemiMarkovTransitionModule:
    contract = h17_config["duration_contract"]
    return CausalSemiMarkovTransitionModule(
        base_transition=base_transition,
        maximum_age=int(contract["maximum_age"]),
        hazard_hidden_size=int(contract["hazard_hidden_size"]),
        maximum_logit_correction=float(contract["maximum_logit_correction"]),
        minimum_differentiable_mode_probability=float(
            contract["minimum_differentiable_mode_probability"]
        ),
        age_risk_representation=str(contract["age_risk_representation"]),
        piecewise_knot_count=int(contract["piecewise_knot_count"]),
    )


def _load_frozen_models(
    config: Mapping[str, Any], h17_config: Mapping[str, Any], root: Path, staging: Path
) -> tuple[Any, dict[str, CausalSemiMarkovTransitionModule], dict[str, Any]]:
    base = _base_transition(h17_config)
    static_source = root / str(config["static_reference"]["checkpoint_path"])
    if _sha256(static_source) != str(config["static_reference"]["checkpoint_sha256"]):
        raise ValueError("frozen static checkpoint hash changed")
    static_destination = staging / "static_reference_checkpoint.pt"
    shutil.copy2(static_source, static_destination)
    static_payload = torch.load(static_destination, map_location="cpu", weights_only=False)
    static = _static_network(h17_config, base)
    static.load_state_dict(static_payload["network_state_dict"], strict=True)
    static.eval()
    if (
        static_payload.get("experiment_id")
        != "h17_supervised_active_row_probability_upper_bound_v01"
        or static_payload.get("method") != "learned_history_free_static_matrix"
        or int(static_payload.get("test_reads_before_selection", -1)) != 0
    ):
        raise ValueError("static checkpoint metadata changed")

    networks: dict[str, CausalSemiMarkovTransitionModule] = {}
    checkpoint_audit: dict[str, Any] = {
        "checkpoint_load_count_before_coverage_pass": 0,
        "static": {
            "source_sha256": _sha256(static_source),
            "copied_sha256": _sha256(static_destination),
            "best_epoch": int(static_payload["best_epoch"]),
        },
        "histories": {},
    }
    for specification in config["source_h17f"]["checkpoints"]:
        seed = int(specification["initialization_seed"])
        source = root / str(specification["path"])
        if _sha256(source) != str(specification["sha256"]):
            raise ValueError(f"frozen history checkpoint hash changed for seed {seed}")
        destination = staging / f"history_seed_{seed}_checkpoint.pt"
        shutil.copy2(source, destination)
        payload = torch.load(destination, map_location="cpu", weights_only=False)
        if (
            payload.get("experiment_id") != config["source_h17f"]["experiment_id"]
            or int(payload.get("initialization_seed", -1)) != seed
            or int(payload.get("best_epoch", -1)) != int(specification["selected_epoch"])
            or payload.get("transition_architecture") != "explicit_causal_duration"
            or int(payload.get("test_reads_before_selection", -1)) != 0
            or bool(payload.get("warm_started"))
        ):
            raise ValueError(f"history checkpoint metadata changed for seed {seed}")
        network = _duration_network(h17_config, base)
        network.load_state_dict(payload["network_state_dict"], strict=True)
        network.eval()
        networks[str(seed)] = network
        checkpoint_audit["histories"][str(seed)] = {
            "source_sha256": _sha256(source),
            "copied_sha256": _sha256(destination),
            "best_epoch": int(payload["best_epoch"]),
            "test_reads_before_selection": int(payload["test_reads_before_selection"]),
        }
    checkpoint_audit["production_checkpoint_load_count"] = 4
    checkpoint_audit["checkpoint_selection_performed"] = False
    checkpoint_audit["all_hashes_verified"] = True
    return static, networks, checkpoint_audit


def _evaluate(
    split: H17DataSplit,
    *,
    h17_config: Mapping[str, Any],
    static: Any,
    networks: Mapping[str, CausalSemiMarkovTransitionModule],
) -> dict[str, ProbabilityRolloutResult]:
    candidates = _parameter_candidates(h17_config)
    with torch.no_grad():
        results: dict[str, ProbabilityRolloutResult] = {
            "static": rollout_static_probability(
                split.supervision,
                static,
                dtype=split.observable.forcing.dtype,
                device=split.observable.forcing.device,
            )
        }
        for seed, network in networks.items():
            results[f"history_seed_{seed}"] = rollout_semi_markov_probability(
                split.observable,
                split.supervision,
                network,
                _estimator(h17_config, candidates),
            )
    return results


def _cell_metrics(
    split: H17DataSplit, result: ProbabilityRolloutResult, selected: torch.Tensor
) -> dict[str, int | float | None]:
    count = int(selected.sum())
    if count == 0:
        return {
            "count": 0,
            "oracle_brier": None,
            "switch_hazard_mean_absolute_error": None,
        }
    blocks, days = torch.nonzero(selected, as_tuple=True)
    sources = split.supervision.source_indices[blocks, days]
    rows = result.transition_matrices[blocks, days, sources]
    targets = split.supervision.target_probabilities[blocks, days]
    index = torch.arange(count)
    brier = float(torch.sum((rows - targets).square(), dim=-1).mean())
    hazard_mae = float(
        torch.abs((1.0 - rows[index, sources]) - (1.0 - targets[index, sources])).mean()
    )
    return {
        "count": count,
        "oracle_brier": brier if math.isfinite(brier) else None,
        "switch_hazard_mean_absolute_error": (
            hazard_mae if math.isfinite(hazard_mae) else None
        ),
    }


def _score_and_decide(
    config: Mapping[str, Any],
    natural: H17DataSplit,
    coverage: H17DataSplit,
    natural_results: Mapping[str, ProbabilityRolloutResult],
    coverage_results: Mapping[str, ProbabilityRolloutResult],
) -> tuple[dict[str, Any], dict[str, Any], bool]:
    threshold = float(config["evaluation_contract"]["minimum_relative_reduction"])
    natural_metrics = {
        name: _cell_metrics(natural, result, natural.supervision.evaluation_mask)
        for name, result in natural_results.items()
    }
    sources = coverage.supervision.source_indices
    ages = coverage.supervision.regime_age_before_transition
    valid = coverage.supervision.evaluation_mask
    age_masks = {
        "age_40_49": (ages >= 40) & (ages <= 49),
        "age_50_plus": ages >= 50,
    }
    coverage_metrics: dict[str, Any] = {name: {} for name in coverage_results}
    for method, result in coverage_results.items():
        for age_name, age_mask in age_masks.items():
            coverage_metrics[method][age_name] = {
                str(source): _cell_metrics(
                    coverage,
                    result,
                    valid & age_mask & (sources == source),
                )
                for source in range(3)
            }
    records: list[dict[str, Any]] = []

    def gate_record(
        *, layer: str, method: str, cell: str, metric: str, baseline: float, candidate: float
    ) -> dict[str, Any]:
        valid = (
            math.isfinite(baseline)
            and baseline > 0.0
            and math.isfinite(candidate)
            and candidate >= 0.0
        )
        reduction = 1.0 - candidate / baseline if valid else None
        return {
            "layer": layer,
            "method": method,
            "cell": cell,
            "metric": metric,
            "static_error": baseline if math.isfinite(baseline) else None,
            "candidate_error": candidate if math.isfinite(candidate) else None,
            "denominator_valid": valid,
            "relative_reduction": reduction,
            "failure_reason": None if valid else "invalid_or_zero_static_denominator_or_nonfinite_candidate",
            "passed": bool(valid and reduction is not None and reduction >= threshold),
        }

    for method in natural_results:
        if method == "static":
            continue
        for metric in ("oracle_brier", "switch_hazard_mean_absolute_error"):
            baseline_value = natural_metrics["static"][metric]
            candidate_value = natural_metrics[method][metric]
            baseline = float(baseline_value) if baseline_value is not None else math.nan
            candidate = float(candidate_value) if candidate_value is not None else math.nan
            records.append(
                gate_record(
                    layer="natural_core",
                    method=method,
                    cell="all_scored_transitions",
                    metric=metric,
                    baseline=baseline,
                    candidate=candidate,
                )
            )
    for method in coverage_results:
        if method == "static":
            continue
        for age_name in age_masks:
            for source in range(3):
                for metric in ("oracle_brier", "switch_hazard_mean_absolute_error"):
                    baseline_value = coverage_metrics["static"][age_name][str(source)][metric]
                    candidate_value = coverage_metrics[method][age_name][str(source)][metric]
                    baseline = float(baseline_value) if baseline_value is not None else math.nan
                    candidate = float(candidate_value) if candidate_value is not None else math.nan
                    records.append(
                        gate_record(
                            layer="rare_duration_coverage",
                            method=method,
                            cell=f"source_{source}_{age_name}",
                            metric=metric,
                            baseline=baseline,
                            candidate=candidate,
                        )
                    )
    if len(records) != int(config["evaluation_contract"]["required_total_performance_conditions"]):
        raise RuntimeError("H17R did not produce exactly 42 frozen performance conditions")
    metrics = {
        "natural_core": natural_metrics,
        "minimum_relative_reduction": threshold,
        "gate_records": records,
        "natural_gate_count": sum(item["layer"] == "natural_core" for item in records),
        "coverage_gate_count": sum(
            item["layer"] == "rare_duration_coverage" for item in records
        ),
        "passed_gate_count": sum(bool(item["passed"]) for item in records),
        "failed_gate_count": sum(not bool(item["passed"]) for item in records),
        "all_42_performance_conditions_passed": all(
            bool(item["passed"]) for item in records
        ),
    }
    stratified = {
        "age_bins": ["age_40_49", "age_50_plus"],
        "source_ids": config["evaluation_contract"]["coverage_source_ids"],
        "methods": coverage_metrics,
    }
    return metrics, stratified, bool(metrics["all_42_performance_conditions_passed"])


def _legality(results_by_layer: Mapping[str, Mapping[str, ProbabilityRolloutResult]]) -> dict[str, Any]:
    values: dict[str, Any] = {"layers": {}}
    maximum_row_error = 0.0
    minimum_probability = math.inf
    all_finite = True
    for layer, methods in results_by_layer.items():
        values["layers"][layer] = {}
        for method, result in methods.items():
            matrices = result.transition_matrices.detach()
            finite = bool(torch.isfinite(matrices).all())
            row_error = (
                float(torch.max(torch.abs(matrices.sum(dim=-1) - 1.0)))
                if finite
                else None
            )
            minimum = float(torch.min(matrices)) if finite else None
            values["layers"][layer][method] = {
                "maximum_transition_row_sum_error": row_error,
                "minimum_transition_probability": minimum,
                "all_values_finite": finite,
            }
            if row_error is not None and minimum is not None:
                maximum_row_error = max(maximum_row_error, row_error)
                minimum_probability = min(minimum_probability, minimum)
            all_finite = all_finite and finite
    if not all_finite:
        maximum_row_error_value: float | None = None
        minimum_probability_value: float | None = None
    else:
        maximum_row_error_value = maximum_row_error
        minimum_probability_value = minimum_probability
    values.update(
        {
            "maximum_transition_row_sum_error": maximum_row_error_value,
            "minimum_transition_probability": minimum_probability_value,
            "all_values_finite": all_finite,
            "passed": bool(
                all_finite
                and minimum_probability_value is not None
                and minimum_probability_value >= 0.0
                and maximum_row_error_value is not None
                and maximum_row_error_value <= 1e-12
            ),
        }
    )
    return values


def _dependency_hashes(config: Mapping[str, Any], root: Path) -> dict[str, Any]:
    values = {}
    for relative, expected in config["source_dependency_contract"].items():
        path = root / str(relative)
        observed = _sha256(path)
        values[str(relative)] = {
            "expected_sha256": str(expected),
            "observed_sha256": observed,
            "verified": observed == str(expected),
        }
    if not all(item["verified"] for item in values.values()):
        raise ValueError("a frozen H17R runtime dependency changed")
    return values


def _verify_named_result_hashes(
    root: Path, result_directory: Path, specifications: Mapping[str, str]
) -> dict[str, Any]:
    result = {}
    for filename, expected in specifications.items():
        path = result_directory / filename
        observed = _sha256(path)
        result[filename] = {
            "expected_sha256": expected,
            "observed_sha256": observed,
            "verified": observed == expected,
        }
    if not all(item["verified"] for item in result.values()):
        raise ValueError(f"frozen result artifact changed under {result_directory}")
    return result


def _verify_checksum_manifest(result_directory: Path) -> bool:
    manifest_path = result_directory / "checksums.json"
    manifest = _read_json(manifest_path)
    return bool(manifest) and all(
        (result_directory / name).is_file()
        and _sha256(result_directory / name) == str(expected)
        for name, expected in manifest.items()
    )


def preopen_eligibility_audit(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    approved_preregistration_sha256: str,
) -> dict[str, Any]:
    root = Path(project_root).resolve()
    repository = config["repository_contract"]
    if root.as_posix().lower() != str(repository["worktree"]).lower():
        raise ValueError("H17R must run only in the authorized worktree")
    branch = _git_branch(root)
    head = _git_head_local(root)
    if branch != repository["branch"] or head != repository["git_head"]:
        raise ValueError("H17R branch or commit changed")
    h17r_row = _registry_row(root, config["experiment_id"])
    if h17r_row["status"] != config["registry_contract"]["eligible_status"]:
        raise ValueError("H17R remains blocked in the live registry")
    if h17r_row["run_dir"] != config["result_relative_path"]:
        raise ValueError("H17R registry output differs from its config")
    if (
        h17r_row["metrics_path"]
        != config["registry_contract"]["metrics_relative_path"]
        or h17r_row["metrics_path"]
        != f"{config['result_relative_path']}/metrics.json"
    ):
        raise ValueError("H17R registry metrics path differs from its config")
    preregistration = _verify_preregistration_manifest(
        config,
        root,
        h17r_row,
        approved_preregistration_sha256=approved_preregistration_sha256,
    )
    rows = _registry_rows(root)
    h18_rows = [row for row in rows if row["exp_id"].lower().startswith("h18")]
    results_parent = root / "results/23_hbv_multilead_joint_uncertainty"
    h18_results = (
        [
            path
            for path in results_parent.iterdir()
            if path.name.lstrip(".").lower().startswith("h18")
        ]
        if results_parent.exists()
        else []
    )
    if h18_rows or h18_results:
        raise ValueError("H18 is registered or has a result")
    for experiment, expected_status in (
        (config["source_h16"]["experiment_id"], config["eligibility_contract"]["h16_required_registry_status"]),
        (config["source_h17p"]["experiment_id"], config["eligibility_contract"]["h17p_required_registry_status"]),
        (config["source_h17f"]["experiment_id"], config["eligibility_contract"]["h17f_required_registry_status"]),
    ):
        if _registry_row(root, experiment)["status"] != expected_status:
            raise ValueError(f"{experiment} registry status changed")

    for source_name in ("source_h16", "source_h17p", "source_h17f"):
        source = config[source_name]
        declaration = root / str(source["declaration"]["path"])
        if _sha256(declaration) != source["declaration"]["sha256"]:
            raise ValueError(f"{source_name} declaration changed")
    h16_root = root / str(config["source_h16"]["result_directory"])
    h16_hashes = _verify_named_result_hashes(
        root,
        h16_root,
        {
            "config_snapshot.json": config["source_h16"]["config_snapshot_sha256"],
            "checksums.json": config["source_h16"]["checksums_sha256"],
            "preflight_arrays.npz": config["source_h16"]["preflight_arrays_sha256"],
            "preflight_report.json": config["source_h16"]["preflight_report_sha256"],
            "independent_verification.json": config["source_h16"]["independent_verification_sha256"],
        },
    )
    h17p_root = root / str(config["source_h17p"]["result_directory"])
    h17p_hashes = _verify_named_result_hashes(
        root,
        h17p_root,
        {
            "config_snapshot.json": config["source_h17p"]["config_snapshot_sha256"],
            "checksums.json": config["source_h17p"]["checksums_sha256"],
            "coverage_report.json": config["source_h17p"]["coverage_report_sha256"],
            "preflight_report.json": config["source_h17p"]["preflight_report_sha256"],
            "seed_namespace_audit.json": config["source_h17p"]["seed_namespace_audit_sha256"],
            "independent_verification.json": config["source_h17p"]["independent_verification_sha256"],
            "source_manifest.json": config["source_h17p"]["source_manifest_sha256"],
            "source_snapshot.zip": config["source_h17p"]["source_snapshot_sha256"],
        },
    )
    h17f_root = root / str(config["source_h17f"]["result_directory"])
    h17f_hashes = _verify_named_result_hashes(
        root,
        h17f_root,
        {
            "config_snapshot.json": config["source_h17f"]["config_snapshot_sha256"],
            "checksums.json": config["source_h17f"]["checksums_sha256"],
            "metrics.json": config["source_h17f"]["metrics_sha256"],
            "independent_verification.json": config["source_h17f"]["independent_verification_sha256"],
            "source_manifest.json": config["source_h17f"]["source_manifest_sha256"],
            "source_snapshot.zip": config["source_h17f"]["source_snapshot_sha256"],
        },
    )
    h16_verification = _read_json(h16_root / "independent_verification.json")
    h17p_verification = _read_json(h17p_root / "independent_verification.json")
    h17f_verification = _read_json(h17f_root / "independent_verification.json")
    h17f_metrics = _read_json(h17f_root / "metrics.json")
    if (
        h16_verification.get("verified") is not True
        or h17p_verification.get("verified") is not True
        or h17f_verification.get("verified") is not True
        or not _verify_checksum_manifest(h17p_root)
        or not _verify_checksum_manifest(h17f_root)
        or not _verify_checksum_manifest(h16_root)
        or h17f_metrics.get("decision")
        != config["eligibility_contract"]["h17f_required_decision"]
    ):
        raise ValueError("H17P or H17F independent verification no longer passes")
    for specification in config["source_h17f"]["checkpoints"]:
        checkpoint = root / str(specification["path"])
        if _sha256(checkpoint) != str(specification["sha256"]):
            raise ValueError("a frozen H17F history checkpoint changed")
    static_path = root / str(config["static_reference"]["checkpoint_path"])
    if _sha256(static_path) != config["static_reference"]["checkpoint_sha256"]:
        raise ValueError("static reference changed")
    static_root = static_path.parent
    if (
        _sha256(static_root / "checksums.json")
        != config["static_reference"]["checksums_sha256"]
        or not _verify_checksum_manifest(static_root)
    ):
        raise ValueError("static reference checksum evidence changed")
    dependencies = _dependency_hashes(config, root)
    return {
        "eligible": True,
        "branch": branch,
        "git_head": head,
        "h17r_registry_status": h17r_row["status"],
        "eligible_registry_row_sha256": _mapping_sha256(h17r_row),
        "eligible_registry_file_sha256": _sha256(
            root / "src/hbv_history_conditioned_imm/configs/experiment_registry.csv"
        ),
        "immutable_registry_fields_sha256": _mapping_sha256(
            _immutable_registry_fields(h17r_row)
        ),
        "h18_registry_row_count": len(h18_rows),
        "h18_result_count": len(h18_results),
        "h16_hashes": h16_hashes,
        "h17p_hashes": h17p_hashes,
        "h17f_hashes": h17f_hashes,
        "h17p_independent_verification_passed": True,
        "h17f_independent_verification_passed": True,
        "h16_independent_verification_passed": True,
        "runtime_dependency_hashes": dependencies,
        "preregistration_manifest": preregistration,
        "final_reserve_schedule_read_count": 0,
        "final_reserve_target_read_count": 0,
        "final_reserve_score_read_count": 0,
    }


def _source_snapshot_bytes(
    config: Mapping[str, Any], root: Path
) -> tuple[dict[str, Any], bytes]:
    entries = []
    values: list[tuple[str, bytes]] = []
    for relative in sorted(str(value) for value in config["source_snapshot"]["files"]):
        path = (root / relative).resolve()
        path.relative_to(root)
        data = path.read_bytes()
        name = Path(relative).as_posix()
        values.append((name, data))
        entries.append(
            {"path": name, "size_bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        )
    manifest = {
        "format": config["source_snapshot"]["format"],
        "fixed_zip_timestamp": config["source_snapshot"]["fixed_zip_timestamp"],
        "source_file_count": len(entries),
        "entries": entries,
    }
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in values:
            information = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            information.compress_type = zipfile.ZIP_DEFLATED
            information.create_system = 3
            information.external_attr = 0o100644 << 16
            archive.writestr(information, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return manifest, buffer.getvalue()


def _verified_preopen_base_artifact_hashes(
    staging: Path,
    *,
    config: Mapping[str, Any],
    eligibility: Mapping[str, Any],
    generator_contract: Mapping[str, Any],
    registry_open_entry: Mapping[str, Any],
    registry_open_snapshot: bytes,
    environment: Mapping[str, Any],
    source_manifest: Mapping[str, Any],
    source_snapshot: bytes,
) -> dict[str, str]:
    expected_files = {
        "config_snapshot.json",
        "eligibility_audit.json",
        "generator_contract.json",
        "registry_open_entry.json",
        "registry_open_snapshot.csv",
        "environment.json",
        "source_manifest.json",
        "source_snapshot.zip",
    }
    found = {path.name for path in staging.iterdir() if path.is_file()}
    if found != expected_files:
        raise RuntimeError("the pre-open base artifact file set is incomplete")
    if (
        _read_json(staging / "config_snapshot.json") != dict(config)
        or _read_json(staging / "eligibility_audit.json") != dict(eligibility)
        or _read_json(staging / "generator_contract.json")
        != dict(generator_contract)
        or _read_json(staging / "registry_open_entry.json")
        != dict(registry_open_entry)
        or (staging / "registry_open_snapshot.csv").read_bytes()
        != registry_open_snapshot
        or _read_json(staging / "environment.json") != dict(environment)
        or _read_json(staging / "source_manifest.json") != dict(source_manifest)
        or (staging / "source_snapshot.zip").read_bytes() != source_snapshot
    ):
        raise RuntimeError("a pre-open base artifact failed its read-back check")
    return {
        "staged_config_snapshot_sha256": _sha256(staging / "config_snapshot.json"),
        "staged_eligibility_audit_sha256": _sha256(
            staging / "eligibility_audit.json"
        ),
        "staged_generator_contract_sha256": _sha256(
            staging / "generator_contract.json"
        ),
        "staged_registry_open_entry_sha256": _sha256(
            staging / "registry_open_entry.json"
        ),
        "staged_registry_open_snapshot_sha256": _sha256(
            staging / "registry_open_snapshot.csv"
        ),
        "staged_environment_sha256": _sha256(staging / "environment.json"),
    }


def _exclusive_open_marker(
    path: Path, config: Mapping[str, Any], *, bindings: Mapping[str, str] | None = None
) -> None:
    binding_values = dict(bindings or {})
    values = {
        "schema": "single_decision_bearing_reserve_open_v1",
        "experiment_id": config["experiment_id"],
        "open_event_id": f"{config['experiment_id']}:final_reserve:1",
        "open_event_count": 1,
        "stage": "final_reserve",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "process_id": os.getpid(),
        "resume_allowed": False,
        "retry_allowed": False,
        "training_allowed": False,
        "pre_open_schedule_read_count": 0,
        "pre_open_target_read_count": 0,
        "pre_open_score_read_count": 0,
        "permanent_tombstone_sha256": binding_values.get(
            "permanent_tombstone_sha256"
        ),
        "bindings": binding_values,
    }
    data = (json.dumps(values, indent=2, sort_keys=True) + "\n").encode("utf-8")
    with path.open("xb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


def _reserve_open_tombstone_path(
    project_root: str | Path, config: Mapping[str, Any]
) -> Path:
    root = Path(project_root).resolve()
    experiment_id = str(config["experiment_id"])
    if Path(experiment_id).name != experiment_id or experiment_id in {"", ".", ".."}:
        raise ValueError("the reserve-open tombstone experiment identifier is unsafe")
    directory = (root / RESERVE_OPEN_TOMBSTONE_DIRECTORY).resolve()
    directory.relative_to(root)
    derived = directory / f"{experiment_id}.reserve_opened.tombstone.json"
    configured = (
        root / str(config["one_read_contract"]["permanent_tombstone_relative_path"])
    ).resolve()
    configured.relative_to(root)
    if configured != derived:
        raise ValueError("the permanent reserve-open tombstone path changed")
    return configured


def _exclusive_open_tombstone(
    path: Path,
    config: Mapping[str, Any],
    *,
    bindings: Mapping[str, str],
    final_path: Path,
    staging_path: Path,
) -> None:
    values = {
        "schema": "permanent_single_reserve_open_tombstone_v1",
        "experiment_id": config["experiment_id"],
        "open_event_id": f"{config['experiment_id']}:final_reserve:1",
        "open_event_count": 1,
        "stage": "final_reserve",
        "result_relative_path": config["result_relative_path"],
        "canonical_final_path": str(final_path.resolve()),
        "canonical_staging_path": str(staging_path.resolve()),
        "canonical_tombstone_path": str(path.resolve()),
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "process_id": os.getpid(),
        "replacement_or_deletion_allowed": False,
        "same_identifier_reopen_allowed": False,
        "resume_allowed": False,
        "retry_allowed": False,
        "training_allowed": False,
        "h18_authorized": False,
        "pre_open_schedule_read_count": 0,
        "pre_open_target_read_count": 0,
        "pre_open_score_read_count": 0,
        "bindings": dict(bindings),
    }
    data = (json.dumps(values, indent=2, sort_keys=True) + "\n").encode("utf-8")
    with path.open("xb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    if path.read_bytes() != data:
        raise OSError("the permanent reserve-open tombstone failed its read-back check")


def _old_seed_set(config: Mapping[str, Any], root: Path) -> set[int]:
    values: set[int] = set()
    sources = (
        root / str(config["source_h16"]["result_directory"]) / "preflight_arrays.npz",
        root / str(config["source_h17p"]["result_directory"]) / "preflight_arrays.npz",
    )
    for path in sources:
        with np.load(path, allow_pickle=False) as arrays:
            for name in arrays.files:
                if "seed" in name and np.issubdtype(arrays[name].dtype, np.integer):
                    values.update(int(value) for value in arrays[name].reshape(-1))
    return values


def _seed_audit(
    config: Mapping[str, Any],
    root: Path,
    natural: LongHistoryParameterSwitchBatch,
    coverage: LongHistoryParameterSwitchBatch,
    process_attempts: Mapping[str, Sequence[Mapping[str, Any]]],
    *,
    inspected_coverage_schedules: int,
) -> dict[str, Any]:
    batches = {"natural_core": natural, "coverage": coverage}
    schedule_seeds = {
        "natural_core": [
            seed_for(config, layer="natural_core", stream="schedule", ordinal=value)
            for value in range(1, int(config["data"]["natural_core_blocks"]) + 1)
        ],
        "coverage_candidates": [
            seed_for(config, layer="coverage", stream="schedule", ordinal=value)
            for value in range(1, int(inspected_coverage_schedules) + 1)
        ],
    }
    actual: list[int] = [
        *schedule_seeds["natural_core"],
        *schedule_seeds["coverage_candidates"],
    ]
    committed: list[int] = list(actual)
    layer_values: dict[str, Any] = {}
    for layer, batch in batches.items():
        requested = [
            seed
            for block in batch.block_seeds
            for seed in (block.forcing_seed, block.process_seed, block.observation_seed)
        ]
        used = requested + list(batch.accepted_process_seeds) + list(batch.rejected_process_seeds)
        actual.extend(used)
        for rank, block in enumerate(batch.block_seeds, start=1):
            committed.extend(
                (block.forcing_seed, block.process_seed, block.observation_seed)
            )
            committed.extend(
                seed_for(
                    config,
                    layer=layer,
                    stream="process_resample",
                    ordinal=rank * 1000 + attempt,
                )
                for attempt in range(
                    1,
                    int(config["seed_namespace"]["maximum_process_resample_attempt"])
                    + 1,
                )
            )
        layer_values[layer] = {
            "block_count": len(batch.block_ids),
            "requested_block_seeds": [list(block.all_seeds) for block in batch.block_seeds],
            "accepted_process_seeds": list(batch.accepted_process_seeds),
            "rejected_process_seeds": list(batch.rejected_process_seeds),
            "rejected_process_seed_count": len(batch.rejected_process_seeds),
            "process_attempts": [dict(value) for value in process_attempts[layer]],
        }
    old = _old_seed_set(config, root)
    unique = len(committed) == len(set(committed))
    disjoint = set(committed).isdisjoint(old)
    actual_committed = set(actual).issubset(set(committed))
    if not unique or not disjoint or not actual_committed:
        raise ValueError("final-reserve seeds collide internally or with prior experiments")
    return {
        "stage": "final_reserve",
        "schedule_seeds": schedule_seeds,
        "schedule_selection_used_only_frozen_fields": True,
        "layers": layer_values,
        "actual_seed_count": len(actual),
        "committed_seed_count": len(committed),
        "committed_seed_unique": unique,
        "all_actual_seeds_are_committed": actual_committed,
        "actual_seeds_disjoint_from_h16_and_h17p": disjoint,
        "legacy_process_seed_arithmetic_used": False,
        "explicit_process_resample_stream_used": True,
        "all_generation_calls_maximum_process_resamples": 1,
        "maximum_total_process_attempts_observed": max(
            int(record["total_attempt_count"])
            for records in process_attempts.values()
            for record in records
        ),
        "all_process_attempt_counts_within_frozen_limit": all(
            int(record["total_attempt_count"])
            <= int(config["seed_namespace"]["maximum_total_process_attempts"])
            for records in process_attempts.values()
            for record in records
        ),
    }


def _process_exhaustion_seed_audit(
    config: Mapping[str, Any],
    root: Path,
    error: ProcessLayerExhaustion,
    *,
    inspected_coverage_schedules: int,
    completed_layer_attempts: Mapping[str, Sequence[Mapping[str, Any]]],
    schedule_ordinals_by_layer: Mapping[str, Sequence[int]],
) -> dict[str, Any]:
    layer_order = ("natural_core", "coverage")
    if error.layer not in layer_order:
        raise ValueError("process exhaustion names an unknown layer")
    schedule_seeds = {
        "natural_core": [
            seed_for(config, layer="natural_core", stream="schedule", ordinal=value)
            for value in range(1, int(config["data"]["natural_core_blocks"]) + 1)
        ],
        "coverage_candidates": [
            seed_for(config, layer="coverage", stream="schedule", ordinal=value)
            for value in range(1, int(inspected_coverage_schedules) + 1)
        ],
    }
    actual: list[int] = [
        *schedule_seeds["natural_core"],
        *schedule_seeds["coverage_candidates"],
    ]
    committed: list[int] = list(actual)
    maximum_resamples = int(
        config["seed_namespace"]["maximum_process_resample_attempt"]
    )
    maximum_attempts = int(config["seed_namespace"]["maximum_total_process_attempts"])
    layer_values: dict[str, Any] = {}
    failed_layer_index = layer_order.index(error.layer)

    def requested_for(layer: str, rank: int, schedule_ordinal: int) -> BlockSeeds:
        return BlockSeeds(
            block_id=f"final_reserve_{layer}_block_{rank:03d}",
            forcing_seed=seed_for(
                config, layer=layer, stream="forcing", ordinal=rank
            ),
            process_seed=seed_for(
                config, layer=layer, stream="process", ordinal=rank
            ),
            observation_seed=seed_for(
                config, layer=layer, stream="observation", ordinal=rank
            ),
            schedule_seed=seed_for(
                config,
                layer=layer,
                stream="schedule",
                ordinal=schedule_ordinal,
            ),
        )

    def accepted_record(
        layer: str,
        rank: int,
        schedule_ordinal: int,
        saved: Mapping[str, Any],
    ) -> dict[str, Any]:
        requested = requested_for(layer, rank, schedule_ordinal)
        rejected = [int(value) for value in saved["rejected_process_seeds"]]
        accepted = int(saved["accepted_process_seed"])
        sequence = [requested.process_seed] + [
            seed_for(
                config,
                layer=layer,
                stream="process_resample",
                ordinal=rank * 1000 + attempt,
            )
            for attempt in range(1, maximum_resamples + 1)
        ]
        if (
            saved.get("block_id") != requested.block_id
            or int(saved.get("requested_process_seed", -1)) != requested.process_seed
            or rejected != sequence[: len(rejected)]
            or len(rejected) >= len(sequence)
            or accepted != sequence[len(rejected)]
            or int(saved.get("total_attempt_count", -1)) != len(rejected) + 1
        ):
            raise ValueError("a completed process-attempt record is not namespaced")
        return {
            "layer": layer,
            "block_rank": rank,
            "schedule_ordinal": int(schedule_ordinal),
            "block_id": requested.block_id,
            "requested_block_seeds": list(requested.all_seeds),
            "attempted_process_seeds": [*rejected, accepted],
            "rejected_process_seeds": rejected,
            "accepted_process_seed": accepted,
            "total_attempt_count": len(rejected) + 1,
            "outcome": "accepted",
        }

    for layer_index, layer in enumerate(layer_order):
        if layer_index > failed_layer_index:
            break
        ordinals = [int(value) for value in schedule_ordinals_by_layer[layer]]
        if layer_index < failed_layer_index:
            saved_records = list(completed_layer_attempts.get(layer, ()))
            if len(saved_records) != len(ordinals):
                raise ValueError("a completed physical layer is missing process-attempt records")
        else:
            saved_records = list(error.completed_attempts)
            if len(saved_records) != error.rank - 1 or not 1 <= error.rank <= len(ordinals):
                raise ValueError("the failed layer process-attempt prefix is incomplete")
        records = [
            accepted_record(layer, rank, ordinals[rank - 1], saved)
            for rank, saved in enumerate(saved_records, start=1)
        ]
        if layer == error.layer:
            requested = requested_for(
                layer, error.rank, ordinals[error.rank - 1]
            )
            attempted = [requested.process_seed] + [
                seed_for(
                    config,
                    layer=layer,
                    stream="process_resample",
                    ordinal=error.rank * 1000 + attempt,
                )
                for attempt in range(1, maximum_resamples + 1)
            ]
            if error.requested != requested or list(error.rejected) != attempted:
                raise ValueError("the exhausted process-attempt sequence is incomplete")
            records.append(
                {
                    "layer": layer,
                    "block_rank": error.rank,
                    "schedule_ordinal": ordinals[error.rank - 1],
                    "block_id": requested.block_id,
                    "requested_block_seeds": list(requested.all_seeds),
                    "attempted_process_seeds": attempted,
                    "rejected_process_seeds": attempted,
                    "accepted_process_seed": None,
                    "total_attempt_count": len(attempted),
                    "outcome": "exhausted",
                }
            )
        accepted_values = [
            int(record["accepted_process_seed"])
            for record in records
            if record["accepted_process_seed"] is not None
        ]
        rejected_values = [
            int(value)
            for record in records
            for value in record["rejected_process_seeds"]
        ]
        for record in records:
            forcing_seed, process_seed, observation_seed, _ = record[
                "requested_block_seeds"
            ]
            actual.extend(
                [
                    int(forcing_seed),
                    int(process_seed),
                    int(observation_seed),
                    *[int(value) for value in record["attempted_process_seeds"]],
                ]
            )
            rank = int(record["block_rank"])
            committed.extend(
                [int(forcing_seed), int(process_seed), int(observation_seed)]
            )
            committed.extend(
                seed_for(
                    config,
                    layer=layer,
                    stream="process_resample",
                    ordinal=rank * 1000 + attempt,
                )
                for attempt in range(1, maximum_resamples + 1)
            )
        layer_values[layer] = {
            "attempted_block_count": len(records),
            "completed_block_count": sum(
                record["outcome"] == "accepted" for record in records
            ),
            "failed_block_count": sum(
                record["outcome"] == "exhausted" for record in records
            ),
            "schedule_ordinals": [
                int(record["schedule_ordinal"]) for record in records
            ],
            "accepted_process_seeds": accepted_values,
            "rejected_process_seeds": rejected_values,
            "rejected_process_seed_count": len(rejected_values),
            "process_attempts": records,
        }
    old = _old_seed_set(config, root)
    unique = len(committed) == len(set(committed))
    disjoint = set(committed).isdisjoint(old)
    actual_committed = set(actual).issubset(set(committed))
    if not unique or not disjoint or not actual_committed:
        raise ValueError("process-exhaustion seeds collide internally or with prior experiments")
    all_records = [
        record
        for layer in layer_values.values()
        for record in layer["process_attempts"]
    ]
    return {
        "stage": "final_reserve",
        "outcome_scope": "physical_process_exhaustion",
        "physical_generation_started": True,
        "schedule_seeds": schedule_seeds,
        "schedule_selection_used_only_frozen_fields": True,
        "layers": layer_values,
        "process_exhaustion": {
            "layer": error.layer,
            "failed_block_rank": error.rank,
            "schedule_ordinal": error.schedule_ordinal,
            "block_id": error.requested.block_id,
        },
        "actual_seed_count": len(actual),
        "committed_seed_count": len(committed),
        "committed_seed_unique": unique,
        "all_actual_seeds_are_committed": actual_committed,
        "actual_seeds_disjoint_from_h16_and_h17p": disjoint,
        "legacy_process_seed_arithmetic_used": False,
        "explicit_process_resample_stream_used": True,
        "all_generation_calls_maximum_process_resamples": 1,
        "maximum_total_process_attempts_observed": max(
            int(record["total_attempt_count"]) for record in all_records
        ),
        "all_process_attempt_counts_within_frozen_limit": all(
            int(record["total_attempt_count"]) <= maximum_attempts
            for record in all_records
        ),
    }


def _schedule_only_seed_audit(
    config: Mapping[str, Any], root: Path, *, inspected_coverage_schedules: int
) -> dict[str, Any]:
    schedule_seeds = {
        "natural_core": [
            seed_for(config, layer="natural_core", stream="schedule", ordinal=value)
            for value in range(1, int(config["data"]["natural_core_blocks"]) + 1)
        ],
        "coverage_candidates": [
            seed_for(config, layer="coverage", stream="schedule", ordinal=value)
            for value in range(1, int(inspected_coverage_schedules) + 1)
        ],
    }
    committed = [*schedule_seeds["natural_core"], *schedule_seeds["coverage_candidates"]]
    old = _old_seed_set(config, root)
    return {
        "stage": "final_reserve",
        "outcome_scope": "schedule_only_before_coverage_decision",
        "schedule_seeds": schedule_seeds,
        "schedule_selection_used_only_frozen_fields": True,
        "actual_seed_count": len(committed),
        "committed_seed_count": len(committed),
        "committed_seed_unique": len(committed) == len(set(committed)),
        "all_actual_seeds_are_committed": True,
        "actual_seeds_disjoint_from_h16_and_h17p": set(committed).isdisjoint(old),
        "legacy_process_seed_arithmetic_used": False,
        "explicit_process_resample_stream_used": False,
        "all_generation_calls_maximum_process_resamples": None,
        "physical_generation_started": False,
    }


def _save_reserve_arrays(
    path: Path,
    layers: Mapping[str, tuple[H17DataSplit, Mapping[str, ProbabilityRolloutResult]]],
) -> None:
    values: dict[str, np.ndarray] = {}
    for layer, (split, results) in layers.items():
        values[f"{layer}_forcing"] = split.observable.forcing.cpu().numpy()
        values[f"{layer}_observations"] = split.observable.observations.cpu().numpy()
        values[f"{layer}_initial_states"] = split.observable.initial_states.cpu().numpy()
        values[f"{layer}_initial_covariances"] = split.observable.initial_covariances.cpu().numpy()
        values[f"{layer}_source_indices"] = split.supervision.source_indices.cpu().numpy()
        values[f"{layer}_target_probabilities"] = split.supervision.target_probabilities.cpu().numpy()
        values[f"{layer}_evaluation_mask"] = split.supervision.evaluation_mask.cpu().numpy()
        values[f"{layer}_switch_event_mask"] = split.supervision.switch_event_mask.cpu().numpy()
        values[f"{layer}_ages"] = split.supervision.regime_age_before_transition.cpu().numpy()
        for method, result in results.items():
            values[f"{layer}_{method}_transition_matrices"] = (
                result.transition_matrices.detach().cpu().numpy()
            )
    _write_npz(path, values)


def _save_generation_arrays(
    path: Path,
    layers: Mapping[str, LongHistoryParameterSwitchBatch],
) -> None:
    values: dict[str, np.ndarray] = {}
    for layer, batch in layers.items():
        for name in TENSOR_BATCH_FIELDS:
            values[f"{layer}_{name}"] = getattr(batch, name).detach().cpu().numpy()
        values[f"{layer}_block_ids"] = np.asarray(batch.block_ids, dtype=np.str_)
        values[f"{layer}_block_seed_matrix"] = np.asarray(
            [block.all_seeds for block in batch.block_seeds], dtype=np.int64
        )
        values[f"{layer}_accepted_process_seeds"] = np.asarray(
            batch.accepted_process_seeds, dtype=np.int64
        )
        values[f"{layer}_rejected_process_seeds"] = np.asarray(
            batch.rejected_process_seeds, dtype=np.int64
        )
    _write_npz(path, values)


def _checksums(directory: Path) -> dict[str, str]:
    return {
        path.name: _sha256(path)
        for path in sorted(directory.iterdir(), key=lambda value: value.name)
        if path.is_file() and path.name != "checksums.json" and not path.name.endswith(".tmp")
    }


def _environment_values() -> dict[str, Any]:
    return {
        "python": sys.version,
        "platform": platform.platform(),
        "numpy": np.__version__,
        "torch": torch.__version__,
        "torch_threads": torch.get_num_threads(),
    }


def _terminal_metrics_without_evaluation(outcome: str, reason: str) -> dict[str, Any]:
    return {
        "schema": "h17r_terminal_metrics_v1",
        "outcome": str(outcome),
        "evaluation_performed": False,
        "all_42_performance_conditions_passed": False,
        "passed_gate_count": None,
        "failed_gate_count": None,
        "reason": str(reason),
    }


def _terminal_registry_entry(
    root: Path,
    config: Mapping[str, Any],
    *,
    completion_status: str,
    outcome: str,
) -> dict[str, str]:
    row = dict(_registry_row(root, str(config["experiment_id"])))
    if row["status"] != config["registry_contract"]["eligible_status"]:
        raise ValueError("the live H17R registry row is not eligible at terminal freeze")
    row["status"] = str(completion_status)
    row["notes"] = f"{row['notes']}; frozen_terminal_outcome={outcome}"
    return row


def _open_bindings(
    config: Mapping[str, Any],
    eligibility: Mapping[str, Any],
    *,
    source_manifest_sha256: str,
    source_snapshot_sha256: str,
) -> dict[str, str]:
    return {
        "preregistration_manifest_sha256": str(
            eligibility["preregistration_manifest"]["sha256"]
        ),
        "live_config_sha256": str(
            eligibility["preregistration_manifest"]["live_config_sha256"]
        ),
        "eligible_registry_row_sha256": str(
            eligibility["eligible_registry_row_sha256"]
        ),
        "eligible_registry_file_sha256": str(
            eligibility["eligible_registry_file_sha256"]
        ),
        "immutable_registry_fields_sha256": str(
            eligibility["immutable_registry_fields_sha256"]
        ),
        "source_manifest_sha256": str(source_manifest_sha256),
        "source_snapshot_sha256": str(source_snapshot_sha256),
        "h17p_independent_verification_sha256": str(
            config["source_h17p"]["independent_verification_sha256"]
        ),
        "h17f_independent_verification_sha256": str(
            config["source_h17f"]["independent_verification_sha256"]
        ),
        "static_reference_checkpoint_sha256": str(
            config["static_reference"]["checkpoint_sha256"]
        ),
    }


def _final_h18_paths(root: Path) -> list[Path]:
    parent = root / "results/23_hbv_multilead_joint_uncertainty"
    if not parent.exists():
        return []
    return [
        path
        for path in parent.iterdir()
        if path.name.lstrip(".").lower().startswith("h18")
    ]


def _existing_h17r_result_paths(root: Path) -> list[Path]:
    parent = root / "results/23_hbv_multilead_joint_uncertainty"
    if not parent.exists():
        return []
    return [
        path
        for path in parent.iterdir()
        if path.name.lstrip(".").lower().startswith("h17r")
    ]


def _finalize_result(
    staging: Path,
    final: Path,
    root: Path,
    config: Mapping[str, Any],
    *,
    expected_files: Sequence[str],
    approved_preregistration_sha256: str,
) -> None:
    from hbv_history_conditioned_imm.scripts.verify_h17_fresh_reserved_confirmation import (
        verify_h17r_result,
    )

    before_verification = set(expected_files) - {
        "independent_verification.json",
        "checksums.json",
    }
    found_before = {path.name for path in staging.iterdir() if path.is_file()}
    if found_before != before_verification:
        raise RuntimeError("H17R pre-verification result file set changed")
    verification = verify_h17r_result(
        staging,
        project_root=root,
        verify_checksums=False,
        verify_live_registry=False,
        semantic_replay=True,
        approved_preregistration_sha256=approved_preregistration_sha256,
    )
    if verification.get("verified") is not True:
        raise RuntimeError("independent H17R semantic verification failed")
    _write_json(staging / "independent_verification.json", verification)
    _write_json(staging / "checksums.json", _checksums(staging))
    closure = verify_h17r_result(
        staging,
        project_root=root,
        verify_checksums=True,
        verify_live_registry=False,
        semantic_replay=False,
        approved_preregistration_sha256=approved_preregistration_sha256,
    )
    if closure.get("verified") is not True:
        raise RuntimeError("independent H17R file-closure verification failed")
    found = {path.name for path in staging.iterdir() if path.is_file()}
    if found != set(expected_files):
        raise RuntimeError("H17R terminal result file set changed")
    if _final_h18_paths(root):
        raise RuntimeError("H18 appeared before H17R atomic publication")
    if _lexists(final):
        raise FileExistsError("H17R final directory appeared before publication")
    staging.replace(final)
    postpublication = verify_h17r_result(
        final,
        project_root=root,
        verify_checksums=True,
        verify_live_registry=False,
        semantic_replay=False,
        approved_preregistration_sha256=approved_preregistration_sha256,
    )
    if postpublication.get("verified") is not True:
        raise RuntimeError("post-publication H17R file closure verification failed")


def _freeze_execution_hold(
    staging: Path,
    final: Path,
    root: Path,
    config: Mapping[str, Any],
    error: BaseException,
    *,
    approved_preregistration_sha256: str,
) -> None:
    # An unexpected post-open failure is deliberately not promoted into a
    # scientifically verified result. Preserve every existing artifact, add a
    # best-effort forensic note, and leave the permanent tombstone plus sealed
    # staging directory in place so this identifier can never be resumed.
    try:
        existing_files = sorted(
            path.name
            for path in staging.iterdir()
            if path.is_file() and not path.name.endswith(".tmp")
        )
        _write_json(
            staging / "unexpected_execution_failure.json",
            {
                "experiment_id": config["experiment_id"],
                "outcome": "burned_unpublished_execution_hold",
                "exception_type": type(error).__name__,
                "exception_message": str(error),
                "traceback": traceback.format_exc(),
                "artifacts_present_before_failure_note": existing_files,
                "evaluation_metrics_artifact_present": "metrics.json" in existing_files,
                "decision_artifact_present": "decision.json" in existing_files,
                "externally_approved_preregistration_sha256": (
                    approved_preregistration_sha256
                ),
                "phase_event_counts_not_claimed": True,
                "scientific_result_verified": False,
                "same_identifier_rerun_allowed": False,
                "h18_authorized": False,
            },
        )
    except BaseException:
        pass
    return
    try:
        _write_json(
            staging / "failure_report.json",
            {
                "experiment_id": config["experiment_id"],
                "decision": "EXECUTION_HOLD_RESERVE_BURNED",
                "exception_type": type(error).__name__,
                "exception_message": str(error),
                "traceback": traceback.format_exc(),
                "same_identifier_rerun_allowed": False,
                "h18_authorized": False,
            },
        )
        _write_json(
            staging / "decision.json",
            {
                "passed": False,
                "outcome": "execution_hold",
                "decision": "EXECUTION_HOLD_RESERVE_BURNED",
                "registry_completion_status": config["registry_contract"]["completion_status_hold"],
                "same_identifier_rerun_allowed": False,
                "threshold_change_allowed": False,
                "additional_sampling_allowed": False,
                "h18_authorized": False,
            },
        )
        _write_json(
            staging / "metrics.json",
            _terminal_metrics_without_evaluation(
                "execution_hold", "unexpected post-open execution failure"
            ),
        )
        _write_json(
            staging / "execution_audit.json",
            {
                "reserve_open_event_count": 1,
                "decision_bearing_schedule_generation_events": None,
                "postdecision_independent_schedule_replay_events": 0,
                "decision_bearing_physical_generation_events": None,
                "postdecision_independent_physical_replay_events": 0,
                "decision_bearing_evaluation_events": None,
                "production_checkpoint_load_count": None,
                "postdecision_semantic_checkpoint_load_count": 0,
                "checksum_only_verification_events": 2,
                "training_started": False,
                "optimizer_created": False,
                "checkpoint_selection_performed": False,
                "architecture_or_hyperparameter_selection_performed": False,
                "human_intermediate_target_or_score_inspection": False,
                "same_identifier_resume_or_retry_allowed": False,
                "h18_registered_or_run": False,
            },
        )
        _write_json(
            staging / "registry_entry.json",
            _terminal_registry_entry(
                root,
                config,
                completion_status=config["registry_contract"]["completion_status_hold"],
                outcome="execution_hold",
            ),
        )
        if not (staging / "environment.json").is_file():
            _write_json(staging / "environment.json", _environment_values())
        existing = {
            path.name
            for path in staging.iterdir()
            if path.is_file()
            and path.name
            not in {
                "partial_artifact_manifest.json",
                "checksums.json",
                "independent_verification.json",
            }
            and not path.name.endswith(".tmp")
        }
        manifest_files = sorted(existing | {"independent_verification.json"})
        _write_json(
            staging / "partial_artifact_manifest.json",
            {
                "outcome": "execution_hold",
                "files": manifest_files,
                "all_listed_files_must_be_checksummed": True,
            },
        )
        expected = [*manifest_files, "partial_artifact_manifest.json", "checksums.json"]
        _finalize_result(
            staging,
            final,
            root,
            config,
            expected_files=expected,
            approved_preregistration_sha256=approved_preregistration_sha256,
        )
    except BaseException:
        # The sealed directory and exclusive marker deliberately remain in place.
        return


def _publish_coverage_hold(
    staging: Path,
    final: Path,
    root: Path,
    config: Mapping[str, Any],
    *,
    inspected: int,
    approved_preregistration_sha256: str,
) -> None:
    seed_audit = _schedule_only_seed_audit(
        config, root, inspected_coverage_schedules=inspected
    )
    if (
        seed_audit["committed_seed_unique"] is not True
        or seed_audit["actual_seeds_disjoint_from_h16_and_h17p"] is not True
    ):
        raise ValueError("coverage-HOLD schedule seeds violate the frozen namespace")
    _write_json(staging / "seed_namespace_audit.json", seed_audit)
    decision = {
        "passed": False,
        "outcome": "coverage_hold",
        "decision": config["decision_contract"]["hold_decision"],
        "registry_completion_status": config["registry_contract"][
            "completion_status_hold"
        ],
        "coverage_passed": False,
        "all_42_performance_conditions_passed": False,
        "probability_legality_passed": None,
        "causality_passed": None,
        "same_identifier_rerun_allowed": False,
        "threshold_change_allowed": False,
        "additional_sampling_allowed": False,
        "h18_authorized": False,
    }
    execution = {
        "reserve_open_event_count": 1,
        "decision_bearing_schedule_generation_events": 1,
        "postdecision_independent_schedule_replay_events": 1,
        "decision_bearing_physical_generation_events": 0,
        "postdecision_independent_physical_replay_events": 0,
        "decision_bearing_evaluation_events": 0,
        "production_checkpoint_load_count": 0,
        "postdecision_semantic_checkpoint_load_count": 0,
        "checksum_only_verification_events": 2,
        "training_started": False,
        "optimizer_created": False,
        "checkpoint_selection_performed": False,
        "architecture_or_hyperparameter_selection_performed": False,
        "human_intermediate_target_or_score_inspection": False,
        "same_identifier_resume_or_retry_allowed": False,
        "h18_registered_or_run": False,
    }
    _write_json(staging / "decision.json", decision)
    _write_json(
        staging / "metrics.json",
        _terminal_metrics_without_evaluation(
            "coverage_hold", "frozen schedule-only rare-duration coverage was insufficient"
        ),
    )
    _write_json(staging / "execution_audit.json", execution)
    _write_json(
        staging / "registry_entry.json",
        _terminal_registry_entry(
            root,
            config,
            completion_status=config["registry_contract"]["completion_status_hold"],
            outcome="coverage_hold",
        ),
    )
    _finalize_result(
        staging,
        final,
        root,
        config,
        expected_files=config["coverage_hold_result_files"],
        approved_preregistration_sha256=approved_preregistration_sha256,
    )


def _publish_process_exhaustion_hold(
    staging: Path,
    final: Path,
    root: Path,
    config: Mapping[str, Any],
    error: ProcessLayerExhaustion,
    *,
    inspected: int,
    completed_layer_attempts: Mapping[str, Sequence[Mapping[str, Any]]],
    schedule_ordinals_by_layer: Mapping[str, Sequence[int]],
    approved_preregistration_sha256: str,
) -> None:
    seed_audit = _process_exhaustion_seed_audit(
        config,
        root,
        error,
        inspected_coverage_schedules=inspected,
        completed_layer_attempts=completed_layer_attempts,
        schedule_ordinals_by_layer=schedule_ordinals_by_layer,
    )
    if (
        seed_audit["physical_generation_started"] is not True
        or seed_audit["committed_seed_unique"] is not True
        or seed_audit["all_actual_seeds_are_committed"] is not True
        or seed_audit["actual_seeds_disjoint_from_h16_and_h17p"] is not True
        or seed_audit["all_process_attempt_counts_within_frozen_limit"] is not True
    ):
        raise ValueError("process-exhaustion seed audit failed")
    _write_json(staging / "seed_namespace_audit.json", seed_audit)
    failed_record = seed_audit["layers"][error.layer]["process_attempts"][-1]
    completed_records = [
        record
        for layer in seed_audit["layers"].values()
        for record in layer["process_attempts"]
        if record["outcome"] == "accepted"
    ]
    _write_json(
        staging / "process_exhaustion_audit.json",
        {
            "layer": error.layer,
            "failed_block_rank": error.rank,
            "schedule_ordinal": error.schedule_ordinal,
            "block_id": error.requested.block_id,
            "requested_block_seeds": list(error.requested.all_seeds),
            "attempted_process_seeds": failed_record["attempted_process_seeds"],
            "attempt_count": failed_record["total_attempt_count"],
            "maximum_total_process_attempts": int(
                config["seed_namespace"]["maximum_total_process_attempts"]
            ),
            "all_generation_calls_maximum_process_resamples": 1,
            "physical_generation_started": True,
            "completed_block_count_before_failure": len(completed_records),
            "attempted_block_count": len(completed_records) + 1,
            "completed_block_attempt_records": completed_records,
            "failed_block_attempt_record": failed_record,
            "all_layer_process_attempts": {
                layer: values["process_attempts"]
                for layer, values in seed_audit["layers"].items()
            },
            "seed_ledger_sha256": _mapping_sha256(seed_audit),
            "checkpoint_load_count": 0,
            "same_identifier_rerun_allowed": False,
        },
    )
    _write_json(
        staging / "failure_report.json",
        {
            "experiment_id": config["experiment_id"],
            "decision": "PROCESS_SEED_EXHAUSTION_HOLD_RESERVE_BURNED",
            "exception_type": type(error).__name__,
            "exception_message": str(error),
            "same_identifier_rerun_allowed": False,
            "h18_authorized": False,
        },
    )
    _write_json(
        staging / "decision.json",
        {
            "passed": False,
            "outcome": "process_exhaustion_hold",
            "decision": config["decision_contract"]["hold_decision"],
            "registry_completion_status": config["registry_contract"][
                "completion_status_hold"
            ],
            "coverage_passed": True,
            "all_42_performance_conditions_passed": False,
            "probability_legality_passed": None,
            "causality_passed": None,
            "same_identifier_rerun_allowed": False,
            "threshold_change_allowed": False,
            "additional_sampling_allowed": False,
            "h18_authorized": False,
        },
    )
    _write_json(
        staging / "metrics.json",
        _terminal_metrics_without_evaluation(
            "process_exhaustion_hold",
            "all 100 frozen process seeds were inadmissible for one reserve block",
        ),
    )
    _write_json(
        staging / "execution_audit.json",
        {
            "reserve_open_event_count": 1,
            "decision_bearing_schedule_generation_events": 1,
            "postdecision_independent_schedule_replay_events": 1,
            "decision_bearing_physical_generation_events": 1,
            "postdecision_independent_physical_replay_events": 1,
            "decision_bearing_evaluation_events": 0,
            "production_checkpoint_load_count": 0,
            "postdecision_semantic_checkpoint_load_count": 0,
            "checksum_only_verification_events": 2,
            "training_started": False,
            "optimizer_created": False,
            "checkpoint_selection_performed": False,
            "architecture_or_hyperparameter_selection_performed": False,
            "human_intermediate_target_or_score_inspection": False,
            "same_identifier_resume_or_retry_allowed": False,
            "h18_registered_or_run": False,
        },
    )
    _write_json(
        staging / "registry_entry.json",
        _terminal_registry_entry(
            root,
            config,
            completion_status=config["registry_contract"]["completion_status_hold"],
            outcome="process_exhaustion_hold",
        ),
    )
    existing = {
        path.name
        for path in staging.iterdir()
        if path.is_file()
        and path.name
        not in {
            "partial_artifact_manifest.json",
            "checksums.json",
            "independent_verification.json",
        }
        and not path.name.endswith(".tmp")
    }
    manifest_files = sorted(existing | {"independent_verification.json"})
    expected = list(config["process_exhaustion_hold_result_files"])
    expected_manifest_files = set(expected) - {
        "partial_artifact_manifest.json",
        "checksums.json",
    }
    if set(manifest_files) != expected_manifest_files:
        raise RuntimeError("process-exhaustion HOLD file set changed")
    _write_json(
        staging / "partial_artifact_manifest.json",
        {
            "outcome": "process_exhaustion_hold",
            "files": manifest_files,
            "all_listed_files_must_be_checksummed": True,
        },
    )
    _finalize_result(
        staging,
        final,
        root,
        config,
        expected_files=expected,
        approved_preregistration_sha256=approved_preregistration_sha256,
    )


def _legacy_incomplete_run_h17r_confirmation(
    config: Mapping[str, Any], *, project_root: str | Path
) -> Path:
    raise RuntimeError("the incomplete legacy H17R entry point is permanently disabled")
    root = Path(project_root).resolve()
    final = root / str(config["result_relative_path"])
    staging = final.parent / f".{config['experiment_id']}.staging-sealed"
    if final.exists() or staging.exists():
        raise FileExistsError("H17R final or sealed staging directory already exists")
    eligibility = preopen_eligibility_audit(config, project_root=root)
    h17f_root = root / str(config["source_h17f"]["result_directory"])
    h17_config = _read_json(h17f_root / "config_snapshot.json")
    source_manifest, source_zip = _source_snapshot_bytes(config, root)
    final.parent.mkdir(parents=True, exist_ok=True)
    staging.mkdir(exist_ok=False)
    _write_json(staging / "config_snapshot.json", dict(config))
    _write_json(staging / "eligibility_audit.json", eligibility)
    _write_json(staging / "source_manifest.json", source_manifest)
    (staging / "source_snapshot.zip").write_bytes(source_zip)
    _write_json(
        staging / "generator_contract.json",
        {
            "data": config["data"],
            "duration_hazard": config["duration_hazard"],
            "model_input_contract": config["model_input_contract"],
        },
    )
    _exclusive_open_marker(staging / "reserve_open_audit.json", config)
    try:
        natural_schedules = _natural_schedules(config)
        accepted_indices, coverage_schedules, coverage_counts, inspected = (
            select_final_coverage_schedules(config)
        )
        coverage_passed = _coverage_complete(coverage_counts, _thresholds(config))
        schedule_values = {
            **_stack_schedules(natural_schedules, "natural_core"),
            **_stack_schedules(coverage_schedules, "coverage"),
            "coverage_accepted_candidate_ordinals": np.asarray(
                accepted_indices, dtype=np.int64
            ),
        }
        _write_npz(staging / "schedule_arrays.npz", schedule_values)
        coverage_report = {
            "coverage_passed": coverage_passed,
            "candidate_schedules_inspected": inspected,
            "accepted_coverage_block_count": len(accepted_indices),
            "accepted_candidate_ordinals": accepted_indices,
            "counts": {name: values.tolist() for name, values in coverage_counts.items()},
            "thresholds": {
                name: values.tolist() for name, values in _thresholds(config).items()
            },
            "selection_used_only_frozen_schedule_fields": True,
            "checkpoint_load_count_before_coverage_pass": 0,
            "physical_generation_count_before_coverage_pass": 0,
            "h17p_preflight_accepted_blocks_reused": False,
        }
        _write_json(staging / "coverage_report.json", coverage_report)
        if not coverage_passed:
            raise RuntimeError("final-reserve rare-duration coverage thresholds failed")

        natural_batch = _generate_layer(
            config,
            h17_config,
            layer="natural_core",
            schedule_ordinals=list(range(1, len(natural_schedules) + 1)),
            expected_schedules=natural_schedules,
        )
        coverage_batch = _generate_layer(
            config,
            h17_config,
            layer="coverage",
            schedule_ordinals=accepted_indices,
            expected_schedules=coverage_schedules,
        )
        seed_audit = _seed_audit(config, root, natural_batch, coverage_batch)
        _write_json(staging / "seed_namespace_audit.json", seed_audit)
        maximum_projection = max(
            float(torch.max(torch.abs(natural_batch.projection_adjustments))),
            float(torch.max(torch.abs(coverage_batch.projection_adjustments))),
        )
        generation_audit = {
            "natural_core_block_count": len(natural_batch.block_ids),
            "coverage_block_count": len(coverage_batch.block_ids),
            "maximum_absolute_projection_adjustment": maximum_projection,
            "zero_projection_required": True,
            "all_physical_values_finite": all(
                bool(torch.isfinite(getattr(batch, name)).all())
                for batch in (natural_batch, coverage_batch)
                for name in TENSOR_BATCH_FIELDS
            ),
            "schedule_prefix_matches_preselected_schedules": True,
        }
        if maximum_projection != 0.0 or not generation_audit["all_physical_values_finite"]:
            raise ValueError("final-reserve physical generation contract failed")
        _write_json(staging / "generation_audit.json", generation_audit)

        static, networks, checkpoint_audit = _load_frozen_models(
            config, h17_config, root, staging
        )
        _write_json(staging / "checkpoint_integrity_audit.json", checkpoint_audit)
        days = int(config["data"]["assimilation_days"])
        natural_split = evaluation_split("natural_core", natural_batch, days=days)
        coverage_split = evaluation_split("coverage", coverage_batch, days=days)
        natural_results = _evaluate(
            natural_split, h17_config=h17_config, static=static, networks=networks
        )
        coverage_results = _evaluate(
            coverage_split, h17_config=h17_config, static=static, networks=networks
        )
        metrics, stratified, performance_passed = _score_and_decide(
            config,
            natural_split,
            coverage_split,
            natural_results,
            coverage_results,
        )
        legality = _legality(
            {"natural_core": natural_results, "coverage": coverage_results}
        )
        audit_count = int(config["evaluation_contract"]["causality_audit_natural_blocks"])
        audit_split = _slice_split(natural_split, audit_count)
        with torch.no_grad():
            audit_histories = {
                seed: (
                    network,
                    rollout_semi_markov_probability(
                        audit_split.observable,
                        audit_split.supervision,
                        network,
                        _estimator(h17_config, _parameter_candidates(h17_config)),
                    ),
                )
                for seed, network in networks.items()
            }
            causality = _causality_audit(
                audit_split,
                audit_histories,
                lambda: _estimator(h17_config, _parameter_candidates(h17_config)),
                forbidden_training_input_count=0,
                test_reads_before_selection=0,
            )
        causality_passed = (
            float(causality["maximum_current_observation_effect_on_same_day_transition"])
            == 0.0
            and float(causality["maximum_future_observation_effect_on_earlier_transition"])
            == 0.0
            and int(causality["forbidden_training_input_count"]) == 0
        )
        _write_json(staging / "metrics.json", metrics)
        _write_json(staging / "stratified_metrics.json", stratified)
        _write_json(staging / "probability_legality_audit.json", legality)
        _write_json(staging / "causality_audit.json", causality)
        _save_reserve_arrays(
            staging / "reserve_arrays.npz",
            {
                "natural_core": (natural_split, natural_results),
                "coverage": (coverage_split, coverage_results),
            },
        )
        passed = bool(performance_passed and legality["passed"] and causality_passed)
        decision_value = (
            config["decision_contract"]["pass_decision"]
            if passed
            else config["decision_contract"]["hold_decision"]
        )
        completion_status = (
            config["registry_contract"]["completion_status_pass"]
            if passed
            else config["registry_contract"]["completion_status_hold"]
        )
        decision = {
            "passed": passed,
            "decision": decision_value,
            "registry_completion_status": completion_status,
            "coverage_passed": coverage_passed,
            "all_42_performance_conditions_passed": performance_passed,
            "probability_legality_passed": bool(legality["passed"]),
            "causality_passed": causality_passed,
            "same_identifier_rerun_allowed": False,
            "threshold_change_allowed": False,
            "additional_sampling_allowed": False,
            "h18_authorized": False,
        }
        execution = {
            "reserve_open_event_count": 1,
            "schedule_generation_events": 1,
            "decision_bearing_evaluation_events": 1,
            "training_started": False,
            "optimizer_created": False,
            "checkpoint_selection_performed": False,
            "architecture_or_hyperparameter_selection_performed": False,
            "checkpoint_load_count_before_coverage_pass": 0,
            "production_checkpoint_load_count": 4,
            "human_intermediate_target_or_score_inspection": False,
            "same_identifier_resume_or_retry_allowed": False,
            "h18_registered_or_run": False,
        }
        _write_json(staging / "decision.json", decision)
        _write_json(staging / "execution_audit.json", execution)
        _write_json(
            staging / "environment.json",
            {
                "python": sys.version,
                "platform": platform.platform(),
                "numpy": np.__version__,
                "torch": torch.__version__,
                "torch_threads": torch.get_num_threads(),
            },
        )
        _write_json(staging / "registry_entry.json", _registry_row(root, config["experiment_id"]))

        from hbv_history_conditioned_imm.scripts.verify_h17_fresh_reserved_confirmation import (
            verify_h17r_result,
        )

        verification = verify_h17r_result(
            staging,
            project_root=root,
            verify_checksums=False,
            verify_live_registry=False,
        )
        if verification.get("verified") is not True:
            raise RuntimeError("independent H17R semantic verification failed")
        _write_json(staging / "independent_verification.json", verification)
        _write_json(staging / "checksums.json", _checksums(staging))
        final_verification = verify_h17r_result(
            staging,
            project_root=root,
            verify_checksums=True,
            verify_live_registry=False,
        )
        if final_verification.get("verified") is not True:
            raise RuntimeError("independent H17R checksum verification failed")
        found = {path.name for path in staging.iterdir() if path.is_file()}
        if found != set(config["required_result_files"]):
            raise RuntimeError("H17R successful result file set changed")
        staging.replace(final)
        print(f"H17R frozen result: {decision_value}", flush=True)
        return final
    except BaseException as error:
        _freeze_execution_hold(staging, final, config, error)
        raise


def run_h17r_confirmation(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    approved_preregistration_sha256: str,
) -> Path:
    """Execute the single decision-bearing reserve open with no resume path."""

    root = Path(project_root).resolve()
    approved_hash = _require_approved_preregistration_sha256(
        approved_preregistration_sha256
    )
    final = root / str(config["result_relative_path"])
    staging = final.parent / f".{config['experiment_id']}.staging-sealed"
    tombstone_path = _reserve_open_tombstone_path(root, config)
    if (
        _lexists(final)
        or _lexists(staging)
        or _lexists(tombstone_path)
        or _existing_h17r_result_paths(root)
    ):
        raise FileExistsError(
            "H17R final, sealed staging, or permanent reserve-open tombstone already exists"
        )
    eligibility = preopen_eligibility_audit(
        config,
        project_root=root,
        approved_preregistration_sha256=approved_hash,
    )
    h17f_root = root / str(config["source_h17f"]["result_directory"])
    h17_config_path = h17f_root / "config_snapshot.json"
    if _sha256(h17_config_path) != config["source_h17f"]["config_snapshot_sha256"]:
        raise ValueError("the frozen H17F config snapshot changed")
    h17_config = _read_json(h17_config_path)
    if (
        config["base_parameters"] != h17_config["base_parameters"]
        or config["parameter_candidates"] != h17_config["parameter_candidates"]
        or float(config["data"]["fixed_process_standard_deviation"])
        != float(h17_config["filter"]["common_process_standard_deviation"])
        or float(config["data"]["observation_standard_deviation"])
        != float(h17_config["filter"]["observation_standard_deviation"])
        or str(config["data"]["fixed_process_state_name"])
        != str(h17_config["filter"]["process_state_name"])
    ):
        raise ValueError("H17R factors differ from the frozen H17F model/data contract")
    source_manifest, source_zip = _source_snapshot_bytes(config, root)
    final.parent.mkdir(parents=True, exist_ok=True)
    staging.mkdir(exist_ok=False)
    marker_path = staging / "reserve_open_audit.json"
    try:
        generator_contract = {
            "data": config["data"],
            "duration_hazard": config["duration_hazard"],
            "model_input_contract": config["model_input_contract"],
        }
        registry_open_entry = dict(_registry_row(root, str(config["experiment_id"])))
        registry_path = (
            root / "src/hbv_history_conditioned_imm/configs/experiment_registry.csv"
        )
        registry_open_snapshot = registry_path.read_bytes()
        if (
            registry_open_entry.get("status")
            != config["registry_contract"]["eligible_status"]
            or _mapping_sha256(registry_open_entry)
            != eligibility["eligible_registry_row_sha256"]
            or hashlib.sha256(registry_open_snapshot).hexdigest()
            != eligibility["eligible_registry_file_sha256"]
        ):
            raise ValueError("the H17R registry row changed during pre-open preparation")
        environment = _environment_values()
        _write_json(staging / "config_snapshot.json", dict(config))
        _write_json(staging / "eligibility_audit.json", eligibility)
        _write_json(staging / "source_manifest.json", source_manifest)
        (staging / "source_snapshot.zip").write_bytes(source_zip)
        _write_json(staging / "generator_contract.json", generator_contract)
        _write_json(staging / "registry_open_entry.json", registry_open_entry)
        (staging / "registry_open_snapshot.csv").write_bytes(registry_open_snapshot)
        _write_json(staging / "environment.json", environment)
        base_hashes = _verified_preopen_base_artifact_hashes(
            staging,
            config=config,
            eligibility=eligibility,
            generator_contract=generator_contract,
            registry_open_entry=registry_open_entry,
            registry_open_snapshot=registry_open_snapshot,
            environment=environment,
            source_manifest=source_manifest,
            source_snapshot=source_zip,
        )
        bindings = {
            **_open_bindings(
                config,
                eligibility,
                source_manifest_sha256=hashlib.sha256(
                    _json_bytes(source_manifest)
                ).hexdigest(),
                source_snapshot_sha256=hashlib.sha256(source_zip).hexdigest(),
            ),
            **base_hashes,
            "externally_approved_preregistration_sha256": approved_hash,
        }
        tombstone_path.parent.mkdir(parents=True, exist_ok=True)
        _exclusive_open_tombstone(
            tombstone_path,
            config,
            bindings=bindings,
            final_path=final,
            staging_path=staging,
        )
        permanent_tombstone_sha256 = _sha256(tombstone_path)
        _exclusive_open_marker(
            marker_path,
            config,
            bindings={
                **bindings,
                "permanent_tombstone_sha256": permanent_tombstone_sha256,
            },
        )
        natural_schedules = _natural_schedules(config)
        (
            accepted_indices,
            coverage_schedules,
            coverage_counts,
            inspected,
            inspected_schedules,
        ) = select_final_coverage_schedules(config)
        days = int(config["data"]["assimilation_days"])
        coverage_passed = _coverage_complete(coverage_counts, _thresholds(config))
        schedule_values = {
            **_stack_schedules(natural_schedules, "natural_core", days=days),
            **_stack_schedules(coverage_schedules, "coverage", days=days),
            **_stack_schedules(
                inspected_schedules, "coverage_candidate_trace", days=days
            ),
            "coverage_accepted_candidate_ordinals": np.asarray(
                accepted_indices, dtype=np.int64
            ),
        }
        _write_npz(staging / "schedule_arrays.npz", schedule_values)
        coverage_report = {
            "coverage_passed": coverage_passed,
            "candidate_schedules_inspected": inspected,
            "accepted_coverage_block_count": len(accepted_indices),
            "accepted_candidate_ordinals": accepted_indices,
            "counts": {
                name: values.tolist() for name, values in coverage_counts.items()
            },
            "thresholds": {
                name: values.tolist() for name, values in _thresholds(config).items()
            },
            "selection_used_only_frozen_schedule_fields": True,
            "checkpoint_load_count_before_coverage_pass": 0,
            "physical_generation_count_before_coverage_pass": 0,
            "h17p_preflight_accepted_blocks_reused": False,
        }
        _write_json(staging / "coverage_report.json", coverage_report)
        if not coverage_passed:
            _publish_coverage_hold(
                staging,
                final,
                root,
                config,
                inspected=inspected,
                approved_preregistration_sha256=approved_hash,
            )
            print("H17R frozen result: coverage HOLD", flush=True)
            return final

        completed_layer_attempts: dict[str, Sequence[Mapping[str, Any]]] = {}
        natural_schedule_ordinals = list(range(1, len(natural_schedules) + 1))
        try:
            natural_batch, natural_attempts = _generate_layer(
                config,
                h17_config,
                layer="natural_core",
                schedule_ordinals=natural_schedule_ordinals,
                expected_schedules=natural_schedules,
            )
            completed_layer_attempts["natural_core"] = natural_attempts
            coverage_batch, coverage_attempts = _generate_layer(
                config,
                h17_config,
                layer="coverage",
                schedule_ordinals=accepted_indices,
                expected_schedules=coverage_schedules,
            )
        except ProcessLayerExhaustion as error:
            _publish_process_exhaustion_hold(
                staging,
                final,
                root,
                config,
                error,
                inspected=inspected,
                completed_layer_attempts=completed_layer_attempts,
                schedule_ordinals_by_layer={
                    "natural_core": natural_schedule_ordinals,
                    "coverage": accepted_indices,
                },
                approved_preregistration_sha256=approved_hash,
            )
            print("H17R frozen result: process-seed exhaustion HOLD", flush=True)
            return final

        process_attempts = {
            "natural_core": natural_attempts,
            "coverage": coverage_attempts,
        }
        seed_audit = _seed_audit(
            config,
            root,
            natural_batch,
            coverage_batch,
            process_attempts,
            inspected_coverage_schedules=inspected,
        )
        if (
            seed_audit["committed_seed_unique"] is not True
            or seed_audit["all_actual_seeds_are_committed"] is not True
            or seed_audit["actual_seeds_disjoint_from_h16_and_h17p"] is not True
            or seed_audit["all_process_attempt_counts_within_frozen_limit"] is not True
        ):
            raise ValueError("final-reserve seed audit failed")
        _write_json(staging / "seed_namespace_audit.json", seed_audit)
        _save_generation_arrays(
            staging / "generation_arrays.npz",
            {"natural_core": natural_batch, "coverage": coverage_batch},
        )
        maximum_projection = max(
            float(torch.max(torch.abs(natural_batch.projection_adjustments))),
            float(torch.max(torch.abs(coverage_batch.projection_adjustments))),
        )
        generation_audit = {
            "natural_core_block_count": len(natural_batch.block_ids),
            "coverage_block_count": len(coverage_batch.block_ids),
            "maximum_absolute_projection_adjustment": maximum_projection,
            "zero_projection_required": True,
            "all_physical_values_finite": all(
                bool(torch.isfinite(getattr(batch, name)).all())
                for batch in (natural_batch, coverage_batch)
                for name in TENSOR_BATCH_FIELDS
            ),
            "schedule_prefix_matches_preselected_schedules": True,
            "physical_days_per_block": days
            + int(config["data"]["maximum_forecast_lead"]),
        }
        if maximum_projection != 0.0 or not generation_audit["all_physical_values_finite"]:
            raise ValueError("final-reserve physical generation contract failed")
        _write_json(staging / "generation_audit.json", generation_audit)

        static, networks, checkpoint_audit = _load_frozen_models(
            config, h17_config, root, staging
        )
        _write_json(staging / "checkpoint_integrity_audit.json", checkpoint_audit)
        natural_split = evaluation_split("natural_core", natural_batch, days=days)
        coverage_split = evaluation_split("coverage", coverage_batch, days=days)
        natural_results = _evaluate(
            natural_split, h17_config=h17_config, static=static, networks=networks
        )
        coverage_results = _evaluate(
            coverage_split, h17_config=h17_config, static=static, networks=networks
        )
        metrics, stratified, performance_passed = _score_and_decide(
            config,
            natural_split,
            coverage_split,
            natural_results,
            coverage_results,
        )
        legality = _legality(
            {"natural_core": natural_results, "coverage": coverage_results}
        )
        audit_count = int(
            config["evaluation_contract"]["causality_audit_natural_blocks"]
        )
        audit_split = _slice_split(natural_split, audit_count)
        with torch.no_grad():
            audit_histories = {
                seed: (
                    network,
                    rollout_semi_markov_probability(
                        audit_split.observable,
                        audit_split.supervision,
                        network,
                        _estimator(h17_config, _parameter_candidates(h17_config)),
                    ),
                )
                for seed, network in networks.items()
            }
            causality = _causality_audit(
                audit_split,
                audit_histories,
                lambda: _estimator(h17_config, _parameter_candidates(h17_config)),
                forbidden_training_input_count=0,
                test_reads_before_selection=0,
            )
        causality_passed = (
            float(
                causality[
                    "maximum_current_observation_effect_on_same_day_transition"
                ]
            )
            == 0.0
            and float(
                causality["maximum_future_observation_effect_on_earlier_transition"]
            )
            == 0.0
            and int(causality["forbidden_training_input_count"]) == 0
        )
        _write_json(staging / "metrics.json", metrics)
        _write_json(staging / "stratified_metrics.json", stratified)
        _write_json(staging / "probability_legality_audit.json", legality)
        _write_json(staging / "causality_audit.json", causality)
        _save_reserve_arrays(
            staging / "reserve_arrays.npz",
            {
                "natural_core": (natural_split, natural_results),
                "coverage": (coverage_split, coverage_results),
            },
        )
        passed = bool(performance_passed and legality["passed"] and causality_passed)
        decision_value = (
            config["decision_contract"]["pass_decision"]
            if passed
            else config["decision_contract"]["hold_decision"]
        )
        completion_status = (
            config["registry_contract"]["completion_status_pass"]
            if passed
            else config["registry_contract"]["completion_status_hold"]
        )
        decision = {
            "passed": passed,
            "outcome": "complete_evaluation",
            "decision": decision_value,
            "registry_completion_status": completion_status,
            "coverage_passed": True,
            "all_42_performance_conditions_passed": performance_passed,
            "probability_legality_passed": bool(legality["passed"]),
            "causality_passed": causality_passed,
            "same_identifier_rerun_allowed": False,
            "threshold_change_allowed": False,
            "additional_sampling_allowed": False,
            "h18_authorized": False,
        }
        execution = {
            "reserve_open_event_count": 1,
            "decision_bearing_schedule_generation_events": 1,
            "postdecision_independent_schedule_replay_events": 1,
            "decision_bearing_physical_generation_events": 1,
            "postdecision_independent_physical_replay_events": 1,
            "decision_bearing_evaluation_events": 1,
            "production_checkpoint_load_count": 4,
            "postdecision_semantic_checkpoint_load_count": 4,
            "checksum_only_verification_events": 2,
            "training_started": False,
            "optimizer_created": False,
            "checkpoint_selection_performed": False,
            "architecture_or_hyperparameter_selection_performed": False,
            "checkpoint_load_count_before_coverage_pass": 0,
            "human_intermediate_target_or_score_inspection": False,
            "same_identifier_resume_or_retry_allowed": False,
            "h18_registered_or_run": False,
        }
        _write_json(staging / "decision.json", decision)
        _write_json(staging / "execution_audit.json", execution)
        _write_json(
            staging / "registry_entry.json",
            _terminal_registry_entry(
                root,
                config,
                completion_status=completion_status,
                outcome="complete_evaluation",
            ),
        )
        _finalize_result(
            staging,
            final,
            root,
            config,
            expected_files=config["required_result_files"],
            approved_preregistration_sha256=approved_hash,
        )
        print(f"H17R frozen result: {decision_value}", flush=True)
        return final
    except BaseException as error:
        if marker_path.is_file() and _lexists(staging) and not _lexists(final):
            _freeze_execution_hold(
                staging,
                final,
                root,
                config,
                error,
                approved_preregistration_sha256=approved_hash,
            )
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PACKAGE_ROOT.parents[1]))
    parser.add_argument("--approved-prereg-sha256", required=True)
    args = parser.parse_args()
    config = load_h17r_config(args.config)
    run_h17r_confirmation(
        config,
        project_root=args.project_root,
        approved_preregistration_sha256=args.approved_prereg_sha256,
    )


if __name__ == "__main__":
    main()
