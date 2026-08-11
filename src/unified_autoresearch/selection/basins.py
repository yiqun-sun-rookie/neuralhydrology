"""Deterministically cover the static-attribute space without using discharge."""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd


SELECTION_METHOD = "deterministic_standardized_farthest_point_v1"
APPROVED_STATIC_ATTRIBUTES = (
    "p_mean",
    "pet_mean",
    "aridity",
    "p_seasonality",
    "frac_snow",
    "high_prec_freq",
    "high_prec_dur",
    "low_prec_freq",
    "low_prec_dur",
    "elev_mean",
    "slope_mean",
    "area_gages2",
    "frac_forest",
    "lai_max",
    "lai_diff",
    "gvf_max",
    "gvf_diff",
    "soil_depth_pelletier",
    "soil_depth_statsgo",
    "soil_porosity",
    "soil_conductivity",
    "max_water_content",
    "sand_frac",
    "silt_frac",
    "clay_frac",
    "carbonate_rocks_frac",
    "geol_permeability",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _eligible_basins(path: Path) -> list[str]:
    basins = [line.strip().zfill(8) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(basins) != len(set(basins)):
        raise ValueError("eligible basin list contains duplicates")
    return sorted(basins)


def _load_static_matrix(static_path: Path, basin_path: Path) -> tuple[list[str], np.ndarray]:
    frame = pd.read_csv(static_path, dtype={"gauge_id": str})
    if "gauge_id" not in frame.columns or len(frame.columns) != 28:
        raise ValueError("selection requires exactly 27 approved static attributes plus gauge_id")
    supplied_static_columns = [column for column in frame.columns if column != "gauge_id"]
    if set(supplied_static_columns) != set(APPROVED_STATIC_ATTRIBUTES):
        raise ValueError("selection requires exactly 27 approved static attributes plus gauge_id")
    static_columns = list(APPROVED_STATIC_ATTRIBUTES)
    try:
        numeric = frame[static_columns].apply(pd.to_numeric, errors="raise")
    except (TypeError, ValueError) as error:
        raise ValueError("all approved static attributes must be numeric") from error

    frame = frame.copy()
    frame["gauge_id"] = frame["gauge_id"].str.zfill(8)
    frame[static_columns] = numeric
    if frame["gauge_id"].duplicated().any():
        raise ValueError("static attribute table contains duplicate gauge_id values")

    eligible = _eligible_basins(basin_path)
    indexed = frame.set_index("gauge_id")
    missing = sorted(set(eligible) - set(indexed.index))
    if missing:
        raise ValueError(f"static attributes missing for {len(missing)} eligible basins")
    selected = indexed.loc[eligible, static_columns].copy()
    selected = selected.fillna(selected.median(axis=0)).fillna(0.0)
    values = selected.to_numpy(dtype=np.float64)
    scale = values.std(axis=0)
    scale[scale == 0.0] = 1.0
    standardized = (values - values.mean(axis=0)) / scale
    return eligible, standardized


def select_development_basins(static_path: str | Path, basin_path: str | Path, *, count: int = 8) -> list[str]:
    """Select a deterministic farthest-point cover of the static-attribute space."""
    static_path = Path(static_path).resolve()
    basin_path = Path(basin_path).resolve()
    basins, matrix = _load_static_matrix(static_path, basin_path)
    if count < 1 or count > len(basins):
        raise ValueError("selection count must be between one and the number of eligible basins")

    distance_from_center = np.square(matrix).sum(axis=1)
    first = int(np.argmax(distance_from_center))
    chosen = [first]
    minimum_distance = np.square(matrix - matrix[first]).sum(axis=1)
    minimum_distance[first] = -1.0
    while len(chosen) < count:
        next_index = int(np.argmax(minimum_distance))
        chosen.append(next_index)
        candidate_distance = np.square(matrix - matrix[next_index]).sum(axis=1)
        minimum_distance = np.minimum(minimum_distance, candidate_distance)
        minimum_distance[chosen] = -1.0
    return [basins[index] for index in chosen]


def select_development_basin_block(
    static_path: str | Path,
    basin_path: str | Path,
    *,
    rank_start: int,
    count: int,
) -> list[str]:
    """Return one contiguous, one-based block from the deterministic basin ordering."""
    if (
        not isinstance(rank_start, int)
        or isinstance(rank_start, bool)
        or not isinstance(count, int)
        or isinstance(count, bool)
        or rank_start < 1
        or count < 1
    ):
        raise ValueError("selection rank range must contain positive integers")
    rank_end = rank_start + count - 1
    eligible_count = len(_eligible_basins(Path(basin_path).resolve()))
    if rank_end > eligible_count:
        raise ValueError("selection rank range exceeds the eligible basin count")
    ranked = select_development_basins(static_path, basin_path, count=rank_end)
    return ranked[rank_start - 1 : rank_end]


def _write_json_exclusive(output_path: Path, record: dict) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{output_path.name}.", suffix=".tmp", dir=output_path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(record, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary_path, output_path)
        except FileExistsError:
            raise FileExistsError(output_path) from None
    finally:
        temporary_path.unlink(missing_ok=True)


def freeze_selection(
    static_path: str | Path,
    basin_path: str | Path,
    output_path: str | Path,
    *,
    count: int = 8,
) -> dict:
    """Atomically create, but never replace, a frozen development-basin record."""
    static_path = Path(static_path).resolve()
    basin_path = Path(basin_path).resolve()
    output_path = Path(output_path).resolve()
    if output_path.exists():
        raise FileExistsError(output_path)
    record = {
        "schema_version": 1,
        "selection_method": SELECTION_METHOD,
        "selection_inputs": "static attributes only; no discharge or model results",
        "static_sha256": _sha256(static_path),
        "eligible_basins_sha256": _sha256(basin_path),
        "basins": select_development_basins(static_path, basin_path, count=count),
    }
    _write_json_exclusive(output_path, record)
    return record


def freeze_selection_block(
    static_path: str | Path,
    basin_path: str | Path,
    historical_selection_path: str | Path,
    output_path: str | Path,
    *,
    rank_start: int,
    count: int,
) -> dict:
    """Freeze a result-independent basin block and bind it to the preceding historical prefix."""
    static_path = Path(static_path).resolve()
    basin_path = Path(basin_path).resolve()
    historical_selection_path = Path(historical_selection_path).resolve()
    output_path = Path(output_path).resolve()
    if output_path.exists():
        raise FileExistsError(output_path)
    if not isinstance(rank_start, int) or isinstance(rank_start, bool) or rank_start < 2:
        raise ValueError("selection rank range requires a preceding historical prefix")
    selected = select_development_basin_block(
        static_path,
        basin_path,
        rank_start=rank_start,
        count=count,
    )
    historical = json.loads(historical_selection_path.read_text(encoding="utf-8"))
    expected_prefix = select_development_basins(static_path, basin_path, count=rank_start - 1)
    if historical.get("basins") != expected_prefix:
        raise ValueError("historical selection does not match the preceding deterministic prefix")
    record = {
        "schema_version": 1,
        "selection_method": "deterministic_standardized_farthest_point_block_v1",
        "selection_inputs": "static attributes only; no discharge or model results",
        "static_sha256": _sha256(static_path),
        "eligible_basins_sha256": _sha256(basin_path),
        "historical_selection_sha256": _sha256(historical_selection_path),
        "selection_rank_range": [rank_start, rank_start + count - 1],
        "basins": selected,
    }
    _write_json_exclusive(output_path, record)
    return record
