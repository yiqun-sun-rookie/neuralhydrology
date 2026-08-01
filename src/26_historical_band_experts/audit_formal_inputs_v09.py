"""Independent, read-only verification of formal version 09 complete inputs."""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
from typing import Mapping, Sequence

import numpy as np

from artifact_v09 import (
    array_payload_sha256,
    assert_no_reparse_components,
    assert_no_reparse_tree,
    canonical_sha256,
    environment_fingerprint_v09,
    exact_file_inventory,
    sha256_file,
)
from data import STATIC_COLUMNS as SOURCE_STATIC_COLUMNS_V09
from formal_input_contract_v09 import WORKTREE_ROOT, primary_repository_root_v09


_MAURER_HEADER = (
    "Year",
    "Mnth",
    "Day",
    "Hr",
    "Dayl(s)",
    "PRCP(mm/day)",
    "SRAD(W/m2)",
    "SWE(mm)",
    "Tmax(C)",
    "Tmin(C)",
    "Vp(Pa)",
)
_PRODUCTION_APPROVAL_TEXT = "批准版本09正式完整输入封存生成；不批准训练、正式预测或评分。"
_MIB = 2**20
_GIB = 2**30
_EXPECTED_SOURCE_TREE_FILES = (
    "src/26_historical_band_experts/configs/formal_v09_protocol.json",
    "src/26_historical_band_experts/artifact_v09.py",
    "src/26_historical_band_experts/audit_formal_inputs_v09.py",
    "src/26_historical_band_experts/build_formal_inputs_v09.py",
    "src/26_historical_band_experts/data.py",
    "src/26_historical_band_experts/formal_input_authorization_v09.py",
    "src/26_historical_band_experts/formal_input_contract_v09.py",
    "src/26_historical_band_experts/formal_input_resources_v09.py",
    "src/26_historical_band_experts/formal_input_sources_v09.py",
    "src/26_historical_band_experts/formal_input_v09.py",
    "src/26_historical_band_experts/formal_v09_protocol.py",
    "src/26_historical_band_experts/memory_safety_v09.py",
    "src/fair_benchmark/task_memory_v09.py",
)


def _normalized_source_text(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.casefold())


def audit_input_source_boundary_v09(
    root: str | Path,
    *,
    relative_paths: Sequence[str],
    protocol: Mapping,
) -> dict:
    """Reject case, punctuation, or string-splitting variants of forbidden interfaces."""
    root = Path(root).resolve()
    paths = tuple(relative_paths)
    forbidden = {
        str(value): _normalized_source_text(str(value))
        for value in protocol["forbidden_inputs"]
    }
    hits = []
    for relative in paths:
        path = (root / relative).resolve()
        if root != path and root not in path.parents:
            raise ValueError("source boundary path escapes the trusted worktree")
        normalized = _normalized_source_text(path.read_text(encoding="utf-8"))
        for token, normalized_token in forbidden.items():
            if normalized_token and normalized_token in normalized:
                hits.append({"relative_path": str(relative), "token": token})
    if hits:
        raise ValueError(f"complete-input source boundary contains forbidden interfaces: {hits}")
    return {"status": "allowed_input_source_boundary_passed", "files_scanned": len(paths)}


def _audit_formal_path_boundaries(
    *,
    root: Path,
    contract: Mapping,
    data_root: Path,
    static_path: Path,
    target_path: Path,
    authorization_path: Path | None,
    consumption_path: Path | None,
) -> None:
    if not str(contract.get("schema", "")).startswith("historical_multiscale_formal_v09"):
        return
    if authorization_path is None or consumption_path is None:
        raise ValueError("formal authorization audit paths are required")
    for path in (root, static_path, target_path, authorization_path, consumption_path):
        assert_no_reparse_components(WORKTREE_ROOT, path)
    assert_no_reparse_components(primary_repository_root_v09(), data_root)


def _same_float_values(recorded, actual: np.ndarray) -> bool:
    return np.array_equal(
        np.asarray(recorded, dtype=np.float64),
        np.asarray(actual, dtype=np.float64),
    )


