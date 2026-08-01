"""File-contract runtime shared by the four isolated reference candidates."""

from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

import method


FEATURE_COLUMNS = ("basin", "date", "prcp", "tmin", "tmax", "srad", "vp")
TARGET_COLUMNS = ("basin", "date", "qobs")


def _canonical_json(value: dict) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False) + "\n"
    ).encode("utf-8")


def _date_key(value) -> str:
    return value.isoformat() if hasattr(value, "isoformat") else str(value)


def _read_rows(path: Path, expected_columns: tuple[str, ...]) -> list[dict]:
    table = pq.read_table(path)
    if set(table.column_names) != set(expected_columns):
        raise ValueError(f"unexpected Parquet columns: {sorted(table.column_names)}")
    rows = table.select(list(expected_columns)).to_pylist()
    normalized = []
    for row in rows:
        basin = str(row["basin"]).zfill(8)
        date = row["date"]
        if date is None:
            raise ValueError("candidate input date is missing")
        value = {"basin": basin, "date": date, "date_key": _date_key(date)}
        for name in expected_columns:
            if name in {"basin", "date"}:
                continue
            numeric = row[name]
            if isinstance(numeric, bool) or not isinstance(numeric, (int, float)) or not math.isfinite(numeric):
                raise ValueError("candidate input contains a non-finite numeric value")
            value[name] = float(numeric)
        normalized.append(value)
    keys = [(row["basin"], row["date_key"]) for row in normalized]
    if len(keys) != len(set(keys)):
        raise ValueError("candidate input contains duplicate basin-date keys")
    return normalized


def _read_statics(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if (
        not isinstance(value, dict)
        or value.get("schema_version") != "development_static_attributes_v1"
        or not isinstance(value.get("basins"), dict)
    ):
        raise ValueError("candidate static attributes do not match the development schema")
    for basin, attributes in value["basins"].items():
        if not isinstance(attributes, dict) or not attributes:
            raise ValueError(f"candidate static attributes are empty for basin {basin}")
        if any(
            isinstance(number, bool)
            or not isinstance(number, (int, float))
            or not math.isfinite(number)
            for number in attributes.values()
        ):
            raise ValueError("candidate static attributes must be finite numbers")
    return value


def _read_targets(path: Path) -> dict[tuple[str, str], float]:
    rows = _read_rows(path, TARGET_COLUMNS)
    return {(row["basin"], row["date_key"]): row["qobs"] for row in rows}


def _validate_model(model: dict) -> None:
    if (
        not isinstance(model, dict)
        or model.get("schema_version") != "reference_candidate_model_v1"
        or model.get("candidate_id") != method.CANDIDATE_ID
        or model.get("category") != method.CATEGORY
        or model.get("method_family") != method.METHOD_FAMILY
    ):
        raise ValueError("reference model identity mismatch")


def _load_model(path: Path) -> dict:
    model = json.loads(path.read_text(encoding="utf-8"))
    _validate_model(model)
    return model


def _stage_checkpoint(model: dict, *, mode: str, resume_root: Path | None) -> None:
    staging = Path(os.environ["UNIFIED_CHECKPOINT_STAGING_ROOT"])
    model_bytes = _canonical_json(model)
    (staging / "model.json").write_bytes(model_bytes)
    parent_checkpoint_id = None
    if resume_root is not None:
        parent = json.loads((resume_root / "CHECKPOINT_VERIFIED.json").read_text(encoding="utf-8"))
        parent_checkpoint_id = parent["checkpoint_id"]
    checkpoint_number = 1 if parent_checkpoint_id is None else 2
    request = {
        "schema_version": "checkpoint_request_v1",
        "checkpoint_id": f"{method.CANDIDATE_ID}-{mode}-checkpoint-{checkpoint_number:04d}",
        "candidate_id": method.CANDIDATE_ID,
        "mode": mode,
        "parent_checkpoint_id": parent_checkpoint_id,
        "files": {"model.json": hashlib.sha256(model_bytes).hexdigest()},
    }
    (staging / "CHECKPOINT_REQUEST.json").write_bytes(_canonical_json(request))
    raise SystemExit(75)


def _train(input_root: Path, output_root: Path, statics: dict, seed: int) -> None:
    resume_value = os.environ.get("UNIFIED_RESUME_CHECKPOINT")
    resume_root = None if resume_value is None else Path(resume_value)
    if resume_root is None:
        features = _read_rows(input_root / "train_features.parquet", FEATURE_COLUMNS)
        targets = _read_targets(input_root / "train_targets.parquet")
        if {(row["basin"], row["date_key"]) for row in features} != set(targets):
            raise ValueError("candidate training features and targets do not have identical keys")
        payload = method.train_model(features, targets, statics, seed)
        model = {
            "schema_version": "reference_candidate_model_v1",
            "candidate_id": method.CANDIDATE_ID,
            "category": method.CATEGORY,
            "method_family": method.METHOD_FAMILY,
            "seed": seed,
            "payload": payload,
        }
        _validate_model(model)
    else:
        model = _load_model(resume_root / "model.json")
    if Path(os.environ["UNIFIED_STOP_REQUEST"]).is_file():
        _stage_checkpoint(model, mode="train", resume_root=resume_root)
    model_root = output_root / "model_artifacts"
    model_root.mkdir()
    (model_root / "model.json").write_bytes(_canonical_json(model))


def _predict(input_root: Path, output_root: Path, statics: dict) -> None:
    model = _load_model(input_root / "model_artifacts" / "model.json")
    resume_value = os.environ.get("UNIFIED_RESUME_CHECKPOINT")
    resume_root = None if resume_value is None else Path(resume_value)
    if Path(os.environ["UNIFIED_STOP_REQUEST"]).is_file():
        _stage_checkpoint(model, mode="predict", resume_root=resume_root)
    features = _read_rows(input_root / "predict_features.parquet", FEATURE_COLUMNS)
    values = method.predict(features, statics, model["payload"])
    if len(values) != len(features) or any(
        isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value)
        for value in values
    ):
        raise ValueError("reference candidate produced invalid predictions")
    table = pa.table(
        {
            "basin": [row["basin"] for row in features],
            "date": [row["date"] for row in features],
            "qsim": [float(value) for value in values],
        }
    )
    pq.write_table(table, output_root / "predictions.parquet")


def main() -> int:
    mode = os.environ["UNIFIED_MODE"]
    seed = int(os.environ["UNIFIED_SEED"])
    input_root = Path(os.environ["UNIFIED_INPUT_ROOT"])
    output_root = Path(os.environ["UNIFIED_OUTPUT_ROOT"])
    statics = _read_statics(input_root / "static_attributes.json")
    if mode == "train":
        _train(input_root, output_root, statics, seed)
    elif mode == "predict":
        _predict(input_root, output_root, statics)
    else:
        raise ValueError(f"unsupported mode: {mode!r}")
    return 0
