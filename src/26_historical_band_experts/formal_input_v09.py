"""Atomic complete-input assembly and sealed loading for formal version 09."""
from __future__ import annotations

from collections.abc import Callable, Mapping
import os
from pathlib import Path
from typing import Any
import json
import tempfile

import numpy as np
import pandas as pd

from artifact_v09 import (
    array_payload_sha256,
    assert_no_reparse_components,
    canonical_sha256,
    exact_file_inventory,
    promote_directory,
    sha256_file,
    write_json_atomic,
)
from formal_input_contract_v09 import (
    FORMAL_BUILDING_RELATIVE,
    FORMAL_OUTPUT_RELATIVE,
    WORKTREE_ROOT,
)
from formal_input_resources_v09 import InputSealRuntimeV09
from formal_input_sources_v09 import (
    load_static_arrays_v09,
    write_forcing_array_v09,
    write_target_array_v09,
)


CORE_ARTIFACTS_V09 = (
    "basins.txt",
    "dates.npy",
    "target_dates.npy",
    "forcing.npy",
    "statics_raw.float64.npy",
    "statics.npy",
    "targets.npy",
    "scaler.json",
    "forcing_manifest.json",
    "environment.json",
    "manifest.json",
)
SEALED_ARTIFACTS_V09 = (*CORE_ARTIFACTS_V09, "input_audit.json", "seal.json")


def _save_npy_new(path: Path, value: np.ndarray) -> None:
    if path.exists():
        raise FileExistsError(f"array artifact already exists: {path}")
    with path.open("xb") as handle:
        np.save(handle, value, allow_pickle=False)
        handle.flush()
        os.fsync(handle.fileno())


def _array_descriptor(path: Path) -> dict:
    value = np.load(path, mmap_mode="r", allow_pickle=False)
    return {
        "relative_path": path.name,
        "dtype": value.dtype.str,
        "shape": list(value.shape),
        "payload_sha256": array_payload_sha256(value),
        "file_sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
    }


def compute_scaler_v09(
    forcing: np.ndarray,
    dates: np.ndarray,
    targets: np.ndarray,
    target_dates: np.ndarray,
    statics_raw: np.ndarray,
) -> dict:
    """Compute all normalization values with frozen scopes and precision."""
    dates_day = np.asarray(dates, dtype="datetime64[D]")
    target_days = np.asarray(target_dates, dtype="datetime64[D]")
    if target_days.ndim != 1 or len(target_days) == 0:
        raise ValueError("target dates must be a nonempty one-dimensional array")
    start_matches = np.nonzero(dates_day == target_days[0])[0]
    end_matches = np.nonzero(dates_day == target_days[-1])[0]
    if len(start_matches) != 1 or len(end_matches) != 1:
        raise ValueError("training dates are not contained exactly once in forcing dates")
    start, end = int(start_matches[0]), int(end_matches[0]) + 1
    if not np.array_equal(dates_day[start:end], target_days):
        raise ValueError("target dates are not one contiguous forcing-date interval")
    if forcing.shape[:2] != (targets.shape[0], len(dates_day)):
        raise ValueError("forcing geometry is inconsistent with basins and dates")
    if targets.shape != (forcing.shape[0], len(target_days)):
        raise ValueError("target geometry is inconsistent with basins and target dates")
    training_forcing = forcing[:, start:end, :]
    dynamic_center = np.asarray(training_forcing.mean(axis=(0, 1), dtype=np.float64), dtype=np.float64)
    dynamic_scale = np.asarray(training_forcing.std(axis=(0, 1), dtype=np.float64, ddof=0), dtype=np.float64)
    q64 = np.asarray(targets, dtype=np.float64)
    q_center = float(q64.mean(dtype=np.float64))
    q_scale = float(q64.std(dtype=np.float64, ddof=0))
    static64 = np.asarray(statics_raw, dtype=np.float64)
    static_center = np.asarray(static64.mean(axis=0, dtype=np.float64), dtype=np.float64)
    static_scale = np.asarray(static64.std(axis=0, dtype=np.float64, ddof=1), dtype=np.float64)
    if (
        not np.isfinite(dynamic_center).all()
        or not np.isfinite(dynamic_scale).all()
        or np.any(dynamic_scale <= 0)
        or not np.isfinite(q_center)
        or not np.isfinite(q_scale)
        or q_scale <= 0
        or not np.isfinite(static_scale).all()
        or np.any(static_scale <= 0)
    ):
        raise ValueError("normalization scales must be finite and positive")
    return {
        "schema": "historical_multiscale_formal_v09_scaler_v1",
        "dynamic_ddof": 0,
        "target_ddof": 0,
        "static_ddof": 1,
        "training_start": str(target_days[0]),
        "training_end": str(target_days[-1]),
        "dynamic_center_float64": dynamic_center.tolist(),
        "dynamic_scale_float64": dynamic_scale.tolist(),
        "target_center_float64": q_center,
        "target_scale_float64": q_scale,
        "per_basin_target_scale_float64": q64.std(axis=1, dtype=np.float64, ddof=0).tolist(),
        "static_center_float64": static_center.tolist(),
        "static_scale_float64": static_scale.tolist(),
    }