def _audit_maurer_against_sources(
    *,
    data_root: Path,
    contract: Mapping,
    dates: np.ndarray,
    forcing: np.ndarray,
) -> dict:
    """Independently parse text rows and compare every sealed float32 forcing value."""
    data_root = Path(data_root)
    start = np.datetime64(dates[0], "D")
    end = np.datetime64(dates[-1], "D")
    total_compared = 0
    for basin_index, source in enumerate(contract["maurer_sources"]):
        relative = Path(source["relative_path"])
        candidate = data_root / relative
        assert_no_reparse_components(data_root, candidate)
        path = candidate.resolve()
        before = sha256_file(path)
        if before != source["sha256"]:
            raise ValueError(f"independent Maurer source hash drift for {source['basin']}")
        seen = np.zeros(len(dates), dtype=bool)
        with path.open("r", encoding="utf-8") as handle:
            handle.readline()
            handle.readline()
            handle.readline()
            if tuple(handle.readline().split()) != _MAURER_HEADER:
                raise ValueError("independent Maurer header audit failed")
            for line_number, line in enumerate(handle, 5):
                fields = line.split()
                if len(fields) != 11:
                    raise ValueError(f"independent Maurer row width drift at line {line_number}")
                date = np.datetime64(
                    f"{int(fields[0]):04d}-{int(fields[1]):02d}-{int(fields[2]):02d}",
                    "D",
                )
                if date < start or date > end:
                    continue
                date_index = int((date - start) / np.timedelta64(1, "D"))
                if seen[date_index]:
                    raise ValueError("independent Maurer audit found a duplicate date")
                seen[date_index] = True
                expected = np.asarray(
                    [
                        float(fields[5]),
                        float(fields[9]),
                        float(fields[8]),
                        float(fields[6]),
                        float(fields[10]),
                    ],
                    dtype=np.float32,
                )
                if not np.array_equal(expected, forcing[basin_index, date_index]):
                    raise ValueError(
                        f"sealed forcing differs from the frozen Maurer source for {source['basin']}"
                    )
                total_compared += len(expected)
        assert_no_reparse_components(data_root, candidate)
        if not seen.all() or sha256_file(path) != before:
            raise ValueError("independent Maurer source coverage or stability audit failed")
    return {"source_count": len(contract["maurer_sources"]), "values_compared": total_compared}


def _audit_statics_against_source(
    *,
    static_path: Path,
    contract: Mapping,
    raw_statics: np.ndarray,
    statics: np.ndarray,
) -> dict:
    if sha256_file(static_path) != contract["static_file_sha256"]:
        raise ValueError("independent static source hash drift")
    source_columns = ("gauge_id", *SOURCE_STATIC_COLUMNS_V09)
    by_basin = {}
    with Path(static_path).open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != source_columns:
            raise ValueError("independent static source-column audit failed")
        for row in reader:
            basin = str(row["gauge_id"]).zfill(8)
            if basin in by_basin:
                raise ValueError("independent static audit found a duplicate basin")
            by_basin[basin] = row
    if set(by_basin) != set(contract["basins"]):
        raise ValueError("independent static basin coverage audit failed")
    expected_raw = np.ascontiguousarray([
        [float(by_basin[basin][column]) for column in contract["static_columns"]]
        for basin in contract["basins"]
    ], dtype=np.float64)
    if not np.array_equal(expected_raw, raw_statics):
        raise ValueError("sealed raw statics differ from the frozen static source")
    center = expected_raw.mean(axis=0, dtype=np.float64)
    scale = expected_raw.std(axis=0, dtype=np.float64, ddof=1)
    expected_normalized = ((expected_raw - center) / scale).astype(np.float32)
    if not np.array_equal(expected_normalized, statics):
        raise ValueError("sealed statics differ from independent float64 ddof=1 normalization")
    return {"values_compared": int(expected_raw.size), "ddof": 1}


