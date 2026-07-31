"""Exact authorization, exclusive consumption, and one post-seal nonce draw."""
from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
import hashlib
import json
import os
from pathlib import Path
import re
import secrets

from .postseal_holdout_v09 import derive_postseal_holdout_v09, public_partition_summary


class CleanPairAuthorizationError(RuntimeError):
    """Raised when a scoring authorization is inexact, stale, or already consumed."""


_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_ROLES = ("baseline", "capacity_control", "challenger")
_EXPERIMENT_ID = "S09C-CLEAN-PAIR"
_TRACK_ID = "track0_forcing_only_clean_v09"
_OUTPUT_ROOT = "results/26_historical_band_experts/formal_v09/clean_pair_score_attempt_01"
_RECEIPT_KEYS = {
    "status",
    "approval",
    "contract_sha256",
    "bundle_sha256",
    "prediction_sha256",
    "prediction_seal_sha256",
    "upstream_evidence",
    "selection_provenance",
    "final_checkpoints",
    "source_tree",
    "runtime",
    "trusted_frozen_inputs",
    "trusted_frozen_root",
    "postseal_holdout",
    "legacy_nonqualifying_inputs",
    "ledger_snapshot",
    "allowed_experiment_id",
    "allowed_track_id",
    "output_root",
    "maximum_attempts",
}
_FORBIDDEN_PREAUTH_KEYS = {
    "nonce_hex",
    "nonce_sha256",
    "partition_salt_sha256",
    "holdout_set_sha256",
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


def _require_hex64(value: object, name: str) -> str:
    if not isinstance(value, str) or _HEX64.fullmatch(value) is None:
        raise CleanPairAuthorizationError(f"{name} must be 64 lowercase hexadecimal characters")
    return value


def _contains_forbidden_key(value: object) -> bool:
    if isinstance(value, Mapping):
        if set(value) & _FORBIDDEN_PREAUTH_KEYS:
            return True
        return any(_contains_forbidden_key(item) for item in value.values())
    if isinstance(value, list):
        return any(_contains_forbidden_key(item) for item in value)
    return False


def render_clean_pair_score_approval_text(bundle_sha256: str) -> str:
    """Render the only acceptable user approval for one exact bundle."""
    bundle_sha256 = _require_hex64(bundle_sha256, "bundle_sha256")
    return (
        "批准版本09清洁同信息配对正式评分；仅授权评分包SHA-256="
        f"{bundle_sha256}"
        "在S09C-CLEAN-PAIR中消费一次授权、抽取一次256位留出随机数并调用评分一次；"
        "不批准重抽、重试或其他评分。"
    )


def _expected_prediction_hashes(bundle: Mapping) -> dict:
    predictions = bundle.get("predictions")
    if not isinstance(predictions, Mapping) or tuple(predictions) != _ROLES:
        raise CleanPairAuthorizationError("bundle prediction roles or order drift")
    hashes = {}
    for role in _ROLES:
        record = predictions[role]
        if not isinstance(record, Mapping):
            raise CleanPairAuthorizationError(f"{role} prediction declaration is invalid")
        hashes[role] = _require_hex64(record.get("sha256"), f"{role} prediction SHA-256")
    return hashes


def _expected_postseal(contract: Mapping, bundle: Mapping) -> dict:
    source = contract.get("postseal_holdout")
    sealed = bundle.get("postseal_holdout")
    if not isinstance(source, Mapping) or not isinstance(sealed, Mapping):
        raise CleanPairAuthorizationError("post-seal holdout binding is missing")
    expected = {
        "method": "postseal_nonce_sha256_rank_v1",
        "nonce_source": "python_secrets_token_bytes_32_after_authorization_consumption",
        "nonce_draws": 1,
        "nonce_redraws": 0,
        "holdout_count": 107,
        "public_count": 424,
    }
    if any(source.get(key) != value for key, value in expected.items()):
        raise CleanPairAuthorizationError("contract post-seal holdout drift")
    if sealed != {
        "method": expected["method"],
        "status": "awaiting_authorized_nonce_draw",
        "holdout_count": expected["holdout_count"],
        "public_count": expected["public_count"],
    }:
        raise CleanPairAuthorizationError("bundle post-seal holdout drift")
    return expected


def _validate_runtime(runtime: object) -> None:
    if not isinstance(runtime, Mapping) or set(runtime) != {
        "python_executable",
        "worktree_src",
        "pythonpath",
    }:
        raise CleanPairAuthorizationError("runtime binding keys drift")
    if runtime["pythonpath"] != runtime["worktree_src"]:
        raise CleanPairAuthorizationError("PYTHONPATH must equal the single worktree src path")
    for key in ("python_executable", "worktree_src", "pythonpath"):
        if not Path(runtime[key]).is_absolute():
            raise CleanPairAuthorizationError(f"runtime {key} must be absolute")


def validate_clean_pair_score_authorization_v09(
    receipt: Mapping,
    *,
    contract: Mapping,
    bundle: Mapping,
    source_tree: Mapping,
    ledger_snapshot: Mapping,
) -> dict:
    """Validate an exact one-attempt receipt without drawing a nonce or scoring."""
    if not isinstance(receipt, Mapping) or set(receipt) != _RECEIPT_KEYS:
        raise CleanPairAuthorizationError("authorization receipt keys drift")
    if receipt.get("status") != "authorized_clean_pair_score":
        raise CleanPairAuthorizationError("authorization status drift")
    if _contains_forbidden_key(receipt):
        raise CleanPairAuthorizationError("authorization must not contain post-draw material")
    if receipt.get("contract_sha256") != bundle.get("contract_sha256"):
        raise CleanPairAuthorizationError("contract SHA-256 binding drift")
    if receipt.get("bundle_sha256") != bundle.get("bundle_sha256"):
        raise CleanPairAuthorizationError("bundle SHA-256 binding drift")
    expected_prediction = _expected_prediction_hashes(bundle)
    if receipt.get("prediction_sha256") != expected_prediction:
        raise CleanPairAuthorizationError("prediction SHA-256 binding drift")
    if receipt.get("prediction_seal_sha256") != bundle.get("prediction_seal_sha256"):
        raise CleanPairAuthorizationError("prediction seal binding drift")
    if receipt.get("upstream_evidence") != bundle.get("upstream_evidence"):
        raise CleanPairAuthorizationError("upstream evidence binding drift")
    if receipt.get("selection_provenance") != contract.get("selection_provenance"):
        raise CleanPairAuthorizationError("selection provenance binding drift")
    if receipt.get("final_checkpoints") != bundle.get("final_checkpoints"):
        raise CleanPairAuthorizationError("final checkpoint binding drift")
    if receipt.get("source_tree") != source_tree:
        raise CleanPairAuthorizationError("source tree binding drift")
    if receipt.get("ledger_snapshot") != ledger_snapshot:
        raise CleanPairAuthorizationError("ledger snapshot binding drift")
    if ledger_snapshot.get("experiment_id_count") != 0 or ledger_snapshot.get("chain_breaks") != 0:
        raise CleanPairAuthorizationError("ledger already contains the attempt or has a broken chain")
    _validate_runtime(receipt.get("runtime"))
    if receipt.get("trusted_frozen_inputs") != contract.get("trusted_frozen_inputs"):
        raise CleanPairAuthorizationError("trusted frozen input binding drift")
    trusted_root = receipt.get("trusted_frozen_root")
    if not isinstance(trusted_root, str) or not Path(trusted_root).is_absolute():
        raise CleanPairAuthorizationError("trusted frozen root must be absolute")
    if receipt.get("postseal_holdout") != _expected_postseal(contract, bundle):
        raise CleanPairAuthorizationError("post-seal holdout authorization drift")
    if receipt.get("legacy_nonqualifying_inputs") != contract.get("legacy_nonqualifying_inputs"):
        raise CleanPairAuthorizationError("legacy nonqualifying snapshot drift")
    if receipt.get("allowed_experiment_id") != _EXPERIMENT_ID:
        raise CleanPairAuthorizationError("allowed experiment identity drift")
    if receipt.get("allowed_track_id") != _TRACK_ID:
        raise CleanPairAuthorizationError("allowed track identity drift")
    if receipt.get("output_root") != _OUTPUT_ROOT:
        raise CleanPairAuthorizationError("authorized output root drift")
    if receipt.get("maximum_attempts") != 1:
        raise CleanPairAuthorizationError("maximum attempts must be one")

    approval = receipt.get("approval")
    if not isinstance(approval, Mapping) or set(approval) != {
        "text",
        "utf8_sha256",
        "task_id",
        "approved_at",
    }:
        raise CleanPairAuthorizationError("approval provenance keys drift")
    expected_text = render_clean_pair_score_approval_text(bundle["bundle_sha256"])
    if approval.get("text") != expected_text:
        raise CleanPairAuthorizationError("approval text is not exact")
    if approval.get("utf8_sha256") != hashlib.sha256(expected_text.encode("utf-8")).hexdigest():
        raise CleanPairAuthorizationError("approval text SHA-256 drift")
    if not approval.get("task_id") or not approval.get("approved_at"):
        raise CleanPairAuthorizationError("approval task identity and timestamp are required")
    return json.loads(json.dumps(receipt))


def _exclusive_json_write(path: Path, payload: Mapping) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(
                payload,
                handle,
                ensure_ascii=False,
                sort_keys=True,
                indent=2,
                allow_nan=False,
            )
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
    except FileExistsError as exc:
        raise CleanPairAuthorizationError(f"exclusive output already exists: {path}") from exc
    return json.loads(json.dumps(payload))


def consume_clean_pair_score_authorization_v09(
    receipt: Mapping,
    consumption_path: str | Path,
    launch_snapshot: Mapping,
) -> dict:
    """Consume one validated receipt using an exclusive, non-retryable file."""
    if not isinstance(receipt, Mapping) or receipt.get("maximum_attempts") != 1:
        raise CleanPairAuthorizationError("receipt does not authorize exactly one attempt")
    if not isinstance(launch_snapshot, Mapping):
        raise CleanPairAuthorizationError("launch snapshot must be an object")
    payload = {
        "status": "consumed_no_retry",
        "authorization_sha256": _canonical_sha256(receipt),
        "approval_utf8_sha256": receipt.get("approval", {}).get("utf8_sha256"),
        "allowed_experiment_id": receipt.get("allowed_experiment_id"),
        "maximum_attempts": 1,
        "retry_allowed": False,
        "launch_snapshot": dict(launch_snapshot),
    }
    return _exclusive_json_write(Path(consumption_path), payload)


def _read_consumption(path: Path) -> dict:
    if not path.is_file():
        raise CleanPairAuthorizationError("authorization consumption receipt is missing")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CleanPairAuthorizationError("authorization consumption receipt is invalid") from exc
    if (
        payload.get("status") != "consumed_no_retry"
        or payload.get("maximum_attempts") != 1
        or payload.get("retry_allowed") is not False
    ):
        raise CleanPairAuthorizationError("authorization consumption receipt drift")
    return payload


def draw_holdout_nonce_once_v09(
    consumption_path: str | Path,
    draw_receipt_path: str | Path,
    *,
    contract: Mapping,
    bundle: Mapping,
    basin_ids: Sequence[str],
    random_bytes: Callable[[int], bytes] = secrets.token_bytes,
) -> dict:
    """Reserve the draw receipt, draw exactly 32 bytes, and persist the split once."""
    consumption_path = Path(consumption_path)
    draw_receipt_path = Path(draw_receipt_path)
    consumption = _read_consumption(consumption_path)
    prediction_sha256 = _expected_prediction_hashes(bundle)
    _expected_postseal(contract, bundle)
    draw_receipt_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        handle = draw_receipt_path.open("x", encoding="utf-8", newline="\n")
    except FileExistsError as exc:
        raise CleanPairAuthorizationError(
            f"exclusive holdout draw receipt already exists: {draw_receipt_path}"
        ) from exc

    try:
        nonce = random_bytes(32)
        if not isinstance(nonce, bytes) or len(nonce) != 32:
            raise CleanPairAuthorizationError("random source must return exactly 32 bytes")
        partition = derive_postseal_holdout_v09(
            basin_ids,
            protocol_sha256=contract["protocol_sha256"],
            prediction_sha256=prediction_sha256,
            nonce_hex=nonce.hex(),
            holdout_count=107,
        )
        payload = {
            "status": "complete_single_holdout_draw",
            "consumption_file_sha256": _sha256_file(consumption_path),
            "consumption_canonical_sha256": _canonical_sha256(consumption),
            "contract_sha256": bundle["contract_sha256"],
            "bundle_sha256": bundle["bundle_sha256"],
            "prediction_sha256": prediction_sha256,
            "nonce_hex": nonce.hex(),
            **public_partition_summary(partition),
            "nonce_draw_count": 1,
            "nonce_redraw_count": 0,
        }
        json.dump(
            payload,
            handle,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
            allow_nan=False,
        )
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    finally:
        handle.close()
    return json.loads(json.dumps(payload))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