def _formal_output_context(building_root: Path, runtime: InputSealRuntimeV09 | None) -> None:
    declared_formal_root = WORKTREE_ROOT / "results/26_historical_band_experts/formal_v09"
    absolute_building = Path(os.path.abspath(building_root))
    if (
        absolute_building == declared_formal_root
        or declared_formal_root in absolute_building.parents
        or runtime is not None
    ):
        assert_no_reparse_components(WORKTREE_ROOT, absolute_building)
    formal_root = declared_formal_root.resolve()
    resolved = building_root.resolve()
    inside = resolved == formal_root or formal_root in resolved.parents
    if inside:
        expected = (WORKTREE_ROOT / FORMAL_BUILDING_RELATIVE).resolve()
        if (
            resolved != expected
            or runtime is None
            or not runtime.is_formal_production_capability()
        ):
            raise ValueError("formal input directory requires the live authorized runtime capability")
    elif runtime is not None:
        raise ValueError("formal runtime cannot publish outside the fixed formal result tree")
    else:
        temporary_root = Path(tempfile.gettempdir()).resolve()
        if resolved != temporary_root and temporary_root not in resolved.parents:
            raise ValueError("synthetic input seals may be written only below the user temporary directory")
        assert_no_reparse_components(temporary_root, absolute_building)
        normalized = "/".join(part.casefold() for part in resolved.parts)
        if "results/26_historical_band_experts/formal_v09" in normalized:
            raise ValueError("synthetic input seals cannot use any formal version-09 result path")


def _build_input_directory_v09(
    *,
    contract: Mapping,
    data_root: str | Path,
    static_path: str | Path,
    target_path: str | Path,
    building_root: str | Path,
    source_tree: Mapping,
    resource_evidence: Mapping,
    authorization_consumption: Mapping,
    authorization_path: str | Path | None = None,
    consumption_path: str | Path | None = None,
    runtime: InputSealRuntimeV09 | None = None,
    checkpoint: Callable[[], object] | None = None,
) -> dict:
    building_root = Path(building_root)
    _formal_output_context(building_root, runtime)
    if runtime is not None and runtime.contract["contract_sha256"] != contract["contract_sha256"]:
        raise ValueError("formal input runtime contract differs from the requested build contract")
    if runtime is not None:
        assert_no_reparse_components(WORKTREE_ROOT, static_path)
        assert_no_reparse_components(WORKTREE_ROOT, target_path)
    if building_root.exists():
        raise FileExistsError(f"input building directory already exists: {building_root}")
    building_root.parent.mkdir(parents=True, exist_ok=True)
    building_root.mkdir()
    _formal_output_context(building_root, runtime)
    checkpoint = runtime.checkpoint if runtime is not None else checkpoint

    basins = tuple(contract["basins"])
    forcing_dates = pd.date_range(*contract["forcing_period"], freq="D")
    target_dates = pd.date_range(*contract["training_period"], freq="D")
    if list(contract["forcing_shape"]) != [len(basins), len(forcing_dates), 5]:
        raise ValueError("contract forcing geometry is inconsistent")
    if list(contract["target_shape"]) != [len(basins), len(target_dates)]:
        raise ValueError("contract target geometry is inconsistent")

    (building_root / "basins.txt").write_text("".join(f"{basin}\n" for basin in basins), encoding="utf-8", newline="\n")
    _save_npy_new(building_root / "dates.npy", forcing_dates.to_numpy(dtype="datetime64[D]"))
    _save_npy_new(building_root / "target_dates.npy", target_dates.to_numpy(dtype="datetime64[D]"))
    forcing_report = write_forcing_array_v09(
        data_root=data_root,
        sources=contract["maurer_sources"],
        basins=basins,
        expected_dates=forcing_dates,
        output_path=building_root / "forcing.npy",
        checkpoint=checkpoint,
    )
    write_json_atomic(building_root / "forcing_manifest.json", forcing_report)
    raw_statics, normalized_statics, static_scaler = load_static_arrays_v09(
        static_path,
        expected_sha256=contract["static_file_sha256"],
        basins=basins,
    )
    if static_scaler["raw_float64_sha256"] != contract["static_raw_float64_sha256"]:
        raise ValueError("raw static payload differs from the complete-input contract")
    if static_scaler["normalized_float32_sha256"] != contract["static_normalized_float32_sha256"]:
        raise ValueError("normalized static payload differs from the complete-input contract")
    _save_npy_new(building_root / "statics_raw.float64.npy", raw_statics)
    _save_npy_new(building_root / "statics.npy", normalized_statics)
    write_target_array_v09(
        target_path,
        expected_sha256=contract["target_bundle_sha256"],
        basins=basins,
        expected_dates=target_dates,
        output_path=building_root / "targets.npy",
        checkpoint=checkpoint,
    )
    forcing = np.load(building_root / "forcing.npy", mmap_mode="r", allow_pickle=False)
    targets = np.load(building_root / "targets.npy", mmap_mode="r", allow_pickle=False)
    scaler = compute_scaler_v09(
        forcing,
        forcing_dates.to_numpy(dtype="datetime64[D]"),
        targets,
        target_dates.to_numpy(dtype="datetime64[D]"),
        raw_statics,
    )
    scaler["dynamic_columns"] = list(contract["dynamic_columns"])
    scaler["static_columns"] = list(contract["static_columns"])
    write_json_atomic(building_root / "scaler.json", scaler)
    environment = source_tree.get("environment")
    if not isinstance(environment, Mapping):
        raise ValueError("input source tree must bind one environment fingerprint")
    write_json_atomic(building_root / "environment.json", environment)
    if checkpoint is not None:
        checkpoint()

    array_names = (
        "dates.npy",
        "target_dates.npy",
        "forcing.npy",
        "statics_raw.float64.npy",
        "statics.npy",
        "targets.npy",
    )
    manifest = {
        "schema": "historical_multiscale_formal_v09_complete_input_manifest_v1",
        "status": "complete_before_audit",
        "contract_sha256": contract["contract_sha256"],
        "protocol_raw_sha256": contract["protocol_raw_sha256"],
        "protocol_canonical_sha256": contract["protocol_canonical_sha256"],
        "basin_count": len(basins),
        "forcing_period": list(contract["forcing_period"]),
        "training_period": list(contract["training_period"]),
        "dynamic_columns": list(contract["dynamic_columns"]),
        "static_columns": list(contract["static_columns"]),
        "target_bundle_sha256": contract["target_bundle_sha256"],
        "target_manifest_sha256": contract["target_manifest_sha256"],
        "arrays": [_array_descriptor(building_root / name) for name in array_names],
        "basins_file_sha256": sha256_file(building_root / "basins.txt"),
        "scaler_file_sha256": sha256_file(building_root / "scaler.json"),
        "forcing_manifest_file_sha256": sha256_file(building_root / "forcing_manifest.json"),
        "environment_file_sha256": sha256_file(building_root / "environment.json"),
        "source_tree": dict(source_tree),
        "resource_evidence": dict(resource_evidence),
        "authorization_consumption": dict(authorization_consumption),
    }
    write_json_atomic(building_root / "manifest.json", manifest)

    from audit_formal_inputs_v09 import audit_input_directory_v09

    audit = audit_input_directory_v09(
        building_root,
        contract=contract,
        require_seal=False,
        data_root=data_root,
        static_path=static_path,
        target_path=target_path,
        authorization_path=authorization_path,
        consumption_path=consumption_path,
    )
    write_json_atomic(building_root / "input_audit.json", audit)
    sealed_inventory = exact_file_inventory(
        building_root,
        (*CORE_ARTIFACTS_V09, "input_audit.json"),
    )
    seal = {
        "schema": "historical_multiscale_formal_v09_complete_input_seal_v1",
        "status": "sealed",
        "contract_sha256": contract["contract_sha256"],
        "sealed_files": sealed_inventory,
        "sealed_files_sha256": canonical_sha256(sealed_inventory),
    }
    write_json_atomic(building_root / "seal.json", seal)
    final_audit = audit_input_directory_v09(
        building_root,
        contract=contract,
        require_seal=True,
        data_root=data_root,
        static_path=static_path,
        target_path=target_path,
        authorization_path=authorization_path,
        consumption_path=consumption_path,
    )
    return final_audit