def _audit_targets_against_source(
    *,
    target_path: Path,
    contract: Mapping,
    target_dates: np.ndarray,
    targets: np.ndarray,
) -> dict:
    if sha256_file(target_path) != contract["target_bundle_sha256"]:
        raise ValueError("independent target source hash drift")
    expected_rows = targets.shape[0] * targets.shape[1]
    row_index = 0
    with Path(target_path).open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != ["basin", "date", "qobs"]:
            raise ValueError("independent target source-column audit failed")
        for row in reader:
            if row_index >= expected_rows:
                raise ValueError("independent target audit found extra rows")
            basin_index, date_index = divmod(row_index, targets.shape[1])
            if str(row["basin"]).zfill(8) != contract["basins"][basin_index]:
                raise ValueError("independent target basin order audit failed")
            if np.datetime64(row["date"], "D") != target_dates[date_index]:
                raise ValueError("independent target date order audit failed")
            if np.float32(float(row["qobs"])) != targets[basin_index, date_index]:
                raise ValueError("sealed target differs from the audited target CSV")
            row_index += 1
    if row_index != expected_rows:
        raise ValueError("independent target coverage audit failed")
    return {"rows_compared": row_index, "values_compared": row_index}


def _independent_scaler(
    forcing: np.ndarray,
    dates: np.ndarray,
    targets: np.ndarray,
    target_dates: np.ndarray,
    raw_statics: np.ndarray,
) -> dict:
    start = int(np.nonzero(dates == target_dates[0])[0][0])
    end = int(np.nonzero(dates == target_dates[-1])[0][0]) + 1
    training_forcing = forcing[:, start:end, :]
    target64 = np.asarray(targets, dtype=np.float64)
    static64 = np.asarray(raw_statics, dtype=np.float64)
    return {
        "dynamic_center_float64": training_forcing.mean(axis=(0, 1), dtype=np.float64),
        "dynamic_scale_float64": training_forcing.std(axis=(0, 1), dtype=np.float64, ddof=0),
        "target_center_float64": float(target64.mean(dtype=np.float64)),
        "target_scale_float64": float(target64.std(dtype=np.float64, ddof=0)),
        "per_basin_target_scale_float64": target64.std(axis=1, dtype=np.float64, ddof=0),
        "static_center_float64": static64.mean(axis=0, dtype=np.float64),
        "static_scale_float64": static64.std(axis=0, dtype=np.float64, ddof=1),
    }


def _audit_resource_evidence(resource: Mapping, contract: Mapping) -> None:
    from formal_input_resources_v09 import formal_input_lock_path_v09

    estimate = resource.get("estimate")
    if not isinstance(estimate, Mapping) or estimate.get("method") != "analytical_input_seal_working_set_v1":
        raise ValueError("formal resource estimate is missing or invalid")
    evidence = estimate.get("evidence")
    expected_evidence = {
        "method": "analytical_input_seal_working_set_v1",
        "contract_sha256": contract["contract_sha256"],
        "formula": (
            "fixed_overhead + maurer_rows_per_basin*maurer_row_bytes_upper_bound + "
            "target_rows_per_basin*target_row_bytes_upper_bound + static_bytes*static_copy_count + "
            "hash_buffer + serialization_buffer"
        ),
        "fixed_overhead_bytes": 384 * _MIB,
        "maurer_rows_per_basin": 10_593,
        "maurer_row_bytes_upper_bound": 1_024,
        "target_rows_per_basin": int(contract["target_shape"][1]),
        "target_row_bytes_upper_bound": 512,
        "static_bytes": int(contract["basin_count"]) * len(contract["static_columns"]) * 8,
        "static_copy_count": 6,
        "hash_buffer_bytes": _MIB,
        "serialization_buffer_bytes": 64 * _MIB,
        "memory_mapped_full_arrays_counted_as_resident": False,
    }
    expected_peak = (
        expected_evidence["fixed_overhead_bytes"]
        + expected_evidence["maurer_rows_per_basin"] * expected_evidence["maurer_row_bytes_upper_bound"]
        + expected_evidence["target_rows_per_basin"] * expected_evidence["target_row_bytes_upper_bound"]
        + expected_evidence["static_bytes"] * expected_evidence["static_copy_count"]
        + expected_evidence["hash_buffer_bytes"]
        + expected_evidence["serialization_buffer_bytes"]
    )
    if (
        evidence != expected_evidence
        or estimate.get("estimated_peak_bytes") != expected_peak
        or estimate.get("evidence_sha256") != canonical_sha256(expected_evidence)
    ):
        raise ValueError("formal resource estimate differs from independent recomputation")
    guarded = (expected_peak * 5 + 3) // 4
    expected_lock_path = str(formal_input_lock_path_v09())
    for name in ("start", "entry"):
        report = resource.get(name)
        if (
            not isinstance(report, Mapping)
            or report.get("safe") is not True
            or report.get("guarded_estimated_peak_bytes") != guarded
            or report.get("physical_reserve_bytes") != 2 * _GIB
            or report.get("commit_headroom_reserve_bytes") != 2 * _GIB
            or (report.get("serial_lease") or {}).get("held") is not True
            or (report.get("serial_lease") or {}).get("lock_path") != expected_lock_path
            or report.get("available_after_guarded_peak_bytes", -1) < 2 * _GIB
            or report.get("commit_headroom_after_guarded_peak_bytes", -1) < 2 * _GIB
        ):
            raise ValueError(f"formal resource {name} evidence is invalid")
    checkpoint = resource.get("entry_checkpoint")
    if (
        not isinstance(checkpoint, Mapping)
        or checkpoint.get("safe") is not True
        or checkpoint.get("available_bytes", -1) < 2 * _GIB
        or checkpoint.get("commit_headroom_bytes", -1) < 2 * _GIB
    ):
        raise ValueError("formal resource checkpoint evidence is invalid")


