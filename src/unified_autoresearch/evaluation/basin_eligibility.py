"""Declare, before any search, the basins where Nash--Sutcliffe efficiency is not meaningful.

Nash--Sutcliffe efficiency divides by the variance of the observed record, so it stops being
informative when that variance is tiny, when it rests on a single day, or when the basin is dry
for most of the window. Deciding which basins those are *after* seeing candidate scores would let
the judgement be tuned to the result, so this module reads validation truth only and is written
once, before the search, next to the frozen package it describes.

Unstable basins are never dropped. They are reported as their own group so a headline number can
be honest about what it covers.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import pandas as pd

from unified_autoresearch.evaluation.scoring import _frozen_basin_list


SCHEMA_VERSION = "basin_eligibility_v1"
DECIDED_FROM = "validation truth only; no candidate prediction is read"

# Over half the validation window is exactly dry: the mean-flow benchmark that Nash--Sutcliffe
# compares against then mostly measures dry-spell bookkeeping rather than hydrological skill.
ZERO_FLOW_FRACTION_LIMIT = 0.5
# One single day supplies at least half the denominator: the score becomes a one-day lottery.
SINGLE_DAY_VARIANCE_SHARE_LIMIT = 0.5


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


def _basin_statistics(observed: np.ndarray) -> dict:
    """Summarise how much of a Nash--Sutcliffe denominator this record actually provides."""
    deviations = observed - observed.mean()
    squared = deviations**2
    total = float(squared.sum())
    share = 1.0 if total <= 0.0 else float(squared.max()) / total
    return {
        "days": int(observed.size),
        "zero_flow_fraction": float((observed == 0.0).mean()),
        "standard_deviation": float(observed.std(ddof=0)),
        "single_day_variance_share": share,
        "zero_variance": total <= 0.0,
    }


def _reasons(statistics: Mapping[str, object]) -> list[str]:
    reasons = []
    if statistics["zero_variance"]:
        reasons.append("zero_variance")
    if float(statistics["zero_flow_fraction"]) >= ZERO_FLOW_FRACTION_LIMIT:
        reasons.append("zero_flow_fraction")
    if float(statistics["single_day_variance_share"]) >= SINGLE_DAY_VARIANCE_SHARE_LIMIT:
        reasons.append("single_day_variance_share")
    return reasons


def classify_development_basins(
    *,
    package_root: str | Path,
    expected_package_manifest_sha256: str,
    output_path: str | Path,
) -> dict:
    """Split the frozen basins into a standard group and an unstable group, from truth alone."""
    package_root = Path(package_root).resolve()
    output_path = Path(output_path).resolve()
    if output_path.exists():
        raise FileExistsError(output_path)

    manifest_path = package_root / "PACKAGE_MANIFEST.json"
    if _sha256(manifest_path) != expected_package_manifest_sha256:
        raise ValueError("development package manifest differs from the frozen digest")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    # Classifying an arbitrary package would let the unstable set be chosen rather than derived.
    basins = _frozen_basin_list([str(basin).zfill(8) for basin in manifest["basins"]])
    protocols = list(manifest["protocols"])

    truth_by_protocol: dict[str, pd.DataFrame] = {}
    for protocol_name in protocols:
        truth_path = package_root / protocol_name / "score" / "validation_truth.parquet"
        relative = truth_path.relative_to(package_root).as_posix()
        if manifest["files"].get(relative) != _sha256(truth_path):
            raise ValueError(f"validation truth hash mismatch: {relative}")
        frame = pd.read_parquet(truth_path)
        frame["basin"] = frame["basin"].astype(str).str.zfill(8)
        truth_by_protocol[protocol_name] = frame

    entries: dict[str, dict] = {}
    for basin in basins:
        per_protocol: dict[str, dict] = {}
        reasons: list[str] = []
        for protocol_name in protocols:
            frame = truth_by_protocol[protocol_name]
            observed = frame.loc[frame["basin"] == basin, "qobs"].to_numpy(dtype=np.float64)
            if observed.size == 0:
                raise ValueError(f"validation truth has no rows for basin {basin} in {protocol_name}")
            statistics = _basin_statistics(observed)
            per_protocol[protocol_name] = statistics
            reasons.extend(_reasons(statistics))
        unique_reasons = sorted(set(reasons))
        entries[basin] = {
            "status": "unstable" if unique_reasons else "standard",
            "reasons": unique_reasons,
            "protocols": per_protocol,
        }

    record = {
        "schema_version": SCHEMA_VERSION,
        "decided_from": DECIDED_FROM,
        "package_manifest_sha256": expected_package_manifest_sha256,
        "protocols": protocols,
        "thresholds": {
            "zero_flow_fraction_at_or_above": ZERO_FLOW_FRACTION_LIMIT,
            "single_day_variance_share_at_or_above": SINGLE_DAY_VARIANCE_SHARE_LIMIT,
        },
        "basins": entries,
        "standard_basins": [basin for basin in basins if entries[basin]["status"] == "standard"],
        "unstable_basins": [basin for basin in basins if entries[basin]["status"] == "unstable"],
    }
    _write_json_exclusive(output_path, record)
    return record


def partition_summary_cells(*, cells: Sequence[Mapping], eligibility: Mapping) -> dict:
    """Split summary cells into the headline group and the separately reported unstable group."""
    if eligibility.get("schema_version") != SCHEMA_VERSION:
        raise ValueError("basin eligibility record schema mismatch")
    standard = list(eligibility["standard_basins"])
    unstable = list(eligibility["unstable_basins"])
    # Guarding only against a missing basin would let a duplicate or an overlap inflate the
    # headline group while every count still looked self-consistent.
    if len(set(standard)) != len(standard) or len(set(unstable)) != len(unstable) or set(standard) & set(unstable):
        raise ValueError("classified basins must be unique and must not overlap")
    by_basin = {str(cell["basin"]).zfill(8): cell for cell in cells}
    if len(by_basin) != len(cells) or set(by_basin) != set(standard) | set(unstable):
        raise ValueError("summary cells must cover exactly the classified basins")
    return {
        "standard": [by_basin[basin] for basin in standard],
        "unstable": [by_basin[basin] for basin in unstable],
        "headline_basin_count": len(standard),
        "unstable_basin_count": len(unstable),
        "thresholds": dict(eligibility["thresholds"]),
    }