def build_synthetic_input_seal_v09(**kwargs) -> dict:
    """Build a tiny complete-input seal only outside the formal result tree."""
    kwargs["runtime"] = None
    return _build_input_directory_v09(**kwargs)


def load_sealed_inputs_v09(
    root: str | Path,
    *,
    contract: Mapping,
    data_root: str | Path,
    static_path: str | Path,
    target_path: str | Path,
    authorization_path: str | Path | None = None,
    consumption_path: str | Path | None = None,
) -> dict[str, Any]:
    """Return only model-consumable sealed arrays; raw statics remain audit-only."""
    from audit_formal_inputs_v09 import audit_input_directory_v09

    root = Path(root)
    audit_input_directory_v09(
        root,
        contract=contract,
        require_seal=True,
        data_root=data_root,
        static_path=static_path,
        target_path=target_path,
        authorization_path=authorization_path,
        consumption_path=consumption_path,
    )
    return {
        "basins": tuple(line.strip() for line in (root / "basins.txt").read_text(encoding="utf-8").splitlines() if line.strip()),
        "dates": np.load(root / "dates.npy", mmap_mode="r", allow_pickle=False),
        "target_dates": np.load(root / "target_dates.npy", mmap_mode="r", allow_pickle=False),
        "forcing": np.load(root / "forcing.npy", mmap_mode="r", allow_pickle=False),
        "statics": np.load(root / "statics.npy", mmap_mode="r", allow_pickle=False),
        "targets": np.load(root / "targets.npy", mmap_mode="r", allow_pickle=False),
        "scaler": json.loads((root / "scaler.json").read_text(encoding="utf-8")),
    }
