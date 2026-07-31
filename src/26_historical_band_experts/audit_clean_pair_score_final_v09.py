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
_STAT_KEYS = {
    "n",
    "challenger_median",
    "baseline_median",
    "median_paired_delta",
    "win_rate",
    "wilcoxon_p",
    "ci_low",
    "ci_high",
}
_PRIMARY_GATE = {
    "min_effect": 0.01,
    "max_wilcoxon_p": 0.05,
    "bootstrap_samples": 10000,
    "bootstrap_seed": 0,
    "ci_low_must_exceed": 0.0,
    "holdout_min_effect": 0.005,
    "holdout_retention": 0.5,
}


def _require_exact_keys(value: object, expected: set[str], name: str) -> Mapping:
    if not isinstance(value, Mapping) or set(value) != expected:
        raise ValueError(f"{name} keys drift")
    return value


def _validate_stat_schema(value: object, name: str) -> None:
    if not isinstance(value, Mapping):
        raise ValueError(f"{name} must be an object")
    keys = set(value)
    if keys not in (_STAT_KEYS, _STAT_KEYS | {"wilcoxon_p_reason"}):
        raise ValueError(f"{name} aggregate keys drift")
    if not isinstance(value["n"], int) or value["n"] < 0:
        raise ValueError(f"{name} count is invalid")
    for key in _STAT_KEYS - {"n", "wilcoxon_p"}:
        item = value[key]
        if not isinstance(item, (int, float)) or not math.isfinite(float(item)):
            raise ValueError(f"{name} statistic is nonnumeric or nonfinite: {key}")
    p_value = value["wilcoxon_p"]
    if p_value is None:
        if value.get("wilcoxon_p_reason") != "all_paired_differences_zero":
            raise ValueError(f"{name} null Wilcoxon value lacks its fixed reason")
    elif not isinstance(p_value, (int, float)) or not math.isfinite(float(p_value)):
        raise ValueError(f"{name} Wilcoxon value is nonnumeric or nonfinite")
    elif "wilcoxon_p_reason" in value:
        raise ValueError(f"{name} has a reason for a finite Wilcoxon value")


