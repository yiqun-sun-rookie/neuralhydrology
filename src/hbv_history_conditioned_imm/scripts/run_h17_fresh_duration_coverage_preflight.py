"""Build a schedule-only fresh-duration coverage preflight without models."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any, Mapping

import numpy as np

from hbv_history_conditioned_imm.long_history import generate_long_history_schedule
from hbv_history_conditioned_imm.scripts.verify_h17_fresh_duration_coverage_preflight import (
    verify_h17p_result,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = (
    PACKAGE_ROOT / "configs/h17p_fresh_duration_coverage_preflight_v01.json"
)
STREAM_NAMES = (
    "schedule",
    "forcing",
    "process",
    "observation",
    "process_resample",
)
SCHEDULE_ARRAY_NAMES = (
    "mode_indices",
    "active_source_indices",
    "regime_age_before_transition",
    "transition_evaluation_mask",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json(path: Path, values: Mapping[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(values, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def _write_arrays(path: Path, values: Mapping[str, np.ndarray]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("wb") as handle:
        np.savez_compressed(handle, **values)
    temporary.replace(path)


def _write_deterministic_source_snapshot(
    *, config: Mapping[str, Any], project_root: Path, staging: Path
) -> dict[str, Any]:
    snapshot = config["source_snapshot"]
    entries = []
    source_values: list[tuple[str, bytes]] = []
    for relative_name in sorted(str(value) for value in snapshot["files"]):
        source_path = (project_root / relative_name).resolve()
        try:
            source_path.relative_to(project_root)
        except ValueError as error:
            raise ValueError("H17P snapshot source escapes the project root") from error
        if not source_path.is_file():
            raise FileNotFoundError(f"H17P snapshot source is missing: {relative_name}")
        data = source_path.read_bytes()
        archive_name = Path(relative_name).as_posix()
        source_values.append((archive_name, data))
        entries.append(
            {
                "path": archive_name,
                "size_bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        )
    manifest = {
        "format": snapshot["format"],
        "fixed_zip_timestamp": snapshot["fixed_zip_timestamp"],
        "source_file_count": len(entries),
        "snapshot_member_order": [item["path"] for item in entries],
        "entries": entries,
    }
    _write_json(staging / "source_manifest.json", manifest)
    temporary = staging / "source_snapshot.zip.tmp"
    with zipfile.ZipFile(
        temporary,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for archive_name, data in source_values:
            information = zipfile.ZipInfo(
                archive_name, date_time=(1980, 1, 1, 0, 0, 0)
            )
            information.compress_type = zipfile.ZIP_DEFLATED
            information.create_system = 3
            information.external_attr = 0o100644 << 16
            archive.writestr(
                information,
                data,
                compress_type=zipfile.ZIP_DEFLATED,
                compresslevel=9,
            )
    temporary.replace(staging / "source_snapshot.zip")
    return manifest


def _validate_runtime_config(config: Mapping[str, Any]) -> None:
    required = {
        "experiment_id",
        "status",
        "publication_authorized",
        "scientific_question",
        "result_relative_path",
        "source_h16_preflight_arrays",
        "parameter_ids",
        "data",
        "duration_hazard",
        "coverage_selection",
        "coverage_thresholds",
        "seed_namespace",
        "final_reserve_contract",
        "registry_contract",
        "source_snapshot",
        "execution",
        "h18_registered_or_run",
        "required_result_files",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"H17P config is missing fields: {sorted(missing)}")
    data = config["data"]
    selection = config["coverage_selection"]
    thresholds = config["coverage_thresholds"]
    if (
        int(data["assimilation_days"]) < 51
        or int(data["natural_core_blocks"]) <= 0
        or int(data["candidate_count"]) != 3
        or selection["candidate_order"] != "ascending"
        or int(selection["maximum_candidate_schedules"]) <= 0
        or int(selection["maximum_accepted_coverage_blocks"]) <= 0
        or int(selection["maximum_accepted_coverage_blocks"])
        > int(selection["maximum_candidate_schedules"])
        or any(int(value) <= 0 for value in thresholds.values())
    ):
        raise ValueError("H17P data and coverage limits are invalid")
    expected_execution = {
        "training_started": False,
        "checkpoint_loaded": False,
        "model_prediction_read_count": 0,
        "filter_loaded": False,
        "static_matrix_loaded": False,
        "optimizer_created": False,
        "final_reserve_schedule_read_count": 0,
    }
    if dict(config["execution"]) != expected_execution:
        raise ValueError("H17P execution contract permits model or reserve access")
    if bool(config["h18_registered_or_run"]):
        raise ValueError("H17P cannot authorize H18")
    if (
        config["status"] != "registered_reserved_coverage_preflight"
        or bool(config["publication_authorized"]) is not True
        or config["registry_contract"]["registered_status"] != config["status"]
        or config["registry_contract"]["completion_status_go"]
        != "completed_reserved_coverage_preflight_go"
        or config["registry_contract"]["completion_status_hold"]
        != "completed_reserved_coverage_preflight_hold"
        or config["registry_contract"]["live_registry_written_by_runner"] is not False
    ):
        raise ValueError("H17P publication and registry contract is invalid")
    if tuple(config["parameter_ids"]) != (
        "slow_recession",
        "calibrated_recession",
        "fast_recession",
    ):
        raise ValueError("H17P requires the frozen ordered three-mode identifiers")
    expected_fields = list(SCHEDULE_ARRAY_NAMES)
    if list(selection["selection_input_fields"]) != expected_fields:
        raise ValueError("H17P selection fields differ from the schedule-only contract")
    namespace = config["seed_namespace"]
    if (
        len(set(namespace["stage_codes"].values())) != 2
        or len(set(namespace["layer_codes"].values())) != 2
        or len(set(namespace["stream_codes"].values())) != len(STREAM_NAMES)
        or set(namespace["stage_codes"]) != {"preflight", "final_reserve"}
        or set(namespace["layer_codes"]) != {"natural_core", "coverage"}
        or set(namespace["stream_codes"]) != set(STREAM_NAMES)
        or int(namespace["maximum_ordinal"]) < 256001
    ):
        raise ValueError("H17P seed namespace is incomplete")
    snapshot = config["source_snapshot"]
    snapshot_files = tuple(str(value) for value in snapshot["files"])
    if (
        snapshot["format"] != "deterministic_zip_v1"
        or snapshot["fixed_zip_timestamp"] != "1980-01-01T00:00:00"
        or not snapshot_files
        or len(snapshot_files) != len(set(snapshot_files))
        or any(
            Path(value).is_absolute() or ".." in Path(value).parts
            for value in snapshot_files
        )
    ):
        raise ValueError("H17P deterministic source snapshot contract is invalid")
    required_files = tuple(str(value) for value in config["required_result_files"])
    if len(required_files) != len(set(required_files)) or {
        "config_snapshot.json",
        "registry_entry.json",
        "preflight_arrays.npz",
        "coverage_report.json",
        "source_manifest.json",
        "source_snapshot.zip",
        "independent_verification.json",
        "checksums.json",
    } - set(required_files):
        raise ValueError("H17P required artifact set is invalid")


def load_h17p_config(path: str | Path) -> dict[str, Any]:
    """Load the implementation-only frozen H17P contract."""

    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    _validate_runtime_config(config)
    if config["experiment_id"] != "h17p_fresh_duration_coverage_preflight_v01":
        raise ValueError("unexpected H17P experiment identifier")
    return config


def seed_for(
    config: Mapping[str, Any],
    *,
    stage: str,
    layer: str,
    stream: str,
    ordinal: int,
) -> int:
    """Return one auditable 64-bit seed from the collision-free namespace."""

    namespace = config["seed_namespace"]
    if stage not in namespace["stage_codes"]:
        raise ValueError(f"unknown seed stage: {stage}")
    if layer not in namespace["layer_codes"]:
        raise ValueError(f"unknown seed layer: {layer}")
    if stream not in namespace["stream_codes"]:
        raise ValueError(f"unknown seed stream: {stream}")
    integer_ordinal = int(ordinal)
    if integer_ordinal != ordinal or not (
        1 <= integer_ordinal <= int(namespace["maximum_ordinal"])
    ):
        raise ValueError("seed ordinal is outside the frozen namespace")
    result = (
        int(namespace["base"])
        + int(namespace["stage_codes"][stage])
        * int(namespace["stage_multiplier"])
        + int(namespace["layer_codes"][layer])
        * int(namespace["layer_multiplier"])
        + int(namespace["stream_codes"][stream])
        * int(namespace["stream_multiplier"])
        + integer_ordinal
    )
    if result <= np.iinfo(np.uint32).max or result > np.iinfo(np.int64).max:
        raise ValueError("H17P seed is not inside the required 64-bit range")
    return result


def _schedule_counts(schedule: Any) -> dict[str, np.ndarray]:
    sources = np.asarray(schedule.active_source_indices, dtype=np.int64)
    ages = np.asarray(schedule.regime_age_before_transition, dtype=np.int64)
    evaluated = np.asarray(schedule.transition_evaluation_mask, dtype=np.bool_)
    days_40_to_49 = np.zeros(3, dtype=np.int64)
    days_50_plus = np.zeros(3, dtype=np.int64)
    segments_reaching_50 = np.zeros(3, dtype=np.int64)
    distinct_50_plus_blocks = np.zeros(3, dtype=np.int64)
    for source in range(3):
        active = evaluated & (sources == source)
        days_40_to_49[source] = np.count_nonzero(
            active & (ages >= 40) & (ages <= 49)
        )
        days_50_plus[source] = np.count_nonzero(active & (ages >= 50))
        segments_reaching_50[source] = np.count_nonzero(active & (ages == 50))
        distinct_50_plus_blocks[source] = int(days_50_plus[source] > 0)
    return {
        "days_40_to_49": days_40_to_49,
        "days_50_plus": days_50_plus,
        "segments_reaching_50": segments_reaching_50,
        "distinct_50_plus_blocks": distinct_50_plus_blocks,
    }


def _empty_counts() -> dict[str, np.ndarray]:
    return {
        name: np.zeros(3, dtype=np.int64)
        for name in (
            "days_40_to_49",
            "days_50_plus",
            "segments_reaching_50",
            "distinct_50_plus_blocks",
        )
    }


def _threshold_arrays(config: Mapping[str, Any]) -> dict[str, np.ndarray]:
    thresholds = config["coverage_thresholds"]
    return {
        "days_40_to_49": np.full(
            3, int(thresholds["minimum_40_to_49_days_per_source"]), dtype=np.int64
        ),
        "days_50_plus": np.full(
            3, int(thresholds["minimum_50_plus_days_per_source"]), dtype=np.int64
        ),
        "segments_reaching_50": np.full(
            3,
            int(thresholds["minimum_segments_reaching_50_per_source"]),
            dtype=np.int64,
        ),
        "distinct_50_plus_blocks": np.full(
            3,
            int(thresholds["minimum_distinct_50_plus_blocks_per_source"]),
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
    names: tuple[str, ...],
) -> bool:
    return any(
        np.any((counts[name] < thresholds[name]) & (candidate[name] > 0))
        for name in names
    )


def _select_coverage_schedules(
    config: Mapping[str, Any],
) -> tuple[list[int], list[Any], dict[str, np.ndarray], int, bool, bool]:
    selection = config["coverage_selection"]
    maximum_candidates = int(selection["maximum_candidate_schedules"])
    maximum_accepted = int(selection["maximum_accepted_coverage_blocks"])
    days = int(config["data"]["assimilation_days"])
    thresholds = _threshold_arrays(config)
    counts = _empty_counts()
    accepted_indices: list[int] = []
    accepted_schedules: list[Any] = []
    inspected = 0
    accepted_limit_exhausted = False
    for candidate_index in range(1, maximum_candidates + 1):
        if len(accepted_indices) >= maximum_accepted:
            accepted_limit_exhausted = True
            break
        schedule = generate_long_history_schedule(
            seed=seed_for(
                config,
                stage="preflight",
                layer="coverage",
                stream="schedule",
                ordinal=candidate_index,
            ),
            total_days=days,
            hazard=config["duration_hazard"],
        )
        inspected = candidate_index
        candidate_counts = _schedule_counts(schedule)
        accept = _reduces_gap(
            candidate_counts,
            counts,
            thresholds,
            (
                "days_50_plus",
                "segments_reaching_50",
                "distinct_50_plus_blocks",
            ),
        )
        if not accept:
            accept = _reduces_gap(
                candidate_counts,
                counts,
                thresholds,
                ("days_40_to_49",),
            )
        if accept:
            accepted_indices.append(candidate_index)
            accepted_schedules.append(schedule)
            for name in counts:
                counts[name] += candidate_counts[name]
        if _coverage_complete(counts, thresholds):
            break
    coverage_passed = _coverage_complete(counts, thresholds)
    candidate_limit_exhausted = not coverage_passed and inspected >= maximum_candidates
    return (
        accepted_indices,
        accepted_schedules,
        counts,
        inspected,
        candidate_limit_exhausted,
        accepted_limit_exhausted,
    )


def _stack_schedules(
    schedules: list[Any], *, days: int, prefix: str
) -> dict[str, np.ndarray]:
    result: dict[str, np.ndarray] = {}
    for name in SCHEDULE_ARRAY_NAMES:
        if schedules:
            value = np.stack([np.asarray(getattr(item, name)) for item in schedules])
        else:
            dtype = np.bool_ if name == "transition_evaluation_mask" else np.int64
            value = np.empty((0, days), dtype=dtype)
        result[f"{prefix}_{name}"] = value
    return result


def _committed_stream_seed_matrix(
    config: Mapping[str, Any],
    *,
    layer: str,
    schedule_ordinals: list[int],
) -> np.ndarray:
    rows = []
    for accepted_rank, schedule_ordinal in enumerate(schedule_ordinals, start=1):
        row = []
        for stream in STREAM_NAMES:
            if stream == "schedule":
                ordinal = schedule_ordinal
            elif stream == "process_resample":
                ordinal = accepted_rank * 1000 + 1
            else:
                ordinal = accepted_rank
            row.append(
                seed_for(
                    config,
                    stage="preflight",
                    layer=layer,
                    stream=stream,
                    ordinal=ordinal,
                )
            )
        rows.append(row)
    return np.asarray(rows, dtype=np.int64).reshape((-1, len(STREAM_NAMES)))


def _all_preflight_seeds(
    config: Mapping[str, Any],
    *,
    natural_count: int,
    accepted_indices: list[int],
) -> list[int]:
    result: list[int] = []
    maximum_attempt = int(config["seed_namespace"]["maximum_process_resample_attempt"])
    for layer, schedule_ordinals in (
        ("natural_core", list(range(1, natural_count + 1))),
        ("coverage", accepted_indices),
    ):
        for accepted_rank, schedule_ordinal in enumerate(schedule_ordinals, start=1):
            result.append(
                seed_for(
                    config,
                    stage="preflight",
                    layer=layer,
                    stream="schedule",
                    ordinal=schedule_ordinal,
                )
            )
            for stream in ("forcing", "process", "observation"):
                result.append(
                    seed_for(
                        config,
                        stage="preflight",
                        layer=layer,
                        stream=stream,
                        ordinal=accepted_rank,
                    )
                )
            for attempt in range(1, maximum_attempt + 1):
                result.append(
                    seed_for(
                        config,
                        stage="preflight",
                        layer=layer,
                        stream="process_resample",
                        ordinal=accepted_rank * 1000 + attempt,
                    )
                )
    return result


def _h16_seeds(config: Mapping[str, Any], root: Path) -> list[int]:
    source = config["source_h16_preflight_arrays"]
    path = (root / str(source["path"])).resolve()
    if _sha256(path) != str(source["sha256"]):
        raise ValueError("H17P frozen H16 seed source hash mismatch")
    with np.load(path, allow_pickle=False) as arrays:
        values = []
        for name in ("block_seeds", "accepted_process_seeds", "rejected_process_seeds"):
            values.extend(np.asarray(arrays[name], dtype=np.int64).reshape(-1).tolist())
    return [int(value) for value in values]


def _final_reserve_seed_interval(config: Mapping[str, Any]) -> tuple[int, int]:
    maximum_ordinal = int(config["seed_namespace"]["maximum_ordinal"])
    values = [
        seed_for(
            config,
            stage="final_reserve",
            layer=layer,
            stream=stream,
            ordinal=ordinal,
        )
        for layer in ("natural_core", "coverage")
        for stream in STREAM_NAMES
        for ordinal in (1, maximum_ordinal)
    ]
    return min(values), max(values)


def _seed_namespace_audit(
    config: Mapping[str, Any],
    *,
    root: Path,
    natural_count: int,
    accepted_indices: list[int],
) -> dict[str, Any]:
    preflight = _all_preflight_seeds(
        config,
        natural_count=natural_count,
        accepted_indices=accepted_indices,
    )
    h16 = _h16_seeds(config, root)
    final_minimum, final_maximum = _final_reserve_seed_interval(config)
    preflight_set = set(preflight)
    h16_set = set(h16)
    return {
        "seed_formula": config["seed_namespace"]["formula"],
        "preflight_seed_count": len(preflight),
        "preflight_unique_seed_count": len(preflight_set),
        "preflight_minimum_seed": min(preflight),
        "preflight_maximum_seed": max(preflight),
        "h16_seed_count": len(h16),
        "h16_minimum_seed": min(h16),
        "h16_maximum_seed": max(h16),
        "final_reserve_namespace_minimum_seed": final_minimum,
        "final_reserve_namespace_maximum_seed": final_maximum,
        "all_preflight_seeds_unique": len(preflight) == len(preflight_set),
        "preflight_disjoint_from_h16": not bool(preflight_set & h16_set),
        "preflight_disjoint_from_final_reserve": max(preflight) < final_minimum,
        "final_reserve_schedule_generated": False,
        "final_reserve_schedule_read_count": 0,
    }


def _coverage_report(
    config: Mapping[str, Any],
    *,
    counts: Mapping[str, np.ndarray],
    accepted_count: int,
    inspected: int,
    candidate_limit_exhausted: bool,
    accepted_limit_exhausted: bool,
) -> dict[str, Any]:
    parameter_ids = tuple(str(value) for value in config["parameter_ids"])
    by_source = {
        parameter_ids[source]: {
            name: int(values[source]) for name, values in counts.items()
        }
        for source in range(3)
    }
    passed = _coverage_complete(counts, _threshold_arrays(config))
    return {
        "natural_core_block_count": int(config["data"]["natural_core_blocks"]),
        "accepted_coverage_block_count": accepted_count,
        "candidate_schedules_inspected": inspected,
        "maximum_candidate_schedules": int(
            config["coverage_selection"]["maximum_candidate_schedules"]
        ),
        "maximum_accepted_coverage_blocks": int(
            config["coverage_selection"]["maximum_accepted_coverage_blocks"]
        ),
        "coverage_thresholds": dict(config["coverage_thresholds"]),
        "coverage_by_source": by_source,
        "coverage_passed": passed,
        "candidate_limit_exhausted": bool(candidate_limit_exhausted),
        "accepted_block_limit_exhausted": bool(accepted_limit_exhausted),
        "natural_core_and_selected_coverage_kept_separate": True,
    }


def _registry_entry(
    config: Mapping[str, Any], *, preflight_passed: bool
) -> dict[str, Any]:
    contract = config["registry_contract"]
    completion_status = str(
        contract[
            "completion_status_go" if preflight_passed else "completion_status_hold"
        ]
    )
    return {
        "exp_id": str(config["experiment_id"]),
        "type": str(contract["type"]),
        "hypothesis": str(config["scientific_question"]),
        "base_config": "h16_long_history_contract_preflight_v02",
        "changed_factor": "fresh disjoint seed namespace and schedule-only rare-duration coverage selection",
        "fixed_factors": "duration hazard; three source modes; 300-day horizon; schedule generator",
        "seeds": str(config["seed_namespace"]["formula"]),
        "status": completion_status,
        "registered_status_before_execution": str(contract["registered_status"]),
        "run_dir": str(config["result_relative_path"]),
        "best_checkpoint": "",
        "metrics_path": str(contract["metrics_relative_path"]),
        "paper_name": "fresh duration coverage preflight",
        "notes": "Schedule-only coverage decision; no filter, checkpoint, model prediction, or final reserve read.",
        "live_registry_written_by_runner": False,
    }


def run_fresh_duration_coverage_preflight(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    result_directory_override: str | Path | None = None,
) -> Path:
    """Generate and atomically verify schedule-only H17P evidence."""

    _validate_runtime_config(config)
    if not bool(config["publication_authorized"]):
        raise PermissionError("H17P publication remains unauthorized")
    root = Path(project_root).resolve()
    final_directory = (
        Path(result_directory_override).resolve()
        if result_directory_override is not None
        else (root / str(config["result_relative_path"])).resolve()
    )
    if final_directory.exists():
        raise FileExistsError(f"result directory already exists: {final_directory}")
    final_directory.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{config['experiment_id']}.staging-",
            dir=final_directory.parent,
        )
    )
    try:
        days = int(config["data"]["assimilation_days"])
        natural_count = int(config["data"]["natural_core_blocks"])
        natural_schedules = [
            generate_long_history_schedule(
                seed=seed_for(
                    config,
                    stage="preflight",
                    layer="natural_core",
                    stream="schedule",
                    ordinal=ordinal,
                ),
                total_days=days,
                hazard=config["duration_hazard"],
            )
            for ordinal in range(1, natural_count + 1)
        ]
        (
            accepted_indices,
            coverage_schedules,
            counts,
            inspected,
            candidate_limit_exhausted,
            accepted_limit_exhausted,
        ) = _select_coverage_schedules(config)
        coverage = _coverage_report(
            config,
            counts=counts,
            accepted_count=len(accepted_indices),
            inspected=inspected,
            candidate_limit_exhausted=candidate_limit_exhausted,
            accepted_limit_exhausted=accepted_limit_exhausted,
        )
        seed_audit = _seed_namespace_audit(
            config,
            root=root,
            natural_count=natural_count,
            accepted_indices=accepted_indices,
        )
        arrays = {
            **_stack_schedules(natural_schedules, days=days, prefix="natural"),
            "natural_schedule_seeds": np.asarray(
                [
                    seed_for(
                        config,
                        stage="preflight",
                        layer="natural_core",
                        stream="schedule",
                        ordinal=ordinal,
                    )
                    for ordinal in range(1, natural_count + 1)
                ],
                dtype=np.int64,
            ),
            "natural_committed_stream_seeds": _committed_stream_seed_matrix(
                config,
                layer="natural_core",
                schedule_ordinals=list(range(1, natural_count + 1)),
            ),
            **_stack_schedules(coverage_schedules, days=days, prefix="coverage"),
            "coverage_schedule_seeds": np.asarray(
                [
                    seed_for(
                        config,
                        stage="preflight",
                        layer="coverage",
                        stream="schedule",
                        ordinal=value,
                    )
                    for value in accepted_indices
                ],
                dtype=np.int64,
            ),
            "coverage_committed_stream_seeds": _committed_stream_seed_matrix(
                config,
                layer="coverage",
                schedule_ordinals=accepted_indices,
            ),
            "accepted_candidate_indices": np.asarray(
                accepted_indices, dtype=np.int64
            ),
            "parameter_ids": np.asarray(config["parameter_ids"], dtype=np.str_),
        }
        generator_contract = {
            "schedule_generator": (
                "hbv_history_conditioned_imm.long_history."
                "generate_long_history_schedule"
            ),
            "assimilation_days": days,
            "duration_hazard": dict(config["duration_hazard"]),
            "natural_core_blocks": natural_count,
            "candidate_order": "ascending",
            "candidate_selection_priority": list(
                config["coverage_selection"]["priority"]
            ),
            "candidate_selection_fields": list(
                config["coverage_selection"]["selection_input_fields"]
            ),
            "physical_data_generated": False,
            "final_reserve_schedule_generated": False,
        }
        interface_audit = {
            "selection_input_fields": list(
                config["coverage_selection"]["selection_input_fields"]
            ),
            "forbidden_selection_fields": list(
                config["coverage_selection"]["forbidden_selection_fields"]
            ),
            "forbidden_selection_field_read_count": 0,
            "saved_array_fields": sorted(arrays),
            "execution": dict(config["execution"]),
            "schedule_only_contract_passed": True,
        }
        gates = {
            "rare_duration_coverage": bool(coverage["coverage_passed"]),
            "preflight_seed_uniqueness": bool(
                seed_audit["all_preflight_seeds_unique"]
            ),
            "preflight_seed_disjoint_from_h16": bool(
                seed_audit["preflight_disjoint_from_h16"]
            ),
            "preflight_seed_disjoint_from_final_reserve": bool(
                seed_audit["preflight_disjoint_from_final_reserve"]
            ),
            "schedule_only_selection": bool(
                interface_audit["schedule_only_contract_passed"]
                and interface_audit["forbidden_selection_field_read_count"] == 0
            ),
            "natural_core_kept_separate": bool(
                coverage["natural_core_and_selected_coverage_kept_separate"]
            ),
            "final_reserve_unread": bool(
                seed_audit["final_reserve_schedule_read_count"] == 0
                and not seed_audit["final_reserve_schedule_generated"]
            ),
        }
        preflight_passed = all(gates.values())
        registry_entry = _registry_entry(
            config, preflight_passed=preflight_passed
        )
        report = {
            "experiment_id": config["experiment_id"],
            "preflight_passed": preflight_passed,
            "decision": (
                "GO_FOR_SEPARATELY_AUTHORIZED_FRESH_RESERVE"
                if preflight_passed
                else "HOLD_FROZEN_COVERAGE_LIMIT_EXHAUSTED"
            ),
            "gates": gates,
            "execution": dict(config["execution"]),
            "model_training_or_evaluation_performed": False,
            "fresh_reserve_authorized": False,
            "expected_registry_completion_status": registry_entry["status"],
            "h18_registered_or_run": False,
        }
        _write_json(staging / "config_snapshot.json", dict(config))
        _write_json(staging / "registry_entry.json", registry_entry)
        _write_json(staging / "generator_contract.json", generator_contract)
        _write_json(staging / "seed_namespace_audit.json", seed_audit)
        _write_arrays(staging / "preflight_arrays.npz", arrays)
        _write_json(staging / "coverage_report.json", coverage)
        _write_json(staging / "data_interface_audit.json", interface_audit)
        _write_json(staging / "preflight_report.json", report)
        _write_deterministic_source_snapshot(
            config=config, project_root=root, staging=staging
        )
        _write_json(
            staging / "environment.json",
            {
                "python": sys.version,
                "platform": platform.platform(),
                "numpy": np.__version__,
            },
        )
        required = set(str(value) for value in config["required_result_files"])
        expected_before_verification = required - {
            "independent_verification.json",
            "checksums.json",
        }
        found = {path.name for path in staging.iterdir() if path.is_file()}
        if found != expected_before_verification:
            raise RuntimeError("H17P staging artifact set is incomplete")
        independent = verify_h17p_result(staging, verify_checksums=False)
        if independent["verified"] is not True:
            raise ValueError("H17P independent staging verification failed")
        _write_json(staging / "independent_verification.json", independent)
        checksums = {
            name: _sha256(staging / name)
            for name in sorted(required - {"checksums.json"})
        }
        _write_json(staging / "checksums.json", checksums)
        found = {path.name for path in staging.iterdir() if path.is_file()}
        if found != required:
            raise RuntimeError("H17P final artifact set differs from the contract")
        published = verify_h17p_result(staging)
        if published["verified"] is not True:
            raise ValueError("H17P checksum verification failed before publication")
        staging.replace(final_directory)
        return final_directory
    except Exception as error:
        raise RuntimeError(
            f"H17P staging preserved after failure: {staging}"
        ) from error


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PACKAGE_ROOT.parents[1]))
    arguments = parser.parse_args()
    config = load_h17p_config(arguments.config)
    output = run_fresh_duration_coverage_preflight(
        config, project_root=arguments.project_root
    )
    print(output)


if __name__ == "__main__":
    main()