def _audit_formal_provenance(
    *,
    manifest: Mapping,
    contract: Mapping,
    authorization_path: Path | None,
    consumption_path: Path | None,
) -> None:
    if not str(contract.get("schema", "")).startswith("historical_multiscale_formal_v09"):
        return
    worktree_root = Path(__file__).resolve().parents[2]
    source_tree = manifest.get("source_tree")
    if not isinstance(source_tree, Mapping) or not source_tree.get("files"):
        raise ValueError("formal source-tree evidence is missing")
    files = source_tree["files"]
    if tuple(item.get("relative_path") for item in files) != _EXPECTED_SOURCE_TREE_FILES:
        raise ValueError("formal source-tree file inventory drift")
    if source_tree.get("tree_sha256") != canonical_sha256(files):
        raise ValueError("formal source-tree digest drift")
    for item in files:
        path = worktree_root / item["relative_path"]
        assert_no_reparse_components(worktree_root, path)
        if sha256_file(path) != item["sha256"]:
            raise ValueError("formal source-tree file drift")
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=worktree_root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=worktree_root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    if source_tree.get("git_commit") != commit or source_tree.get("git_worktree_clean") is not True or status:
        raise ValueError("formal source-tree Git binding drift")
    if source_tree.get("environment") != environment_fingerprint_v09(worktree_root):
        raise ValueError("formal input environment fingerprint drift")
    _audit_resource_evidence(manifest.get("resource_evidence", {}), contract)
    _audit_authorization_evidence(
        manifest=manifest,
        contract=contract,
        source_tree=source_tree,
        authorization_path=authorization_path,
        consumption_path=consumption_path,
    )


def _audit_authorization_evidence(
    *,
    manifest: Mapping,
    contract: Mapping,
    source_tree: Mapping,
    authorization_path: Path | None,
    consumption_path: Path | None,
) -> None:
    if authorization_path is None or consumption_path is None:
        raise ValueError("formal authorization audit paths are required")
    if str(contract.get("schema", "")).startswith("historical_multiscale_formal_v09"):
        worktree_root = Path(__file__).resolve().parents[2]
        assert_no_reparse_components(worktree_root, authorization_path)
        assert_no_reparse_components(worktree_root, consumption_path)
    authorization = json.loads(Path(authorization_path).read_text(encoding="utf-8"))
    consumption = json.loads(Path(consumption_path).read_text(encoding="utf-8"))
    approval = authorization.get("approval") or {}
    if (
        authorization.get("schema") != "historical_multiscale_formal_v09_input_authorization_v1"
        or authorization.get("status") != "authorized_once"
        or authorization.get("allowed_action") != "formal_input_seal_generation"
        or authorization.get("maximum_attempts") != 1
        or authorization.get("contract_sha256") != contract["contract_sha256"]
        or authorization.get("protocol_raw_sha256") != contract["protocol_raw_sha256"]
        or authorization.get("protocol_canonical_sha256") != contract["protocol_canonical_sha256"]
        or authorization.get("target_bundle_sha256") != contract["target_bundle_sha256"]
        or authorization.get("target_manifest_sha256") != contract["target_manifest_sha256"]
        or authorization.get("allowed_output") != contract["formal_output"]
        or authorization.get("source_tree") != source_tree
        or approval.get("text") != _PRODUCTION_APPROVAL_TEXT
        or approval.get("sha256") != hashlib.sha256(_PRODUCTION_APPROVAL_TEXT.encode("utf-8")).hexdigest()
    ):
        raise ValueError("formal input authorization evidence drift")
    if (
        consumption.get("schema")
        != "historical_multiscale_formal_v09_input_authorization_consumption_v1"
        or consumption.get("status") != "consumed_once"
        or consumption.get("allowed_action") != "formal_input_seal_generation"
        or consumption.get("authorization_file_sha256") != sha256_file(authorization_path)
        or consumption.get("authorization_canonical_sha256") != canonical_sha256(authorization)
        or consumption.get("contract_sha256") != contract["contract_sha256"]
        or consumption.get("source_tree_sha256") != source_tree["tree_sha256"]
    ):
        raise ValueError("formal input authorization consumption evidence drift")
    recorded = manifest.get("authorization_consumption") or {}
    if (
        {key: value for key, value in recorded.items() if key != "consumption_canonical_sha256"} != consumption
        or recorded.get("consumption_canonical_sha256") != canonical_sha256(consumption)
    ):
        raise ValueError("manifest authorization consumption binding drift")


