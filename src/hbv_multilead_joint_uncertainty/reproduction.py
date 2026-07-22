"""Resilient per-basin reproduction of a frozen sixteen-basin result.

The numerical model and filtering code stay in the original frozen modules.  This
module adds only session binding, one-basin atomic execution, exact comparison,
and aggregation.
"""

from __future__ import annotations

import gc
import json
import os
import re
import shutil
import tempfile
from pathlib import Path, PureWindowsPath
from typing import Mapping, Sequence

import numpy as np
import pandas as pd

from hbv_joint_uncertainty.candidates import sha256_file
from hbv_joint_uncertainty.hbv_adapter import simulate_adapter

from .experiment import (
    CONTRACT_TABLE_FILES,
    _artifact_checksums,
    _dataframe_values_equal,
    _expected_candidate_ids,
    _validate_result_method_arrays,
    calculate_metrics,
    summarize_metrics,
    verify_contract_package,
)
from .input_audit import audit_evaluation_discharge
from .methods import METHOD_ORDER
from .orchestrator import _execution_signature, _verified_execution_signature
from .preparation import _load_complete_period, _load_forcing_only_period, _method_contract_parts
from .registry import RunRegistry
from .reporting import (
    _candidate_probability_tables,
    _lead_time_plot,
    build_study_report,
    paired_method_comparisons,
    write_result_diagnostics,
)
from .resource_monitor import ResourceRecorder, verify_resource_history_rows
from .runner import run_five_methods


EXPECTED_FORMAL_BASIN_COUNT = 16
EXPECTED_ARRAY_COUNT_PER_BASIN = 36
EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN = 366_960
EXPECTED_TOTAL_ARRAY_COUNT = EXPECTED_FORMAL_BASIN_COUNT * EXPECTED_ARRAY_COUNT_PER_BASIN
EXPECTED_TOTAL_NUMERIC_ELEMENT_COUNT = (
    EXPECTED_FORMAL_BASIN_COUNT * EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN
)
EXPECTED_FROZEN_NUMERICAL_SOURCE_FILE_COUNT = 37
EXPECTED_FROZEN_INPUT_FILE_COUNT = 62
EXPECTED_FORMAL_CONTRACT_ID = "formal_contract_sixteen_v05"
EXPECTED_REFERENCE_RESULT_ID = "formal_result_sixteen_v01"
EXPECTED_FORMAL_CONTRACT_CHECKSUMS_SHA256 = (
    "c7615c868b747d1b633eb5d32432376b5648087846d97d0ff5fa507ecdf4c357"
)
EXPECTED_REFERENCE_RESULT_CHECKSUMS_SHA256 = (
    "88ab2297e02179cc0e3e432c958871e1d6e7985358b9394970154a65f2348bd0"
)

REPRODUCTION_RESOURCE_ESTIMATES_GIB = {
    "session": {"estimated_peak_gib": 1.0, "estimated_output_gib": 0.1},
    "shard": {"estimated_peak_gib": 0.5, "estimated_output_gib": 0.05},
    "aggregation": {"estimated_peak_gib": 0.5, "estimated_output_gib": 0.1},
}

CONTROL_FILE_PATHS = (
    "src/hbv_multilead_joint_uncertainty/reproduction.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_reproduction.py",
    "test/test_hbv_multilead_reproduction.py",
)


def _safe_identifier(value: str) -> str:
    identifier = str(value)
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", identifier) is None:
        raise ValueError("identifier must use 1-128 letters, digits, dots, underscores, or hyphens")
    return identifier


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _resolve_repo_relative(repo_root: Path, supplied: str) -> Path:
    value = str(supplied)
    if Path(value).is_absolute() or bool(PureWindowsPath(value).anchor):
        raise ValueError("artifact path must be relative to the repository")
    root = Path(repo_root).resolve()
    resolved = (root / value).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise ValueError("artifact path escapes the repository") from error
    return resolved


def _repo_relative(repo_root: Path, path: Path) -> str:
    root = Path(repo_root).resolve()
    resolved = Path(path).resolve()
    try:
        return resolved.relative_to(root).as_posix()
    except ValueError as error:
        raise ValueError(f"path is outside the repository: {resolved}") from error


def _verify_artifact_checksums(directory: Path) -> dict[str, str]:
    path = Path(directory).resolve()
    checksum_path = path / "checksums.json"
    if not checksum_path.is_file():
        raise ValueError("artifact checksum file is missing")
    expected = json.loads(checksum_path.read_text(encoding="utf-8"))
    actual = _artifact_checksums(path)
    if expected != actual:
        differing = sorted(set(expected) | set(actual))
        differing = [key for key in differing if expected.get(key) != actual.get(key)]
        raise ValueError(f"artifact checksum mismatch: {differing[:10]}")
    return expected


def _verify_not_failed_or_incomplete(directory: Path, artifact: str) -> None:
    path = Path(directory)
    if path.name.startswith(".") and path.name.endswith(".incomplete"):
        raise ValueError(f"incomplete {artifact} artifact cannot verify as successful")
    if path.name.endswith(".failed") or (path / "failure.json").exists():
        raise ValueError(f"failed {artifact} artifact cannot verify as successful")


def _verify_content_hashes(directory: Path, expected: Mapping[str, str]) -> None:
    root = Path(directory).resolve()
    actual_names = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    if actual_names != set(expected):
        raise ValueError("frozen artifact file set changed")
    mismatches = [name for name, digest in expected.items() if sha256_file(root / name) != digest]
    if mismatches:
        raise ValueError(f"frozen artifact content changed: {mismatches[:10]}")


