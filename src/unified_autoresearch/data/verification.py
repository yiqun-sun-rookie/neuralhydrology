"""Independently verify a built development source root and its two protocol packages.

Every claim is re-derived from the raw archive and the frozen tables. The builder is never
re-run, so a builder defect cannot vouch for itself. Only development-window rows are ever
read from the raw archive, and the sealed final evaluation interval is counted, never emitted.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd

from unified_autoresearch.data.packages import DEVELOPMENT_DATE_BOUNDS, SOURCE_FILES, load_frozen_selection
from unified_autoresearch.data.real_source import (
    CUBIC_FEET_PER_SECOND_TO_MILLIMETRES,
    DISCHARGE_COLUMNS,
)
from unified_autoresearch.protocols.validation import load_and_validate_development_protocol
from unified_autoresearch.selection.basins import APPROVED_STATIC_ATTRIBUTES


SCHEMA_VERSION = "development_artifact_verification_v1"
DISCHARGE_CONVERSION = "28316846.592 * cfs * 86400 / (area_m2 * 10**6)"
SENSITIVE_BASINS = ("06847900", "08190500")
PREDICTION_FEATURE_COLUMNS = {"basin", "date", "prcp", "tmin", "tmax", "srad", "vp"}
DISCHARGE_COLUMN_NAMES = ("qobs", "QObs", "discharge", "streamflow")


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


def _raw_discharge(camels_root: Path, basin: str, window: pd.DatetimeIndex) -> tuple[pd.DataFrame, int]:
    """Read the header area and the development-window discharge rows straight from the archive."""
    forcing_path = _single_match(camels_root / "basin_mean_forcing" / "maurer", f"{basin}_*_forcing_leap.txt")
    with forcing_path.open("r", encoding="utf-8") as stream:
        stream.readline()
        stream.readline()
        area = int(stream.readline())

    flow_path = _single_match(camels_root / "usgs_streamflow", f"{basin}_streamflow_qc.txt")
    frame = pd.read_csv(flow_path, sep=r"\s+", header=None, names=list(DISCHARGE_COLUMNS))
    dates = pd.to_datetime(frame[["Year", "Mnth", "Day"]].rename(columns={"Year": "year", "Mnth": "month", "Day": "day"}))
    frame = frame.assign(date=dates)
    frame = frame.loc[frame["date"].between(window[0], window[-1])].sort_values("date").reset_index(drop=True)
    return frame[["date", "QObs"]], area


def _dated_frames(root: Path) -> dict[str, pd.DataFrame]:
    """Every parquet artifact under a root, keyed by its path relative to that root."""
    frames: dict[str, pd.DataFrame] = {}
    for path in sorted(root.rglob("*.parquet")):
        frames[path.relative_to(root).as_posix()] = pd.read_parquet(path)
    return frames


def verify_development_artifacts(
    *,
    source_root: str | Path,
    package_root: str | Path,
    camels_root: str | Path,
    static_table_path: str | Path,
    protocol_path: str | Path,
    selection_path: str | Path,
) -> dict:
    """Re-derive and check every per-basin claim about the built development artifacts."""
    source_root = Path(source_root).resolve()
    package_root = Path(package_root).resolve()
    camels_root = Path(camels_root).resolve()
    static_table_path = Path(static_table_path).resolve()

    protocol = load_and_validate_development_protocol(protocol_path)
    selection = load_frozen_selection(selection_path)
    basins = [str(basin).zfill(8) for basin in selection["basins"]]
    sealed_start, sealed_end = pd.to_datetime(protocol["sealed_final_evaluation"])
    window = pd.date_range(*pd.to_datetime(DEVELOPMENT_DATE_BOUNDS), freq="D")
    protocol_windows = {
        name: {phase: list(bounds) for phase, bounds in windows.items()}
        for name, windows in protocol["development_protocols"].items()
    }

    failures: list[str] = []
    artifact_sha256: dict[str, str] = {}
    for root, prefix in ((source_root, "source"), (package_root, "package")):
        for path in sorted(root.rglob("*")):
            if path.is_file():
                artifact_sha256[f"{prefix}/{path.relative_to(root).as_posix()}"] = _sha256(path)

    source_manifest = json.loads((source_root / "SOURCE_MANIFEST.json").read_text(encoding="utf-8"))
    source_manifest_hashes_match = all(
        artifact_sha256.get(f"source/{name}") == source_manifest["files"].get(name) for name in SOURCE_FILES
    )
    if not source_manifest_hashes_match:
        failures.append("source artifact hashes do not match SOURCE_MANIFEST.json")

    package_manifest = json.loads((package_root / "PACKAGE_MANIFEST.json").read_text(encoding="utf-8"))
    package_manifest_hashes_match = all(
        artifact_sha256.get(f"package/{name}") == digest for name, digest in package_manifest["files"].items()
    )
    if not package_manifest_hashes_match:
        failures.append("package artifact hashes do not match PACKAGE_MANIFEST.json")
    if package_manifest["basins"] != basins:
        failures.append("package manifest basins do not match the frozen selection")

    source_frames = _dated_frames(source_root)
    package_frames = _dated_frames(package_root)
    all_frames = {f"source/{name}": frame for name, frame in source_frames.items()}
    all_frames.update({f"package/{name}": frame for name, frame in package_frames.items()})
    for frame in all_frames.values():
        frame["basin"] = frame["basin"].astype(str).str.zfill(8)
        frame["date"] = pd.to_datetime(frame["date"])

    prediction_free_of_discharge = True
    for name, frame in all_frames.items():
        if not name.endswith("predict_features.parquet"):
            continue
        leaked = sorted(set(frame.columns) & set(DISCHARGE_COLUMN_NAMES))
        if leaked or set(frame.columns) != PREDICTION_FEATURE_COLUMNS:
            prediction_free_of_discharge = False
            failures.append(f"observed discharge or undeclared columns reached {name}: {leaked or sorted(frame.columns)}")

    statics = json.loads((source_root / "static_attributes.json").read_text(encoding="utf-8"))
    reference_statics = pd.read_csv(static_table_path, dtype={"gauge_id": str})
    reference_statics["gauge_id"] = reference_statics["gauge_id"].str.zfill(8)
    reference_statics = reference_statics.set_index("gauge_id")

    source_features = source_frames["features.parquet"]
    source_targets = source_frames["targets.parquet"]
    expected_days = len(window)
    sealed_rows_total = 0
    report_basins: dict[str, dict] = {}

    for basin in basins:
        basin_failures: list[str] = []
        sealed_rows = int(sum(int(frame.loc[frame["basin"] == basin, "date"].between(sealed_start, sealed_end).sum()) for frame in all_frames.values()))
        sealed_rows_total += sealed_rows
        if sealed_rows:
            basin_failures.append("sealed final evaluation rows present")

        basin_targets = source_targets.loc[source_targets["basin"] == basin].sort_values("date").reset_index(drop=True)
        basin_features = source_features.loc[source_features["basin"] == basin].sort_values("date").reset_index(drop=True)
        present_days = set(basin_features["date"]) & set(basin_targets["date"])
        missing_days = int(len(set(window) - present_days))
        if missing_days or len(basin_features) != expected_days or len(basin_targets) != expected_days:
            basin_failures.append("development window is not a complete daily record")
        date_bounds = (
            [basin_targets["date"].min().strftime("%Y-%m-%d"), basin_targets["date"].max().strftime("%Y-%m-%d")]
            if len(basin_targets)
            else []
        )
        if date_bounds != DEVELOPMENT_DATE_BOUNDS:
            basin_failures.append("development date bounds are wrong")

        raw, area = _raw_discharge(camels_root, basin, window)
        merged = basin_targets.merge(raw, on="date", how="inner")
        expected_discharge = merged["QObs"].to_numpy(dtype=np.float64) * CUBIC_FEET_PER_SECOND_TO_MILLIMETRES / area
        difference = np.abs(merged["qobs"].to_numpy(dtype=np.float64) - expected_discharge)
        discharge_error = float(difference.max()) if difference.size else math.inf
        if not (discharge_error == 0.0):
            basin_failures.append("converted discharge does not reproduce from the raw archive")

        basin_statics = statics["basins"].get(basin, {})
        missing_attributes = sorted(set(APPROVED_STATIC_ATTRIBUTES) - set(basin_statics))
        statics_match = not missing_attributes and all(
            float(basin_statics[name]) == float(reference_statics.loc[basin, name]) for name in APPROVED_STATIC_ATTRIBUTES
        )
        if missing_attributes:
            basin_failures.append(f"static attributes missing: {missing_attributes}")
        elif not statics_match:
            basin_failures.append("static attributes differ from the frozen table")

        protocol_days: dict[str, dict[str, int]] = {}
        prediction_rows_with_discharge = 0
        validation_standard_deviation: dict[str, float] = {}
        for protocol_name, windows in protocol["development_protocols"].items():
            train_start, train_end = pd.to_datetime(windows["train"])
            validation_start, validation_end = pd.to_datetime(windows["validation"])
            train = package_frames[f"{protocol_name}/train/train_targets.parquet"]
            predict = package_frames[f"{protocol_name}/predict/predict_features.parquet"]
            truth = package_frames[f"{protocol_name}/score/validation_truth.parquet"]
            train_rows = train.loc[(train["basin"] == basin) & train["date"].between(train_start, train_end)]
            predict_rows = predict.loc[(predict["basin"] == basin) & predict["date"].between(validation_start, validation_end)]
            truth_rows = truth.loc[(truth["basin"] == basin) & truth["date"].between(validation_start, validation_end)]
            protocol_days[protocol_name] = {"train": int(len(train_rows)), "validation": int(len(predict_rows))}
            if len(predict_rows) != len(truth_rows):
                basin_failures.append(f"{protocol_name}: prediction and validation-truth day counts differ")
            if len(train.loc[train["basin"] == basin]) != len(train_rows) or len(predict.loc[predict["basin"] == basin]) != len(predict_rows):
                basin_failures.append(f"{protocol_name}: package rows fall outside the declared protocol window")
            if any(column in predict.columns for column in DISCHARGE_COLUMN_NAMES):
                prediction_rows_with_discharge += int(len(predict_rows))
            validation_standard_deviation[protocol_name] = float(truth_rows["qobs"].std(ddof=0)) if len(truth_rows) else 0.0

        for protocol_name, days in protocol_days.items():
            if days["train"] + days["validation"] != expected_days:
                basin_failures.append(f"{protocol_name}: train and validation days do not tile the development window")

        report_basins[basin] = {
            "passed": not basin_failures,
            "failures": basin_failures,
            "sealed_interval_rows": sealed_rows,
            "development_days": int(len(basin_targets)),
            "missing_days": missing_days,
            "date_bounds": date_bounds,
            "header_area_m2": area,
            "discharge_max_absolute_error": discharge_error,
            "static_attribute_count": len(basin_statics),
            "static_attributes_missing": missing_attributes,
            "static_attributes_match_frozen_table": bool(statics_match),
            "protocol_days": protocol_days,
            "prediction_rows_with_discharge": prediction_rows_with_discharge,
            "diagnostics": {
                "zero_flow_days": int((basin_targets["qobs"] == 0.0).sum()),
                "validation_discharge_standard_deviation": validation_standard_deviation,
            },
        }
        failures.extend(f"{basin}: {message}" for message in basin_failures)

    # A fixed watchlist stops being correct as the basin set grows, so rank the extremes instead.
    diagnostic_extremes = {
        "most_zero_flow_days": [
            {"basin": basin, "zero_flow_days": report_basins[basin]["diagnostics"]["zero_flow_days"]}
            for basin in sorted(
                report_basins, key=lambda name: (-report_basins[name]["diagnostics"]["zero_flow_days"], name)
            )[:5]
        ],
        "lowest_validation_discharge_standard_deviation": [
            {
                "basin": basin,
                "standard_deviation": min(
                    report_basins[basin]["diagnostics"]["validation_discharge_standard_deviation"].values()
                ),
            }
            for basin in sorted(
                report_basins,
                key=lambda name: (
                    min(report_basins[name]["diagnostics"]["validation_discharge_standard_deviation"].values()),
                    name,
                ),
            )[:5]
        ],
    }

    if sealed_rows_total:
        failures.append(f"sealed final evaluation rows reached the artifacts: {sealed_rows_total}")

    return {
        "schema_version": SCHEMA_VERSION,
        "all_passed": not failures,
        "failures": failures,
        "basin_count": len(basins),
        "basins": report_basins,
        "sensitive_basins": list(SENSITIVE_BASINS),
        "diagnostic_extremes": diagnostic_extremes,
        "sealed_final_evaluation": [timestamp.strftime("%Y-%m-%d") for timestamp in (sealed_start, sealed_end)],
        "sealed_interval_rows_total": sealed_rows_total,
        "development_date_bounds": list(DEVELOPMENT_DATE_BOUNDS),
        "protocol_windows": protocol_windows,
        "discharge_conversion": DISCHARGE_CONVERSION,
        "prediction_packages_free_of_observed_discharge": prediction_free_of_discharge,
        "source_manifest_hashes_match": source_manifest_hashes_match,
        "package_manifest_hashes_match": package_manifest_hashes_match,
        "artifact_files_scanned": len(artifact_sha256),
        "artifact_sha256": artifact_sha256,
    }