def _validate_report_schema(report: Mapping) -> None:
    _require_exact_keys(
        report,
        {
            "contract_id",
            "track",
            "verdict",
            "reasons",
            "primary",
            "capacity_comparison",
            "historical_reference",
            "provenance",
            "ledger",
            _CALL_COUNT_KEY,
            "ledger_append_count",
        },
        "report",
    )
    primary = _require_exact_keys(
        report["primary"],
        {
            "baseline_id",
            "challenger_id",
            "gate",
            "public",
            "holdout",
            "coverage_ok",
            "leakage_hits",
            "leakage_detail",
            "contract_ok",
            "finite_metric_coverage",
        },
        "primary",
    )
    gate = _require_exact_keys(
        primary["gate"],
        set(_PRIMARY_GATE),
        "primary gate",
    )
    if dict(gate) != _PRIMARY_GATE:
        raise ValueError("primary gate values differ from the frozen contract")
    _require_exact_keys(
        primary["finite_metric_coverage"],
        set(_ROLES),
        "finite metric coverage",
    )
    finite = primary["finite_metric_coverage"]
    if any(not isinstance(finite[role], bool) for role in _ROLES):
        raise ValueError("finite metric coverage values must be booleans")
    if primary["contract_ok"] is not all(finite.values()):
        raise ValueError("primary contract status differs from finite metric coverage")
    if (
        primary["baseline_id"] != "B09-CLASSIC"
        or primary["challenger_id"] != "E09-CONTINUOUS"
        or not isinstance(primary["coverage_ok"], bool)
        or not isinstance(primary["leakage_hits"], int)
    ):
        raise ValueError("primary identities or integrity values drift")
    _validate_stat_schema(primary["public"], "primary public")
    _validate_stat_schema(primary["holdout"], "primary holdout")
    leakage_detail = primary["leakage_detail"]
    if not isinstance(leakage_detail, list) or len(leakage_detail) > 20:
        raise ValueError("leakage detail schema drift")
    for index, hit in enumerate(leakage_detail):
        _require_exact_keys(hit, {"file", "line", "pattern", "text"}, f"leakage hit {index}")
    if primary["leakage_hits"] < len(leakage_detail):
        raise ValueError("leakage hit count is smaller than its persisted detail")
    capacity = _require_exact_keys(
        report["capacity_comparison"],
        {
            "baseline_id",
            "challenger_id",
            "verdict_role",
            "may_affect_primary_verdict",
            "public",
            "holdout",
        },
        "capacity comparison",
    )
    _validate_stat_schema(capacity["public"], "capacity public")
    _validate_stat_schema(capacity["holdout"], "capacity holdout")
    if (
        capacity["baseline_id"] != "B09-CAPACITY"
        or capacity["challenger_id"] != "E09-CONTINUOUS"
    ):
        raise ValueError("capacity comparison identities drift")
    _require_exact_keys(
        report["historical_reference"],
        {"status", "median_nse", "qualifying", "may_affect_verdict"},
        "historical reference",
    )
    if report["historical_reference"]["median_nse"] != 0.759225:
        raise ValueError("historical nonqualifying reference value drift")
    _require_exact_keys(
        report["provenance"],
        {
            "contract_sha256",
            "bundle_sha256",
            "prediction_seal_sha256",
            "prediction_sha256",
            "answer_key_sha256",
            "basin_file_sha256",
            "holdout_draw_receipt_sha256",
            "nonce_sha256",
            "partition_salt_sha256",
            "holdout_set_sha256",
            "authorization_sha256",
            "consumption_file_sha256",
            "consumption_canonical_sha256",
            "trusted_source_tree_sha256",
            "candidate_source_tree_sha256",
            "module_import_paths_sha256",
            "execution_task_id",
        },
        "report provenance",
    )
    ledger = _require_exact_keys(report["ledger"], {"before", "after", "new_row_hash"}, "report ledger")
    snapshot_keys = {"row_count", "sha256", "last_row_hash"}
    _require_exact_keys(ledger["before"], snapshot_keys, "ledger before")
    _require_exact_keys(ledger["after"], snapshot_keys, "ledger after")
    if (
        report["contract_id"] != _EXPERIMENT_ID
        or report["track"] != _TRACK_ID
        or report[_CALL_COUNT_KEY] != 1
        or report["ledger_append_count"] != 1
        or not isinstance(report["reasons"], list)
        or not report["reasons"]
        or any(not isinstance(reason, str) for reason in report["reasons"])
    ):
        raise ValueError("report identity, execution count, or reason schema drift")


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


