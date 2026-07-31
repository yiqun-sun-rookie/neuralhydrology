"""Trusted one-call scoring core for the formal version-09 clean comparison."""
from __future__ import annotations

import argparse
from collections.abc import Mapping
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import sys

import numpy as np
import psutil

from .clean_pair_authorization_v09 import (
    clean_pair_ledger_snapshot_v09,
    consume_clean_pair_score_authorization_v09,
    draw_holdout_nonce_once_v09,
    trusted_source_tree_v09,
    validate_clean_pair_score_authorization_v09,
)
from .clean_pair_contract_v09 import load_clean_pair_contract_v09
from .gate import GateConfig
from .io import load_obs_csv, load_predictions
from .leakage import DEFAULT_FORBIDDEN, scan_for_forbidden_access
from .ledger import count_attempts, read_rows
from .metrics import nse, per_basin_score
from .postseal_holdout_v09 import derive_postseal_holdout_v09
from .score import score_submission
from .stats import paired_comparison
from .tracks import Track


class CleanPairScoreError(RuntimeError):
    """Raised before or after the one permitted scorer call when a binding drifts."""


_ROLES = ("baseline", "capacity_control", "challenger")
_EXPERIMENT_ID = "S09C-CLEAN-PAIR"
_TRACK_ID = "track0_forcing_only_clean_v09"
_BASIN_COUNT = 531
_HOLDOUT_COUNT = 107
_PUBLIC_COUNT = 424
CLEAN_PAIR_FORBIDDEN_PATTERNS = list(DEFAULT_FORBIDDEN) + [
    r"track0_forcing_only_baseline_per_basin_nse",
    r"track0_forcing_only_secret_holdout_basins",
    r"portfolio_ledger",
    r"fair_benchmark[/\\]experiments[/\\].*report\.json",
]


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


