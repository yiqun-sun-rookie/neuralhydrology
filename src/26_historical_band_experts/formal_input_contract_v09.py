"""Frozen allowed-input contract for the formal version 09 complete input seal."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Mapping

from artifact_v09 import canonical_sha256, sha256_file
from formal_v09_protocol import load_protocol_v09


IDEA_ROOT = Path(__file__).resolve().parent
WORKTREE_ROOT = IDEA_ROOT.parents[1]
DEFAULT_PROTOCOL = IDEA_ROOT / "configs/formal_v09_protocol.json"
DEFAULT_TARGET = WORKTREE_ROOT / "results/26_historical_band_experts/formal_v09/inputs/training_targets.csv"
DEFAULT_TARGET_MANIFEST = DEFAULT_TARGET.with_suffix(".manifest.json")
FORMAL_OUTPUT_RELATIVE = Path("results/26_historical_band_experts/formal_v09/input_attempt_01")
FORMAL_BUILDING_RELATIVE = Path(str(FORMAL_OUTPUT_RELATIVE) + ".building")
TARGET_BUNDLE_SHA256 = "6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb"
TARGET_MANIFEST_SHA256 = "3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8"
PROTOCOL_RAW_SHA256 = "2a018755422eb102259eba11558bc190ba11034d3390f64df7bbc54e8756a0f7"
PROTOCOL_CANONICAL_SHA256 = "d2652a0415677ced1656e24485688c3a3f542e11cdd173523899b6f6d04d184c"
STATIC_RAW_FLOAT64_SHA256 = "6c59dcad191e71bf5f7acabb91f7117882d7d1f6736be4d94193921c57dc60a3"
STATIC_NORMALIZED_FLOAT32_SHA256 = "aa53d1d06247b246f5557efe6761b9b7becd2be3a680f99d667d2e3c89b9b37a"

DYNAMIC_COLUMNS_V09 = (
    "PRCP(mm/day)",
    "Tmin(C)",
    "Tmax(C)",
    "SRAD(W/m2)",
    "Vp(Pa)",
)
FORMAL_V09_STATIC_COLUMNS = (
    "area_gages2",
    "aridity",
    "carbonate_rocks_frac",
    "clay_frac",
    "elev_mean",
    "frac_forest",
    "frac_snow",
    "geol_permeability",
    "gvf_diff",
    "gvf_max",
    "high_prec_dur",
    "high_prec_freq",
    "lai_diff",
    "lai_max",
    "low_prec_dur",
    "low_prec_freq",
    "max_water_content",
    "p_mean",
    "p_seasonality",
    "pet_mean",
    "sand_frac",
    "silt_frac",
    "slope_mean",
    "soil_conductivity",
    "soil_depth_pelletier",
    "soil_depth_statsgo",
    "soil_porosity",
)


def primary_repository_root_v09() -> Path:
    if WORKTREE_ROOT.parent.name == ".worktrees":
        return WORKTREE_ROOT.parents[1]
    return WORKTREE_ROOT


def _load_basins(path: Path) -> list[str]:
    basins = [line.strip().zfill(8) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(basins) != 531 or len(set(basins)) != 531 or any(len(value) != 8 or not value.isdigit() for value in basins):
        raise ValueError("formal basin list must contain 531 unique eight-digit identifiers")
    return basins


def _maurer_inventory(manifest: Mapping, basins: list[str]) -> list[dict]:
    records = [
        {"basin": str(item.get("basin", "")).zfill(8), "relative_path": item.get("relative_path"), "sha256": item.get("sha256")}
        for item in manifest.get("source_files", [])
        if item.get("kind") == "maurer"
    ]
    if len(records) != len(basins) or [item["basin"] for item in records] != basins:
        raise ValueError("Maurer source inventory must contain one ordered record per basin")
    if any(not isinstance(item["relative_path"], str) or not isinstance(item["sha256"], str) or len(item["sha256"]) != 64 for item in records):
        raise ValueError("Maurer source inventory contains an invalid record")
    for item in records:
        relative = Path(item["relative_path"])
        if relative.is_absolute() or ".." in relative.parts or relative.parts[:2] != ("basin_mean_forcing", "maurer"):
            raise ValueError("Maurer source inventory must remain below the canonical Maurer root")
    return records


def load_formal_input_contract_v09(
    *,
    protocol_path: str | Path = DEFAULT_PROTOCOL,
    target_path: str | Path = DEFAULT_TARGET,
    target_manifest_path: str | Path = DEFAULT_TARGET_MANIFEST,
    expected_target_manifest_sha256: str | None = TARGET_MANIFEST_SHA256,
) -> dict:
    """Load and cross-check the immutable complete-input dependencies."""
    protocol_path = Path(protocol_path)
    target_path = Path(target_path)
    target_manifest_path = Path(target_manifest_path)
    protocol = load_protocol_v09(protocol_path)
    if protocol_path.resolve() == DEFAULT_PROTOCOL.resolve():
        if sha256_file(protocol_path) != PROTOCOL_RAW_SHA256:
            raise ValueError("formal protocol raw SHA-256 drift")
        if canonical_sha256(protocol) != PROTOCOL_CANONICAL_SHA256:
            raise ValueError("formal protocol canonical SHA-256 drift")
    if sha256_file(target_path) != TARGET_BUNDLE_SHA256:
        raise ValueError("target bundle SHA-256 drift")
    if expected_target_manifest_sha256 is not None and sha256_file(target_manifest_path) != expected_target_manifest_sha256:
        raise ValueError("target manifest SHA-256 drift")
    manifest = json.loads(target_manifest_path.read_text(encoding="utf-8"))
    if manifest.get("target_bundle_sha256") != TARGET_BUNDLE_SHA256 or manifest.get("status") != "complete":
        raise ValueError("target manifest does not bind the audited target bundle")
    basin_path = WORKTREE_ROOT / protocol["basin_file"]
    if sha256_file(basin_path) != protocol["basin_file_sha256"]:
        raise ValueError("basin file SHA-256 drift")
    static_path = WORKTREE_ROOT / protocol["static_file"]
    if sha256_file(static_path) != protocol["static_file_sha256"]:
        raise ValueError("static file SHA-256 drift")
    basins = _load_basins(basin_path)
    authorization = dict(protocol["authorization"])
    allowed_true = {"protocol_implementation", "synthetic_tests"}
    if any(value is not (key in allowed_true) for key, value in authorization.items()):
        raise ValueError("formal downstream authorization must remain closed")
    if protocol["formal_evaluation_target_access"] is not False:
        raise ValueError("formal evaluation target access must remain closed")
    contract = {
        "schema": "historical_multiscale_formal_v09_complete_input_contract_v1",
        "protocol_id": protocol["protocol_id"],
        "protocol_raw_sha256": sha256_file(protocol_path),
        "protocol_canonical_sha256": canonical_sha256(protocol),
        "basin_file": protocol["basin_file"],
        "basin_file_sha256": protocol["basin_file_sha256"],
        "basin_count": len(basins),
        "basins": basins,
        "forcing_period": list(protocol["forcing_period"]),
        "training_period": list(protocol["train_period"]),
        "evaluation_period": list(protocol["evaluation_period"]),
        "forcing_shape": [len(basins), protocol["expected_forcing_dates"], len(DYNAMIC_COLUMNS_V09)],
        "target_shape": [len(basins), protocol["expected_training_dates_per_basin"]],
        "dynamic_columns": list(DYNAMIC_COLUMNS_V09),
        "static_columns": list(FORMAL_V09_STATIC_COLUMNS),
        "static_file": protocol["static_file"],
        "static_file_sha256": protocol["static_file_sha256"],
        "static_raw_float64_sha256": STATIC_RAW_FLOAT64_SHA256,
        "static_normalized_float32_sha256": STATIC_NORMALIZED_FLOAT32_SHA256,
        "target_path": DEFAULT_TARGET.relative_to(WORKTREE_ROOT).as_posix(),
        "target_bundle_sha256": TARGET_BUNDLE_SHA256,
        "target_manifest_path": DEFAULT_TARGET_MANIFEST.relative_to(WORKTREE_ROOT).as_posix(),
        "target_manifest_sha256": sha256_file(target_manifest_path),
        "maurer_sources": _maurer_inventory(manifest, basins),
        "data_root_relative": "data/camels_us",
        "formal_output": FORMAL_OUTPUT_RELATIVE.as_posix(),
        "formal_building_output": FORMAL_BUILDING_RELATIVE.as_posix(),
        "authorization": authorization,
        "formal_evaluation_target_access": protocol["formal_evaluation_target_access"],
    }
    contract["contract_sha256"] = canonical_sha256(contract)
    return contract