def _verify_canonical_final_paths(paths: Mapping[str, Path]) -> dict:
    formal_root = REPO_ROOT / "results" / "26_historical_band_experts" / "formal_v09"
    main_repo_root = REPO_ROOT.parents[1]
    expected = {
        "report": formal_root / "clean_pair_score_attempt_01" / "report.json",
        "authorization": (
            formal_root / "authorizations" / "clean_pair_scoring_authorization.json"
        ),
        "consumption": formal_root / "clean_pair_scoring_authorization_consumed.json",
        "holdout_draw": formal_root / "clean_pair_holdout_draw_receipt.json",
        "bundle": formal_root / "predictions" / "clean_pair_bundle.json",
        "basins": (
            main_repo_root
            / "src"
            / "fair_benchmark"
            / "frozen"
            / "track0_forcing_only_basins.txt"
        ),
        "ledger": WORKTREE_SRC / "fair_benchmark" / "registry" / "portfolio_ledger.csv",
    }
    drift = [
        name
        for name, expected_path in expected.items()
        if paths[name].resolve() != expected_path.resolve()
    ]
    if drift:
        raise ValueError(f"noncanonical final-audit path(s): {drift}")
    return {name: str(path.resolve()) for name, path in expected.items()}


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
    require_canonical_module_paths: bool,
) -> dict:
    prediction_hashes = _prediction_hashes(bundle)
    bundle_payload = {key: value for key, value in bundle.items() if key != "bundle_sha256"}
    if (
        bundle.get("bundle_sha256") != _canonical_sha256(bundle_payload)
        or bundle.get("status") != "complete_clean_pair_bundle"
        or bundle.get("contract_id") != _EXPERIMENT_ID
        or bundle.get("track_id") != _TRACK_ID
        or report.get("contract_id") != _EXPERIMENT_ID
        or report.get("track") != _TRACK_ID
    ):
        raise ValueError("bundle self-hash, contract, track, or report identity drift")
    if bundle.get("postseal_holdout") != {
        "method": "postseal_nonce_sha256_rank_v1",
        "status": "awaiting_authorized_nonce_draw",
        "holdout_count": 107,
        "public_count": 424,
    }:
        raise ValueError("bundle post-seal holdout contract drift")
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
    source_files = source_tree.get("files")
    if (
        not isinstance(source_files, Mapping)
        or not source_files
        or source_tree.get("tree_sha256") != _canonical_sha256(source_files)
    ):
        raise ValueError("trusted source tree self-hash drift")
    expected_provenance.update({
        "authorization_sha256": _canonical_sha256(authorization),
        "consumption_file_sha256": consumption_file_sha256,
        "consumption_canonical_sha256": _canonical_sha256(consumption),
        "trusted_source_tree_sha256": source_tree.get("tree_sha256"),
        "candidate_source_tree_sha256": source_bundle.get("tree_sha256"),
    })
    trusted_answer = authorization.get("trusted_frozen_inputs", {}).get("answer_key", {})
    launch_snapshot = consumption.get("launch_snapshot")
    approval = authorization.get("approval")
    if not isinstance(launch_snapshot, Mapping) or not isinstance(approval, Mapping):
        raise ValueError("launch snapshot or approval provenance is missing")
    module_probe = launch_snapshot.get("module_import_probe")
    execution_task_id = launch_snapshot.get("task_id")
    if (
        not isinstance(module_probe, Mapping)
        or not isinstance(execution_task_id, str)
        or not execution_task_id
        or execution_task_id == approval.get("task_id")
    ):
        raise ValueError("independent execution task or module import probe drift")
    if set(module_probe) != {"clean_subprocess", "paths_sha256", "live_process"}:
        raise ValueError("module import probe keys drift")
    clean_paths = module_probe["clean_subprocess"]
    live_paths = module_probe["live_process"]
    if (
        not isinstance(clean_paths, Mapping)
        or not clean_paths
        or clean_paths != live_paths
        or module_probe["paths_sha256"] != _canonical_sha256(clean_paths)
    ):
        raise ValueError("clean-subprocess and live module import paths differ or have a bad hash")
    if require_canonical_module_paths:
        expected_module_paths = {
            relative_path.removesuffix(".py").replace("/", "."): str(
                (WORKTREE_SRC / relative_path).resolve()
            )
            for relative_path in source_files
        }
        if clean_paths != expected_module_paths:
            raise ValueError("module import paths differ from the authorized trusted source files")
    expected_provenance.update({
        "answer_key_sha256": trusted_answer.get("sha256"),
        "module_import_paths_sha256": module_probe.get("paths_sha256"),
        "execution_task_id": execution_task_id,
    })
    if any(provenance.get(key) != value for key, value in expected_provenance.items()):
        raise ValueError("report provenance binding drift")
    authorized_ledger = authorization.get("ledger_snapshot")
    if not isinstance(authorized_ledger, Mapping):
        raise ValueError("authorized ledger snapshot is missing")
    report_before = report.get("ledger", {}).get("before", {})
    if any(
        report_before.get(key) != authorized_ledger.get(key)
        for key in ("row_count", "sha256", "last_row_hash")
    ):
        raise ValueError("report pre-score ledger snapshot differs from the authorization")
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
    *,
    require_canonical_paths: bool = True,
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
        canonical_paths = (
            _verify_canonical_final_paths(paths)
            if require_canonical_paths
            else {"canonical_path_check_skipped": True}
        )
        report = _strict_json(paths["report"])
        authorization = _strict_json(paths["authorization"])
        consumption = _strict_json(paths["consumption"])
        draw = _strict_json(paths["holdout_draw"])
        bundle = _strict_json(paths["bundle"])
        _validate_report_schema(report)
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
            require_canonical_paths,
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
            "canonical_paths": canonical_paths,
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
