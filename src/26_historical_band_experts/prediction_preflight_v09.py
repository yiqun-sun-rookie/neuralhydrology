"""Memory-bounded, observation-blind prediction checks for formal version 09."""
from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np
import pandas as pd

from memory_safety_v09 import HostMemorySnapshot, MemorySafetyGate, sample_host_memory


_COLUMNS = ["basin", "date", "qsim"]
_SEEDS = tuple(range(100, 801, 100))


class PredictionPreflightError(RuntimeError):
    """Raised before malformed predictions can reach the official scoring service."""


def _prediction_chunks(path: Path, chunk_rows: int):
    suffix = path.suffix.lower()
    if suffix == ".csv":
        yield from pd.read_csv(
            path,
            dtype={"basin": "string", "date": "string"},
            chunksize=chunk_rows,
        )
        return
    if suffix == ".parquet":
        try:
            import pyarrow.parquet as parquet
        except ImportError as error:
            raise PredictionPreflightError("PyArrow is required for chunked Parquet preflight") from error
        parquet_file = parquet.ParquetFile(path)
        for batch in parquet_file.iter_batches(batch_size=chunk_rows):
            yield batch.to_pandas()
        return
    raise PredictionPreflightError("prediction file must be CSV or Parquet")


def _require_schema(frame: pd.DataFrame) -> None:
    if list(frame.columns) != _COLUMNS:
        extras = sorted(set(frame.columns) - set(_COLUMNS))
        missing = sorted(set(_COLUMNS) - set(frame.columns))
        if extras:
            raise PredictionPreflightError(f"extra column in prediction file: {extras}")
        if missing:
            raise PredictionPreflightError(f"missing column in prediction file: {missing}")
        raise PredictionPreflightError("prediction columns are in the wrong order")


def _numeric_qsim(frame: pd.DataFrame) -> np.ndarray:
    try:
        values = pd.to_numeric(frame["qsim"], errors="raise").to_numpy(dtype=np.float64)
    except (TypeError, ValueError) as error:
        raise PredictionPreflightError("qsim contains a nonnumeric value") from error
    if not np.isfinite(values).all():
        raise PredictionPreflightError("nonfinite qsim value")
    return values


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_exact_prediction_coverage_v09(
    path: str | Path,
    *,
    basin_ids: tuple[str, ...],
    start_date: str,
    end_date: str,
    chunk_rows: int = 50_000,
    gate: MemorySafetyGate | None = None,
    snapshot: HostMemorySnapshot | None = None,
) -> dict:
    """Validate every expected basin-date key without reading observations."""
    path = Path(path)
    if not path.is_file():
        raise PredictionPreflightError(f"prediction file does not exist: {path}")
    if int(chunk_rows) <= 0:
        raise ValueError("chunk_rows must be positive")
    if not basin_ids or len(set(basin_ids)) != len(basin_ids):
        raise ValueError("basin_ids must be nonempty and unique")
    if any(not isinstance(basin, str) or not basin for basin in basin_ids):
        raise ValueError("basin_ids must contain nonempty strings")
    dates = pd.date_range(start_date, end_date, freq="D")
    if dates.empty:
        raise ValueError("prediction date range must be nonempty")
    expected_rows = len(basin_ids) * len(dates)
    use_live_snapshots = snapshot is None
    if use_live_snapshots:
        snapshot = sample_host_memory()
    if gate is None:
        gate = MemorySafetyGate.from_snapshot(snapshot)
    gate.assert_allocation_safe(snapshot, (expected_rows,), np.bool_)
    seen = np.zeros(expected_rows, dtype=np.bool_)
    basin_lookup = {basin: index for index, basin in enumerate(basin_ids)}
    start = dates[0]
    row_count = 0

    for frame in _prediction_chunks(path, int(chunk_rows)):
        gate.assert_runtime_safe(sample_host_memory() if use_live_snapshots else snapshot)
        _require_schema(frame)
        if frame.empty:
            continue
        if frame["basin"].isna().any() or frame["date"].isna().any():
            raise PredictionPreflightError("missing basin or date value")
        basin_values = frame["basin"].astype(str)
        basin_indices = basin_values.map(basin_lookup)
        if basin_indices.isna().any():
            unknown = sorted(set(basin_values[basin_indices.isna()].tolist()))
            raise PredictionPreflightError(f"unknown basin in prediction file: {unknown[:3]}")
        raw_dates = frame["date"].astype(str)
        try:
            parsed_dates = pd.to_datetime(raw_dates, format="%Y-%m-%d", errors="raise")
        except (TypeError, ValueError) as error:
            raise PredictionPreflightError("invalid prediction date") from error
        if not np.array_equal(parsed_dates.dt.strftime("%Y-%m-%d").to_numpy(), raw_dates.to_numpy()):
            raise PredictionPreflightError("prediction date must use exact YYYY-MM-DD format")
        date_indices = (parsed_dates - start).dt.days.to_numpy(dtype=np.int64)
        if np.any(date_indices < 0) or np.any(date_indices >= len(dates)):
            raise PredictionPreflightError("prediction date is outside the required range")
        _numeric_qsim(frame)
        keys = basin_indices.to_numpy(dtype=np.int64) * len(dates) + date_indices
        unique_keys = np.unique(keys)
        if unique_keys.size != keys.size or seen[keys].any():
            raise PredictionPreflightError("duplicate basin-date prediction key")
        seen[keys] = True
        row_count += len(frame)

    missing_count = int((~seen).sum())
    if missing_count:
        raise PredictionPreflightError(f"missing {missing_count} prediction keys")
    if row_count != expected_rows:
        raise PredictionPreflightError(f"row count mismatch: {row_count} != {expected_rows}")
    return {
        "status": "exact_coverage",
        "basin_count": len(basin_ids),
        "dates_per_basin": len(dates),
        "row_count": row_count,
        "duplicate_count": 0,
        "missing_count": 0,
        "nonfinite_count": 0,
    }


