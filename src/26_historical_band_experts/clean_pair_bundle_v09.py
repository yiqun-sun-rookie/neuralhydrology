"""Build an observation-blind bundle for the formal version-09 clean comparison."""
from __future__ import annotations

from collections.abc import Mapping, Sequence
import hashlib
import json
from pathlib import Path
import re

import numpy as np
import pandas as pd


class CleanPairBundleError(RuntimeError):
    """Raised when prediction coverage or its upstream seal is incomplete."""


_ROLES = ("baseline", "capacity_control", "challenger")
_SEEDS = tuple(range(100, 801, 100))
_COLUMNS = ("basin", "date", "qsim")
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_EVIDENCE_KEYS = {
    "input_seal_sha256",
    "input_external_audit_sha256",
    "trusted_target_source_audit_sha256",
    "legacy_reference_bridge_audit_sha256",
    "strict_nesting_seal_sha256",
    "strict_nesting_external_audit_sha256",
    "training_seal_sha256",
    "training_external_audit_sha256",
    "state_diagnostics_preregistration_sha256",
    "state_diagnostics_external_audit_sha256",
    "prediction_external_audit_sha256",
    "source_bundle_manifest_sha256",
    "environment_sha256",
}


def _canonical_sha256(value: Mapping) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_hex64(value: object, name: str) -> str:
    if not isinstance(value, str) or _HEX64.fullmatch(value) is None:
        raise CleanPairBundleError(f"{name} must be 64 lowercase hexadecimal characters")
    return value


