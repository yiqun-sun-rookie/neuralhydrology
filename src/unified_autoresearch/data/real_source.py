"""Build the proven development-only source root from the real CAMELS-US archive.

This is the single component allowed to open the raw archive. It slices the development
window before anything is written, and never emits a value from the sealed final
evaluation interval.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd

from unified_autoresearch.data.packages import (
    DEVELOPMENT_DATE_BOUNDS,
    SOURCE_FILES,
    load_frozen_selection,
)
from unified_autoresearch.protocols.validation import load_and_validate_development_protocol
from unified_autoresearch.selection.basins import APPROVED_STATIC_ATTRIBUTES


FORCING_COLUMNS = {
    "PRCP(mm/day)": "prcp",
    "Tmin(C)": "tmin",
    "Tmax(C)": "tmax",
    "SRAD(W/m2)": "srad",
    "Vp(Pa)": "vp",
}
DISCHARGE_COLUMNS = ("basin", "Year", "Mnth", "Day", "QObs", "flag")
CUBIC_FEET_PER_SECOND_TO_MILLIMETRES = 28316846.592 * 86400 / 10**6
MISSING_DISCHARGE = -999.0


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _single_match(root: Path, pattern: str) -> Path:
    matches = sorted(root.rglob(pattern))
    if len(matches) != 1:
        raise ValueError(f"the archive must contain exactly one file matching {pattern}")
    return matches[0]


def _daily_dates(frame: pd.DataFrame) -> pd.Series:
    return pd.to_datetime(frame[["Year", "Mnth", "Day"]].rename(columns={"Year": "year", "Mnth": "month", "Day": "day"}))


def _require_complete_window(dates: pd.Series, expected: pd.DatetimeIndex) -> None:
    if len(dates) != len(expected) or not dates.reset_index(drop=True).equals(pd.Series(expected)):
        raise ValueError("development window requires a complete daily record")


def _read_basin_forcing(camels_root: Path, basin: str, window: pd.DatetimeIndex) -> tuple[pd.DataFrame, int]:
    path = _single_match(camels_root / "basin_mean_forcing" / "maurer", f"{basin}_*_forcing_leap.txt")
    with path.open("r", encoding="utf-8") as stream:
        stream.readline()
        stream.readline()
        area = int(stream.readline())
        frame = pd.read_csv(stream, sep=r"\s+")
    missing = sorted(set(FORCING_COLUMNS) - set(frame.columns))
    if missing:
        raise ValueError(f"forcing file is missing approved dynamic inputs: {missing}")
    frame = frame.assign(date=_daily_dates(frame))
    frame = frame.loc[frame["date"].between(window[0], window[-1])].sort_values("date").reset_index(drop=True)
    _require_complete_window(frame["date"], window)
    values = frame[list(FORCING_COLUMNS)].apply(pd.to_numeric, errors="coerce")
    if not np.isfinite(values.to_numpy(dtype=np.float64)).all():
        raise ValueError("development window requires finite meteorological forcing")
    forcing = values.rename(columns=FORCING_COLUMNS)
    forcing.insert(0, "date", frame["date"])
    forcing.insert(0, "basin", basin)
    return forcing, area


def _read_basin_discharge(camels_root: Path, basin: str, area: int, window: pd.DatetimeIndex) -> pd.DataFrame:
    path = _single_match(camels_root / "usgs_streamflow", f"{basin}_streamflow_qc.txt")
    frame = pd.read_csv(path, sep=r"\s+", header=None, names=list(DISCHARGE_COLUMNS))
    frame = frame.assign(date=_daily_dates(frame))
    frame = frame.loc[frame["date"].between(window[0], window[-1])].sort_values("date").reset_index(drop=True)
    _require_complete_window(frame["date"], window)
    observed = pd.to_numeric(frame["QObs"], errors="coerce").to_numpy(dtype=np.float64)
    if not np.isfinite(observed).all() or (observed == MISSING_DISCHARGE).any():
        raise ValueError("development window requires finite observed discharge")
    return pd.DataFrame(
        {
            "basin": basin,
            "date": frame["date"],
            "qobs": observed * CUBIC_FEET_PER_SECOND_TO_MILLIMETRES / area,
        }
    )


def _frozen_static_attributes(static_table_path: Path, basins: list[str], expected_static_sha256: str) -> dict:
    if _sha256(static_table_path) != expected_static_sha256:
        raise ValueError("static attribute table hash does not match the frozen selection input")
    table = pd.read_csv(static_table_path, dtype={"gauge_id": str})
    table["gauge_id"] = table["gauge_id"].str.zfill(8)
    indexed = table.set_index("gauge_id")
    missing = sorted(set(basins) - set(indexed.index))
    if missing:
        raise ValueError(f"static attribute table is missing frozen development basins: {missing}")
    attributes: dict[str, dict[str, float]] = {}
    for basin in basins:
        values = {name: float(indexed.loc[basin, name]) for name in APPROVED_STATIC_ATTRIBUTES}
        if any(not math.isfinite(value) for value in values.values()):
            raise ValueError(f"static attributes must be finite for every frozen development basin: {basin}")
        attributes[basin] = values
    return {"schema_version": "development_static_attributes_v1", "basins": attributes}


def build_development_source_root(
    *,
    camels_root: str | Path,
    static_table_path: str | Path,
    protocol_path: str | Path,
    selection_path: str | Path,
    output_root: str | Path,
) -> dict:
    """Slice the raw archive into the attested development-only source root."""
    camels_root = Path(camels_root).resolve()
    static_table_path = Path(static_table_path).resolve()
    output_root = Path(output_root).resolve()
    if output_root.exists():
        raise FileExistsError(output_root)

    protocol = load_and_validate_development_protocol(protocol_path)
    selection = load_frozen_selection(selection_path)
    basins = [str(basin).zfill(8) for basin in selection["basins"]]

    window = pd.date_range(*pd.to_datetime(DEVELOPMENT_DATE_BOUNDS), freq="D")
    sealed_start, sealed_end = pd.to_datetime(protocol["sealed_final_evaluation"])
    if window[0] <= sealed_end:
        raise ValueError("development window must start after the sealed final evaluation interval")

    static_attributes = _frozen_static_attributes(static_table_path, basins, selection["static_sha256"])
    feature_frames = []
    target_frames = []
    for basin in basins:
        forcing, area = _read_basin_forcing(camels_root, basin, window)
        feature_frames.append(forcing)
        target_frames.append(_read_basin_discharge(camels_root, basin, area, window))
    features = pd.concat(feature_frames, ignore_index=True)
    targets = pd.concat(target_frames, ignore_index=True)
    for frame in (features, targets):
        if frame["date"].between(sealed_start, sealed_end).any():
            raise ValueError("sealed final evaluation dates must never reach the development source")

    output_root.mkdir(parents=True)
    features.to_parquet(output_root / "features.parquet", index=False)
    targets.to_parquet(output_root / "targets.parquet", index=False)
    (output_root / "static_attributes.json").write_text(
        json.dumps(static_attributes, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    manifest = {
        "schema_version": "development_source_v1",
        "source_kind": "explicitly_pre_sliced_development_only",
        "forcing_product": "maurer",
        "date_bounds": list(DEVELOPMENT_DATE_BOUNDS),
        "sealed_final_evaluation_present": False,
        "files": {name: _sha256(output_root / name) for name in SOURCE_FILES},
    }
    (output_root / "SOURCE_MANIFEST.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest
