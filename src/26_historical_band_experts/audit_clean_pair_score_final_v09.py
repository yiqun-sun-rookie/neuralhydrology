"""Final no-rescore audit for the formal version-09 clean paired result."""
from __future__ import annotations

import argparse
from collections.abc import Mapping
import hashlib
import json
import math
import os
from pathlib import Path
import sys


IDEA_ROOT = Path(__file__).resolve().parent
REPO_ROOT = IDEA_ROOT.parents[1]
WORKTREE_SRC = REPO_ROOT / "src"
if str(WORKTREE_SRC) not in sys.path:
    sys.path.insert(0, str(WORKTREE_SRC))

from fair_benchmark.gate import GateConfig, decide  # noqa: E402
from fair_benchmark.governance import verify_chain  # noqa: E402
from fair_benchmark.ledger import read_rows  # noqa: E402
from fair_benchmark.postseal_holdout_v09 import derive_postseal_holdout_v09  # noqa: E402


_EXPERIMENT_ID = "S09C-CLEAN-PAIR"
_TRACK_ID = "track0_forcing_only_clean_v09"
_ROLES = ("baseline", "capacity_control", "challenger")
_CALL_COUNT_KEY = "score_" + "submission_call_count"
_FORBIDDEN_RESULT_KEYS = {
    "holdout_ids",
    "public_ids",
    "basin_ids",
    "per_basin",
    "per_basin_metrics",
    "daily_values",
    "qobs",
    "qsim",
}


def _canonical_bytes(value: Mapping) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def _canonical_sha256(value: Mapping) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _strict_json(path: Path) -> dict:
    def reject_constant(value: str):
        raise ValueError(f"non-finite JSON constant is forbidden: {value}")

    payload = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    if not isinstance(payload, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return payload


def _prediction_hashes(bundle: Mapping) -> dict:
    predictions = bundle.get("predictions")
    if not isinstance(predictions, Mapping) or tuple(predictions) != _ROLES:
        raise ValueError("bundle prediction roles or order drift")
    result = {}
    for role in _ROLES:
        record = predictions[role]
        if not isinstance(record, Mapping) or not isinstance(record.get("sha256"), str):
            raise ValueError(f"bundle prediction declaration is invalid: {role}")
        result[role] = record["sha256"]
    return result


def _contains_sensitive_output(value: object, basin_ids: set[str]) -> bool:
    if isinstance(value, Mapping):
        for key, item in value.items():
            if str(key).lower() in _FORBIDDEN_RESULT_KEYS or str(key) in basin_ids:
                return True
            if _contains_sensitive_output(item, basin_ids):
                return True
        return False
    if isinstance(value, list):
        return any(_contains_sensitive_output(item, basin_ids) for item in value)
    return isinstance(value, str) and value in basin_ids


def _normalise_stat_for_gate(stats: Mapping) -> dict:
    result = dict(stats)
    if result.get("wilcoxon_p") is None:
        if result.get("wilcoxon_p_reason") != "all_paired_differences_zero":
            raise ValueError("null Wilcoxon value lacks the only permitted reason")
        result["wilcoxon_p"] = float("nan")
    return result


def _numeric_equal(raw: object, expected: object, *, null_reason: str | None = None) -> bool:
    if expected is None:
        return str(raw).lower() == "nan" and null_reason == "all_paired_differences_zero"
    try:
        actual = float(raw)
        target = float(expected)
    except (TypeError, ValueError):
        return False
    return math.isfinite(actual) and math.isfinite(target) and actual == target


def _verify_ledger(report: Mapping, ledger_path: Path, prediction_hashes: Mapping) -> dict:
    chain = verify_chain(ledger_path)
    rows = read_rows(ledger_path)
    if not chain["ok"]:
        raise ValueError(f"ledger hash chain has {len(chain['breaks'])} break(s)")
    matching = [row for row in rows if row.get("experiment_id") == _EXPERIMENT_ID]
    if len(matching) != 1:
        raise ValueError("ledger must contain exactly one clean-pair row")
    row = matching[0]
    primary = report["primary"]["public"]
    after = report["ledger"]["after"]
    before = report["ledger"]["before"]
    if (
        after.get("row_count") != len(rows)
        or after.get("sha256") != _sha256(ledger_path)
        or after.get("last_row_hash") != rows[-1].get("row_hash")
        or report["ledger"].get("new_row_hash") != row.get("row_hash")
        or after.get("row_count") != before.get("row_count") + 1
    ):
        raise ValueError("report ledger snapshot or one-row delta drift")
    exact = {
        "experiment_id": _EXPERIMENT_ID,
        "track": _TRACK_ID,
        "verdict": report.get("verdict"),
        "n": str(primary.get("n")),
        "predictions_sha": prediction_hashes["challenger"],
    }
    if any(row.get(key) != value for key, value in exact.items()):
        raise ValueError("report primary identity does not match the ledger row")
    numeric = {
        "median_paired_delta": primary.get("median_paired_delta"),
        "wilcoxon_p": primary.get("wilcoxon_p"),
        "challenger_median": primary.get("challenger_median"),
        "baseline_median": primary.get("baseline_median"),
    }
    for key, value in numeric.items():
        reason = primary.get("wilcoxon_p_reason") if key == "wilcoxon_p" else None
        if not _numeric_equal(row.get(key), value, null_reason=reason):
            raise ValueError(f"report primary statistic does not match ledger field: {key}")
    return {
        "row_count": len(rows),
        "chain_breaks": 0,
        "experiment_id_count": 1,
        "new_row_hash": row["row_hash"],
    }


def _verify_gate(report: Mapping) -> dict:
    primary = report.get("primary")
    if not isinstance(primary, Mapping):
        raise ValueError("primary result is missing")
    gate = primary.get("gate")
    public = primary.get("public")
    holdout = primary.get("holdout")
    if not all(isinstance(value, Mapping) for value in (gate, public, holdout)):
        raise ValueError("primary gate or aggregate statistics are missing")
    if public.get("n") != 424 or holdout.get("n") != 107:
        raise ValueError("public or holdout aggregate count drift")
    if float(gate.get("ci_low_must_exceed")) != 0.0:
        raise ValueError("confidence interval gate drift")
    config = GateConfig(
        min_effect=float(gate["min_effect"]),
        max_wilcoxon_p=float(gate["max_wilcoxon_p"]),
        holdout_min_effect=float(gate["holdout_min_effect"]),
        holdout_retention=float(gate["holdout_retention"]),
    )
    derived = decide(
        has_predictions=True,
        contract_ok=primary.get("contract_ok") is True,
        coverage_ok=primary.get("coverage_ok") is True,
        public=_normalise_stat_for_gate(public),
        holdout=_normalise_stat_for_gate(holdout),
        cfg=config,
        leakage_ok=primary.get("leakage_hits") == 0,
    )
    if derived["verdict"] != report.get("verdict") or derived["reasons"] != report.get("reasons"):
        raise ValueError("reported primary verdict cannot be rederived from aggregate statistics")
    return derived


def _verify_receipts_and_partition(
    report: Mapping,
    authorization: Mapping,
    consumption: Mapping,
    consumption_file_sha256: str,
    draw: Mapping,
    bundle: Mapping,
    basin_ids: list[str],
    basin_file_sha256: str,
) -> dict:
    prediction_hashes = _prediction_hashes(bundle)
    if (
        authorization.get("status") != "authorized_clean_pair_score"
        or authorization.get("maximum_attempts") != 1
        or authorization.get("allowed_experiment_id") != _EXPERIMENT_ID
        or authorization.get("allowed_track_id") != _TRACK_ID
        or authorization.get("contract_sha256") != bundle.get("contract_sha256")
        or authorization.get("bundle_sha256") != bundle.get("bundle_sha256")
        or authorization.get("prediction_sha256") != prediction_hashes
        or authorization.get("prediction_seal_sha256") != bundle.get("prediction_seal_sha256")
    ):
        raise ValueError("authorization-to-bundle binding drift")
    trusted_basins = authorization.get("trusted_frozen_inputs", {}).get("basins", {})
    if trusted_basins.get("sha256") != basin_file_sha256:
        raise ValueError("frozen basin list SHA-256 drift")
    if (
        consumption.get("status") != "consumed_no_retry"
        or consumption.get("authorization_sha256") != _canonical_sha256(authorization)
        or consumption.get("maximum_attempts") != 1
        or consumption.get("retry_allowed") is not False
    ):
        raise ValueError("authorization consumption receipt drift")
    if (
        draw.get("status") != "complete_single_holdout_draw"
        or draw.get("consumption_file_sha256") != consumption_file_sha256
        or draw.get("consumption_canonical_sha256") != _canonical_sha256(consumption)
        or draw.get("contract_sha256") != bundle.get("contract_sha256")
        or draw.get("bundle_sha256") != bundle.get("bundle_sha256")
        or draw.get("prediction_sha256") != prediction_hashes
        or draw.get("nonce_draw_count") != 1
        or draw.get("nonce_redraw_count") != 0
    ):
        raise ValueError("single holdout draw binding drift")
    nonce_hex = draw.get("nonce_hex")
    if not isinstance(nonce_hex, str) or len(nonce_hex) != 64:
        raise ValueError("holdout draw must contain exactly one 256-bit nonce")
    partition = derive_postseal_holdout_v09(
        basin_ids,
        protocol_sha256=bundle["protocol_sha256"],
        prediction_sha256=prediction_hashes,
        nonce_hex=nonce_hex,
        holdout_count=107,
    )
    for key in (
        "method",
        "holdout_count",
        "public_count",
        "nonce_sha256",
        "partition_salt_sha256",
        "holdout_set_sha256",
    ):
        if draw.get(key) != partition[key]:
            raise ValueError(f"deterministic holdout receipt drift: {key}")
    provenance = report.get("provenance")
    if not isinstance(provenance, Mapping):
        raise ValueError("report provenance is missing")
    expected_provenance = {
        "contract_sha256": bundle.get("contract_sha256"),
        "bundle_sha256": bundle.get("bundle_sha256"),
        "prediction_seal_sha256": bundle.get("prediction_seal_sha256"),
        "prediction_sha256": prediction_hashes,
        "basin_file_sha256": basin_file_sha256,
        "holdout_draw_receipt_sha256": _canonical_sha256(draw),
        "nonce_sha256": partition["nonce_sha256"],
        "partition_salt_sha256": partition["partition_salt_sha256"],
        "holdout_set_sha256": partition["holdout_set_sha256"],
    }
    source_tree = authorization.get("source_tree")
    source_bundle = bundle.get("source_bundle")
    if not isinstance(source_tree, Mapping) or not isinstance(source_bundle, Mapping):
        raise ValueError("trusted or candidate source tree binding is missing")
    expected_provenance.update({
        "authorization_sha256": _canonical_sha256(authorization),
        "consumption_file_sha256": consumption_file_sha256,
        "consumption_canonical_sha256": _canonical_sha256(consumption),
        "trusted_source_tree_sha256": source_tree.get("tree_sha256"),
        "candidate_source_tree_sha256": source_bundle.get("tree_sha256"),
    })
    if any(provenance.get(key) != value for key, value in expected_provenance.items()):
        raise ValueError("report provenance binding drift")
    return {
        "method": partition["method"],
        "holdout_count": partition["holdout_count"],
        "public_count": partition["public_count"],
        "nonce_draw_count": 1,
        "nonce_redraw_count": 0,
        "holdout_set_sha256": partition["holdout_set_sha256"],
    }


def _verify_descriptive_boundaries(report: Mapping) -> dict:
    capacity = report.get("capacity_comparison")
    historical = report.get("historical_reference")
    if (
        not isinstance(capacity, Mapping)
        or capacity.get("verdict_role") != "descriptive_only"
        or capacity.get("may_affect_primary_verdict") is not False
    ):
        raise ValueError("capacity comparison is not strictly descriptive")
    if (
        not isinstance(historical, Mapping)
        or historical.get("status") != "historical_reference_nonqualifying"
        or historical.get("qualifying") is not False
        or historical.get("may_affect_verdict") is not False
    ):
        raise ValueError("historical reference qualification drift")
    supported = True
    for part in ("public", "holdout"):
        stats = capacity.get(part)
        if not isinstance(stats, Mapping):
            raise ValueError(f"capacity aggregate is missing: {part}")
        p_value = stats.get("wilcoxon_p")
        supported = supported and (
            float(stats.get("median_paired_delta", float("nan"))) > 0.0
            and p_value is not None
            and float(p_value) < 0.05
            and float(stats.get("ci_low", float("nan"))) > 0.0
        )
    return {
        "capacity_comparison_descriptive": True,
        "capacity_explanation_excluded": bool(supported),
    }


def audit_clean_pair_score_final_v09(
    report_path: str | Path,
    authorization_path: str | Path,
    consumption_path: str | Path,
    holdout_draw_receipt_path: str | Path,
    bundle_path: str | Path,
    basin_file_path: str | Path,
    ledger_path: str | Path,
) -> dict:
    """Audit one persisted result without opening target or prediction values."""
    paths = {
        "report": Path(report_path),
        "authorization": Path(authorization_path),
        "consumption": Path(consumption_path),
        "holdout_draw": Path(holdout_draw_receipt_path),
        "bundle": Path(bundle_path),
        "basins": Path(basin_file_path),
        "ledger": Path(ledger_path),
    }
    result = {
        "status": "HOLD_INCOMPLETE_NO_RETRY",
        "errors": [],
        "answer_reopened": False,
        "prediction_values_opened": False,
        "retry_allowed": False,
    }
    missing = [name for name, path in paths.items() if not path.is_file()]
    if missing:
        result["errors"].append(f"missing required final artifact(s): {missing}")
        return result
    try:
        report = _strict_json(paths["report"])
        authorization = _strict_json(paths["authorization"])
        consumption = _strict_json(paths["consumption"])
        draw = _strict_json(paths["holdout_draw"])
        bundle = _strict_json(paths["bundle"])
        basin_file_sha256 = _sha256(paths["basins"])
        basin_ids = [
            value.strip()
            for value in paths["basins"].read_text(encoding="utf-8").splitlines()
            if value.strip()
        ]
        if len(basin_ids) != 531 or len(set(basin_ids)) != 531:
            raise ValueError("frozen basin list must contain exactly 531 unique identifiers")
        if _contains_sensitive_output(report, set(basin_ids)):
            raise ValueError("report exposes basin identities or per-basin/daily values")
        if report.get(_CALL_COUNT_KEY) != 1 or report.get("ledger_append_count") != 1:
            raise ValueError("report does not prove exactly one trusted call and ledger append")

        partition = _verify_receipts_and_partition(
            report,
            authorization,
            consumption,
            _sha256(paths["consumption"]),
            draw,
            bundle,
            basin_ids,
            basin_file_sha256,
        )
        gate = _verify_gate(report)
        ledger = _verify_ledger(report, paths["ledger"], _prediction_hashes(bundle))
        descriptive = _verify_descriptive_boundaries(report)
        result.update({
            "status": gate["verdict"],
            "reasons": gate["reasons"],
            _CALL_COUNT_KEY: 1,
            "ledger_rows_added": 1,
            "ledger": ledger,
            "postseal_holdout": partition,
            **descriptive,
        })
    except Exception as exc:
        result["status"] = "REJECT"
        result["errors"].append(f"{type(exc).__name__}: {exc}")
    return result


def _exclusive_write(path: Path, payload: Mapping) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True)
    parser.add_argument("--authorization", required=True)
    parser.add_argument("--consumption", required=True)
    parser.add_argument("--holdout-draw-receipt", required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--basin-file", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    result = audit_clean_pair_score_final_v09(
        args.report,
        args.authorization,
        args.consumption,
        args.holdout_draw_receipt,
        args.bundle,
        args.basin_file,
        args.ledger,
    )
    _exclusive_write(Path(args.out), result)
    print(json.dumps(result, sort_keys=True, ensure_ascii=False, allow_nan=False))
    return 0 if result["status"] in {"PASS", "HOLD", "REJECT"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