def compose_seed_mean_v09(
    seed_paths: list[str | Path],
    output_path: str | Path,
    *,
    chunk_rows: int = 50_000,
    gate: MemorySafetyGate | None = None,
    snapshot: HostMemorySnapshot | None = None,
) -> dict:
    """Write the fixed-order eight-seed arithmetic mean with a float64 accumulator."""
    paths = [Path(path) for path in seed_paths]
    output_path = Path(output_path)
    if int(chunk_rows) <= 0:
        raise ValueError("chunk_rows must be positive")
    if len(paths) != len(_SEEDS):
        raise PredictionPreflightError("version 09 ensemble requires exactly eight seed files")
    if output_path.exists():
        raise FileExistsError(f"ensemble output already exists: {output_path}")
    if any(path.suffix.lower() != ".csv" for path in paths):
        raise PredictionPreflightError("seed-mean composition currently requires CSV inputs")
    for path in paths:
        if not path.is_file():
            raise PredictionPreflightError(f"seed prediction file does not exist: {path}")
    temporary = output_path.with_suffix(output_path.suffix + ".tmp")
    if temporary.exists():
        raise FileExistsError(f"temporary ensemble output already exists: {temporary}")
    use_live_snapshots = snapshot is None
    if use_live_snapshots:
        snapshot = sample_host_memory()
    if gate is None:
        gate = MemorySafetyGate.from_snapshot(snapshot)
    estimated_chunk_peak = int(chunk_rows) * len(paths) * 256
    gate.assert_start_safe(
        snapshot,
        estimated_peak_bytes=estimated_chunk_peak,
        long_running=False,
    )
    readers = [
        pd.read_csv(
            path,
            dtype={"basin": "string", "date": "string"},
            chunksize=int(chunk_rows),
        )
        for path in paths
    ]
    sentinel = object()
    wrote_header = False
    row_count = 0
    try:
        while True:
            gate.assert_runtime_safe(sample_host_memory() if use_live_snapshots else snapshot)
            chunks = [next(reader, sentinel) for reader in readers]
            if all(chunk is sentinel for chunk in chunks):
                break
            if any(chunk is sentinel for chunk in chunks):
                raise PredictionPreflightError("seed files have different row counts")
            reference = chunks[0]
            _require_schema(reference)
            reference_keys = reference[["basin", "date"]].reset_index(drop=True)
            accumulator = _numeric_qsim(reference).astype(np.float64, copy=True)
            for chunk in chunks[1:]:
                _require_schema(chunk)
                keys = chunk[["basin", "date"]].reset_index(drop=True)
                if not reference_keys.equals(keys):
                    raise PredictionPreflightError("seed prediction key order mismatch")
                accumulator += _numeric_qsim(chunk)
            output = reference_keys.copy()
            output["qsim"] = accumulator / float(len(paths))
            output.to_csv(
                temporary,
                mode="a",
                header=not wrote_header,
                index=False,
                float_format="%.17g",
            )
            wrote_header = True
            row_count += len(output)
        if row_count == 0:
            raise PredictionPreflightError("seed prediction files are empty")
        temporary.replace(output_path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    finally:
        for reader in readers:
            reader.close()
    return {
        "status": "complete",
        "seed_count": len(paths),
        "seed_order": list(_SEEDS),
        "accumulator_dtype": "float64",
        "row_count": row_count,
        "output_sha256": _sha256(output_path),
    }