def capture_contract_identity(contract_directory: Path) -> dict:
    directory = Path(contract_directory).resolve()
    _verify_not_failed_or_incomplete(directory, "contract")
    checksum_path = directory / "checksums.json"
    expected = json.loads(checksum_path.read_text(encoding="utf-8"))
    _verify_content_hashes(directory, expected)
    manifest = json.loads((directory / "contract_manifest.json").read_text(encoding="utf-8"))
    basin_ids = [str(value).zfill(8) for value in manifest.get("basins", [])]
    if (
        manifest.get("artifact_type") != "calibration_only_uncertainty_contract"
        or int(manifest.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or len(basin_ids) != EXPECTED_FORMAL_BASIN_COUNT
        or len(set(basin_ids)) != EXPECTED_FORMAL_BASIN_COUNT
    ):
        raise ValueError("reproduction requires the complete sixteen-basin formal contract")
    return {
        "contract_id": str(manifest["contract_id"]),
        "basin_count": len(basin_ids),
        "basins": basin_ids,
        "checksums_sha256": sha256_file(checksum_path),
        "manifest_sha256": sha256_file(directory / "contract_manifest.json"),
        "content_files_sha256": expected,
    }


def capture_reference_identity(reference_directory: Path) -> dict:
    directory = Path(reference_directory).resolve()
    _verify_not_failed_or_incomplete(directory, "reference result")
    expected = _verify_artifact_checksums(directory)
    manifest = json.loads((directory / "result_manifest.json").read_text(encoding="utf-8"))
    basin_ids = [str(value).zfill(8) for value in manifest.get("basins", [])]
    if (
        manifest.get("artifact_type") != "diagnostic_hindcast_result"
        or int(manifest.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or len(basin_ids) != EXPECTED_FORMAL_BASIN_COUNT
        or len(set(basin_ids)) != EXPECTED_FORMAL_BASIN_COUNT
        or tuple(manifest.get("methods", [])) != METHOD_ORDER
    ):
        raise ValueError("reference result is not the complete frozen sixteen-basin result")
    basin_hashes = {}
    for basin_id in basin_ids:
        relative = f"basins/{basin_id}.npz"
        if relative not in expected:
            raise ValueError(f"reference result lacks basin array {basin_id}")
        basin_hashes[basin_id] = expected[relative]
    return {
        "experiment_id": str(manifest["experiment_id"]),
        "contract_id": str(manifest["contract_id"]),
        "basin_count": len(basin_ids),
        "basins": basin_ids,
        "checksums_sha256": sha256_file(directory / "checksums.json"),
        "manifest_sha256": sha256_file(directory / "result_manifest.json"),
        "basin_files_sha256": basin_hashes,
        "content_files_sha256": expected,
    }


def _snapshot_manifest_identity(repo_root: Path, reference_directory: Path) -> dict:
    root = Path(repo_root).resolve()
    reference = Path(reference_directory).resolve()
    manifest = json.loads((reference / "snapshot_manifest.json").read_text(encoding="utf-8"))
    groups = {}
    for category, expected_count in (
        ("source_files", EXPECTED_FROZEN_NUMERICAL_SOURCE_FILE_COUNT),
        ("input_files", EXPECTED_FROZEN_INPUT_FILE_COUNT),
    ):
        rows = list(manifest.get(category, []))
        if len(rows) != expected_count:
            raise ValueError(f"reference {category} count is not {expected_count}")
        hashes = {}
        for row in rows:
            relative = str(row["original_path"])
            current = _resolve_repo_relative(root, relative)
            snapshot = reference / str(row["snapshot_path"])
            expected_hash = str(row["sha256"])
            if (
                relative in hashes
                or not current.is_file()
                or not snapshot.is_file()
                or sha256_file(current) != expected_hash
                or sha256_file(snapshot) != expected_hash
            ):
                raise ValueError(f"reference-bound file changed or is duplicated: {relative}")
            hashes[relative] = expected_hash
        groups[category] = hashes
    control_hashes = {}
    for relative in CONTROL_FILE_PATHS:
        path = _resolve_repo_relative(root, relative)
        if not path.is_file():
            raise ValueError(f"reproduction control file is missing: {relative}")
        control_hashes[relative] = sha256_file(path)
    return {
        **groups,
        "control_files": control_hashes,
        "reference_snapshot_manifest_sha256": sha256_file(reference / "snapshot_manifest.json"),
    }


def _current_bound_file_hashes(repo_root: Path, identity: Mapping) -> dict[str, str]:
    root = Path(repo_root).resolve()
    expected = {}
    for category in ("source_files", "input_files", "control_files"):
        rows = dict(identity.get(category, {}))
        expected.update(rows)
    actual = {relative: sha256_file(_resolve_repo_relative(root, relative)) for relative in expected}
    if actual != expected:
        differing = sorted(key for key in expected if actual.get(key) != expected.get(key))
        raise ValueError(f"frozen source, input, or reproduction control file changed: {differing[:10]}")
    return actual


def compare_npz_exact(reference_path: Path, reproduced_path: Path) -> dict:
    reference_file = Path(reference_path).resolve()
    reproduced_file = Path(reproduced_path).resolve()
    with np.load(reference_file) as reference, np.load(reproduced_file) as reproduced:
        reference_names = tuple(reference.files)
        reproduced_names = tuple(reproduced.files)
        if set(reference_names) != set(reproduced_names):
            raise ValueError("reproduction array names differ from the reference")
        if len(reference_names) != EXPECTED_ARRAY_COUNT_PER_BASIN:
            raise ValueError("reproduction requires exactly 36 arrays per basin")
        numeric_element_count = 0
        details = []
        for name in reference_names:
            expected = reference[name]
            actual = reproduced[name]
            if expected.dtype != actual.dtype:
                raise ValueError(f"array {name} dtype differs from the reference")
            if expected.shape != actual.shape:
                raise ValueError(f"array {name} shape differs from the reference")
            if not np.array_equal(expected, actual):
                raise ValueError(f"array {name} differs from the reference")
            numeric_count = int(expected.size) if np.issubdtype(expected.dtype, np.number) else 0
            numeric_element_count += numeric_count
            details.append(
                {
                    "array_name": name,
                    "dtype": str(expected.dtype),
                    "shape": list(expected.shape),
                    "numeric_element_count": numeric_count,
                    "exact_equal": True,
                    "maximum_absolute_difference": 0.0 if numeric_count else None,
                }
            )
    return {
        "exact_equal": True,
        "array_count": len(reference_names),
        "numeric_element_count": numeric_element_count,
        "maximum_absolute_difference": 0.0,
        "reference_npz_sha256": sha256_file(reference_file),
        "reproduced_npz_sha256": sha256_file(reproduced_file),
        "arrays": details,
    }


def validate_verified_shard_set(
    expected_basin_ids: Sequence[str],
    shard_verifications: Sequence[Mapping],
    session_checksums_sha256: str,
) -> list[dict]:
    expected = [str(value).zfill(8) for value in expected_basin_ids]
    rows = [dict(row) for row in shard_verifications]
    if len(expected) != EXPECTED_FORMAL_BASIN_COUNT or len(rows) != EXPECTED_FORMAL_BASIN_COUNT:
        raise ValueError("aggregation requires exactly 16 formal basins and 16 successful shards")
    basin_ids = [str(row.get("basin_id", "")).zfill(8) for row in rows]
    if len(set(basin_ids)) != EXPECTED_FORMAL_BASIN_COUNT:
        raise ValueError("aggregation requires 16 unique shard basins")
    if set(basin_ids) != set(expected):
        raise ValueError("verified shard basins do not equal the frozen formal basin set")
    for row in rows:
        if row.get("status") != "verified":
            raise ValueError("every aggregation input shard must be verified")
        if row.get("session_checksums_sha256") != session_checksums_sha256:
            raise ValueError("aggregation shard session identity differs")
        if int(row.get("array_count", -1)) != EXPECTED_ARRAY_COUNT_PER_BASIN:
            raise ValueError("aggregation shard array count differs")
        if int(row.get("numeric_element_count", -1)) != EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN:
            raise ValueError("aggregation shard numeric element count differs")
        if float(row.get("maximum_absolute_difference", float("inf"))) != 0.0:
            raise ValueError("aggregation shard is not exactly equal to the reference")
    by_basin = {str(row["basin_id"]).zfill(8): row for row in rows}
    return [by_basin[basin_id] for basin_id in expected]


def _method_arrays(methods: Mapping, dates: np.ndarray, observations: np.ndarray, basin_contract: Mapping) -> dict:
    reference = methods["fixed_filter"]
    arrays = {
        "dates": np.asarray(dates, dtype="U10"),
        "observations": np.asarray(observations, dtype=np.float64),
        "lead_days": reference.lead_days,
        "origin_indices": reference.origin_indices,
        "target_indices": reference.target_indices,
        "origin_dates": np.asarray(dates, dtype="U10")[reference.origin_indices],
        "target_dates": np.asarray(dates, dtype="U10")[reference.target_indices],
        "target_observations": reference.target_observations,
    }
    expected_ids = _expected_candidate_ids(basin_contract)
    for method_name, method in methods.items():
        _validate_result_method_arrays(
            method_name=method_name,
            predictions=method.predictions,
            candidate_ids=method.candidate_ids,
            candidate_predictions=method.candidate_predictions,
            probabilities=method.probabilities,
            candidate_covariance_diagonals=method.candidate_covariance_diagonals,
            combined_covariance_diagonals=method.combined_covariance_diagonals,
            target_shape=reference.target_indices.shape,
            basin_id=str(basin_contract["basin_id"]),
            expected_candidate_ids=expected_ids[method_name],
        )
        arrays[f"{method_name}__predictions"] = method.predictions
        arrays[f"{method_name}__candidate_ids"] = np.asarray(method.candidate_ids, dtype="U128")
        arrays[f"{method_name}__candidate_predictions"] = method.candidate_predictions
        arrays[f"{method_name}__probabilities"] = method.probabilities
        if method.candidate_covariance_diagonals is not None:
            arrays[f"{method_name}__candidate_covariance_diagonals"] = method.candidate_covariance_diagonals
            arrays[f"{method_name}__combined_covariance_diagonals"] = method.combined_covariance_diagonals
    if len(arrays) != EXPECTED_ARRAY_COUNT_PER_BASIN:
        raise RuntimeError("computed basin output does not contain exactly 36 arrays")
    return arrays


def _recompute_basin(
    repo_root: Path,
    contract_directory: Path,
    basin_id: str,
    config: Mapping,
    recorder: ResourceRecorder,
) -> tuple[dict, dict]:
    root = Path(repo_root).resolve()
    contract = Path(contract_directory).resolve()
    evaluation_audit = audit_evaluation_discharge(root, basin_id, contract)
    if not evaluation_audit["passed"]:
        raise ValueError(f"basin {basin_id} failed evaluation input checks")
    basin_contract = json.loads(
        (contract / "basin_contracts" / f"{basin_id}.json").read_text(encoding="utf-8")
    )
    warmup = _load_forcing_only_period(
        root,
        basin_id,
        config,
        config["evaluation_warmup_start"],
        config["evaluation_warmup_end"],
    )
    evaluation, observations = _load_complete_period(
        root,
        basin_id,
        config,
        config["evaluation_start"],
        config["evaluation_end"],
    )
    if not np.all(np.isfinite(observations)):
        raise ValueError(f"basin {basin_id} has missing evaluation discharge")
    parameter_vectors, process_scales, process_covariances = _method_contract_parts(basin_contract)
    initial_states = {}
    for parameter_id, parameters in parameter_vectors.items():
        _, states = simulate_adapter(warmup[:, 0], warmup[:, 1], warmup[:, 2], parameters)
        initial_states[parameter_id] = states[-1]
    center_state = initial_states["trained_center"]
    initial_covariance = np.diag(
        (float(config["initial_covariance_fraction"]) * np.maximum(np.abs(center_state), 1.0))**2
    )
    methods = run_five_methods(
        forcing=evaluation,
        observations=observations,
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=basin_contract["process_noise"]["selected_process_id"],
        initial_states=initial_states,
        initial_covariance=initial_covariance,
        observation_standard_deviation=basin_contract["observation_noise"][
            "selected_standard_deviation_mm_day"
        ],
        factor_transition_stay_probability=float(config["factor_transition_stay_probability"]),
        interaction_mode=config["formal_interaction_mode"],
        lead_days=tuple(config["lead_days"]),
        progress_callback=lambda method, completed, total: recorder.checkpoint(
            "reproduction_progress",
            basin_id=basin_id,
            method=method,
            completed=completed,
            total=total,
        ),
    )
    dates = pd.date_range(config["evaluation_start"], config["evaluation_end"], freq="D")
    arrays = _method_arrays(
        methods,
        dates.strftime("%Y-%m-%d").to_numpy(),
        observations,
        basin_contract,
    )
    del methods, initial_states, process_covariances, evaluation, observations, warmup
    gc.collect()
    return arrays, evaluation_audit


def _bound_paths(repo_root: Path, identity: Mapping) -> tuple[list[Path], list[Path]]:
    root = Path(repo_root).resolve()
    source_relatives = [*identity["source_files"], *identity["control_files"]]
    input_relatives = list(identity["input_files"])
    return (
        [_resolve_repo_relative(root, relative) for relative in source_relatives],
        [_resolve_repo_relative(root, relative) for relative in input_relatives],
    )


def _verify_execution_binding(repo_root: Path, signature: Mapping, file_identity: Mapping) -> None:
    root = Path(repo_root).resolve()
    expected = {
        **dict(file_identity["source_files"]),
        **dict(file_identity["input_files"]),
        **dict(file_identity["control_files"]),
    }
    if signature.get("verified_unchanged_from_start_to_finish") is not True:
        raise ValueError("execution signature does not bind unchanged start and finish files")
    if dict(signature.get("files_sha256", {})) != expected:
        raise ValueError("execution signature does not equal the frozen source and input identity")
    _current_bound_file_hashes(root, file_identity)
    freshness = signature.get("source_process_freshness", {})
    process = signature.get("environment", {}).get("process", {})
    if (
        freshness.get("passed") is not True
        or freshness.get("process_create_time_unix_seconds") != process.get("create_time_unix_seconds")
        or float(freshness.get("latest_source_mtime_unix_seconds", float("inf")))
        > float(freshness.get("process_create_time_unix_seconds", float("-inf")))
        + float(freshness.get("maximum_clock_tolerance_seconds", 0.0))
    ):
        raise ValueError("execution signature does not prove a fresh source process")


def _verify_resource_history(history: Sequence[Mapping], config: Mapping, run_kind: str) -> dict:
    verified = verify_resource_history_rows(
        history,
        config["resource"],
        require_finish=True,
    )
    expected = REPRODUCTION_RESOURCE_ESTIMATES_GIB[run_kind]
    if (
        verified["estimated_peak_gib"] != expected["estimated_peak_gib"]
        or verified["estimated_output_gib"] != expected["estimated_output_gib"]
    ):
        raise ValueError(f"resource history does not match the fixed reproduction {run_kind} estimate")
    required_event = f"after_{run_kind}_content_verification"
    events = [str(row.get("event")) for row in history]
    if required_event not in events[:-1] or events[-1] != "finish":
        raise ValueError(f"resource history does not cover {run_kind} content verification before finish")
    return verified


def _registry_status(repo_root: Path, relative_path: str, run_id: str, required: str) -> dict:
    path = _resolve_repo_relative(repo_root, relative_path)
    record = json.loads(path.read_text(encoding="utf-8"))
    if record.get("run_id") != run_id or record.get("status") != required:
        raise ValueError(f"run registry is not closed with status {required}")
    return record


def verify_reproduction_session(
    session_directory: Path,
    repo_root: Path,
    *,
    _allow_incomplete: bool = False,
    _require_registry_verified: bool = True,
    _content_only: bool = False,
) -> dict:
    directory = Path(session_directory).resolve()
    if not _allow_incomplete:
        _verify_not_failed_or_incomplete(directory, "reproduction session")
    elif directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed reproduction session cannot verify as successful")
    if not _content_only:
        _verify_artifact_checksums(directory)
    manifest = json.loads((directory / "session_manifest.json").read_text(encoding="utf-8"))
    if (
        manifest.get("artifact_type") != "formal_reproduction_session"
        or manifest.get("status") != "verified"
        or int(manifest.get("frozen_numerical_source_file_count", -1))
        != EXPECTED_FROZEN_NUMERICAL_SOURCE_FILE_COUNT
        or int(manifest.get("frozen_input_file_count", -1)) != EXPECTED_FROZEN_INPUT_FILE_COUNT
        or int(manifest.get("control_file_count", -1)) != len(CONTROL_FILE_PATHS)
        or manifest.get("reference_arrays_are_comparison_only") is not True
        or manifest.get("reference_array_values_opened_during_session_preparation") is not False
    ):
        raise ValueError("reproduction session manifest is invalid")
    basin_ids = [str(value).zfill(8) for value in manifest.get("basins", [])]
    if (
        len(basin_ids) != EXPECTED_FORMAL_BASIN_COUNT
        or len(set(basin_ids)) != EXPECTED_FORMAL_BASIN_COUNT
        or int(manifest.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
    ):
        raise ValueError("reproduction session does not bind exactly 16 unique formal basins")
    root = Path(repo_root).resolve()
    contract = _resolve_repo_relative(root, manifest["contract_directory_repo_relative"])
    reference = _resolve_repo_relative(root, manifest["reference_directory_repo_relative"])
    contract_identity = capture_contract_identity(contract)
    reference_identity = capture_reference_identity(reference)
    if contract_identity != json.loads((directory / "contract_identity_start.json").read_text(encoding="utf-8")):
        raise ValueError("current contract identity differs from the reproduction-session start identity")
    if contract_identity != json.loads((directory / "contract_identity_end.json").read_text(encoding="utf-8")):
        raise ValueError("contract identity changed during reproduction-session preparation")
    if reference_identity != json.loads((directory / "reference_identity_start.json").read_text(encoding="utf-8")):
        raise ValueError("current reference identity differs from the reproduction-session start identity")
    if reference_identity != json.loads((directory / "reference_identity_end.json").read_text(encoding="utf-8")):
        raise ValueError("reference identity changed during reproduction-session preparation")
    if (
        contract_identity["contract_id"] != EXPECTED_FORMAL_CONTRACT_ID
        or contract_identity["checksums_sha256"] != EXPECTED_FORMAL_CONTRACT_CHECKSUMS_SHA256
        or reference_identity["experiment_id"] != EXPECTED_REFERENCE_RESULT_ID
        or reference_identity["checksums_sha256"] != EXPECTED_REFERENCE_RESULT_CHECKSUMS_SHA256
        or reference_identity["contract_id"] != contract_identity["contract_id"]
        or reference_identity["basins"] != contract_identity["basins"]
        or basin_ids != contract_identity["basins"]
    ):
        raise ValueError("reproduction session does not bind the required frozen formal artifacts")
    reference_contract = json.loads((reference / "contract_reference.json").read_text(encoding="utf-8"))
    reference_contract_value = str(reference_contract["contract_directory"])
    if Path(reference_contract_value).is_absolute() or bool(PureWindowsPath(reference_contract_value).anchor):
        raise ValueError("reference result contract path must be relative")
    reference_contract_path = (reference / reference_contract_value).resolve()
    if (
        reference_contract_path != contract
        or reference_contract.get("contract_checksums_sha256") != contract_identity["checksums_sha256"]
    ):
        raise ValueError("reference result does not point to the supplied frozen contract")
    file_identity = json.loads((directory / "bound_file_identity.json").read_text(encoding="utf-8"))
    if file_identity != _snapshot_manifest_identity(root, reference):
        raise ValueError("session-bound 37 source or 62 input files differ from the reference run")
    signature = json.loads((directory / "execution_signature.json").read_text(encoding="utf-8"))
    _verify_execution_binding(root, signature, file_identity)
    contract_verification = json.loads(
        (directory / "contract_full_verification.json").read_text(encoding="utf-8")
    )
    if (
        contract_verification.get("status") != "verified"
        or contract_verification.get("contract_id") != contract_identity["contract_id"]
        or int(contract_verification.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
    ):
        raise ValueError("session lacks one full scientific verification of the formal contract")
    config = json.loads((directory / "config_snapshot.json").read_text(encoding="utf-8"))
    if sha256_file(directory / "config_snapshot.json") != contract_identity["content_files_sha256"].get(
        "config_snapshot.json"
    ):
        raise ValueError("session configuration does not equal the frozen contract configuration")
    content_verification = {
        "status": "verified",
        "session_id": str(manifest["session_id"]),
        "basin_count": len(basin_ids),
        "basins": basin_ids,
        "contract_id": contract_identity["contract_id"],
        "contract_checksums_sha256": contract_identity["checksums_sha256"],
        "reference_experiment_id": reference_identity["experiment_id"],
        "reference_checksums_sha256": reference_identity["checksums_sha256"],
        "bound_numerical_source_file_count": len(file_identity["source_files"]),
        "bound_input_file_count": len(file_identity["input_files"]),
        "bound_control_file_count": len(file_identity["control_files"]),
        "contract_directory": str(contract),
        "reference_directory": str(reference),
    }
    if _content_only:
        return content_verification
    saved_content_verification = json.loads(
        (directory / "session_content_verification.json").read_text(encoding="utf-8")
    )
    if saved_content_verification != content_verification:
        raise ValueError("saved session content verification differs from independent recomputation")
    resource_history = json.loads((directory / "resource_history.json").read_text(encoding="utf-8"))
    resource_verification = _verify_resource_history(resource_history, config, "session")
    if _require_registry_verified:
        record = _registry_status(
            root,
            manifest["registry_record_repo_relative"],
            str(manifest["session_id"]),
            "verified",
        )
        terminal = record["history"][-1]
        if (
            Path(terminal.get("output_directory", "")).resolve() != directory
            or terminal.get("output_checksums_sha256") != sha256_file(directory / "checksums.json")
        ):
            raise ValueError("session registry terminal does not bind the verified output checksum")
    return {
        **content_verification,
        "resource_verification": resource_verification,
        "session_checksums_sha256": sha256_file(directory / "checksums.json"),
    }


def verify_reproduction_session_closure(
    session_directory: Path,
    repo_root: Path,
    *,
    allow_incomplete: bool = False,
    require_registry_verified: bool = True,
) -> dict:
    """Verify only immutable packaging, resource tail, and registry closure."""
    directory = Path(session_directory).resolve()
    if not allow_incomplete:
        _verify_not_failed_or_incomplete(directory, "reproduction session")
    elif directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed reproduction session cannot close as successful")
    _verify_artifact_checksums(directory)
    root = Path(repo_root).resolve()
    manifest = json.loads((directory / "session_manifest.json").read_text(encoding="utf-8"))
    content = json.loads(
        (directory / "session_content_verification.json").read_text(encoding="utf-8")
    )
    if (
        manifest.get("artifact_type") != "formal_reproduction_session"
        or manifest.get("status") != "verified"
        or content.get("status") != "verified"
        or content.get("session_id") != manifest.get("session_id")
        or int(content.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or len(content.get("basins", [])) != EXPECTED_FORMAL_BASIN_COUNT
        or int(manifest.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or [str(value).zfill(8) for value in manifest.get("basins", [])] != content.get("basins")
        or int(manifest.get("frozen_numerical_source_file_count", -1))
        != EXPECTED_FROZEN_NUMERICAL_SOURCE_FILE_COUNT
        or int(manifest.get("frozen_input_file_count", -1)) != EXPECTED_FROZEN_INPUT_FILE_COUNT
        or int(manifest.get("control_file_count", -1)) != len(CONTROL_FILE_PATHS)
        or manifest.get("reference_arrays_are_comparison_only") is not True
        or manifest.get("reference_array_values_opened_during_session_preparation") is not False
        or content.get("contract_id") != EXPECTED_FORMAL_CONTRACT_ID
        or content.get("contract_checksums_sha256") != EXPECTED_FORMAL_CONTRACT_CHECKSUMS_SHA256
        or content.get("reference_experiment_id") != EXPECTED_REFERENCE_RESULT_ID
        or content.get("reference_checksums_sha256")
        != EXPECTED_REFERENCE_RESULT_CHECKSUMS_SHA256
        or Path(content.get("contract_directory", "")).resolve()
        != _resolve_repo_relative(root, manifest["contract_directory_repo_relative"])
        or Path(content.get("reference_directory", "")).resolve()
        != _resolve_repo_relative(root, manifest["reference_directory_repo_relative"])
    ):
        raise ValueError("reproduction session content-verification closure is inconsistent")
    config = json.loads((directory / "config_snapshot.json").read_text(encoding="utf-8"))
    history = json.loads((directory / "resource_history.json").read_text(encoding="utf-8"))
    resource = _verify_resource_history(history, config, "session")
    if require_registry_verified:
        record = _registry_status(
            root,
            manifest["registry_record_repo_relative"],
            str(manifest["session_id"]),
            "verified",
        )
        terminal = record["history"][-1]
        if (
            Path(terminal.get("output_directory", "")).resolve() != directory
            or terminal.get("output_checksums_sha256") != sha256_file(directory / "checksums.json")
        ):
            raise ValueError("session registry terminal does not bind the output checksum")
    return {
        **content,
        "resource_verification": resource,
        "session_checksums_sha256": sha256_file(directory / "checksums.json"),
    }


def _preserve_failed_directory(temporary: Path, failed: Path, error: Exception) -> Path | None:
    temporary_path = Path(temporary)
    if not temporary_path.exists():
        return None
    _write_json(
        temporary_path / "failure.json",
        {
            "status": "failed",
            "error_type": type(error).__name__,
            "message": str(error),
        },
    )
    if failed.exists():
        raise FileExistsError(f"failed artifact path already exists: {failed}")
    os.replace(temporary_path, failed)
    return failed


def prepare_reproduction_session(
    repo_root: Path,
    contract_directory: Path,
    reference_directory: Path,
    session_id: str,
) -> dict:
    root = Path(repo_root).resolve()
    contract = Path(contract_directory).resolve()
    reference = Path(reference_directory).resolve()
    identifier = _safe_identifier(session_id)
    config = json.loads((contract / "config_snapshot.json").read_text(encoding="utf-8"))
    results_root = (root / config["results_root"]).resolve()
    output = results_root / identifier
    temporary = results_root / f".{identifier}.incomplete"
    failed = results_root / f"{identifier}.failed"
    if any(path.exists() for path in (output, temporary, failed)):
        raise FileExistsError(f"refusing to overwrite reproduction session {identifier}")
    registry = RunRegistry(results_root, identifier)
    registry.reserve("formal_reproduction_session")
    recorder = None
    try:
        temporary.mkdir(parents=True)
        recorder = ResourceRecorder(
            results_root,
            config["resource"],
            temporary / "resource_history.json",
        )
        recorder.start(**REPRODUCTION_RESOURCE_ESTIMATES_GIB["session"], session_id=identifier)
        reference_identity_start = capture_reference_identity(reference)
        contract_identity_start = capture_contract_identity(contract)
        file_identity = _snapshot_manifest_identity(root, reference)
        source_files, input_files = _bound_paths(root, file_identity)
        signature_start = _execution_signature(
            root,
            contract_identity_start["basins"],
            config,
            source_files,
            input_files,
            include_calibration_discharge=False,
        )
        recorder.checkpoint("before_full_contract_verification", force=True)
        contract_verification = verify_contract_package(contract)
        recorder.checkpoint("after_full_contract_verification", force=True)
        if (
            contract_verification.get("contract_id") != contract_identity_start["contract_id"]
            or int(contract_verification.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        ):
            raise ValueError("full contract verification returned a different formal identity")
        signature_end = _execution_signature(
            root,
            contract_identity_start["basins"],
            config,
            source_files,
            input_files,
            include_calibration_discharge=False,
        )
        signature = _verified_execution_signature(signature_start, signature_end)
        contract_identity_end = capture_contract_identity(contract)
        reference_identity_end = capture_reference_identity(reference)
        if contract_identity_start != contract_identity_end:
            raise RuntimeError("formal contract changed during reproduction-session preparation")
        if reference_identity_start != reference_identity_end:
            raise RuntimeError("reference result changed during reproduction-session preparation")
        shutil.copy2(contract / "config_snapshot.json", temporary / "config_snapshot.json")
        _write_json(temporary / "bound_file_identity.json", file_identity)
        _write_json(temporary / "execution_signature_start.json", signature_start)
        _write_json(temporary / "execution_signature_end.json", signature_end)
        _write_json(temporary / "execution_signature.json", signature)
        _write_json(temporary / "contract_identity_start.json", contract_identity_start)
        _write_json(temporary / "contract_identity_end.json", contract_identity_end)
        _write_json(temporary / "reference_identity_start.json", reference_identity_start)
        _write_json(temporary / "reference_identity_end.json", reference_identity_end)
        _write_json(temporary / "contract_full_verification.json", contract_verification)
        registry_relative = _repo_relative(root, registry.path)
        _write_json(
            temporary / "session_manifest.json",
            {
                "artifact_type": "formal_reproduction_session",
                "status": "verified",
                "session_id": identifier,
                "contract_directory_repo_relative": _repo_relative(root, contract),
                "reference_directory_repo_relative": _repo_relative(root, reference),
                "registry_record_repo_relative": registry_relative,
                "basin_count": EXPECTED_FORMAL_BASIN_COUNT,
                "basins": contract_identity_start["basins"],
                "frozen_numerical_source_file_count": EXPECTED_FROZEN_NUMERICAL_SOURCE_FILE_COUNT,
                "frozen_input_file_count": EXPECTED_FROZEN_INPUT_FILE_COUNT,
                "control_file_count": len(CONTROL_FILE_PATHS),
                "reference_arrays_are_comparison_only": True,
                "reference_array_values_opened_during_session_preparation": False,
            },
        )
        content_verification = verify_reproduction_session(
            temporary,
            root,
            _allow_incomplete=True,
            _require_registry_verified=False,
            _content_only=True,
        )
        _write_json(temporary / "session_content_verification.json", content_verification)
        recorder.checkpoint("after_session_content_verification", force=True)
        recorder.finish(session_id=identifier)
        _write_json(temporary / "checksums.json", _artifact_checksums(temporary))
        verify_reproduction_session_closure(
            temporary,
            root,
            allow_incomplete=True,
            require_registry_verified=False,
        )
        os.replace(temporary, output)
        registry.update(
            "verified",
            output_directory=str(output),
            output_checksums_sha256=sha256_file(output / "checksums.json"),
        )
        verification = verify_reproduction_session_closure(output, root)
        return {**verification, "output_directory": str(output)}
    except Exception as error:
        if recorder is not None:
            try:
                recorder.abort()
            except Exception:
                pass
        if output.exists() and not failed.exists():
            os.replace(output, failed)
            _write_json(failed / "failure.json", {"status": "failed", "message": str(error)})
        elif temporary.exists():
            _preserve_failed_directory(temporary, failed, error)
        try:
            registry.update("failed", error_type=type(error).__name__, message=str(error))
        except Exception:
            pass
        raise


def _verify_shard_log(
    log_directory: Path,
    repo_root: Path,
    config: Mapping,
    shard_id: str,
    result_directory: Path,
    *,
    allow_incomplete: bool = False,
    declared_result_directory: Path | None = None,
) -> dict:
    directory = Path(log_directory).resolve()
    if not allow_incomplete:
        _verify_not_failed_or_incomplete(directory, "reproduction shard log")
    elif directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed reproduction shard log cannot verify as successful")
    _verify_artifact_checksums(directory)
    summary = json.loads((directory / "run_summary.json").read_text(encoding="utf-8"))
    if (
        summary.get("status") != "verified"
        or summary.get("shard_id") != shard_id
        or _resolve_repo_relative(repo_root, summary["result_directory_repo_relative"])
        != (
            Path(declared_result_directory).resolve()
            if declared_result_directory is not None
            else Path(result_directory).resolve()
        )
    ):
        raise ValueError("reproduction shard log summary is not bound to the result package")
    history_path = directory / "resource_history.json"
    if summary.get("resource_history_sha256") != sha256_file(history_path):
        raise ValueError("reproduction shard log resource checksum differs")
    history = json.loads(history_path.read_text(encoding="utf-8"))
    resource = _verify_resource_history(history, config, "shard")
    if (
        int(summary.get("resource_sample_count", -1)) != resource["sample_count"]
        or summary.get("resource_last_event") != "finish"
        or summary.get("resource_monitor_covers_compute_save_compare_and_content_verification")
        is not True
    ):
        raise ValueError("reproduction shard log does not close its resource history")
    return resource


def verify_reproduction_shard(
    shard_directory: Path,
    session_directory: Path,
    repo_root: Path,
    *,
    _allow_incomplete: bool = False,
    _log_directory_override: Path | None = None,
    _published_result_directory_override: Path | None = None,
    _require_registry_verified: bool = True,
    _content_only: bool = False,
) -> dict:
    directory = Path(shard_directory).resolve()
    if not _allow_incomplete:
        _verify_not_failed_or_incomplete(directory, "reproduction shard")
    elif directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed reproduction shard cannot verify as successful")
    if not _content_only:
        _verify_artifact_checksums(directory)
    root = Path(repo_root).resolve()
    session = Path(session_directory).resolve()
    session_verification = verify_reproduction_session(session, root)
    manifest = json.loads((directory / "shard_manifest.json").read_text(encoding="utf-8"))
    if manifest.get("artifact_type") != "formal_reproduction_basin_shard":
        raise ValueError("reproduction shard manifest is invalid")
    shard_id = str(manifest["shard_id"])
    basin_id = str(manifest["basin_id"]).zfill(8)
    if (
        manifest.get("status") != "verified"
        or tuple(manifest.get("methods", [])) != METHOD_ORDER
        or list(manifest.get("lead_days", [])) != [1, 3, 7]
        or int(manifest.get("array_count", -1)) != EXPECTED_ARRAY_COUNT_PER_BASIN
        or int(manifest.get("numeric_element_count", -1))
        != EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN
        or manifest.get("failed_run_arrays_reused") is not False
        or manifest.get("reference_opened_only_after_recomputed_array_save") is not True
    ):
        raise ValueError("reproduction shard manifest methods, leads, or counts are invalid")
    if basin_id not in session_verification["basins"]:
        raise ValueError("reproduction shard basin is absent from the formal contract")
    if _resolve_repo_relative(root, manifest["session_directory_repo_relative"]) != session:
        raise ValueError("reproduction shard points to a different session")
    session_checksum = sha256_file(session / "checksums.json")
    if manifest.get("session_checksums_sha256") != session_checksum:
        raise ValueError("reproduction shard session checksum differs")
    contract = Path(session_verification["contract_directory"])
    reference = Path(session_verification["reference_directory"])
    contract_identity = capture_contract_identity(contract)
    reference_identity = capture_reference_identity(reference)
    for name, expected in (
        ("contract_identity_start.json", contract_identity),
        ("contract_identity_end.json", contract_identity),
        ("reference_identity_start.json", reference_identity),
        ("reference_identity_end.json", reference_identity),
    ):
        actual = json.loads((directory / name).read_text(encoding="utf-8"))
        if actual != expected:
            raise ValueError(f"reproduction shard identity differs: {name}")
    file_identity = json.loads((session / "bound_file_identity.json").read_text(encoding="utf-8"))
    signature = json.loads((directory / "execution_signature.json").read_text(encoding="utf-8"))
    _verify_execution_binding(root, signature, file_identity)
    audit = json.loads((directory / "evaluation_input_audit.json").read_text(encoding="utf-8"))
    if (
        audit.get("basin_id") != basin_id
        or audit.get("passed") is not True
        or audit.get("performed_after_verified_contract") is not True
        or audit.get("verified_contract_id") != contract_identity["contract_id"]
        or audit.get("verified_contract_checksums_sha256") != contract_identity["checksums_sha256"]
    ):
        raise ValueError("reproduction shard evaluation input audit is invalid")
    reproduced = directory / "reproduced_basin.npz"
    reference_npz = reference / "basins" / f"{basin_id}.npz"
    comparison = compare_npz_exact(reference_npz, reproduced)
    if comparison["numeric_element_count"] != EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN:
        raise ValueError("reproduction shard does not contain exactly 366,960 numeric elements")
    saved_comparison = json.loads((directory / "array_comparison.json").read_text(encoding="utf-8"))
    if saved_comparison != comparison:
        raise ValueError("saved reproduction array comparison differs from independent recomputation")
    content_verification = {
        "status": "verified",
        "shard_id": shard_id,
        "basin_id": basin_id,
        "formal_basin_index": session_verification["basins"].index(basin_id) + 1,
        "session_checksums_sha256": session_checksum,
        "contract_checksums_sha256": contract_identity["checksums_sha256"],
        "reference_checksums_sha256": reference_identity["checksums_sha256"],
        "array_count": comparison["array_count"],
        "numeric_element_count": comparison["numeric_element_count"],
        "maximum_absolute_difference": comparison["maximum_absolute_difference"],
        "reproduced_npz_sha256": comparison["reproduced_npz_sha256"],
    }
    if _content_only:
        return content_verification
    saved_content_verification = json.loads(
        (directory / "shard_content_verification.json").read_text(encoding="utf-8")
    )
    if saved_content_verification != content_verification:
        raise ValueError("saved shard content verification differs from independent recomputation")
    config = json.loads((session / "config_snapshot.json").read_text(encoding="utf-8"))
    log_directory = (
        Path(_log_directory_override).resolve()
        if _log_directory_override is not None
        else _resolve_repo_relative(root, manifest["log_directory_repo_relative"])
    )
    resource = _verify_shard_log(
        log_directory,
        root,
        config,
        shard_id,
        directory,
        allow_incomplete=_allow_incomplete,
        declared_result_directory=_published_result_directory_override,
    )
    log_reference = json.loads((directory / "log_reference.json").read_text(encoding="utf-8"))
    if (
        _resolve_repo_relative(root, log_reference["log_directory_repo_relative"])
        != _resolve_repo_relative(root, manifest["log_directory_repo_relative"])
        or log_reference.get("log_checksums_sha256")
        != sha256_file(log_directory / "checksums.json")
    ):
        raise ValueError("reproduction shard result does not bind the verified log checksum")
    if _require_registry_verified:
        record = _registry_status(
            root,
            manifest["registry_record_repo_relative"],
            shard_id,
            "verified",
        )
        terminal = record["history"][-1]
        if (
            str(terminal.get("basin_id", "")).zfill(8) != basin_id
            or Path(terminal.get("output_directory", "")).resolve() != directory
            or Path(terminal.get("log_directory", "")).resolve() != log_directory
            or terminal.get("result_checksums_sha256")
            != sha256_file(directory / "checksums.json")
            or terminal.get("log_checksums_sha256")
            != sha256_file(log_directory / "checksums.json")
        ):
            raise ValueError("shard registry terminal does not bind result and log checksums")
    return {
        **content_verification,
        "shard_checksums_sha256": sha256_file(directory / "checksums.json"),
        "shard_directory": str(directory),
        "log_directory": str(log_directory),
        "resource_verification": resource,
    }


def verify_reproduction_shard_closure(
    shard_directory: Path,
    session_directory: Path,
    repo_root: Path,
    *,
    allow_incomplete: bool = False,
    log_directory_override: Path | None = None,
    published_result_directory_override: Path | None = None,
    require_registry_verified: bool = True,
) -> dict:
    """Verify shard checksums, resource tail, log binding, and registry only."""
    directory = Path(shard_directory).resolve()
    if not allow_incomplete:
        _verify_not_failed_or_incomplete(directory, "reproduction shard")
    elif directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed reproduction shard cannot close as successful")
    _verify_artifact_checksums(directory)
    root = Path(repo_root).resolve()
    session = Path(session_directory).resolve()
    session_closure = verify_reproduction_session_closure(session, root)
    manifest = json.loads((directory / "shard_manifest.json").read_text(encoding="utf-8"))
    content = json.loads(
        (directory / "shard_content_verification.json").read_text(encoding="utf-8")
    )
    basin_id = str(manifest.get("basin_id", "")).zfill(8)
    shard_id = str(manifest.get("shard_id", ""))
    if (
        manifest.get("artifact_type") != "formal_reproduction_basin_shard"
        or manifest.get("status") != "verified"
        or content.get("status") != "verified"
        or content.get("shard_id") != shard_id
        or str(content.get("basin_id", "")).zfill(8) != basin_id
        or basin_id not in session_closure["basins"]
        or int(content.get("array_count", -1)) != EXPECTED_ARRAY_COUNT_PER_BASIN
        or int(content.get("numeric_element_count", -1))
        != EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN
        or float(content.get("maximum_absolute_difference", float("inf"))) != 0.0
        or content.get("session_checksums_sha256") != session_closure["session_checksums_sha256"]
        or content.get("contract_checksums_sha256") != session_closure["contract_checksums_sha256"]
        or content.get("reference_checksums_sha256") != session_closure["reference_checksums_sha256"]
        or _resolve_repo_relative(root, manifest["session_directory_repo_relative"]) != session
        or tuple(manifest.get("methods", [])) != METHOD_ORDER
        or list(manifest.get("lead_days", [])) != [1, 3, 7]
        or int(manifest.get("array_count", -1)) != EXPECTED_ARRAY_COUNT_PER_BASIN
        or int(manifest.get("numeric_element_count", -1))
        != EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN
        or manifest.get("failed_run_arrays_reused") is not False
        or manifest.get("reference_opened_only_after_recomputed_array_save") is not True
    ):
        raise ValueError("reproduction shard content-verification closure is inconsistent")
    reproduced = directory / "reproduced_basin.npz"
    if content.get("reproduced_npz_sha256") != sha256_file(reproduced):
        raise ValueError("reproduction shard content record does not bind the saved array checksum")
    config = json.loads((session / "config_snapshot.json").read_text(encoding="utf-8"))
    log_directory = (
        Path(log_directory_override).resolve()
        if log_directory_override is not None
        else _resolve_repo_relative(root, manifest["log_directory_repo_relative"])
    )
    resource = _verify_shard_log(
        log_directory,
        root,
        config,
        shard_id,
        directory,
        allow_incomplete=allow_incomplete,
        declared_result_directory=published_result_directory_override,
    )
    log_reference = json.loads((directory / "log_reference.json").read_text(encoding="utf-8"))
    if (
        _resolve_repo_relative(root, log_reference["log_directory_repo_relative"])
        != _resolve_repo_relative(root, manifest["log_directory_repo_relative"])
        or log_reference.get("log_checksums_sha256")
        != sha256_file(log_directory / "checksums.json")
    ):
        raise ValueError("reproduction shard closure does not bind the log checksum")
    if require_registry_verified:
        record = _registry_status(
            root,
            manifest["registry_record_repo_relative"],
            shard_id,
            "verified",
        )
        terminal = record["history"][-1]
        if (
            str(terminal.get("basin_id", "")).zfill(8) != basin_id
            or Path(terminal.get("output_directory", "")).resolve() != directory
            or Path(terminal.get("log_directory", "")).resolve() != log_directory
            or terminal.get("result_checksums_sha256")
            != sha256_file(directory / "checksums.json")
            or terminal.get("log_checksums_sha256")
            != sha256_file(log_directory / "checksums.json")
        ):
            raise ValueError("shard registry terminal does not bind result and log checksums")
    return {
        **content,
        "shard_checksums_sha256": sha256_file(directory / "checksums.json"),
        "shard_directory": str(directory),
        "log_directory": str(log_directory),
        "resource_verification": resource,
    }


def run_reproduction_shard(
    repo_root: Path,
    session_directory: Path,
    shard_root: Path,
    shard_id: str,
    basin_id: str,
    log_root: Path | None = None,
) -> dict:
    root = Path(repo_root).resolve()
    session = Path(session_directory).resolve()
    session_verification = verify_reproduction_session_closure(session, root)
    identifier = _safe_identifier(shard_id)
    normalized_basin = str(basin_id).strip().zfill(8)
    if normalized_basin not in session_verification["basins"]:
        raise ValueError("requested basin is absent from the frozen sixteen-basin session")
    results_parent = Path(shard_root).resolve()
    _repo_relative(root, results_parent)
    config = json.loads((session / "config_snapshot.json").read_text(encoding="utf-8"))
    logs_parent = (
        Path(log_root).resolve()
        if log_root is not None
        else (root / config["logs_root"] / results_parent.name).resolve()
    )
    _repo_relative(root, logs_parent)
    output = results_parent / identifier
    temporary = results_parent / f".{identifier}.incomplete"
    failed = results_parent / f"{identifier}.failed"
    log_output = logs_parent / identifier
    log_temporary = logs_parent / f".{identifier}.incomplete"
    log_failed = logs_parent / f"{identifier}.failed"
    if any(
        path.exists()
        for path in (output, temporary, failed, log_output, log_temporary, log_failed)
    ):
        raise FileExistsError(f"refusing to overwrite reproduction shard or log {identifier}")
    registry = RunRegistry(results_parent, identifier)
    registry.reserve(
        "formal_reproduction_basin_shard",
        basin_id=normalized_basin,
        session_id=session_verification["session_id"],
    )
    recorder = None
    try:
        temporary.mkdir(parents=True)
        log_temporary.mkdir(parents=True)
        recorder = ResourceRecorder(
            results_parent,
            config["resource"],
            log_temporary / "resource_history.json",
        )
        recorder.start(
            **REPRODUCTION_RESOURCE_ESTIMATES_GIB["shard"],
            shard_id=identifier,
            basin_id=normalized_basin,
        )
        contract = Path(session_verification["contract_directory"])
        reference = Path(session_verification["reference_directory"])
        contract_identity_start = capture_contract_identity(contract)
        reference_identity_start = capture_reference_identity(reference)
        file_identity = json.loads((session / "bound_file_identity.json").read_text(encoding="utf-8"))
        source_files, input_files = _bound_paths(root, file_identity)
        signature_start = _execution_signature(
            root,
            session_verification["basins"],
            config,
            source_files,
            input_files,
            include_calibration_discharge=False,
        )
        recorder.checkpoint("before_basin_recomputation", force=True, basin_id=normalized_basin)
        arrays, evaluation_audit = _recompute_basin(
            root,
            contract,
            normalized_basin,
            config,
            recorder,
        )
        reproduced_path = temporary / "reproduced_basin.npz"
        np.savez_compressed(reproduced_path, **arrays)
        del arrays
        gc.collect()
        recorder.checkpoint("recomputed_arrays_saved", force=True, basin_id=normalized_basin)
        comparison = compare_npz_exact(
            reference / "basins" / f"{normalized_basin}.npz",
            reproduced_path,
        )
        if comparison["numeric_element_count"] != EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN:
            raise ValueError("recomputed basin does not contain exactly 366,960 numeric elements")
        recorder.checkpoint("reference_comparison_complete", force=True, basin_id=normalized_basin)
        signature_end = _execution_signature(
            root,
            session_verification["basins"],
            config,
            source_files,
            input_files,
            include_calibration_discharge=False,
        )
        signature = _verified_execution_signature(signature_start, signature_end)
        contract_identity_end = capture_contract_identity(contract)
        reference_identity_end = capture_reference_identity(reference)
        if contract_identity_start != contract_identity_end:
            raise RuntimeError("formal contract changed during basin reproduction")
        if reference_identity_start != reference_identity_end:
            raise RuntimeError("reference result changed during basin reproduction")
        _write_json(temporary / "evaluation_input_audit.json", evaluation_audit)
        _write_json(temporary / "array_comparison.json", comparison)
        _write_json(temporary / "execution_signature_start.json", signature_start)
        _write_json(temporary / "execution_signature_end.json", signature_end)
        _write_json(temporary / "execution_signature.json", signature)
        _write_json(temporary / "contract_identity_start.json", contract_identity_start)
        _write_json(temporary / "contract_identity_end.json", contract_identity_end)
        _write_json(temporary / "reference_identity_start.json", reference_identity_start)
        _write_json(temporary / "reference_identity_end.json", reference_identity_end)
        _write_json(
            temporary / "shard_manifest.json",
            {
                "artifact_type": "formal_reproduction_basin_shard",
                "status": "verified",
                "shard_id": identifier,
                "basin_id": normalized_basin,
                "formal_basin_index": session_verification["basins"].index(normalized_basin) + 1,
                "session_directory_repo_relative": _repo_relative(root, session),
                "session_checksums_sha256": sha256_file(session / "checksums.json"),
                "log_directory_repo_relative": _repo_relative(root, log_output),
                "registry_record_repo_relative": _repo_relative(root, registry.path),
                "method_count": len(METHOD_ORDER),
                "methods": list(METHOD_ORDER),
                "lead_days": [1, 3, 7],
                "array_count": EXPECTED_ARRAY_COUNT_PER_BASIN,
                "numeric_element_count": EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN,
                "failed_run_arrays_reused": False,
                "reference_opened_only_after_recomputed_array_save": True,
            },
        )
        content_verification = verify_reproduction_shard(
            temporary,
            session,
            root,
            _allow_incomplete=True,
            _require_registry_verified=False,
            _content_only=True,
        )
        _write_json(temporary / "shard_content_verification.json", content_verification)
        recorder.checkpoint(
            "after_shard_content_verification",
            force=True,
            basin_id=normalized_basin,
        )
        recorder.finish(shard_id=identifier, basin_id=normalized_basin)
        history_path = log_temporary / "resource_history.json"
        history = json.loads(history_path.read_text(encoding="utf-8"))
        _write_json(
            log_temporary / "run_summary.json",
            {
                "status": "verified",
                "shard_id": identifier,
                "basin_id": normalized_basin,
                "result_directory_repo_relative": _repo_relative(root, output),
                "resource_sample_count": len(history),
                "resource_last_event": history[-1]["event"],
                "resource_history_sha256": sha256_file(history_path),
                "resource_monitor_covers_compute_save_compare_and_content_verification": True,
            },
        )
        _write_json(log_temporary / "checksums.json", _artifact_checksums(log_temporary))
        _write_json(
            temporary / "log_reference.json",
            {
                "log_directory_repo_relative": _repo_relative(root, log_output),
                "log_checksums_sha256": sha256_file(log_temporary / "checksums.json"),
            },
        )
        _write_json(temporary / "checksums.json", _artifact_checksums(temporary))
        verify_reproduction_shard_closure(
            temporary,
            session,
            root,
            allow_incomplete=True,
            log_directory_override=log_temporary,
            published_result_directory_override=output,
            require_registry_verified=False,
        )
        os.replace(temporary, output)
        try:
            os.replace(log_temporary, log_output)
        except Exception:
            raise
        registry.update(
            "verified",
            basin_id=normalized_basin,
            output_directory=str(output),
            log_directory=str(log_output),
            result_checksums_sha256=sha256_file(output / "checksums.json"),
            log_checksums_sha256=sha256_file(log_output / "checksums.json"),
        )
        verification = verify_reproduction_shard_closure(output, session, root)
        return verification
    except Exception as error:
        if recorder is not None:
            try:
                recorder.abort()
            except Exception:
                pass
        if output.exists() and not failed.exists():
            os.replace(output, failed)
            _write_json(failed / "failure.json", {"status": "failed", "message": str(error)})
        elif temporary.exists():
            _preserve_failed_directory(temporary, failed, error)
        if log_output.exists() and not log_failed.exists():
            os.replace(log_output, log_failed)
            _write_json(log_failed / "failure.json", {"status": "failed", "message": str(error)})
        elif log_temporary.exists():
            _preserve_failed_directory(log_temporary, log_failed, error)
        try:
            registry.update(
                "failed",
                basin_id=normalized_basin,
                error_type=type(error).__name__,
                message=str(error),
            )
        except Exception:
            pass
        raise


def _metric_rows_from_npz(basin_id: str, npz_path: Path) -> list[dict]:
    rows = []
    with np.load(npz_path) as arrays:
        leads = arrays["lead_days"]
        target_observations = arrays["target_observations"]
        fixed_predictions = arrays["fixed_filter__predictions"]
        origins = arrays["origin_indices"]
        if tuple(leads.tolist()) != (1, 3, 7):
            raise ValueError(f"basin {basin_id} lead days differ from 1, 3, and 7")
        for lead_index, lead in enumerate(leads):
            observed = target_observations[:, lead_index]
            fixed = calculate_metrics(observed, fixed_predictions[:, lead_index])
            for method in METHOD_ORDER:
                metrics = calculate_metrics(
                    observed,
                    arrays[f"{method}__predictions"][:, lead_index],
                )
                rows.append(
                    {
                        "basin_id": basin_id,
                        "method": method,
                        "lead_days": int(lead),
                        "n_origins": len(origins),
                        **metrics,
                        "rmse_change_percent_vs_fixed_filter": 100.0
                        * (metrics["rmse"] - fixed["rmse"])
                        / fixed["rmse"],
                        "mae_change_percent_vs_fixed_filter": 100.0
                        * (metrics["mae"] - fixed["mae"])
                        / fixed["mae"],
                        "nse_change_vs_fixed_filter": metrics["nse"] - fixed["nse"],
                        "strict_rmse_win_vs_fixed_filter": bool(metrics["rmse"] < fixed["rmse"]),
                    }
                )
    return rows


def _successful_shard_directories(shard_root: Path) -> list[Path]:
    root = Path(shard_root).resolve()
    if not root.is_dir():
        raise ValueError("reproduction shard root is missing")
    return sorted(
        path
        for path in root.iterdir()
        if path.is_dir()
        and not path.name.startswith(".")
        and not path.name.endswith(".failed")
        and not (path / "failure.json").exists()
        and (path / "shard_manifest.json").is_file()
    )


def _verify_saved_diagnostics(directory: Path, metrics: pd.DataFrame, summary: pd.DataFrame) -> None:
    loaded_metrics = pd.read_csv(directory / "metrics.csv", dtype={"basin_id": str})
    metric_sort = ["basin_id", "method", "lead_days"]
    if not _dataframe_values_equal(
        metrics.sort_values(metric_sort).reset_index(drop=True),
        loaded_metrics.sort_values(metric_sort).reset_index(drop=True),
        list(metrics.columns),
    ):
        raise ValueError("aggregation metrics do not equal recomputed shard metrics")
    loaded_summary = pd.read_csv(directory / "cross_basin_summary.csv")
    summary_sort = ["method", "lead_days"]
    if not _dataframe_values_equal(
        summary.sort_values(summary_sort).reset_index(drop=True),
        loaded_summary.sort_values(summary_sort).reset_index(drop=True),
        list(summary.columns),
    ):
        raise ValueError("aggregation cross-basin summary differs from recomputation")
    comparisons = paired_method_comparisons(metrics)
    loaded_comparisons = pd.read_csv(directory / "paired_method_comparisons.csv")
    comparison_sort = ["comparison_id", "lead_days"]
    if not _dataframe_values_equal(
        comparisons.sort_values(comparison_sort).reset_index(drop=True),
        loaded_comparisons.sort_values(comparison_sort).reset_index(drop=True),
        list(comparisons.columns),
    ):
        raise ValueError("aggregation paired comparisons differ from recomputation")
    basin_ids = list(dict.fromkeys(metrics["basin_id"].astype(str).str.zfill(8).tolist()))
    candidates, factors = _candidate_probability_tables(directory, basin_ids)
    loaded_candidates = pd.read_csv(
        directory / "candidate_probability_summary.csv", dtype={"basin_id": str}
    )
    loaded_factors = pd.read_csv(
        directory / "joint_factor_probability_summary.csv", dtype={"basin_id": str}
    )
    candidate_sort = ["basin_id", "method", "lead_days", "candidate_id"]
    factor_sort = ["basin_id", "lead_days", "factor_type", "factor_id"]
    if not _dataframe_values_equal(
        candidates.sort_values(candidate_sort).reset_index(drop=True),
        loaded_candidates.sort_values(candidate_sort).reset_index(drop=True),
        list(candidates.columns),
    ):
        raise ValueError("aggregation candidate probabilities differ from recomputation")
    if not _dataframe_values_equal(
        factors.sort_values(factor_sort).reset_index(drop=True),
        loaded_factors.sort_values(factor_sort).reset_index(drop=True),
        list(factors.columns),
    ):
        raise ValueError("aggregation factor probabilities differ from recomputation")
    with tempfile.TemporaryDirectory(prefix="verify-reproduction-plot-") as temporary:
        expected_figure = Path(temporary) / "expected.png"
        _lead_time_plot(comparisons, expected_figure)
        try:
            from PIL import Image

            with Image.open(directory / "lead_time_effects.png") as actual_image, Image.open(
                expected_figure
            ) as expected_image:
                actual_pixels = np.asarray(actual_image.convert("RGBA"))
                expected_pixels = np.asarray(expected_image.convert("RGBA"))
        except Exception as error:
            raise ValueError("aggregation lead-time figure is invalid") from error
    if not np.array_equal(actual_pixels, expected_pixels):
        raise ValueError("aggregation lead-time figure differs from recomputed paired comparisons")
    expected_report = build_study_report(comparisons, summary, metrics)
    if (directory / "study_report.md").read_text(encoding="utf-8") != expected_report:
        raise ValueError("aggregation study report differs from recomputed results")


def verify_reproduction_aggregation(
    aggregation_directory: Path,
    repo_root: Path,
    *,
    _allow_incomplete: bool = False,
    _require_registry_verified: bool = True,
    _content_only: bool = False,
) -> dict:
    directory = Path(aggregation_directory).resolve()
    if not _allow_incomplete:
        _verify_not_failed_or_incomplete(directory, "reproduction aggregation")
    elif directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed reproduction aggregation cannot verify as successful")
    if not _content_only:
        _verify_artifact_checksums(directory)
    root = Path(repo_root).resolve()
    manifest = json.loads((directory / "aggregation_manifest.json").read_text(encoding="utf-8"))
    if (
        manifest.get("artifact_type") != "formal_reproduction_aggregation"
        or manifest.get("status") != "verified"
    ):
        raise ValueError("reproduction aggregation manifest is invalid")
    session = _resolve_repo_relative(root, manifest["session_directory_repo_relative"])
    session_verification = verify_reproduction_session(session, root)
    if (
        [str(value).zfill(8) for value in manifest.get("basins", [])]
        != session_verification["basins"]
        or int(manifest.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or int(manifest.get("shard_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or int(manifest.get("array_count", -1)) != EXPECTED_TOTAL_ARRAY_COUNT
        or int(manifest.get("numeric_element_count", -1))
        != EXPECTED_TOTAL_NUMERIC_ELEMENT_COUNT
        or float(manifest.get("maximum_absolute_difference", float("inf"))) != 0.0
        or manifest.get("failed_shard_directories_used") is not False
    ):
        raise ValueError("reproduction aggregation manifest totals or basin order are invalid")
    session_checksum = sha256_file(session / "checksums.json")
    if manifest.get("session_checksums_sha256") != session_checksum:
        raise ValueError("reproduction aggregation session checksum differs")
    shard_root = _resolve_repo_relative(root, manifest["shard_root_repo_relative"])
    shard_directories = _successful_shard_directories(shard_root)
    if len(shard_directories) != EXPECTED_FORMAL_BASIN_COUNT:
        raise ValueError("aggregation shard root does not contain exactly 16 successful shards")
    shard_verifications = [
        verify_reproduction_shard(path, session, root) for path in shard_directories
    ]
    ordered = validate_verified_shard_set(
        session_verification["basins"],
        shard_verifications,
        session_checksum,
    )
    saved_shards = list(manifest.get("shards", []))
    expected_shards = [
        {
            "basin_id": row["basin_id"],
            "shard_id": row["shard_id"],
            "shard_directory_repo_relative": _repo_relative(root, Path(row["shard_directory"])),
            "shard_checksums_sha256": row["shard_checksums_sha256"],
            "reproduced_npz_sha256": row["reproduced_npz_sha256"],
        }
        for row in ordered
    ]
    if saved_shards != expected_shards:
        raise ValueError("aggregation manifest shard identities differ from verified shards")
    metric_rows = []
    total_arrays = 0
    total_numeric = 0
    maximum_difference = 0.0
    comparison_rows = []
    for row in ordered:
        basin_id = row["basin_id"]
        aggregate_npz = directory / "basins" / f"{basin_id}.npz"
        shard_npz = Path(row["shard_directory"]) / "reproduced_basin.npz"
        comparison = compare_npz_exact(shard_npz, aggregate_npz)
        if comparison["numeric_element_count"] != EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN:
            raise ValueError("aggregation basin has the wrong numeric element count")
        metric_rows.extend(_metric_rows_from_npz(basin_id, aggregate_npz))
        total_arrays += comparison["array_count"]
        total_numeric += comparison["numeric_element_count"]
        maximum_difference = max(maximum_difference, comparison["maximum_absolute_difference"])
        comparison_rows.append(
            {
                "basin_id": basin_id,
                "shard_id": row["shard_id"],
                "array_count": comparison["array_count"],
                "numeric_element_count": comparison["numeric_element_count"],
                "maximum_absolute_difference": comparison["maximum_absolute_difference"],
            }
        )
    if (
        total_arrays != EXPECTED_TOTAL_ARRAY_COUNT
        or total_numeric != EXPECTED_TOTAL_NUMERIC_ELEMENT_COUNT
        or maximum_difference != 0.0
    ):
        raise ValueError("aggregation totals do not equal 576 arrays and 5,871,360 numeric elements")
    saved_comparisons = pd.read_csv(
        directory / "basin_array_comparisons.csv", dtype={"basin_id": str}
    )
    recomputed_comparisons = pd.DataFrame(comparison_rows)
    if not _dataframe_values_equal(
        recomputed_comparisons,
        saved_comparisons,
        list(recomputed_comparisons.columns),
    ):
        raise ValueError("aggregation basin comparison table differs from recomputation")
    metrics = pd.DataFrame(metric_rows)
    summary = summarize_metrics(metrics)
    if len(metrics) != 240 or len(summary) != 15:
        raise ValueError("aggregation metric row counts differ from 240 and 15")
    _verify_saved_diagnostics(directory, metrics, summary)
    contract = Path(session_verification["contract_directory"])
    contract_checksums = json.loads((contract / "checksums.json").read_text(encoding="utf-8"))
    copied = directory / "contract_tables"
    copied_names = {
        path.relative_to(copied).as_posix() for path in copied.rglob("*") if path.is_file()
    }
    if copied_names != set(CONTRACT_TABLE_FILES):
        raise ValueError("aggregation contract table set is incomplete")
    for name in CONTRACT_TABLE_FILES:
        if sha256_file(copied / name) != contract_checksums[name]:
            raise ValueError(f"aggregation contract table differs: {name}")
    content_verification = {
        "status": "verified",
        "aggregation_id": str(manifest["aggregation_id"]),
        "basin_count": EXPECTED_FORMAL_BASIN_COUNT,
        "shard_count": EXPECTED_FORMAL_BASIN_COUNT,
        "array_count": total_arrays,
        "numeric_element_count": total_numeric,
        "maximum_absolute_difference": maximum_difference,
        "metric_row_count": len(metrics),
        "cross_basin_summary_row_count": len(summary),
        "session_checksums_sha256": session_checksum,
    }
    if _content_only:
        return content_verification
    saved_content_verification = json.loads(
        (directory / "aggregation_content_verification.json").read_text(encoding="utf-8")
    )
    if saved_content_verification != content_verification:
        raise ValueError("saved aggregation content verification differs from recomputation")
    config = json.loads((session / "config_snapshot.json").read_text(encoding="utf-8"))
    history = json.loads((directory / "resource_history.json").read_text(encoding="utf-8"))
    resource = _verify_resource_history(history, config, "aggregation")
    if _require_registry_verified:
        record = _registry_status(
            root,
            manifest["registry_record_repo_relative"],
            str(manifest["aggregation_id"]),
            "verified",
        )
        terminal = record["history"][-1]
        if (
            Path(terminal.get("output_directory", "")).resolve() != directory
            or terminal.get("output_checksums_sha256") != sha256_file(directory / "checksums.json")
        ):
            raise ValueError("aggregation registry terminal does not bind the verified output checksum")
    return {
        **content_verification,
        "aggregation_checksums_sha256": sha256_file(directory / "checksums.json"),
        "resource_verification": resource,
    }


def verify_reproduction_aggregation_closure(
    aggregation_directory: Path,
    repo_root: Path,
    *,
    allow_incomplete: bool = False,
    require_registry_verified: bool = True,
) -> dict:
    """Verify aggregate packaging and run closure without reopening numerical arrays."""
    directory = Path(aggregation_directory).resolve()
    if not allow_incomplete:
        _verify_not_failed_or_incomplete(directory, "reproduction aggregation")
    elif directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed reproduction aggregation cannot close as successful")
    _verify_artifact_checksums(directory)
    root = Path(repo_root).resolve()
    manifest = json.loads((directory / "aggregation_manifest.json").read_text(encoding="utf-8"))
    content = json.loads(
        (directory / "aggregation_content_verification.json").read_text(encoding="utf-8")
    )
    session = _resolve_repo_relative(root, manifest["session_directory_repo_relative"])
    session_closure = verify_reproduction_session_closure(session, root)
    if (
        manifest.get("artifact_type") != "formal_reproduction_aggregation"
        or manifest.get("status") != "verified"
        or content.get("status") != "verified"
        or content.get("aggregation_id") != manifest.get("aggregation_id")
        or int(content.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or int(content.get("shard_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or int(content.get("array_count", -1)) != EXPECTED_TOTAL_ARRAY_COUNT
        or int(content.get("numeric_element_count", -1))
        != EXPECTED_TOTAL_NUMERIC_ELEMENT_COUNT
        or float(content.get("maximum_absolute_difference", float("inf"))) != 0.0
        or int(content.get("metric_row_count", -1)) != 240
        or int(content.get("cross_basin_summary_row_count", -1)) != 15
        or content.get("session_checksums_sha256") != session_closure["session_checksums_sha256"]
        or [str(value).zfill(8) for value in manifest.get("basins", [])]
        != session_closure["basins"]
        or int(manifest.get("basin_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or int(manifest.get("shard_count", -1)) != EXPECTED_FORMAL_BASIN_COUNT
        or int(manifest.get("array_count", -1)) != EXPECTED_TOTAL_ARRAY_COUNT
        or int(manifest.get("numeric_element_count", -1))
        != EXPECTED_TOTAL_NUMERIC_ELEMENT_COUNT
        or float(manifest.get("maximum_absolute_difference", float("inf"))) != 0.0
        or int(manifest.get("metric_row_count", -1)) != 240
        or int(manifest.get("cross_basin_summary_row_count", -1)) != 15
        or manifest.get("failed_shard_directories_used") is not False
    ):
        raise ValueError("reproduction aggregation content-verification closure is inconsistent")
    config = json.loads((session / "config_snapshot.json").read_text(encoding="utf-8"))
    history = json.loads((directory / "resource_history.json").read_text(encoding="utf-8"))
    resource = _verify_resource_history(history, config, "aggregation")
    if require_registry_verified:
        record = _registry_status(
            root,
            manifest["registry_record_repo_relative"],
            str(manifest["aggregation_id"]),
            "verified",
        )
        terminal = record["history"][-1]
        if (
            Path(terminal.get("output_directory", "")).resolve() != directory
            or terminal.get("output_checksums_sha256") != sha256_file(directory / "checksums.json")
        ):
            raise ValueError("aggregation registry terminal does not bind the output checksum")
    return {
        **content,
        "aggregation_checksums_sha256": sha256_file(directory / "checksums.json"),
        "resource_verification": resource,
    }


def aggregate_reproduction_shards(
    repo_root: Path,
    session_directory: Path,
    shard_root: Path,
    aggregation_id: str,
) -> dict:
    root = Path(repo_root).resolve()
    session = Path(session_directory).resolve()
    shards_parent = Path(shard_root).resolve()
    identifier = _safe_identifier(aggregation_id)
    config = json.loads((session / "config_snapshot.json").read_text(encoding="utf-8"))
    results_root = (root / config["results_root"]).resolve()
    output = results_root / identifier
    temporary = results_root / f".{identifier}.incomplete"
    failed = results_root / f"{identifier}.failed"
    if any(path.exists() for path in (output, temporary, failed)):
        raise FileExistsError(f"refusing to overwrite reproduction aggregation {identifier}")
    registry = RunRegistry(results_root, identifier)
    registry.reserve("formal_reproduction_aggregation")
    recorder = None
    try:
        temporary.mkdir(parents=True)
        (temporary / "basins").mkdir()
        recorder = ResourceRecorder(
            results_root,
            config["resource"],
            temporary / "resource_history.json",
        )
        recorder.start(**REPRODUCTION_RESOURCE_ESTIMATES_GIB["aggregation"], aggregation_id=identifier)
        session_verification = verify_reproduction_session(session, root)
        session_checksum = sha256_file(session / "checksums.json")
        shard_directories = _successful_shard_directories(shards_parent)
        shard_verifications = []
        for path in shard_directories:
            shard_verifications.append(verify_reproduction_shard(path, session, root))
            recorder.checkpoint(
                "aggregation_shard_verified",
                shard_id=shard_verifications[-1]["shard_id"],
                basin_id=shard_verifications[-1]["basin_id"],
            )
        ordered = validate_verified_shard_set(
            session_verification["basins"],
            shard_verifications,
            session_checksum,
        )
        comparison_rows = []
        metric_rows = []
        shard_rows = []
        for row in ordered:
            basin_id = row["basin_id"]
            source_npz = Path(row["shard_directory"]) / "reproduced_basin.npz"
            destination_npz = temporary / "basins" / f"{basin_id}.npz"
            shutil.copy2(source_npz, destination_npz)
            comparison = compare_npz_exact(source_npz, destination_npz)
            if comparison["numeric_element_count"] != EXPECTED_NUMERIC_ELEMENT_COUNT_PER_BASIN:
                raise ValueError("aggregation input shard has the wrong numeric element count")
            comparison_rows.append(
                {
                    "basin_id": basin_id,
                    "shard_id": row["shard_id"],
                    "array_count": comparison["array_count"],
                    "numeric_element_count": comparison["numeric_element_count"],
                    "maximum_absolute_difference": comparison["maximum_absolute_difference"],
                }
            )
            metric_rows.extend(_metric_rows_from_npz(basin_id, destination_npz))
            shard_rows.append(
                {
                    "basin_id": basin_id,
                    "shard_id": row["shard_id"],
                    "shard_directory_repo_relative": _repo_relative(
                        root, Path(row["shard_directory"])
                    ),
                    "shard_checksums_sha256": row["shard_checksums_sha256"],
                    "reproduced_npz_sha256": row["reproduced_npz_sha256"],
                }
            )
        comparisons = pd.DataFrame(comparison_rows)
        if (
            int(comparisons["array_count"].sum()) != EXPECTED_TOTAL_ARRAY_COUNT
            or int(comparisons["numeric_element_count"].sum())
            != EXPECTED_TOTAL_NUMERIC_ELEMENT_COUNT
            or float(comparisons["maximum_absolute_difference"].max()) != 0.0
        ):
            raise ValueError("aggregation inputs do not total 576 exact arrays and 5,871,360 numbers")
        comparisons.to_csv(temporary / "basin_array_comparisons.csv", index=False)
        metrics = pd.DataFrame(metric_rows)
        summary = summarize_metrics(metrics)
        metrics.to_csv(temporary / "metrics.csv", index=False)
        summary.to_csv(temporary / "cross_basin_summary.csv", index=False)
        write_result_diagnostics(
            temporary,
            metrics,
            summary,
            session_verification["basins"],
        )
        contract = Path(session_verification["contract_directory"])
        contract_table_directory = temporary / "contract_tables"
        contract_table_directory.mkdir()
        for name in CONTRACT_TABLE_FILES:
            shutil.copy2(contract / name, contract_table_directory / name)
        _write_json(
            temporary / "aggregation_manifest.json",
            {
                "artifact_type": "formal_reproduction_aggregation",
                "status": "verified",
                "aggregation_id": identifier,
                "session_directory_repo_relative": _repo_relative(root, session),
                "session_checksums_sha256": session_checksum,
                "shard_root_repo_relative": _repo_relative(root, shards_parent),
                "registry_record_repo_relative": _repo_relative(root, registry.path),
                "basin_count": EXPECTED_FORMAL_BASIN_COUNT,
                "basins": session_verification["basins"],
                "shard_count": EXPECTED_FORMAL_BASIN_COUNT,
                "array_count": EXPECTED_TOTAL_ARRAY_COUNT,
                "numeric_element_count": EXPECTED_TOTAL_NUMERIC_ELEMENT_COUNT,
                "maximum_absolute_difference": 0.0,
                "metric_row_count": 240,
                "cross_basin_summary_row_count": 15,
                "shards": shard_rows,
                "failed_shard_directories_used": False,
            },
        )
        content_verification = verify_reproduction_aggregation(
            temporary,
            root,
            _allow_incomplete=True,
            _require_registry_verified=False,
            _content_only=True,
        )
        _write_json(
            temporary / "aggregation_content_verification.json",
            content_verification,
        )
        recorder.checkpoint("after_aggregation_content_verification", force=True)
        recorder.finish(aggregation_id=identifier)
        _write_json(temporary / "checksums.json", _artifact_checksums(temporary))
        verify_reproduction_aggregation_closure(
            temporary,
            root,
            allow_incomplete=True,
            require_registry_verified=False,
        )
        os.replace(temporary, output)
        registry.update(
            "verified",
            output_directory=str(output),
            output_checksums_sha256=sha256_file(output / "checksums.json"),
        )
        verification = verify_reproduction_aggregation_closure(output, root)
        return {**verification, "output_directory": str(output)}
    except Exception as error:
        if recorder is not None:
            try:
                recorder.abort()
            except Exception:
                pass
        if output.exists() and not failed.exists():
            os.replace(output, failed)
            _write_json(failed / "failure.json", {"status": "failed", "message": str(error)})
        elif temporary.exists():
            _preserve_failed_directory(temporary, failed, error)
        try:
            registry.update("failed", error_type=type(error).__name__, message=str(error))
        except Exception:
            pass
        raise
