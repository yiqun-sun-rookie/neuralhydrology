"""Build isolated packages from an explicitly development-only source."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
from pathlib import Path

import numpy as np
import pandas as pd

from unified_autoresearch.protocols.validation import load_and_validate_development_protocol
from unified_autoresearch.selection.basins import APPROVED_STATIC_ATTRIBUTES


DEVELOPMENT_DATE_BOUNDS = ["1999-10-01", "2008-09-30"]
SOURCE_FILES = ("features.parquet", "targets.parquet", "static_attributes.json")
FROZEN_DEVELOPMENT_SELECTION = {
    "schema_version": 1,
    "selection_method": "deterministic_standardized_farthest_point_v1",
    "selection_inputs": "static attributes only; no discharge or model results",
    "static_sha256": "085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2",
    "eligible_basins_sha256": "cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85",
    "basins": ["10259000", "04045500", "12175500", "02300700", "08190500", "02038850", "11230500", "06847900"],
}
FROZEN_DEVELOPMENT_SELECTION_64 = {
    "schema_version": 1,
    "selection_method": "deterministic_standardized_farthest_point_v1",
    "selection_inputs": "static attributes only; no discharge or model results",
    "static_sha256": "085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2",
    "eligible_basins_sha256": "cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85",
    "basins": [
        "10259000", "04045500", "12175500", "02300700", "08190500", "02038850", "11230500", "06847900", "11143000",
        "14301000", "04122500", "09306242", "05458000", "02450250", "06289000", "08109700", "08267500", "14216500",
        "11151300", "12375900", "11528700", "06879650", "02472000", "06614800", "04213075", "12073500", "04296000",
        "13313000", "06350000", "01491000", "03281500", "08194200", "04057510", "13240000", "04063700", "11476600",
        "01466500", "07060710", "08158810", "10244950", "14020000", "14138800", "12010000", "04115265", "08066300",
        "04185000", "06409000", "02231000", "09378170", "07142300", "02077200", "02102908", "01451800", "09512280",
        "06906800", "03455500", "13161500", "04027000", "09494000", "09430600", "12167000", "11381500", "12377150",
        "08189500",
    ],
}
FROZEN_DEVELOPMENT_SELECTIONS = (FROZEN_DEVELOPMENT_SELECTION, FROZEN_DEVELOPMENT_SELECTION_64)


def load_frozen_selection(selection_path: str | Path) -> dict:
    """Read a basin selection and refuse anything that is not one of the frozen records."""
    selection = json.loads(Path(selection_path).read_text(encoding="utf-8"))
    if selection not in FROZEN_DEVELOPMENT_SELECTIONS:
        raise ValueError("frozen development basin selection mismatch")
    return selection


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _load_source_manifest(source_root: Path, manifest_path: Path) -> dict:
    try:
        manifest_path.relative_to(source_root)
    except ValueError as error:
        raise ValueError("source manifest must be inside the dedicated source root") from error
    if manifest_path != source_root / "SOURCE_MANIFEST.json":
        raise ValueError("source manifest must be the dedicated root manifest")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    required_fields = {
        "schema_version",
        "source_kind",
        "forcing_product",
        "date_bounds",
        "sealed_final_evaluation_present",
        "files",
    }
    if set(manifest) != required_fields:
        raise ValueError("source manifest fields do not match the frozen contract")
    if manifest["date_bounds"] != DEVELOPMENT_DATE_BOUNDS:
        raise ValueError("source date bounds must exactly match the development-only interval")
    if (
        manifest["schema_version"] != "development_source_v1"
        or manifest["source_kind"] != "explicitly_pre_sliced_development_only"
        or manifest["forcing_product"] != "maurer"
        or manifest["sealed_final_evaluation_present"] is not False
        or set(manifest["files"]) != set(SOURCE_FILES)
    ):
        raise ValueError("source manifest does not attest an approved development-only source")
    if {path.name for path in source_root.iterdir()} != {*SOURCE_FILES, "SOURCE_MANIFEST.json"}:
        raise ValueError("dedicated source root contains undeclared files")
    if any(path.is_symlink() or not path.is_file() or path.stat().st_nlink != 1 for path in source_root.iterdir()):
        raise ValueError("source files must be unlinked regular files")
    for name in SOURCE_FILES:
        path = source_root / name
        if not path.is_file() or _sha256(path) != manifest["files"][name]:
            raise ValueError(f"source file hash mismatch: {name}")
    return manifest


def build_development_packages(
    *,
    source_root: str | Path,
    source_manifest_path: str | Path,
    protocol_path: str | Path,
    selection_path: str | Path,
    output_root: str | Path,
) -> dict:
    """Build the two frozen development protocols without opening an untrusted source."""
    source_root = Path(source_root).resolve()
    manifest_path = Path(source_manifest_path).resolve()
    source_manifest = _load_source_manifest(source_root, manifest_path)
    protocol = load_and_validate_development_protocol(protocol_path)
    selection = load_frozen_selection(selection_path)
    basins = [str(basin).zfill(8) for basin in selection["basins"]]

    final_root = Path(output_root).resolve()
    if final_root.exists():
        raise FileExistsError(final_root)
    features = pd.read_parquet(source_root / "features.parquet")
    targets = pd.read_parquet(source_root / "targets.parquet")
    static_attributes = json.loads((source_root / "static_attributes.json").read_text(encoding="utf-8"))
    if set(features.columns) != {"basin", "date", "prcp", "tmin", "tmax", "srad", "vp"}:
        raise ValueError("source feature columns do not match the frozen contract")
    if set(targets.columns) != {"basin", "date", "qobs"}:
        raise ValueError("source target columns do not match the frozen contract")
    numeric_columns = {
        "features": ["prcp", "tmin", "tmax", "srad", "vp"],
        "targets": ["qobs"],
    }
    for name, frame in (("features", features), ("targets", targets)):
        try:
            numeric = frame[numeric_columns[name]].apply(pd.to_numeric, errors="raise")
        except (TypeError, ValueError) as error:
            raise ValueError("time-series values must be finite numbers") from error
        if not np.isfinite(numeric.to_numpy(dtype=np.float64)).all():
            raise ValueError("time-series values must be finite numbers")
        frame[numeric_columns[name]] = numeric
    if (
        set(static_attributes) != {"schema_version", "basins"}
        or static_attributes["schema_version"] != "development_static_attributes_v1"
        or set(static_attributes["basins"]) != set(basins)
        or any(set(values) != set(APPROVED_STATIC_ATTRIBUTES) for values in static_attributes["basins"].values())
    ):
        raise ValueError("source statics require exactly 27 approved static attributes for each frozen basin")
    if any(
        not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value)
        for values in static_attributes["basins"].values()
        for value in values.values()
    ):
        raise ValueError("static attributes must be finite numeric values")
    for frame in (features, targets):
        frame["basin"] = frame["basin"].astype(str).str.zfill(8)
        frame["date"] = pd.to_datetime(frame["date"], errors="raise")
        if frame["date"].isna().any() or frame["date"].dt.normalize().ne(frame["date"]).any():
            raise ValueError("source dates must be present daily timestamps")
        if set(frame["basin"]) != set(basins):
            raise ValueError("source tables must contain exactly the frozen development basins")
        minimum_date = frame["date"].min().strftime("%Y-%m-%d")
        maximum_date = frame["date"].max().strftime("%Y-%m-%d")
        if [minimum_date, maximum_date] != DEVELOPMENT_DATE_BOUNDS:
            raise ValueError("source table dates do not match the attested development-only interval")
    feature_keys = pd.MultiIndex.from_frame(features[["basin", "date"]])
    target_keys = pd.MultiIndex.from_frame(targets[["basin", "date"]])
    if feature_keys.has_duplicates or target_keys.has_duplicates or set(feature_keys) != set(target_keys):
        raise ValueError("source tables require unique basin-date rows and identical feature-target keys")

    final_root.mkdir(parents=True)
    package_files: dict[str, str] = {}
    for protocol_name, windows in protocol["development_protocols"].items():
        protocol_root = final_root / protocol_name
        train_root = protocol_root / "train"
        predict_root = protocol_root / "predict"
        score_root = protocol_root / "score"
        train_root.mkdir(parents=True)
        predict_root.mkdir()
        score_root.mkdir()

        train_start, train_end = pd.to_datetime(windows["train"])
        validation_start, validation_end = pd.to_datetime(windows["validation"])
        train_features = features.loc[features["date"].between(train_start, train_end)].copy()
        train_targets = targets.loc[targets["date"].between(train_start, train_end)].copy()
        predict_features = features.loc[features["date"].between(validation_start, validation_end)].copy()
        validation_truth = targets.loc[targets["date"].between(validation_start, validation_end)].copy()

        train_features.to_parquet(train_root / "train_features.parquet", index=False)
        train_targets.to_parquet(train_root / "train_targets.parquet", index=False)
        predict_features.to_parquet(predict_root / "predict_features.parquet", index=False)
        validation_truth.to_parquet(score_root / "validation_truth.parquet", index=False)
        shutil.copy2(source_root / "static_attributes.json", train_root / "static_attributes.json")
        shutil.copy2(source_root / "static_attributes.json", predict_root / "static_attributes.json")

    for path in sorted(final_root.rglob("*")):
        if path.is_file():
            package_files[path.relative_to(final_root).as_posix()] = _sha256(path)
    package_manifest = {
        "schema_version": "development_packages_v1",
        "protocols": list(protocol["development_protocols"]),
        "development_protocols": protocol["development_protocols"],
        "basins": basins,
        "source_manifest_sha256": _sha256(manifest_path),
        "source_files": source_manifest["files"],
        "files": package_files,
    }
    _write_json(final_root / "PACKAGE_MANIFEST.json", package_manifest)
    return package_manifest
