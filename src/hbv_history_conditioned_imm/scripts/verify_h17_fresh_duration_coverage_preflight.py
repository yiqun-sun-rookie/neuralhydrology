"""Independently verify a schedule-only H17P coverage preflight."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
from typing import Any, Mapping
import zipfile

import numpy as np


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = PACKAGE_ROOT.parents[1]
STREAM_NAMES = (
    "schedule",
    "forcing",
    "process",
    "observation",
    "process_resample",
)
SCHEDULE_NAMES = (
    "mode_indices",
    "active_source_indices",
    "regime_age_before_transition",
    "transition_evaluation_mask",
)
EXPECTED_ARRAY_NAMES = {
    "natural_mode_indices",
    "natural_active_source_indices",
    "natural_regime_age_before_transition",
    "natural_transition_evaluation_mask",
    "natural_schedule_seeds",
    "natural_committed_stream_seeds",
    "coverage_mode_indices",
    "coverage_active_source_indices",
    "coverage_regime_age_before_transition",
    "coverage_transition_evaluation_mask",
    "coverage_schedule_seeds",
    "coverage_committed_stream_seeds",
    "accepted_candidate_indices",
    "parameter_ids",
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _seed(
    config: Mapping[str, Any],
    *,
    stage: str,
    layer: str,
    stream: str,
    ordinal: int,
) -> int:
    namespace = config["seed_namespace"]
    return (
        int(namespace["base"])
        + int(namespace["stage_codes"][stage])
        * int(namespace["stage_multiplier"])
        + int(namespace["layer_codes"][layer])
        * int(namespace["layer_multiplier"])
        + int(namespace["stream_codes"][stream])
        * int(namespace["stream_multiplier"])
        + int(ordinal)
    )


def _hazard(age: int, specification: Mapping[str, Any]) -> float:
    if age < int(specification["ramp_start_age"]):
        return float(specification["early_hazard"])
    if age <= int(specification["ramp_end_age"]):
        return float(specification["ramp_start_hazard"]) + float(
            specification["ramp_slope_per_day"]
        ) * (age - int(specification["ramp_start_age"]))
    return float(specification["late_hazard"])


def _schedule(
    *, seed: int, total_days: int, hazard: Mapping[str, Any]
) -> dict[str, np.ndarray]:
    generator = np.random.default_rng(int(seed))
    modes = np.empty(total_days, dtype=np.int64)
    sources = np.full(total_days, -1, dtype=np.int64)
    ages = np.zeros(total_days, dtype=np.int64)
    evaluated = np.zeros(total_days, dtype=np.bool_)
    modes[0] = int(generator.integers(0, 3))
    current_age = 1
    for day in range(1, total_days):
        source = int(modes[day - 1])
        sources[day] = source
        ages[day] = current_age
        evaluated[day] = True
        if float(generator.random()) < _hazard(current_age, hazard):
            alternatives = tuple(value for value in range(3) if value != source)
            modes[day] = alternatives[int(generator.integers(0, 2))]
            current_age = 1
        else:
            modes[day] = source
            current_age += 1
    return {
        "mode_indices": modes,
        "active_source_indices": sources,
        "regime_age_before_transition": ages,
        "transition_evaluation_mask": evaluated,
    }


def _counts(schedule: Mapping[str, np.ndarray]) -> dict[str, np.ndarray]:
    sources = schedule["active_source_indices"]
    ages = schedule["regime_age_before_transition"]
    evaluated = schedule["transition_evaluation_mask"]
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
            3,
            int(values["minimum_segments_reaching_50_per_source"]),
            dtype=np.int64,
        ),
        "distinct_50_plus_blocks": np.full(
            3,
            int(values["minimum_distinct_50_plus_blocks_per_source"]),
            dtype=np.int64,
        ),
    }


def _complete(
    counts: Mapping[str, np.ndarray], thresholds: Mapping[str, np.ndarray]
) -> bool:
    return all(np.all(counts[name] >= thresholds[name]) for name in thresholds)


def _reduces(
    candidate: Mapping[str, np.ndarray],
    counts: Mapping[str, np.ndarray],
    thresholds: Mapping[str, np.ndarray],
    names: tuple[str, ...],
) -> bool:
    return any(
        np.any((counts[name] < thresholds[name]) & (candidate[name] > 0))
        for name in names
    )


def _scan(config: Mapping[str, Any]) -> dict[str, Any]:
    days = int(config["data"]["assimilation_days"])
    maximum_candidates = int(
        config["coverage_selection"]["maximum_candidate_schedules"]
    )
    maximum_accepted = int(
        config["coverage_selection"]["maximum_accepted_coverage_blocks"]
    )
    thresholds = _thresholds(config)
    aggregate = {name: np.zeros(3, dtype=np.int64) for name in thresholds}
    accepted_indices: list[int] = []
    schedules: list[dict[str, np.ndarray]] = []
    inspected = 0
    accepted_limit = False
    for candidate_index in range(1, maximum_candidates + 1):
        if len(accepted_indices) >= maximum_accepted:
            accepted_limit = True
            break
        schedule = _schedule(
            seed=_seed(
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
        candidate = _counts(schedule)
        accept = _reduces(
            candidate,
            aggregate,
            thresholds,
            (
                "days_50_plus",
                "segments_reaching_50",
                "distinct_50_plus_blocks",
            ),
        )
        if not accept:
            accept = _reduces(
                candidate,
                aggregate,
                thresholds,
                ("days_40_to_49",),
            )
        if accept:
            accepted_indices.append(candidate_index)
            schedules.append(schedule)
            for name in aggregate:
                aggregate[name] += candidate[name]
        if _complete(aggregate, thresholds):
            break
    passed = _complete(aggregate, thresholds)
    return {
        "accepted_indices": accepted_indices,
        "schedules": schedules,
        "counts": aggregate,
        "inspected": inspected,
        "passed": passed,
        "candidate_limit_exhausted": not passed and inspected >= maximum_candidates,
        "accepted_limit_exhausted": not passed and accepted_limit,
    }


def _stack(
    schedules: list[Mapping[str, np.ndarray]], *, days: int
) -> dict[str, np.ndarray]:
    result = {}
    for name in SCHEDULE_NAMES:
        if schedules:
            result[name] = np.stack([schedule[name] for schedule in schedules])
        else:
            dtype = np.bool_ if name == "transition_evaluation_mask" else np.int64
            result[name] = np.empty((0, days), dtype=dtype)
    return result


def _stream_matrix(
    config: Mapping[str, Any],
    *,
    layer: str,
    schedule_ordinals: list[int],
) -> np.ndarray:
    rows = []
    for accepted_rank, schedule_ordinal in enumerate(schedule_ordinals, start=1):
        rows.append(
            [
                _seed(
                    config,
                    stage="preflight",
                    layer=layer,
                    stream=stream,
                    ordinal=(
                        schedule_ordinal
                        if stream == "schedule"
                        else accepted_rank * 1000 + 1
                        if stream == "process_resample"
                        else accepted_rank
                    ),
                )
                for stream in STREAM_NAMES
            ]
        )
    return np.asarray(rows, dtype=np.int64).reshape((-1, len(STREAM_NAMES)))


def _preflight_seed_values(
    config: Mapping[str, Any], *, natural_count: int, accepted: list[int]
) -> list[int]:
    maximum_attempt = int(config["seed_namespace"]["maximum_process_resample_attempt"])
    values: list[int] = []
    for layer, schedule_ordinals in (
        ("natural_core", list(range(1, natural_count + 1))),
        ("coverage", accepted),
    ):
        for rank, schedule_ordinal in enumerate(schedule_ordinals, start=1):
            values.append(
                _seed(
                    config,
                    stage="preflight",
                    layer=layer,
                    stream="schedule",
                    ordinal=schedule_ordinal,
                )
            )
            for stream in ("forcing", "process", "observation"):
                values.append(
                    _seed(
                        config,
                        stage="preflight",
                        layer=layer,
                        stream=stream,
                        ordinal=rank,
                    )
                )
            for attempt in range(1, maximum_attempt + 1):
                values.append(
                    _seed(
                        config,
                        stage="preflight",
                        layer=layer,
                        stream="process_resample",
                        ordinal=rank * 1000 + attempt,
                    )
                )
    return values


def _h16_seed_values(config: Mapping[str, Any]) -> tuple[list[int], bool]:
    source = config["source_h16_preflight_arrays"]
    path = (PROJECT_ROOT / str(source["path"])).resolve()
    source_hash_matches = path.is_file() and _sha256(path) == str(source["sha256"])
    if not source_hash_matches:
        return [], False
    with np.load(path, allow_pickle=False) as arrays:
        values = []
        for name in ("block_seeds", "accepted_process_seeds", "rejected_process_seeds"):
            values.extend(np.asarray(arrays[name], dtype=np.int64).reshape(-1).tolist())
    return [int(value) for value in values], True


def _expected_seed_audit(
    config: Mapping[str, Any], *, natural_count: int, accepted: list[int]
) -> dict[str, Any]:
    preflight = _preflight_seed_values(
        config, natural_count=natural_count, accepted=accepted
    )
    h16, source_hash_matches = _h16_seed_values(config)
    maximum_ordinal = int(config["seed_namespace"]["maximum_ordinal"])
    final_values = [
        _seed(
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
        "final_reserve_namespace_minimum_seed": min(final_values),
        "final_reserve_namespace_maximum_seed": max(final_values),
        "all_preflight_seeds_unique": len(preflight) == len(preflight_set),
        "preflight_disjoint_from_h16": source_hash_matches
        and not bool(preflight_set & h16_set),
        "preflight_disjoint_from_final_reserve": max(preflight) < min(final_values),
        "final_reserve_schedule_generated": False,
        "final_reserve_schedule_read_count": 0,
    }


def _expected_coverage_report(
    config: Mapping[str, Any], scan: Mapping[str, Any]
) -> dict[str, Any]:
    identifiers = tuple(str(value) for value in config["parameter_ids"])
    counts = scan["counts"]
    return {
        "natural_core_block_count": int(config["data"]["natural_core_blocks"]),
        "accepted_coverage_block_count": len(scan["accepted_indices"]),
        "candidate_schedules_inspected": int(scan["inspected"]),
        "maximum_candidate_schedules": int(
            config["coverage_selection"]["maximum_candidate_schedules"]
        ),
        "maximum_accepted_coverage_blocks": int(
            config["coverage_selection"]["maximum_accepted_coverage_blocks"]
        ),
        "coverage_thresholds": dict(config["coverage_thresholds"]),
        "coverage_by_source": {
            identifiers[source]: {
                name: int(values[source]) for name, values in counts.items()
            }
            for source in range(3)
        },
        "coverage_passed": bool(scan["passed"]),
        "candidate_limit_exhausted": bool(scan["candidate_limit_exhausted"]),
        "accepted_block_limit_exhausted": bool(
            scan["accepted_limit_exhausted"]
        ),
        "natural_core_and_selected_coverage_kept_separate": True,
    }


def _expected_registry_entry(
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


def _source_snapshot_checks(
    config: Mapping[str, Any], result_root: Path
) -> dict[str, bool]:
    manifest = json.loads((result_root / "source_manifest.json").read_text("utf-8"))
    expected_paths = sorted(
        Path(str(value)).as_posix() for value in config["source_snapshot"]["files"]
    )
    manifest_paths = [str(item["path"]) for item in manifest["entries"]]
    manifest_contract_matches = (
        manifest["format"] == "deterministic_zip_v1"
        and manifest["fixed_zip_timestamp"] == "1980-01-01T00:00:00"
        and int(manifest["source_file_count"]) == len(expected_paths)
        and manifest["snapshot_member_order"] == expected_paths
        and manifest_paths == expected_paths
    )
    archive_path = result_root / "source_snapshot.zip"
    archive_content_matches = True
    archive_metadata_deterministic = True
    live_source_matches = True
    archived_values: list[tuple[str, bytes]] = []
    with zipfile.ZipFile(archive_path, "r") as archive:
        information = archive.infolist()
        if [item.filename for item in information] != expected_paths:
            archive_content_matches = False
        for item, expected in zip(information, manifest["entries"]):
            data = archive.read(item.filename)
            archived_values.append((item.filename, data))
            archive_content_matches = archive_content_matches and (
                len(data) == int(expected["size_bytes"])
                and hashlib.sha256(data).hexdigest() == expected["sha256"]
            )
            archive_metadata_deterministic = archive_metadata_deterministic and (
                item.date_time == (1980, 1, 1, 0, 0, 0)
                and item.compress_type == zipfile.ZIP_DEFLATED
                and item.create_system == 3
                and (item.external_attr >> 16) == 0o100644
            )
            live_path = (PROJECT_ROOT / item.filename).resolve()
            live_source_matches = live_source_matches and (
                live_path.is_file() and live_path.read_bytes() == data
            )
    rebuilt = io.BytesIO()
    with zipfile.ZipFile(
        rebuilt,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for archive_name, data in archived_values:
            item = zipfile.ZipInfo(archive_name, date_time=(1980, 1, 1, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            item.create_system = 3
            item.external_attr = 0o100644 << 16
            archive.writestr(
                item,
                data,
                compress_type=zipfile.ZIP_DEFLATED,
                compresslevel=9,
            )
    return {
        "source_manifest_contract_matches": manifest_contract_matches,
        "source_snapshot_content_matches_manifest": archive_content_matches,
        "source_snapshot_metadata_is_deterministic": archive_metadata_deterministic,
        "source_snapshot_bytes_are_deterministic": rebuilt.getvalue()
        == archive_path.read_bytes(),
        "live_source_matches_snapshot": live_source_matches,
    }


def _live_registry_matches(
    config: Mapping[str, Any], expected_entry: Mapping[str, Any]
) -> bool:
    registry_path = (
        PROJECT_ROOT
        / "src/hbv_history_conditioned_imm/configs/experiment_registry.csv"
    )
    with registry_path.open("r", encoding="utf-8", newline="") as handle:
        rows = [
            row
            for row in csv.DictReader(handle)
            if row.get("exp_id") == config["experiment_id"]
        ]
    return len(rows) == 1 and all(
        rows[0].get(name, "") == str(expected_entry[name])
        for name in ("exp_id", "type", "status", "run_dir", "metrics_path")
    )


def verify_h17p_result(
    result_directory: str | Path,
    *,
    verify_checksums: bool = True,
    verify_live_registry: bool = False,
) -> dict[str, Any]:
    """Recompute H17P schedules, selection, coverage, seeds, and decision."""

    root = Path(result_directory).resolve()
    config = json.loads((root / "config_snapshot.json").read_text("utf-8"))
    required = set(str(value) for value in config["required_result_files"])
    found = {path.name for path in root.iterdir() if path.is_file()}
    expected_found = (
        required
        if verify_checksums
        else required - {"independent_verification.json", "checksums.json"}
    )
    exact_file_set = found == expected_found
    checksum_coverage = True
    checksum_ok = True
    if verify_checksums:
        path = root / "checksums.json"
        if not path.is_file():
            checksum_coverage = False
            checksum_ok = False
        else:
            checksums = json.loads(path.read_text("utf-8"))
            checksum_coverage = set(checksums) == required - {"checksums.json"}
            checksum_ok = checksum_coverage and all(
                (root / name).is_file() and _sha256(root / name) == value
                for name, value in checksums.items()
            )

    with np.load(root / "preflight_arrays.npz", allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    array_fields_exact = set(arrays) == EXPECTED_ARRAY_NAMES
    days = int(config["data"]["assimilation_days"])
    natural_count = int(config["data"]["natural_core_blocks"])
    natural_schedules = [
        _schedule(
            seed=_seed(
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
    natural_stacked = _stack(natural_schedules, days=days)
    expected_natural_schedule_seeds = np.asarray(
        [
            _seed(
                config,
                stage="preflight",
                layer="natural_core",
                stream="schedule",
                ordinal=ordinal,
            )
            for ordinal in range(1, natural_count + 1)
        ],
        dtype=np.int64,
    )
    natural_matches = all(
        np.array_equal(arrays[f"natural_{name}"], value)
        for name, value in natural_stacked.items()
    ) and np.array_equal(
        arrays["natural_schedule_seeds"], expected_natural_schedule_seeds
    )

    scan = _scan(config)
    accepted = np.asarray(scan["accepted_indices"], dtype=np.int64)
    selection_matches = np.array_equal(arrays["accepted_candidate_indices"], accepted)
    coverage_stacked = _stack(scan["schedules"], days=days)
    coverage_arrays_match = all(
        np.array_equal(arrays[f"coverage_{name}"], value)
        for name, value in coverage_stacked.items()
    )
    expected_coverage_schedule_seeds = np.asarray(
        [
            _seed(
                config,
                stage="preflight",
                layer="coverage",
                stream="schedule",
                ordinal=int(value),
            )
            for value in accepted
        ],
        dtype=np.int64,
    )
    committed_seed_matrices_match = (
        np.array_equal(
            arrays["natural_committed_stream_seeds"],
            _stream_matrix(
                config,
                layer="natural_core",
                schedule_ordinals=list(range(1, natural_count + 1)),
            ),
        )
        and np.array_equal(
            arrays["coverage_committed_stream_seeds"],
            _stream_matrix(
                config,
                layer="coverage",
                schedule_ordinals=scan["accepted_indices"],
            ),
        )
        and np.array_equal(
            arrays["coverage_schedule_seeds"], expected_coverage_schedule_seeds
        )
    )
    parameter_ids_match = np.array_equal(
        arrays["parameter_ids"], np.asarray(config["parameter_ids"], dtype=np.str_)
    )

    coverage_report = json.loads((root / "coverage_report.json").read_text("utf-8"))
    coverage_report_matches = coverage_report == _expected_coverage_report(
        config, scan
    )
    expected_registry = _expected_registry_entry(
        config, preflight_passed=bool(scan["passed"])
    )
    saved_registry = json.loads((root / "registry_entry.json").read_text("utf-8"))
    registry_artifact_matches = saved_registry == expected_registry
    live_registry_matches = (
        _live_registry_matches(config, expected_registry)
        if verify_live_registry
        else True
    )
    source_snapshot_checks = _source_snapshot_checks(config, root)
    saved_seed_audit = json.loads(
        (root / "seed_namespace_audit.json").read_text("utf-8")
    )
    expected_seed_audit = _expected_seed_audit(
        config,
        natural_count=natural_count,
        accepted=scan["accepted_indices"],
    )
    seed_audit_matches = saved_seed_audit == expected_seed_audit
    interface = json.loads(
        (root / "data_interface_audit.json").read_text("utf-8")
    )
    execution_matches = interface["execution"] == config["execution"] and config[
        "execution"
    ] == {
        "training_started": False,
        "checkpoint_loaded": False,
        "model_prediction_read_count": 0,
        "filter_loaded": False,
        "static_matrix_loaded": False,
        "optimizer_created": False,
        "final_reserve_schedule_read_count": 0,
    }
    schedule_only_fields = (
        interface["selection_input_fields"]
        == config["coverage_selection"]["selection_input_fields"]
        and int(interface["forbidden_selection_field_read_count"]) == 0
        and set(interface["saved_array_fields"]) == EXPECTED_ARRAY_NAMES
        and set(arrays) == EXPECTED_ARRAY_NAMES
    )
    generator_contract = json.loads(
        (root / "generator_contract.json").read_text("utf-8")
    )
    generator_contract_matches = (
        generator_contract["physical_data_generated"] is False
        and generator_contract["final_reserve_schedule_generated"] is False
        and generator_contract["candidate_order"] == "ascending"
        and generator_contract["candidate_selection_fields"]
        == config["coverage_selection"]["selection_input_fields"]
    )
    report = json.loads((root / "preflight_report.json").read_text("utf-8"))
    expected_pass = bool(scan["passed"]) and all(
        (
            expected_seed_audit["all_preflight_seeds_unique"],
            expected_seed_audit["preflight_disjoint_from_h16"],
            expected_seed_audit["preflight_disjoint_from_final_reserve"],
            schedule_only_fields,
            generator_contract_matches,
            expected_seed_audit["final_reserve_schedule_read_count"] == 0,
        )
    )
    expected_decision = (
        "GO_FOR_SEPARATELY_AUTHORIZED_FRESH_RESERVE"
        if expected_pass
        else "HOLD_FROZEN_COVERAGE_LIMIT_EXHAUSTED"
    )
    report_logic_matches = (
        bool(report["preflight_passed"]) == expected_pass
        and report["decision"] == expected_decision
        and report["expected_registry_completion_status"]
        == expected_registry["status"]
        and report["execution"] == config["execution"]
        and report["model_training_or_evaluation_performed"] is False
        and report["fresh_reserve_authorized"] is False
        and report["h18_registered_or_run"] is False
    )
    no_model_artifacts = not any(
        path.suffix == ".pt"
        or "checkpoint" in path.name
        or "prediction" in path.name
        or "metric" in path.name
        for path in root.iterdir()
    )
    checks = {
        "exact_required_file_set": exact_file_set,
        "checksum_coverage": checksum_coverage,
        "checksums": checksum_ok,
        "exact_schedule_only_array_fields": array_fields_exact,
        "natural_core_schedules_match": natural_matches,
        "ascending_candidate_selection_matches": selection_matches,
        "coverage_schedule_arrays_match": coverage_arrays_match,
        "committed_seed_matrices_match": committed_seed_matrices_match,
        "parameter_identifiers_match": parameter_ids_match,
        "coverage_report_matches": coverage_report_matches,
        "registry_entry_artifact_matches": registry_artifact_matches,
        "live_registry_completion_status_matches_or_is_deferred": live_registry_matches,
        **source_snapshot_checks,
        "seed_namespace_audit_matches": seed_audit_matches,
        "preflight_seed_disjoint_from_h16": bool(
            expected_seed_audit["preflight_disjoint_from_h16"]
        ),
        "preflight_seed_disjoint_from_final_reserve": bool(
            expected_seed_audit["preflight_disjoint_from_final_reserve"]
        ),
        "execution_contract_matches": execution_matches,
        "schedule_only_selection_fields_match": schedule_only_fields,
        "generator_contract_matches": generator_contract_matches,
        "preflight_decision_logic_matches": report_logic_matches,
        "no_model_or_checkpoint_artifacts": no_model_artifacts,
        "final_reserve_unread": bool(
            expected_seed_audit["final_reserve_schedule_read_count"] == 0
            and not expected_seed_audit["final_reserve_schedule_generated"]
        ),
    }
    return {
        "experiment_id": config["experiment_id"],
        "verified": all(checks.values()),
        "checksum_verification_requested": verify_checksums,
        "live_registry_verification_requested": verify_live_registry,
        "checks": checks,
        "independent_values": {
            "coverage_passed": bool(scan["passed"]),
            "candidate_schedules_inspected": int(scan["inspected"]),
            "accepted_coverage_block_count": len(scan["accepted_indices"]),
            "model_prediction_read_count": 0,
            "final_reserve_schedule_read_count": 0,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_directory")
    parser.add_argument("--verify-live-registry", action="store_true")
    arguments = parser.parse_args()
    print(
        json.dumps(
            verify_h17p_result(
                arguments.result_directory,
                verify_live_registry=arguments.verify_live_registry,
            ),
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
