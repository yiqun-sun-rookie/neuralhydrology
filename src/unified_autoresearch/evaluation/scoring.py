"""External Nash--Sutcliffe efficiency scoring for development packages."""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd

from unified_autoresearch.data.packages import FROZEN_DEVELOPMENT_SELECTIONS
from unified_autoresearch.protocols.validation import FROZEN_DEVELOPMENT_PROTOCOL
from unified_autoresearch.runtime.descriptor import CANDIDATE_CATEGORIES, CANDIDATE_ID_PATTERN


SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
FROZEN_BASIN_LISTS = tuple(list(selection["basins"]) for selection in FROZEN_DEVELOPMENT_SELECTIONS)


def _frozen_basin_list(basins) -> list[str]:
    """Return the frozen basin list matching this set, or refuse a basin set nobody froze."""
    for candidate in FROZEN_BASIN_LISTS:
        if set(candidate) == set(basins):
            return list(candidate)
    raise ValueError("basin set is not one of the frozen development selections")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json_exclusive(path: Path, value: dict) -> None:
    content = (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        path.unlink(missing_ok=True)
        raise


def _is_symbolic_link(path: str | Path) -> bool:
    """Test the link property on the given path, before resolve() erases it."""
    return Path(path).is_symlink()


def score_development_predictions(
    *,
    package_root: str | Path,
    expected_package_manifest_sha256: str,
    candidate_id: str,
    category: str,
    registered_run_id: str,
    protocol_name: str,
    predictions_path: str | Path,
    output_path: str | Path,
) -> dict:
    """Score one candidate output without invoking the sealed evaluation service."""
    package_root = Path(package_root).resolve()
    predictions_are_linked = _is_symbolic_link(predictions_path)
    predictions_path = Path(predictions_path).resolve()
    output_path = Path(output_path).resolve()
    if output_path.exists():
        raise FileExistsError(output_path)
    if protocol_name not in FROZEN_DEVELOPMENT_PROTOCOL["development_protocols"]:
        raise ValueError("unknown development protocol")
    if (
        SHA256_PATTERN.fullmatch(expected_package_manifest_sha256) is None
        or CANDIDATE_ID_PATTERN.fullmatch(candidate_id) is None
        or category not in CANDIDATE_CATEGORIES
        or CANDIDATE_ID_PATTERN.fullmatch(registered_run_id) is None
    ):
        raise ValueError("development score identity is invalid")
    if (
        predictions_are_linked
        or predictions_path.is_symlink()
        or not predictions_path.is_file()
        or predictions_path.stat().st_nlink != 1
    ):
        raise ValueError("predictions must be an unlinked regular Parquet file")

    manifest_path = package_root / "PACKAGE_MANIFEST.json"
    if _sha256(manifest_path) != expected_package_manifest_sha256:
        raise ValueError("development package manifest differs from the frozen digest")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if (
        set(manifest)
        != {
            "schema_version",
            "protocols",
            "development_protocols",
            "basins",
            "source_manifest_sha256",
            "source_files",
            "files",
        }
        or
        manifest.get("schema_version") != "development_packages_v1"
        or manifest.get("protocols") != ["forward", "reverse"]
        or manifest.get("development_protocols") != FROZEN_DEVELOPMENT_PROTOCOL["development_protocols"]
        or manifest.get("basins") not in FROZEN_BASIN_LISTS
        or not isinstance(manifest.get("source_manifest_sha256"), str)
        or SHA256_PATTERN.fullmatch(manifest["source_manifest_sha256"]) is None
    ):
        raise ValueError("development package manifest mismatch")
    expected_files = set(manifest["files"])
    actual_paths = [path for path in package_root.rglob("*") if path.is_file()]
    actual_files = {path.relative_to(package_root).as_posix() for path in actual_paths} - {"PACKAGE_MANIFEST.json"}
    if (
        actual_files != expected_files
        or any(
            path.is_symlink()
            or path.stat().st_nlink != 1
            or manifest["files"].get(path.relative_to(package_root).as_posix()) != _sha256(path)
            for path in actual_paths
            if path != manifest_path
        )
    ):
        raise ValueError("development package file set or hash mismatch")
    truth_path = package_root / protocol_name / "score" / "validation_truth.parquet"
    truth_relative = truth_path.relative_to(package_root).as_posix()
    if manifest["files"].get(truth_relative) != _sha256(truth_path):
        raise ValueError("development truth hash mismatch")

    truth = pd.read_parquet(truth_path)
    predictions = pd.read_parquet(predictions_path)
    if set(truth.columns) != {"basin", "date", "qobs"} or set(predictions.columns) != {"basin", "date", "qsim"}:
        raise ValueError("development scoring columns do not match the frozen contract")
    for frame in (truth, predictions):
        frame["basin"] = frame["basin"].astype(str).str.zfill(8)
        frame["date"] = pd.to_datetime(frame["date"], errors="raise")
    truth_keys = pd.MultiIndex.from_frame(truth[["basin", "date"]])
    prediction_keys = pd.MultiIndex.from_frame(predictions[["basin", "date"]])
    if truth_keys.has_duplicates or prediction_keys.has_duplicates or set(truth_keys) != set(prediction_keys):
        raise ValueError("prediction rows must exactly match development truth")
    if pd.api.types.is_bool_dtype(predictions["qsim"].dtype):
        raise ValueError("prediction values must be finite non-boolean numbers")
    try:
        predictions["qsim"] = pd.to_numeric(predictions["qsim"], errors="raise")
    except (TypeError, ValueError) as error:
        raise ValueError("prediction values must be finite non-boolean numbers") from error
    if not np.isfinite(predictions["qsim"].to_numpy(dtype=np.float64)).all():
        raise ValueError("prediction values must be finite non-boolean numbers")
    paired = truth.merge(predictions, on=["basin", "date"], how="inner", validate="one_to_one")
    metrics: dict[str, float] = {}
    for basin, frame in paired.groupby("basin", sort=True):
        observed = frame["qobs"].to_numpy(dtype=float)
        simulated = frame["qsim"].to_numpy(dtype=float)
        denominator = float(((observed - observed.mean()) ** 2).sum())
        if denominator <= 0.0:
            raise ValueError("development truth must have nonzero variance for every basin")
        value = 1.0 - float(((simulated - observed) ** 2).sum()) / denominator
        if not math.isfinite(value):
            raise ValueError("development metric must be finite")
        metrics[str(basin).zfill(8)] = value
    report = {
        "schema_version": "development_score_v1",
        "candidate_id": candidate_id,
        "category": category,
        "registered_run_id": registered_run_id,
        "protocol": protocol_name,
        "row_count": len(paired),
        "basin_metrics": metrics,
        "package_manifest_sha256": _sha256(manifest_path),
        "truth_sha256": _sha256(truth_path),
        "predictions_sha256": _sha256(predictions_path),
    }
    _write_json_exclusive(output_path, report)
    return report


def summarize_candidate_development_scores(
    *,
    candidate_id: str,
    category: str,
    registered_run_ids: Mapping[str, str],
    expected_package_manifest_sha256: str,
    score_paths: Mapping[str, str | Path],
    output_path: str | Path,
) -> dict:
    """Combine two protocol reports into eight candidate--basin cells."""
    if CANDIDATE_ID_PATTERN.fullmatch(candidate_id) is None or category not in CANDIDATE_CATEGORIES:
        raise ValueError("candidate summary identity is invalid")
    if (
        set(score_paths) != {"forward", "reverse"}
        or set(registered_run_ids) != {"forward", "reverse"}
        or any(CANDIDATE_ID_PATTERN.fullmatch(value) is None for value in registered_run_ids.values())
        or SHA256_PATTERN.fullmatch(expected_package_manifest_sha256) is None
    ):
        raise ValueError("candidate summary requires exactly both development protocols")
    output_path = Path(output_path).resolve()
    if output_path.exists():
        raise FileExistsError(output_path)

    reports: dict[str, dict] = {}
    hashes: dict[str, str] = {}
    frozen_basins: list[str] | None = None
    expected_report_fields = {
        "schema_version",
        "candidate_id",
        "category",
        "registered_run_id",
        "protocol",
        "row_count",
        "basin_metrics",
        "package_manifest_sha256",
        "truth_sha256",
        "predictions_sha256",
    }
    for protocol_name in ("forward", "reverse"):
        report_is_linked = _is_symbolic_link(score_paths[protocol_name])
        path = Path(score_paths[protocol_name]).resolve()
        if report_is_linked or path.is_symlink() or not path.is_file() or path.stat().st_nlink != 1:
            raise ValueError("score reports must be unlinked regular files")
        report = json.loads(path.read_text(encoding="utf-8"))
        metrics = report.get("basin_metrics")
        if isinstance(metrics, dict):
            # Both protocols must report the same frozen basin set; nothing else is accepted.
            try:
                protocol_basins = _frozen_basin_list(metrics)
            except ValueError as error:
                raise ValueError("development score report identity or source mismatch") from error
            if frozen_basins is None:
                frozen_basins = protocol_basins
            if protocol_basins != frozen_basins:
                raise ValueError("development score report identity or source mismatch")
        if (
            set(report) != expected_report_fields
            or report.get("schema_version") != "development_score_v1"
            or report.get("candidate_id") != candidate_id
            or report.get("category") != category
            or report.get("registered_run_id") != registered_run_ids[protocol_name]
            or report.get("protocol") != protocol_name
            or report.get("package_manifest_sha256") != expected_package_manifest_sha256
            or not isinstance(report.get("row_count"), int)
            or isinstance(report.get("row_count"), bool)
            or report["row_count"] < 1
            or not isinstance(report.get("truth_sha256"), str)
            or SHA256_PATTERN.fullmatch(report["truth_sha256"]) is None
            or not isinstance(report.get("predictions_sha256"), str)
            or SHA256_PATTERN.fullmatch(report["predictions_sha256"]) is None
            or not isinstance(metrics, dict)
            or any(isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) for value in metrics.values())
        ):
            raise ValueError("development score report identity or source mismatch")
        reports[protocol_name] = report
        hashes[protocol_name] = _sha256(path)

    cells = []
    for basin in frozen_basins or []:
        forward = float(reports["forward"]["basin_metrics"][basin])
        reverse = float(reports["reverse"]["basin_metrics"][basin])
        mean = forward / 2.0 + reverse / 2.0
        if not math.isfinite(mean):
            raise ValueError("candidate summary mean must be finite")
        cells.append(
            {
                "basin": basin,
                "forward_nse": forward,
                "reverse_nse": reverse,
                "mean_nse": mean,
            }
        )
    summary = {
        "schema_version": "candidate_development_summary_v1",
        "candidate_id": candidate_id,
        "category": category,
        "registered_run_ids": dict(registered_run_ids),
        "package_manifest_sha256": expected_package_manifest_sha256,
        "cell_count": len(cells),
        "cells": cells,
        "score_sha256": hashes,
    }
    _write_json_exclusive(output_path, summary)
    return summary
