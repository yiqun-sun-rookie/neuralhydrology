"""Streaming allowed-input readers for the formal version 09 input seal."""
from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
import csv
from pathlib import Path

import numpy as np
import pandas as pd

from artifact_v09 import array_payload_sha256, assert_no_reparse_components, sha256_file
from data import STATIC_COLUMNS as SOURCE_STATIC_COLUMNS_V09
from formal_input_contract_v09 import DYNAMIC_COLUMNS_V09, FORMAL_V09_STATIC_COLUMNS


_MAURER_SOURCE_COLUMNS = (
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


def read_maurer_window_v09(
    path: str | Path,
    *,
    expected_sha256: str,
    expected_dates: pd.DatetimeIndex,
) -> tuple[np.ndarray, dict]:
    """Read one hash-bound Maurer file and return the fixed five model columns."""
    path = Path(path)
    before = sha256_file(path)
    if before != expected_sha256:
        raise ValueError(f"Maurer source SHA-256 mismatch: expected {expected_sha256}, got {before}")
    frame = pd.read_csv(path, sep=r"\s+", skiprows=3)
    if tuple(frame.columns) != _MAURER_SOURCE_COLUMNS:
        raise ValueError("Maurer source header differs from the frozen schema")
    dates = pd.to_datetime(
        {"year": frame["Year"], "month": frame["Mnth"], "day": frame["Day"]},
        errors="raise",
    )
    if dates.duplicated().any():
        raise ValueError("Maurer source contains duplicate dates")
    frame.index = pd.DatetimeIndex(dates)
    selected = frame.reindex(expected_dates)
    if selected.isna().any().any():
        raise ValueError("Maurer source does not cover the complete expected period")
    values = np.ascontiguousarray(selected.loc[:, list(DYNAMIC_COLUMNS_V09)].to_numpy(dtype=np.float32))
    if not np.isfinite(values).all():
        raise ValueError("Maurer source contains non-finite allowed inputs")
    after = sha256_file(path)
    if after != before:
        raise ValueError("Maurer source changed while it was read")
    equal_rows = int(np.count_nonzero(values[:, 1] == values[:, 2]))
    return values, {
        "sha256": before,
        "rows": len(expected_dates),
        "tmin_equals_tmax_rows": equal_rows,
    }


def _validate_output_path(path: Path) -> None:
    if path.exists():
        raise FileExistsError(f"array artifact already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)


def write_forcing_array_v09(
    *,
    data_root: str | Path,
    sources: Sequence[Mapping],
    basins: Sequence[str],
    expected_dates: pd.DatetimeIndex,
    output_path: str | Path,
    checkpoint: Callable[[], object] | None = None,
) -> dict:
    """Write a complete forcing memory map while holding only one basin in memory."""
    data_root = Path(data_root).resolve()
    output_path = Path(output_path)
    _validate_output_path(output_path)
    basin_ids = tuple(str(value).zfill(8) for value in basins)
    if len(sources) != len(basin_ids) or [str(item.get("basin", "")).zfill(8) for item in sources] != list(basin_ids):
        raise ValueError("Maurer source inventory order differs from the basin order")
    output = np.lib.format.open_memmap(
        output_path,
        mode="w+",
        dtype=np.float32,
        shape=(len(basin_ids), len(expected_dates), len(DYNAMIC_COLUMNS_V09)),
    )
    records = []
    equal_rows = 0
    if checkpoint is not None:
        checkpoint()
    for basin_index, (basin, source) in enumerate(zip(basin_ids, sources, strict=True)):
        relative = Path(str(source["relative_path"]))
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Maurer source path must remain inside the canonical root")
        candidate = data_root / relative
        assert_no_reparse_components(data_root, candidate)
        path = candidate.resolve()
        if data_root not in path.parents:
            raise ValueError("Maurer source path escapes the canonical root")
        values, report = read_maurer_window_v09(
            path,
            expected_sha256=str(source["sha256"]),
            expected_dates=expected_dates,
        )
        output[basin_index] = values
        equal_rows += report["tmin_equals_tmax_rows"]
        records.append({
            "basin": basin,
            "relative_path": relative.as_posix(),
            "sha256": report["sha256"],
            "rows": report["rows"],
            "tmin_equals_tmax_rows": report["tmin_equals_tmax_rows"],
        })
        if checkpoint is not None:
            checkpoint()
    output.flush()
    del output
    return {
        "schema": "stream_one_maurer_basin_v1",
        "source_count": len(records),
        "records": records,
        "tmin_equals_tmax_rows": equal_rows,
        "forcing_file_sha256": sha256_file(output_path),
    }


def load_static_arrays_v09(
    path: str | Path,
    *,
    expected_sha256: str,
    basins: Sequence[str],
) -> tuple[np.ndarray, np.ndarray, dict]:
    """Load raw statics in float64 and normalize in float64 with sample standard deviation."""
    path = Path(path)
    if sha256_file(path) != expected_sha256:
        raise ValueError("static source SHA-256 mismatch")
    frame = pd.read_csv(path, dtype={"gauge_id": str})
    if tuple(frame.columns) != ("gauge_id", *SOURCE_STATIC_COLUMNS_V09):
        raise ValueError("static source columns or source-column order differ from the frozen table")
    frame["gauge_id"] = frame["gauge_id"].str.zfill(8)
    if frame["gauge_id"].duplicated().any():
        raise ValueError("static source contains duplicate basin identifiers")
    basin_ids = tuple(str(value).zfill(8) for value in basins)
    indexed = frame.set_index("gauge_id")
    if set(indexed.index) != set(basin_ids):
        raise ValueError("static basin coverage differs from the frozen basin set")
    raw = np.ascontiguousarray(indexed.loc[list(basin_ids), list(FORMAL_V09_STATIC_COLUMNS)].to_numpy(dtype=np.float64))
    if not np.isfinite(raw).all():
        raise ValueError("static source contains non-finite values")
    center = np.ascontiguousarray(raw.mean(axis=0, dtype=np.float64))
    scale = np.ascontiguousarray(raw.std(axis=0, ddof=1, dtype=np.float64))
    if not np.isfinite(scale).all() or np.any(scale <= 0):
        raise ValueError("static sample standard deviation must be finite and positive")
    normalized = np.ascontiguousarray(((raw - center) / scale).astype(np.float32))
    return raw, normalized, {
        "columns": list(FORMAL_V09_STATIC_COLUMNS),
        "ddof": 1,
        "center": center,
        "scale": scale,
        "raw_float64_sha256": array_payload_sha256(raw),
        "normalized_float32_sha256": array_payload_sha256(normalized),
    }


def write_target_array_v09(
    source_path: str | Path,
    *,
    expected_sha256: str,
    basins: Sequence[str],
    expected_dates: pd.DatetimeIndex,
    output_path: str | Path,
    checkpoint: Callable[[], object] | None = None,
) -> dict:
    """Stream the audited target CSV into a basin-by-training-date array."""
    source_path = Path(source_path)
    output_path = Path(output_path)
    before = sha256_file(source_path)
    if before != expected_sha256:
        raise ValueError("target bundle SHA-256 mismatch")
    _validate_output_path(output_path)
    basin_ids = tuple(str(value).zfill(8) for value in basins)
    dates = pd.DatetimeIndex(expected_dates)
    output = np.lib.format.open_memmap(
        output_path,
        mode="w+",
        dtype=np.float32,
        shape=(len(basin_ids), len(dates)),
    )
    expected_rows = len(basin_ids) * len(dates)
    row_index = 0
    with source_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != ["basin", "date", "qobs"]:
            raise ValueError("target bundle columns or column order differ")
        for row in reader:
            if row_index >= expected_rows:
                raise ValueError("target bundle contains extra rows")
            basin_index, date_index = divmod(row_index, len(dates))
            basin = str(row["basin"]).zfill(8)
            date = pd.Timestamp(row["date"])
            if basin != basin_ids[basin_index] or date != dates[date_index]:
                raise ValueError("target bundle basin-date order differs from the contract")
            value = float(row["qobs"])
            if not np.isfinite(value) or value < 0:
                raise ValueError("target bundle contains a non-finite or negative value")
            output[basin_index, date_index] = value
            row_index += 1
            if date_index == len(dates) - 1 and checkpoint is not None:
                checkpoint()
    if row_index != expected_rows:
        raise ValueError("target bundle is incomplete")
    output.flush()
    del output
    after = sha256_file(source_path)
    if after != before:
        raise ValueError("target bundle changed while it was read")
    return {
        "schema": "stream_one_target_basin_v1",
        "row_count": row_index,
        "source_sha256": before,
        "target_file_sha256": sha256_file(output_path),
    }
