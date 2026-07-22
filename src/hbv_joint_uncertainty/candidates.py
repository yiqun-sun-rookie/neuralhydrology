"""Frozen parameter and process-noise candidate contracts."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

from .hbv_adapter import HYDRO_STATE_NAMES, PARAMETER_NAMES, V1_PARAMETER_BOUNDS


DEFAULT_CONFIG_PATH = Path("src/hbv_joint_uncertainty/configs/preflight_v01.json")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_preflight_config(repo_root: Path, config_path: Path | None = None) -> dict:
    """Load the frozen JSON and attach the ordered basin list."""
    root = Path(repo_root).resolve()
    path = root / (config_path or DEFAULT_CONFIG_PATH)
    with path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    basin_path = root / config["basin_file"]
    basin_table = pd.read_csv(basin_path, dtype={"basin_id": str})
    basin_table["basin_id"] = basin_table["basin_id"].str.zfill(8)
    basins = basin_table["basin_id"].tolist()
    if len(basins) != 6 or len(set(basins)) != 6:
        raise ValueError("preflight basin file must contain exactly six unique basins")
    config["basins"] = basins
    config["config_path"] = str(path.relative_to(root)).replace("\\", "/")
    return config


def verify_source_artifacts(config: dict, repo_root: Path) -> dict:
    """Verify source checksums and the metadata fields required by the bank."""
    root = Path(repo_root).resolve()
    source = config["parameter_source"]
    table_path = root / source["table_path"]
    metadata_path = root / source["metadata_path"]
    table_hash = sha256_file(table_path)
    metadata_hash = sha256_file(metadata_path)
    if table_hash != source["table_sha256"]:
        raise ValueError(f"parameter table checksum mismatch: {table_hash}")
    if metadata_hash != source["metadata_sha256"]:
        raise ValueError(f"parameter metadata checksum mismatch: {metadata_hash}")
    with metadata_path.open("r", encoding="utf-8") as handle:
        metadata = json.load(handle)
    for key in (
        "forcing",
        "pet_method",
        "bounds_preset",
        "warmup_year",
        "calibration_start",
        "calibration_end",
    ):
        if metadata.get(key) != source[key]:
            raise ValueError(
                f"parameter metadata field {key!r} is {metadata.get(key)!r}, expected {source[key]!r}"
            )
    return {
        "parameter_table_sha256": table_hash,
        "metadata_sha256": metadata_hash,
        **{key: metadata[key] for key in ("forcing", "pet_method", "bounds_preset", "warmup_year")},
    }


def load_trained_parameter_table(config: dict, repo_root: Path) -> pd.DataFrame:
    verify_source_artifacts(config, repo_root)
    path = Path(repo_root).resolve() / config["parameter_source"]["table_path"]
    table = pd.read_csv(path, dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    required = {"basin_id", "run_status", *(f"p_{name}" for name in PARAMETER_NAMES)}
    missing = required - set(table.columns)
    if missing:
        raise ValueError(f"trained parameter table is missing columns: {sorted(missing)}")
    if len(table) != 531 or set(table["run_status"]) != {"success"}:
        raise ValueError("trained parameter table must contain 531 successful rows")
    return table


def extract_center_parameters(table: pd.DataFrame, basin_id: str) -> dict[str, float]:
    rows = table.loc[table["basin_id"] == str(basin_id).zfill(8)]
    if len(rows) != 1:
        raise ValueError(f"expected one trained row for basin {basin_id}, found {len(rows)}")
    row = rows.iloc[0]
    parameters = {name: float(row[f"p_{name}"]) for name in PARAMETER_NAMES}
    for name, value in parameters.items():
        lower, upper = V1_PARAMETER_BOUNDS[name]
        if value < lower or value > upper:
            raise ValueError(f"trained parameter {name}={value} is outside v1 bounds [{lower}, {upper}]")
    return parameters


def extract_saved_warmup_state(table: pd.DataFrame, basin_id: str) -> dict[str, float]:
    """Read the persisted 1989-09-30 evaluation initialization stores."""
    rows = table.loc[table["basin_id"] == str(basin_id).zfill(8)]
    if len(rows) != 1:
        raise ValueError(f"expected one trained row for basin {basin_id}, found {len(rows)}")
    row = rows.iloc[0]
    expected_mode = "warmup_year_end_1989-09-30"
    if row.get("state_init_mode") != expected_mode:
        raise ValueError(
            f"trained row for basin {basin_id} has state_init_mode={row.get('state_init_mode')!r}, "
            f"expected {expected_mode!r}"
        )
    missing = [name for name in HYDRO_STATE_NAMES if f"state_{name}" not in table.columns]
    if missing:
        raise ValueError(f"trained table is missing saved warmup states: {missing}")
    stores = {name: float(row[f"state_{name}"]) for name in HYDRO_STATE_NAMES}
    if not np.all(np.isfinite(list(stores.values()))):
        raise ValueError(f"saved warmup state for basin {basin_id} contains non-finite values")
    return stores


def derive_parameter_vectors(center: dict[str, float], fraction: float = 0.1) -> dict[str, dict[str, float]]:
    if not 0.0 < fraction < 1.0:
        raise ValueError("parameter stress fraction must be between zero and one")
    missing = set(PARAMETER_NAMES) - set(center)
    if missing:
        raise ValueError(f"center parameter vector is missing: {sorted(missing)}")
    lower_vector = {}
    upper_vector = {}
    center_vector = {}
    for name in PARAMETER_NAMES:
        value = float(center[name])
        lower, upper = V1_PARAMETER_BOUNDS[name]
        if value < lower or value > upper:
            raise ValueError(f"center parameter {name}={value} is outside v1 bounds [{lower}, {upper}]")
        lower_vector[name] = value - fraction * (value - lower)
        center_vector[name] = value
        upper_vector[name] = value + fraction * (upper - value)
    return {
        "toward_lower_10pct": lower_vector,
        "trained_center": center_vector,
        "toward_upper_10pct": upper_vector,
    }


@dataclass(frozen=True)
class CandidateDefinition:
    candidate_id: str
    parameter_id: str
    noise_variance_scale: float
    parameters: dict[str, float]
    parameter_group: tuple[float, ...]


def build_candidate_definitions(center: dict[str, float], config: dict) -> list[CandidateDefinition]:
    fraction = float(config["parameter_stress_fraction"])
    if fraction != 0.1:
        raise ValueError("preflight parameter stress fraction must be exactly 0.1")
    vectors = derive_parameter_vectors(center, fraction=fraction)
    noise_scales = tuple(float(value) for value in config["noise_variance_scales"])
    if noise_scales != (1e-5, 1e-4, 1e-3):
        raise ValueError("preflight noise scales must be exactly [1e-5, 1e-4, 1e-3]")
    candidates = []
    for parameter_id, parameters in vectors.items():
        group = tuple(parameters[name] for name in PARAMETER_NAMES)
        for noise_scale in noise_scales:
            candidates.append(
                CandidateDefinition(
                    candidate_id=f"{parameter_id}__noise_{noise_scale:.0e}",
                    parameter_id=parameter_id,
                    noise_variance_scale=noise_scale,
                    parameters=parameters.copy(),
                    parameter_group=group,
                )
            )
    if len({candidate.candidate_id for candidate in candidates}) != len(candidates):
        raise ValueError("candidate identifiers must be unique")
    return candidates