def audit_input_directory_v09(
    root: str | Path,
    *,
    contract: Mapping,
    require_seal: bool,
    data_root: str | Path,
    static_path: str | Path,
    target_path: str | Path,
    authorization_path: str | Path | None = None,
    consumption_path: str | Path | None = None,
) -> dict:
    """Reopen sealed artifacts and independently compare every value to frozen sources."""
    from formal_input_v09 import CORE_ARTIFACTS_V09, SEALED_ARTIFACTS_V09

    root = Path(root)
    data_root = Path(data_root)
    static_path = Path(static_path)
    target_path = Path(target_path)
    authorization_path = Path(authorization_path) if authorization_path is not None else None
    consumption_path = Path(consumption_path) if consumption_path is not None else None
    formal_path_arguments = {
        "root": root,
        "contract": contract,
        "data_root": data_root,
        "static_path": static_path,
        "target_path": target_path,
        "authorization_path": authorization_path,
        "consumption_path": consumption_path,
    }
    _audit_formal_path_boundaries(**formal_path_arguments)
    assert_no_reparse_tree(root)
    expected_files = SEALED_ARTIFACTS_V09 if require_seal else CORE_ARTIFACTS_V09
    actual = sorted(path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file())
    if actual != sorted(expected_files):
        raise ValueError(f"complete-input artifact inventory drift: {actual}")
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("status") != "complete_before_audit" or manifest.get("contract_sha256") != contract["contract_sha256"]:
        raise ValueError("complete-input manifest status or contract binding drift")
    _audit_formal_provenance(
        manifest=manifest,
        contract=contract,
        authorization_path=authorization_path,
        consumption_path=consumption_path,
    )
    basins = tuple(
        line.strip()
        for line in (root / "basins.txt").read_text(encoding="utf-8").splitlines()
        if line.strip()
    )
    if basins != tuple(contract["basins"]):
        raise ValueError("sealed basin order drift")
    dates = np.load(root / "dates.npy", mmap_mode="r", allow_pickle=False)
    target_dates = np.load(root / "target_dates.npy", mmap_mode="r", allow_pickle=False)
    forcing = np.load(root / "forcing.npy", mmap_mode="r", allow_pickle=False)
    raw_statics = np.load(root / "statics_raw.float64.npy", mmap_mode="r", allow_pickle=False)
    statics = np.load(root / "statics.npy", mmap_mode="r", allow_pickle=False)
    targets = np.load(root / "targets.npy", mmap_mode="r", allow_pickle=False)
    expected_dates = np.arange(
        np.datetime64(contract["forcing_period"][0], "D"),
        np.datetime64(contract["forcing_period"][1], "D") + np.timedelta64(1, "D"),
    )
    expected_target_dates = np.arange(
        np.datetime64(contract["training_period"][0], "D"),
        np.datetime64(contract["training_period"][1], "D") + np.timedelta64(1, "D"),
    )
    if not np.array_equal(dates, expected_dates) or not np.array_equal(target_dates, expected_target_dates):
        raise ValueError("sealed forcing or target dates drift")
    if dates.dtype != np.dtype("datetime64[D]") or list(forcing.shape) != list(contract["forcing_shape"]) or forcing.dtype != np.float32:
        raise ValueError("sealed forcing geometry or dtype drift")
    if target_dates.dtype != np.dtype("datetime64[D]") or list(targets.shape) != list(contract["target_shape"]) or targets.dtype != np.float32:
        raise ValueError("sealed target geometry or dtype drift")
    if raw_statics.shape != (len(basins), len(contract["static_columns"])) or raw_statics.dtype != np.float64:
        raise ValueError("sealed raw-static geometry or dtype drift")
    if statics.shape != raw_statics.shape or statics.dtype != np.float32:
        raise ValueError("sealed normalized-static geometry or dtype drift")
    if not np.isfinite(forcing).all() or not np.isfinite(raw_statics).all() or not np.isfinite(statics).all() or not np.isfinite(targets).all() or np.any(targets < 0):
        raise ValueError("sealed input contains non-finite or negative target values")
    if int(np.count_nonzero(forcing[:, :, 1] == forcing[:, :, 2])) != forcing.shape[0] * forcing.shape[1]:
        raise ValueError("frozen Maurer temperature equality condition drift")
    _audit_formal_path_boundaries(**formal_path_arguments)
    source_audit = {
        "maurer": _audit_maurer_against_sources(
            data_root=data_root,
            contract=contract,
            dates=dates,
            forcing=forcing,
        ),
        "statics": _audit_statics_against_source(
            static_path=static_path,
            contract=contract,
            raw_statics=raw_statics,
            statics=statics,
        ),
        "targets": _audit_targets_against_source(
            target_path=target_path,
            contract=contract,
            target_dates=target_dates,
            targets=targets,
        ),
    }
    if array_payload_sha256(raw_statics) != contract["static_raw_float64_sha256"] or array_payload_sha256(statics) != contract["static_normalized_float32_sha256"]:
        raise ValueError("sealed static payload hash drift")
    scaler = json.loads((root / "scaler.json").read_text(encoding="utf-8"))
    recomputed_scaler = _independent_scaler(forcing, dates, targets, target_dates, raw_statics)
    for key in (
        "dynamic_center_float64",
        "dynamic_scale_float64",
        "per_basin_target_scale_float64",
        "static_center_float64",
        "static_scale_float64",
    ):
        if not _same_float_values(scaler.get(key), recomputed_scaler[key]):
            raise ValueError(f"sealed scaler drift: {key}")
    for key in ("target_center_float64", "target_scale_float64"):
        if float(scaler.get(key, float("nan"))) != recomputed_scaler[key]:
            raise ValueError(f"sealed scaler drift: {key}")
    expected_scaler_metadata = {
        "schema": "historical_multiscale_formal_v09_scaler_v1",
        "dynamic_ddof": 0,
        "target_ddof": 0,
        "static_ddof": 1,
        "training_start": str(expected_target_dates[0]),
        "training_end": str(expected_target_dates[-1]),
        "dynamic_columns": list(contract["dynamic_columns"]),
        "static_columns": list(contract["static_columns"]),
    }
    for key, expected in expected_scaler_metadata.items():
        if scaler.get(key) != expected:
            raise ValueError(f"sealed scaler metadata drift: {key}")
    forcing_manifest = json.loads((root / "forcing_manifest.json").read_text(encoding="utf-8"))
    environment = json.loads((root / "environment.json").read_text(encoding="utf-8"))
    if environment != manifest.get("source_tree", {}).get("environment"):
        raise ValueError("sealed environment differs from the authorized source-tree environment")
    compact_records = [
        {"basin": item["basin"], "relative_path": item["relative_path"], "sha256": item["sha256"]}
        for item in forcing_manifest.get("records", [])
    ]
    if compact_records != list(contract["maurer_sources"]):
        raise ValueError("sealed Maurer source inventory drift")
    if (
        forcing_manifest.get("source_count") != len(basins)
        or forcing_manifest.get("tmin_equals_tmax_rows") != forcing.shape[0] * forcing.shape[1]
        or forcing_manifest.get("forcing_file_sha256") != sha256_file(root / "forcing.npy")
    ):
        raise ValueError("sealed Maurer summary drift")
    expected_array_names = {
        "dates.npy",
        "target_dates.npy",
        "forcing.npy",
        "statics_raw.float64.npy",
        "statics.npy",
        "targets.npy",
    }
    descriptor_by_name = {item["relative_path"]: item for item in manifest.get("arrays", [])}
    if len(manifest.get("arrays", [])) != len(expected_array_names) or set(descriptor_by_name) != expected_array_names:
        raise ValueError("sealed array descriptor inventory drift")
    for name in sorted(expected_array_names):
        descriptor = descriptor_by_name[name]
        value = np.load(root / name, mmap_mode="r", allow_pickle=False)
        if (
            descriptor.get("file_sha256") != sha256_file(root / name)
            or descriptor.get("payload_sha256") != array_payload_sha256(value)
            or descriptor.get("shape") != list(value.shape)
            or descriptor.get("dtype") != value.dtype.str
        ):
            raise ValueError(f"sealed array descriptor drift: {name}")
    if (
        manifest.get("basins_file_sha256") != sha256_file(root / "basins.txt")
        or manifest.get("scaler_file_sha256") != sha256_file(root / "scaler.json")
        or manifest.get("forcing_manifest_file_sha256") != sha256_file(root / "forcing_manifest.json")
        or manifest.get("environment_file_sha256") != sha256_file(root / "environment.json")
    ):
        raise ValueError("sealed non-array artifact hash drift")
    manifest_contract_fields = {
        "protocol_raw_sha256": contract["protocol_raw_sha256"],
        "protocol_canonical_sha256": contract["protocol_canonical_sha256"],
        "basin_count": len(basins),
        "forcing_period": list(contract["forcing_period"]),
        "training_period": list(contract["training_period"]),
        "dynamic_columns": list(contract["dynamic_columns"]),
        "static_columns": list(contract["static_columns"]),
        "target_bundle_sha256": contract["target_bundle_sha256"],
        "target_manifest_sha256": contract["target_manifest_sha256"],
    }
    for key, expected in manifest_contract_fields.items():
        if manifest.get(key) != expected:
            raise ValueError(f"complete-input manifest field drift: {key}")
    evaluation_start = np.datetime64(contract["evaluation_period"][0], "D")
    evaluation_end = np.datetime64(contract["evaluation_period"][1], "D")
    evaluation_targets_present = int(np.count_nonzero((target_dates >= evaluation_start) & (target_dates <= evaluation_end)))
    if evaluation_targets_present != 0:
        raise ValueError("sealed target dates intersect the formal evaluation period")
    report = {
        "schema": "historical_multiscale_formal_v09_complete_input_audit_v1",
        "status": "complete_input_audit_passed",
        "phase": "post_seal" if require_seal else "pre_promotion",
        "contract_sha256": contract["contract_sha256"],
        "basin_count": len(basins),
        "forcing_rows": int(np.prod(forcing.shape[:2])),
        "target_rows": int(np.prod(targets.shape)),
        "tmin_equals_tmax_rows": int(forcing.shape[0] * forcing.shape[1]),
        "formal_evaluation_targets_present": evaluation_targets_present,
        "independent_source_audit": source_audit,
    }
    if require_seal:
        stored_audit = json.loads((root / "input_audit.json").read_text(encoding="utf-8"))
        if stored_audit != {**report, "phase": "pre_promotion"}:
            raise ValueError("stored pre-promotion input audit drift")
        seal = json.loads((root / "seal.json").read_text(encoding="utf-8"))
        sealed_inventory = exact_file_inventory(
            root,
            (*CORE_ARTIFACTS_V09, "input_audit.json", "seal.json"),
        )
        without_seal = [item for item in sealed_inventory if item["relative_path"] != "seal.json"]
        if (
            seal.get("status") != "sealed"
            or seal.get("contract_sha256") != contract["contract_sha256"]
            or seal.get("sealed_files") != without_seal
            or seal.get("sealed_files_sha256") != canonical_sha256(without_seal)
        ):
            raise ValueError("complete-input seal drift")
    _audit_formal_path_boundaries(**formal_path_arguments)
    assert_no_reparse_tree(root)
    return report