def _safe_child(root: Path, relative_path: object, name: str) -> Path:
    if not isinstance(relative_path, str):
        raise CleanPairScoreError(f"{name} relative path is invalid")
    relative = Path(relative_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise CleanPairScoreError(f"{name} must be a safe relative path")
    resolved_root = root.resolve()
    resolved = (root / relative).resolve()
    if not resolved.is_relative_to(resolved_root):
        raise CleanPairScoreError(f"{name} escapes its trusted root")
    return resolved


def _require_file_hash(path: Path, expected: object, name: str) -> str:
    if not path.is_file():
        raise CleanPairScoreError(f"{name} is missing")
    actual = _sha256(path)
    if actual != expected:
        raise CleanPairScoreError(f"{name} SHA-256 drift")
    return actual


def _prediction_hashes(bundle: Mapping, prediction_root: Path) -> tuple[dict, dict]:
    predictions = bundle.get("predictions")
    if not isinstance(predictions, Mapping) or tuple(predictions) != _ROLES:
        raise CleanPairScoreError("prediction roles or order drift")
    hashes = {}
    paths = {}
    for role in _ROLES:
        record = predictions[role]
        if not isinstance(record, Mapping):
            raise CleanPairScoreError(f"{role} prediction declaration is invalid")
        path = _safe_child(prediction_root, record.get("relative_path"), f"{role} prediction")
        hashes[role] = _require_file_hash(path, record.get("sha256"), f"{role} prediction")
        paths[role] = path
    return hashes, paths


def _load_basin_ids(path: Path) -> list[str]:
    basin_ids = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(basin_ids) != _BASIN_COUNT or len(set(basin_ids)) != _BASIN_COUNT:
        raise CleanPairScoreError("trusted basin list must contain exactly 531 unique identifiers")
    return basin_ids


def _validate_receipt_before_answer(
    contract: Mapping,
    bundle: Mapping,
    receipt: Mapping,
    basin_ids: list[str],
    prediction_sha256: Mapping[str, str],
) -> dict:
    if receipt.get("status") != "complete_single_holdout_draw":
        raise CleanPairScoreError("holdout draw receipt is incomplete")
    if (
        receipt.get("contract_sha256") != bundle.get("contract_sha256")
        or receipt.get("bundle_sha256") != bundle.get("bundle_sha256")
        or receipt.get("nonce_draw_count") != 1
        or receipt.get("nonce_redraw_count") != 0
    ):
        raise CleanPairScoreError("holdout draw contract, bundle, or draw-count binding drift")
    if receipt.get("prediction_sha256") != dict(prediction_sha256):
        raise CleanPairScoreError("holdout draw prediction binding drift")
    partition = derive_postseal_holdout_v09(
        basin_ids,
        protocol_sha256=contract["protocol_sha256"],
        prediction_sha256=prediction_sha256,
        nonce_hex=receipt.get("nonce_hex"),
        holdout_count=_HOLDOUT_COUNT,
    )
    expected = {
        "method": bundle["postseal_holdout"]["method"],
        "holdout_count": bundle["postseal_holdout"]["holdout_count"],
        "public_count": bundle["postseal_holdout"]["public_count"],
        "nonce_sha256": receipt.get("nonce_sha256"),
        "partition_salt_sha256": receipt.get("partition_salt_sha256"),
        "holdout_set_sha256": receipt.get("holdout_set_sha256"),
    }
    actual = {
        "method": partition["method"],
        "holdout_count": partition["holdout_count"],
        "public_count": partition["public_count"],
        "nonce_sha256": partition["nonce_sha256"],
        "partition_salt_sha256": partition["partition_salt_sha256"],
        "holdout_set_sha256": partition["holdout_set_sha256"],
    }
    if actual != expected:
        raise CleanPairScoreError("holdout draw receipt or derived holdout summary drift")
    return partition


def _require_complete_finite_scores(scores: Mapping, basin_ids: list[str], name: str) -> bool:
    return set(scores) == set(basin_ids) and all(math.isfinite(float(scores[basin])) for basin in basin_ids)


def _comparison(
    challenger: Mapping[str, float],
    baseline: Mapping[str, float],
    basin_ids: list[str],
    *,
    bootstrap_samples: int,
    bootstrap_seed: int,
) -> dict:
    return paired_comparison(
        {basin: challenger[basin] for basin in basin_ids},
        {basin: baseline[basin] for basin in basin_ids},
        n_bootstrap=bootstrap_samples,
        seed=bootstrap_seed,
    )


def _stats_match(first: Mapping, second: Mapping) -> bool:
    if set(first) != set(second):
        return False
    for key in first:
        left = first[key]
        right = second[key]
        if isinstance(left, (float, np.floating)) or isinstance(right, (float, np.floating)):
            if math.isnan(float(left)) and math.isnan(float(right)):
                continue
            if float(left) != float(right):
                return False
        elif left != right:
            return False
    return True


def _strict_stats(stats: Mapping) -> dict:
    result = dict(stats)
    for key, value in tuple(result.items()):
        if not isinstance(value, (float, np.floating)) or math.isfinite(float(value)):
            continue
        if key == "wilcoxon_p" and float(result.get("median_paired_delta", float("nan"))) == 0.0:
            result[key] = None
            result["wilcoxon_p_reason"] = "all_paired_differences_zero"
            continue
        raise CleanPairScoreError(f"non-finite aggregate statistic is not permitted: {key}")
    return result


def _ledger_snapshot(path: Path) -> dict:
    rows = read_rows(path)
    return {
        "row_count": len(rows),
        "sha256": _sha256(path) if path.is_file() else None,
        "last_row_hash": rows[-1].get("row_hash") if rows else None,
    }


def _validate_contract_and_bundle(contract: Mapping, bundle: Mapping) -> None:
    if contract.get("contract_id") != _EXPERIMENT_ID or bundle.get("contract_id") != _EXPERIMENT_ID:
        raise CleanPairScoreError("clean-pair contract identity drift")
    if contract.get("track_id") != _TRACK_ID or bundle.get("track_id") != _TRACK_ID:
        raise CleanPairScoreError("clean-pair track identity drift")
    if tuple(contract.get("roles", {})) != _ROLES:
        raise CleanPairScoreError("clean-pair roles or order drift")
    if bundle.get("contract_sha256") != _canonical_sha256(contract):
        raise CleanPairScoreError("contract-to-bundle hash drift")
    if bundle.get("bundle_sha256") != _canonical_sha256({
        key: value for key, value in bundle.items() if key != "bundle_sha256"
    }):
        raise CleanPairScoreError("clean-pair bundle self-hash drift")
    if bundle.get("status") != "complete_clean_pair_bundle":
        raise CleanPairScoreError("clean-pair bundle is incomplete")
    postseal = bundle.get("postseal_holdout")
    if postseal != {
        "method": "postseal_nonce_sha256_rank_v1",
        "status": "awaiting_authorized_nonce_draw",
        "holdout_count": _HOLDOUT_COUNT,
        "public_count": _PUBLIC_COUNT,
    }:
        raise CleanPairScoreError("post-seal holdout bundle contract drift")


def score_clean_pair_core_v09(
    *,
    contract: Mapping,
    bundle: Mapping,
    holdout_draw_receipt: Mapping,
    trusted_frozen_root: str | Path,
    prediction_root: str | Path,
    source_bundle: str | Path,
    ledger_path: str | Path,
    timestamp: str,
) -> dict:
    """Perform the one permitted existing-scorer call for a sealed clean comparison."""
    _validate_contract_and_bundle(contract, bundle)
    trusted_frozen_root = Path(trusted_frozen_root)
    prediction_root = Path(prediction_root)
    source_bundle = Path(source_bundle)
    ledger_path = Path(ledger_path)
    if not source_bundle.is_dir():
        raise CleanPairScoreError("candidate source bundle is missing")
    if any(row.get("experiment_id") == _EXPERIMENT_ID for row in read_rows(ledger_path)):
        raise CleanPairScoreError("clean-pair experiment already exists in the ledger")

    prediction_sha256, prediction_paths = _prediction_hashes(bundle, prediction_root)
    trusted = contract.get("trusted_frozen_inputs")
    if not isinstance(trusted, Mapping):
        raise CleanPairScoreError("trusted frozen input contract is missing")
    basin_path = _safe_child(
        trusted_frozen_root,
        trusted.get("basins", {}).get("relative_path"),
        "trusted basin list",
    )
    answer_path = _safe_child(
        trusted_frozen_root,
        trusted.get("answer_key", {}).get("relative_path"),
        "trusted answer key",
    )
    basin_sha256 = _require_file_hash(
        basin_path,
        trusted.get("basins", {}).get("sha256"),
        "trusted basin list",
    )
    answer_sha256 = _require_file_hash(
        answer_path,
        trusted.get("answer_key", {}).get("sha256"),
        "trusted answer key",
    )
    basin_ids = _load_basin_ids(basin_path)
    partition = _validate_receipt_before_answer(
        contract,
        bundle,
        holdout_draw_receipt,
        basin_ids,
        prediction_sha256,
    )

    obs = load_obs_csv(answer_path)
    if set(obs) != set(basin_ids):
        raise CleanPairScoreError("trusted answer key basin coverage drift")
    simulations = {}
    scores = {}
    for role in _ROLES:
        simulations[role] = load_predictions(prediction_paths[role])
        if set(simulations[role]) != set(basin_ids):
            raise CleanPairScoreError(f"{role} prediction basin coverage drift")
        scores[role] = per_basin_score(obs, simulations[role], nse)
        del simulations[role]

    finite_status = {
        role: _require_complete_finite_scores(scores[role], basin_ids, role) for role in _ROLES
    }
    contract_ok = all(finite_status.values())
    public_ids = [basin for basin in basin_ids if basin not in partition["holdout_ids"]]
    holdout_ids = [basin for basin in basin_ids if basin in partition["holdout_ids"]]
    if len(public_ids) != _PUBLIC_COUNT or len(holdout_ids) != _HOLDOUT_COUNT:
        raise CleanPairScoreError("derived public or holdout count drift")

    gate = contract["primary_gate"]
    comparison_kwargs = {
        "bootstrap_samples": int(gate["bootstrap_samples"]),
        "bootstrap_seed": int(gate["bootstrap_seed"]),
    }
    expected_public = _comparison(
        scores["challenger"],
        scores["baseline"],
        public_ids,
        **comparison_kwargs,
    )
    expected_holdout = _comparison(
        scores["challenger"],
        scores["baseline"],
        holdout_ids,
        **comparison_kwargs,
    )
    capacity_public = _comparison(
        scores["challenger"],
        scores["capacity_control"],
        public_ids,
        **comparison_kwargs,
    )
    capacity_holdout = _comparison(
        scores["challenger"],
        scores["capacity_control"],
        holdout_ids,
        **comparison_kwargs,
    )

    track = Track(
        name=_TRACK_ID,
        baseline_nse=scores["baseline"],
        obs=obs,
        secret_holdout=partition["holdout_ids"],
        gate_cfg=GateConfig(
            min_effect=float(gate["min_effect"]),
            max_wilcoxon_p=float(gate["max_wilcoxon_p"]),
            holdout_min_effect=float(gate["holdout_min_effect"]),
            holdout_retention=float(gate["holdout_retention"]),
        ),
        allow_observed_q=False,
        forbidden_patterns=CLEAN_PAIR_FORBIDDEN_PATTERNS,
        metric=nse,
        spec={"confirmed": True, "contract_id": _EXPERIMENT_ID},
    )
    ledger_before = _ledger_snapshot(ledger_path)
    primary = score_submission(
        predictions_path=prediction_paths["challenger"],
        track=track,
        ledger_path=ledger_path,
        experiment_id=_EXPERIMENT_ID,
        timestamp=timestamp,
        contract_ok=contract_ok,
        coverage_min_ratio=0.99,
        experiment_dir=source_bundle,
    )
    ledger_after = _ledger_snapshot(ledger_path)
    if ledger_after["row_count"] != ledger_before["row_count"] + 1:
        raise CleanPairScoreError("the clean-pair scorer did not append exactly one ledger row")
    if not _stats_match(primary["public"], expected_public):
        raise CleanPairScoreError("existing scorer public statistics drift from the precomputed comparison")
    if not _stats_match(primary["holdout"], expected_holdout):
        raise CleanPairScoreError("existing scorer holdout statistics drift from the precomputed comparison")

    report = {
        "contract_id": _EXPERIMENT_ID,
        "track": _TRACK_ID,
        "verdict": primary["verdict"],
        "reasons": list(primary["reasons"]),
        "primary": {
            "baseline_id": contract["roles"]["baseline"],
            "challenger_id": contract["roles"]["challenger"],
            "gate": dict(gate),
            "public": _strict_stats(expected_public),
            "holdout": _strict_stats(expected_holdout),
            "coverage_ok": bool(primary["coverage_ok"]),
            "leakage_hits": int(primary["leakage_hits"]),
            "leakage_detail": list(primary["leakage_detail"]),
            "contract_ok": contract_ok,
            "finite_metric_coverage": finite_status,
        },
        "capacity_comparison": {
            "baseline_id": contract["roles"]["capacity_control"],
            "challenger_id": contract["roles"]["challenger"],
            "verdict_role": "descriptive_only",
            "may_affect_primary_verdict": False,
            "public": _strict_stats(capacity_public),
            "holdout": _strict_stats(capacity_holdout),
        },
        "historical_reference": {
            "status": "historical_reference_nonqualifying",
            "median_nse": 0.759225,
            "qualifying": False,
            "may_affect_verdict": False,
        },
        "provenance": {
            "contract_sha256": bundle["contract_sha256"],
            "bundle_sha256": bundle["bundle_sha256"],
            "prediction_seal_sha256": bundle["prediction_seal_sha256"],
            "prediction_sha256": prediction_sha256,
            "answer_key_sha256": answer_sha256,
            "basin_file_sha256": basin_sha256,
            "holdout_draw_receipt_sha256": _canonical_sha256(holdout_draw_receipt),
            "nonce_sha256": partition["nonce_sha256"],
            "partition_salt_sha256": partition["partition_salt_sha256"],
            "holdout_set_sha256": partition["holdout_set_sha256"],
        },
        "ledger": {
            "before": ledger_before,
            "after": ledger_after,
            "new_row_hash": ledger_after["last_row_hash"],
        },
        "score_submission_call_count": 1,
        "ledger_append_count": 1,
    }
    json.dumps(report, allow_nan=False, sort_keys=True)
    return report


def _strict_json_load(path: Path) -> dict:
    def reject_constant(value: str):
        raise CleanPairScoreError(f"non-finite JSON constant is forbidden: {value}")

    try:
        value = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise CleanPairScoreError(f"unable to load strict JSON from {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise CleanPairScoreError(f"JSON root must be an object: {path}")
    return value


def _source_bundle_tree_sha256(root: Path) -> str:
    if not root.is_dir():
        raise CleanPairScoreError("candidate source bundle is missing")
    files = {
        path.relative_to(root).as_posix(): _sha256(path)
        for path in sorted(root.rglob("*"), key=lambda item: item.as_posix())
        if path.is_file()
    }
    if not files:
        raise CleanPairScoreError("candidate source bundle is empty")
    return _canonical_sha256(files)


def _assert_score_start_memory_safe() -> dict:
    memory = psutil.virtual_memory()
    required = max(12 * 2**30, math.ceil(0.40 * int(memory.total)))
    if int(memory.available) < required:
        raise CleanPairScoreError(
            f"available physical memory below scoring threshold: {memory.available} < {required}"
        )
    return {
        "total_bytes": int(memory.total),
        "available_bytes": int(memory.available),
        "required_available_bytes": required,
    }


def _exclusive_atomic_report(path: Path, report: Mapping) -> None:
    if path.exists():
        raise CleanPairScoreError(f"score report already exists: {path}")
    building = path.with_suffix(path.suffix + ".building")
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with building.open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(
                report,
                handle,
                ensure_ascii=False,
                sort_keys=True,
                indent=2,
                allow_nan=False,
            )
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        if path.exists():
            raise CleanPairScoreError(f"score report appeared during exclusive write: {path}")
        os.replace(building, path)
    except FileExistsError as exc:
        raise CleanPairScoreError(f"score report building file already exists: {building}") from exc


def run_clean_pair_score_once_v09(
    *,
    contract_path: str | Path,
    bundle_path: str | Path,
    authorization_path: str | Path,
    prediction_root: str | Path,
    source_bundle: str | Path,
    trusted_frozen_root: str | Path,
    ledger_path: str | Path,
    consumption_path: str | Path,
    holdout_draw_receipt_path: str | Path,
    out_path: str | Path,
    execution_task_id: str,
    timestamp: str | None = None,
) -> dict:
    """Validate, consume, draw, score, and persist exactly one non-retryable attempt."""
    worktree_src = Path(__file__).resolve().parents[1]
    expected_pythonpath = str(worktree_src)
    if os.environ.get("PYTHONPATH") != expected_pythonpath:
        raise CleanPairScoreError("PYTHONPATH must equal the single resolved worktree src path")
    if not execution_task_id.strip():
        raise CleanPairScoreError("an independent execution task identity is required")

    contract_path = Path(contract_path)
    bundle_path = Path(bundle_path)
    authorization_path = Path(authorization_path)
    prediction_root = Path(prediction_root)
    source_bundle = Path(source_bundle)
    trusted_frozen_root = Path(trusted_frozen_root).resolve()
    ledger_path = Path(ledger_path)
    consumption_path = Path(consumption_path)
    draw_path = Path(holdout_draw_receipt_path)
    out_path = Path(out_path)
    for output in (consumption_path, draw_path, out_path, out_path.with_suffix(out_path.suffix + ".building")):
        if output.exists():
            raise CleanPairScoreError(f"one-attempt output already exists: {output}")

    protocol_path = contract_path.parent / "formal_v09_protocol.json"
    contract = load_clean_pair_contract_v09(contract_path, protocol_path=protocol_path)
    bundle = _strict_json_load(bundle_path)
    authorization = _strict_json_load(authorization_path)
    _validate_contract_and_bundle(contract, bundle)

    source_tree = trusted_source_tree_v09(worktree_src)
    ledger_snapshot = clean_pair_ledger_snapshot_v09(ledger_path)
    validated_authorization = validate_clean_pair_score_authorization_v09(
        authorization,
        contract=contract,
        bundle=bundle,
        source_tree=source_tree,
        ledger_snapshot=ledger_snapshot,
    )
    runtime = {
        "python_executable": str(Path(sys.executable).resolve()),
        "worktree_src": expected_pythonpath,
        "pythonpath": expected_pythonpath,
    }
    if validated_authorization["runtime"] != runtime:
        raise CleanPairScoreError("live Python runtime differs from the authorized runtime")
    if Path(validated_authorization["trusted_frozen_root"]).resolve() != trusted_frozen_root:
        raise CleanPairScoreError("live trusted frozen root differs from the authorization")
    if validated_authorization["approval"]["task_id"] == execution_task_id:
        raise CleanPairScoreError("the scoring executor task must differ from the approval task")

    memory = _assert_score_start_memory_safe()
    prediction_sha256, _ = _prediction_hashes(bundle, prediction_root)
    if prediction_sha256 != validated_authorization["prediction_sha256"]:
        raise CleanPairScoreError("live prediction hashes differ from the authorization")
    source_tree_sha256 = _source_bundle_tree_sha256(source_bundle)
    if source_tree_sha256 != bundle.get("source_bundle", {}).get("tree_sha256"):
        raise CleanPairScoreError("candidate source bundle tree drift before authorization consumption")
    hits = scan_for_forbidden_access(source_bundle, CLEAN_PAIR_FORBIDDEN_PATTERNS)
    if hits:
        raise CleanPairScoreError(f"candidate source bundle has {len(hits)} forbidden-access hit(s)")

    trusted = contract["trusted_frozen_inputs"]
    basin_path = _safe_child(trusted_frozen_root, trusted["basins"]["relative_path"], "trusted basin list")
    _require_file_hash(basin_path, trusted["basins"]["sha256"], "trusted basin list")
    basin_ids = _load_basin_ids(basin_path)
    answer_path = _safe_child(trusted_frozen_root, trusted["answer_key"]["relative_path"], "trusted answer key")
    _require_file_hash(answer_path, trusted["answer_key"]["sha256"], "trusted answer key")
    if clean_pair_ledger_snapshot_v09(ledger_path) != ledger_snapshot:
        raise CleanPairScoreError("ledger changed before authorization consumption")

    timestamp = timestamp or datetime.now(timezone.utc).isoformat()
    launch_snapshot = {
        "timestamp": timestamp,
        "task_id": execution_task_id,
        "runtime": runtime,
        "memory": memory,
        "source_tree": source_tree,
        "ledger_snapshot": ledger_snapshot,
    }
    consumption = consume_clean_pair_score_authorization_v09(
        validated_authorization,
        consumption_path,
        launch_snapshot,
    )
    draw_receipt = draw_holdout_nonce_once_v09(
        consumption_path,
        draw_path,
        contract=contract,
        bundle=bundle,
        basin_ids=basin_ids,
    )
    if clean_pair_ledger_snapshot_v09(ledger_path) != ledger_snapshot:
        raise CleanPairScoreError("ledger changed after the nonce draw; attempt is consumed without retry")

    report = score_clean_pair_core_v09(
        contract=contract,
        bundle=bundle,
        holdout_draw_receipt=draw_receipt,
        trusted_frozen_root=trusted_frozen_root,
        prediction_root=prediction_root,
        source_bundle=source_bundle,
        ledger_path=ledger_path,
        timestamp=timestamp,
    )
    report["provenance"].update({
        "authorization_sha256": _canonical_sha256(validated_authorization),
        "consumption_file_sha256": _sha256(consumption_path),
        "consumption_canonical_sha256": _canonical_sha256(consumption),
        "trusted_source_tree_sha256": source_tree["tree_sha256"],
        "candidate_source_tree_sha256": source_tree_sha256,
        "execution_task_id": execution_task_id,
    })
    json.dumps(report, allow_nan=False, sort_keys=True)
    _exclusive_atomic_report(out_path, report)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--authorization", required=True)
    parser.add_argument("--prediction-root", required=True)
    parser.add_argument("--source-bundle", required=True)
    parser.add_argument("--trusted-frozen-root", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--consumption", required=True)
    parser.add_argument("--holdout-draw-receipt", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--execution-task-id", required=True)
    args = parser.parse_args(argv)
    report = run_clean_pair_score_once_v09(
        contract_path=args.contract,
        bundle_path=args.bundle,
        authorization_path=args.authorization,
        prediction_root=args.prediction_root,
        source_bundle=args.source_bundle,
        trusted_frozen_root=args.trusted_frozen_root,
        ledger_path=args.ledger,
        consumption_path=args.consumption,
        holdout_draw_receipt_path=args.holdout_draw_receipt,
        out_path=args.out,
        execution_task_id=args.execution_task_id,
    )
    print(json.dumps(report, sort_keys=True, ensure_ascii=False, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