def validate_clean_pair_prediction_file_v09(
    path: str | Path,
    basin_ids: Sequence[str],
    dates: Sequence[str],
    *,
    chunk_rows: int = 50_000,
) -> dict:
    """Stream one file and prove exact basin-major, date-minor finite coverage."""
    path = Path(path)
    basins = tuple(str(value) for value in basin_ids)
    expected_dates = tuple(str(value) for value in dates)
    if not path.is_file():
        raise CleanPairBundleError(f"prediction file is missing: {path}")
    if not basins or len(set(basins)) != len(basins) or any(not value for value in basins):
        raise CleanPairBundleError("basin identifiers must be nonempty and unique")
    if not expected_dates or len(set(expected_dates)) != len(expected_dates):
        raise CleanPairBundleError("prediction dates must be nonempty and unique")
    if int(chunk_rows) <= 0:
        raise ValueError("chunk_rows must be positive")

    expected_rows = len(basins) * len(expected_dates)
    row_count = 0
    try:
        chunks = pd.read_csv(
            path,
            dtype={"basin": "string", "date": "string"},
            chunksize=int(chunk_rows),
        )
        for frame in chunks:
            if tuple(frame.columns) != _COLUMNS:
                raise CleanPairBundleError("prediction columns must be exactly basin,date,qsim")
            if frame[["basin", "date"]].isna().any().any():
                raise CleanPairBundleError("prediction key contains a missing value")
            try:
                qsim = pd.to_numeric(frame["qsim"], errors="raise").to_numpy(dtype=np.float64)
            except (TypeError, ValueError) as exc:
                raise CleanPairBundleError("qsim contains a nonnumeric value") from exc
            if not np.isfinite(qsim).all():
                raise CleanPairBundleError("qsim contains a nonfinite value")

            positions = np.arange(row_count, row_count + len(frame), dtype=np.int64)
            if positions.size and int(positions[-1]) >= expected_rows:
                raise CleanPairBundleError("prediction file has extra rows")
            expected_basin = np.asarray(basins, dtype=object)[positions // len(expected_dates)]
            expected_date = np.asarray(expected_dates, dtype=object)[positions % len(expected_dates)]
            actual_basin = frame["basin"].astype(str).to_numpy(dtype=object)
            actual_date = frame["date"].astype(str).to_numpy(dtype=object)
            if not np.array_equal(actual_basin, expected_basin):
                raise CleanPairBundleError("prediction basin order, coverage, or uniqueness drift")
            if not np.array_equal(actual_date, expected_date):
                raise CleanPairBundleError("prediction date order, coverage, or uniqueness drift")
            row_count += len(frame)
    except (OSError, pd.errors.ParserError) as exc:
        raise CleanPairBundleError(f"unable to stream prediction file: {exc}") from exc

    if row_count != expected_rows:
        raise CleanPairBundleError(f"prediction row count drift: {row_count} != {expected_rows}")
    return {
        "status": "exact_ordered_coverage",
        "sha256": _sha256(path),
        "columns": list(_COLUMNS),
        "basin_count": len(basins),
        "dates_per_basin": len(expected_dates),
        "row_count": row_count,
        "key_order": "basin_major_date_minor",
        "qsim_finite": True,
        "qsim_parse_dtype": "float64",
    }


def _validate_contract_shape(contract: Mapping) -> None:
    if contract.get("contract_id") != "S09C-CLEAN-PAIR":
        raise CleanPairBundleError("clean-pair contract identity drift")
    if contract.get("track_id") != "track0_forcing_only_clean_v09":
        raise CleanPairBundleError("clean-pair track identity drift")
    if tuple(contract.get("roles", {})) != _ROLES:
        raise CleanPairBundleError("clean-pair role order drift")
    if tuple(contract.get("ensemble_paths", {})) != _ROLES:
        raise CleanPairBundleError("ensemble path role order drift")
    prediction = contract.get("prediction_contract")
    if not isinstance(prediction, Mapping) or prediction.get("columns") != list(_COLUMNS):
        raise CleanPairBundleError("prediction contract drift")
    if prediction.get("seeds") != list(_SEEDS):
        raise CleanPairBundleError("prediction seed order drift")
    if prediction.get("ensemble_operation") != "float64_arithmetic_mean":
        raise CleanPairBundleError("ensemble operation drift")
    holdout = contract.get("postseal_holdout")
    if not isinstance(holdout, Mapping):
        raise CleanPairBundleError("post-seal holdout contract is missing")
    if holdout.get("method") != "postseal_nonce_sha256_rank_v1":
        raise CleanPairBundleError("post-seal holdout method drift")
    if holdout.get("holdout_count", 0) + holdout.get("public_count", 0) != prediction.get("basin_count"):
        raise CleanPairBundleError("post-seal partition counts drift")


def _validate_seal_evidence(
    contract: Mapping,
    prediction_seal: Mapping,
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    if prediction_seal.get("status") != "complete_prediction_seal":
        raise CleanPairBundleError("prediction seal is incomplete")
    if prediction_seal.get("protocol_sha256") != contract.get("protocol_sha256"):
        raise CleanPairBundleError("prediction seal protocol drift")
    if prediction_seal.get("official_score_called") is not False:
        raise CleanPairBundleError("prediction seal indicates a prior score call")

    evidence = prediction_seal.get("upstream_evidence")
    if not isinstance(evidence, Mapping) or set(evidence) != _EVIDENCE_KEYS:
        raise CleanPairBundleError("upstream evidence keys are incomplete or unknown")
    for key, value in evidence.items():
        _require_hex64(value, f"upstream_evidence[{key}]")

    source_bundle = prediction_seal.get("source_bundle")
    if (
        not isinstance(source_bundle, Mapping)
        or source_bundle.get("status") != "complete_source_bundle"
        or source_bundle.get("scan_hits") != 0
    ):
        raise CleanPairBundleError("candidate source bundle is incomplete or has scan hits")
    _require_hex64(source_bundle.get("tree_sha256"), "source_bundle tree SHA-256")

    checkpoints = prediction_seal.get("final_checkpoints")
    if not isinstance(checkpoints, list) or len(checkpoints) != len(_ROLES) * len(_SEEDS):
        raise CleanPairBundleError("exactly 24 final checkpoints are required")
    expected_pairs = {(role, seed) for role in _ROLES for seed in _SEEDS}
    actual_pairs = set()
    for record in checkpoints:
        if not isinstance(record, Mapping):
            raise CleanPairBundleError("checkpoint record must be an object")
        role = record.get("role")
        seed = record.get("seed")
        if role not in _ROLES or seed not in _SEEDS:
            raise CleanPairBundleError("checkpoint role or seed drift")
        if record.get("experiment_id") != contract["roles"][role] or record.get("epoch") != 30:
            raise CleanPairBundleError("checkpoint experiment or epoch drift")
        _require_hex64(record.get("sha256"), "checkpoint SHA-256")
        actual_pairs.add((role, seed))
    if actual_pairs != expected_pairs:
        raise CleanPairBundleError("checkpoint role-seed coverage drift")

    coverage = prediction_seal.get("coverage")
    if not isinstance(coverage, Mapping):
        raise CleanPairBundleError("prediction coverage declaration is missing")
    basins = tuple(str(value) for value in coverage.get("basin_ids", ()))
    if len(basins) != contract["prediction_contract"]["basin_count"] or len(set(basins)) != len(basins):
        raise CleanPairBundleError("prediction basin coverage declaration drift")
    if coverage.get("start_date") != contract["prediction_contract"]["start_date"]:
        raise CleanPairBundleError("prediction start date drift")
    if coverage.get("end_date") != contract["prediction_contract"]["end_date"]:
        raise CleanPairBundleError("prediction end date drift")
    dates = tuple(
        pd.date_range(coverage["start_date"], coverage["end_date"], freq="D").strftime("%Y-%m-%d")
    )
    if len(dates) != contract["prediction_contract"]["dates_per_basin"]:
        raise CleanPairBundleError("prediction dates-per-basin drift")
    return basins, dates


def _resolve_prediction(root: Path, relative_path: str) -> Path:
    relative = Path(relative_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise CleanPairBundleError("prediction path must be a safe relative path")
    resolved_root = root.resolve()
    resolved = (root / relative).resolve()
    if not resolved.is_relative_to(resolved_root):
        raise CleanPairBundleError("prediction path escapes the sealed root")
    return resolved


def clean_pair_bundle_sha256(bundle: Mapping) -> str:
    """Hash the compact sorted bundle after excluding its self-hash field."""
    payload = dict(bundle)
    payload.pop("bundle_sha256", None)
    return _canonical_sha256(payload)


def build_clean_pair_bundle_v09(
    contract: Mapping,
    prediction_seal: Mapping,
    prediction_root: str | Path,
) -> dict:
    """Build the three-role bundle without metrics, random draws, or held targets."""
    _validate_contract_shape(contract)
    basins, dates = _validate_seal_evidence(contract, prediction_seal)
    prediction_root = Path(prediction_root)
    sealed_predictions = prediction_seal.get("predictions")
    if not isinstance(sealed_predictions, Mapping) or tuple(sealed_predictions) != _ROLES:
        raise CleanPairBundleError("sealed prediction roles or order drift")

    predictions = {}
    for role in _ROLES:
        declared = sealed_predictions[role]
        if not isinstance(declared, Mapping):
            raise CleanPairBundleError(f"sealed prediction declaration for {role} is invalid")
        relative_path = contract["ensemble_paths"][role]
        if declared.get("relative_path") != relative_path:
            raise CleanPairBundleError(f"{role} prediction path drift")
        if declared.get("experiment_id") != contract["roles"][role]:
            raise CleanPairBundleError(f"{role} experiment identity drift")
        if declared.get("status") != "complete_prediction":
            raise CleanPairBundleError(f"{role} prediction is incomplete")
        path = _resolve_prediction(prediction_root, relative_path)
        coverage = validate_clean_pair_prediction_file_v09(path, basins, dates)
        for field in ("sha256", "row_count", "basin_count", "dates_per_basin"):
            if declared.get(field) != coverage[field]:
                raise CleanPairBundleError(f"{role} declared {field} drift")
        if coverage["row_count"] != contract["prediction_contract"]["rows_per_file"]:
            raise CleanPairBundleError(f"{role} row count violates the contract")
        predictions[role] = {
            "experiment_id": contract["roles"][role],
            "relative_path": relative_path,
            **coverage,
        }

    bundle = {
        "bundle_version": 1,
        "contract_id": contract["contract_id"],
        "contract_sha256": _canonical_sha256(contract),
        "protocol_id": contract["protocol_id"],
        "protocol_sha256": contract["protocol_sha256"],
        "track_id": contract["track_id"],
        "prediction_seal_sha256": _canonical_sha256(prediction_seal),
        "upstream_evidence": dict(prediction_seal["upstream_evidence"]),
        "source_bundle": dict(prediction_seal["source_bundle"]),
        "final_checkpoints": [dict(record) for record in prediction_seal["final_checkpoints"]],
        "predictions": predictions,
        "postseal_holdout": {
            "method": contract["postseal_holdout"]["method"],
            "status": "awaiting_authorized_nonce_draw",
            "holdout_count": contract["postseal_holdout"]["holdout_count"],
            "public_count": contract["postseal_holdout"]["public_count"],
        },
        "status": "complete_clean_pair_bundle",
    }
    bundle["bundle_sha256"] = clean_pair_bundle_sha256(bundle)
    return bundle
