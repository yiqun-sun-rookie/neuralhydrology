"""Exact one-use authorization receipts for formal version-09 execution stages."""
from __future__ import annotations

from collections.abc import Mapping
import hashlib
import json
from pathlib import Path

from artifact_v09 import canonical_sha256, sha256_file

STRICT_NESTING_APPROVAL_TEXT = ("批准版本09严格嵌套训练阶段；仅授权R09-NEST种子100的一次531流域30轮训练，"
                                "不批准主实验训练、正式预测或评分。")
MAIN_TRAINING_APPROVAL_TEXT = ("批准版本09正式主训练阶段；仅授权B09-CLASSIC、B09-CAPACITY和E09-CONTINUOUS"
                               "各八个固定随机数的一次训练，并授权训练完成后的预注册状态诊断和独立重放审核；"
                               "不批准正式预测或评分。")

_STRICT_PREREQUISITES = (
    "input_seal",
    "input_artifact_external_audit",
    "trusted_target_external_audit",
    "legacy_checkpoint_bridge_external_audit",
    "training_resource_preflight_external_audit",
)
_MAIN_PREREQUISITES = (
    *_STRICT_PREREQUISITES,
    "strict_nesting_run_seal",
    "strict_nesting_external_audit",
    "state_diagnostics_preregistration",
)
_MAIN_ORDER = (
    (100, "B09-CLASSIC"),
    (100, "B09-CAPACITY"),
    (100, "E09-CONTINUOUS"),
    (200, "B09-CLASSIC"),
    (200, "E09-CONTINUOUS"),
    (200, "B09-CAPACITY"),
    (300, "B09-CAPACITY"),
    (300, "B09-CLASSIC"),
    (300, "E09-CONTINUOUS"),
    (400, "B09-CAPACITY"),
    (400, "E09-CONTINUOUS"),
    (400, "B09-CLASSIC"),
    (500, "E09-CONTINUOUS"),
    (500, "B09-CLASSIC"),
    (500, "B09-CAPACITY"),
    (600, "E09-CONTINUOUS"),
    (600, "B09-CAPACITY"),
    (600, "B09-CLASSIC"),
    (700, "B09-CLASSIC"),
    (700, "B09-CAPACITY"),
    (700, "E09-CONTINUOUS"),
    (800, "B09-CAPACITY"),
    (800, "E09-CONTINUOUS"),
    (800, "B09-CLASSIC"),
)
MAIN_ALLOWED_RUNS = tuple(f"{family}-S{seed}" for seed, family in _MAIN_ORDER)

_SCOPE_SPECS = {
    "R09-NEST-S100": {
        "receipt_id": "A09-NEST-01",
        "approval_text": STRICT_NESTING_APPROVAL_TEXT,
        "prerequisites": _STRICT_PREREQUISITES,
        "allowed_runs": ("R09-NEST-S100",),
    },
    "FORMAL-MAIN-24": {
        "receipt_id": "A09-TRAIN-01",
        "approval_text": MAIN_TRAINING_APPROVAL_TEXT,
        "prerequisites": _MAIN_PREREQUISITES,
        "allowed_runs": MAIN_ALLOWED_RUNS,
    },
}
_AUTHORIZATION_DIRECTORY = Path("results/26_historical_band_experts/formal_v09/authorizations")


def _require_sha256(value: object, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64:
        raise ValueError(f"{label} must be a 64-character SHA-256")
    try:
        int(value, 16)
    except ValueError as exc:
        raise ValueError(f"{label} must be hexadecimal") from exc
    return value.lower()


def _validated_prerequisites(scope: str, values: Mapping) -> dict[str, str]:
    if not isinstance(values, Mapping):
        raise ValueError("prerequisite SHA-256 values must be an object")
    expected = _SCOPE_SPECS[scope]["prerequisites"]
    if tuple(values) != expected:
        raise ValueError(f"prerequisite key set or order drift for {scope}")
    return {key: _require_sha256(values[key], f"prerequisite {key}") for key in expected}


def _resolved_output_root(worktree_root: str | Path, output_root: str | Path) -> str:
    worktree = Path(worktree_root).resolve()
    output = Path(output_root)
    if not output.is_absolute():
        output = worktree / output
    output = output.resolve()
    if output == worktree or worktree not in output.parents:
        raise ValueError("stage authorization output root must be inside the bound worktree")
    return str(output)


def create_stage_authorization_v09(
    *,
    approval_text: str,
    scope: str,
    protocol_sha256: str,
    prerequisite_sha256: Mapping,
    executable_tree_sha256: str,
    git_commit: str,
    worktree_root: str | Path,
    output_root: str,
    created_utc: str,
) -> dict:
    """Create but do not consume one exact formal training-stage receipt."""
    if scope not in _SCOPE_SPECS:
        raise ValueError(f"unsupported formal stage scope: {scope}")
    spec = _SCOPE_SPECS[scope]
    if approval_text != spec["approval_text"]:
        raise ValueError("stage authorization requires the exact direct approval text")
    if not isinstance(git_commit, str) or len(git_commit) != 40:
        raise ValueError("stage authorization requires a full Git commit")
    if not isinstance(output_root, str) or not output_root:
        raise ValueError("stage authorization output root is required")
    resolved_worktree = str(Path(worktree_root).resolve())
    resolved_output = _resolved_output_root(worktree_root, output_root)
    if not isinstance(created_utc, str) or not created_utc:
        raise ValueError("stage authorization creation time is required")
    prerequisites = _validated_prerequisites(scope, prerequisite_sha256)
    return {
        "schema": "historical_multiscale_formal_v09_stage_authorization_v1",
        "status": "authorized_once",
        "receipt_id": spec["receipt_id"],
        "action": "training",
        "scope": scope,
        "maximum_attempts": 1,
        "allowed_runs": list(spec["allowed_runs"]),
        "protocol_sha256": _require_sha256(protocol_sha256, "protocol SHA-256"),
        "prerequisite_sha256": prerequisites,
        "executable_tree_sha256": _require_sha256(executable_tree_sha256, "executable tree SHA-256"),
        "git_commit": git_commit.lower(),
        "worktree_root": resolved_worktree,
        "output_root": resolved_output,
        "approval": {
            "text": approval_text,
            "sha256": hashlib.sha256(approval_text.encode("utf-8")).hexdigest(),
        },
        "created_utc": created_utc,
        "formal_prediction_generation_authorized": False,
        "official_scoring_authorized": False,
    }


def stage_authorization_paths_v09(
    scope: str,
    *,
    worktree_root: str | Path,
) -> tuple[Path, Path]:
    """Return the only legal authorization and consumption paths for one scope."""
    if scope not in _SCOPE_SPECS:
        raise ValueError(f"unsupported formal stage scope: {scope}")
    root = Path(worktree_root).resolve()
    receipt_id = _SCOPE_SPECS[scope]["receipt_id"]
    directory = root / _AUTHORIZATION_DIRECTORY
    return (
        directory / f"{receipt_id}.authorization.json",
        directory / f"{receipt_id}.consumption.json",
    )


def validate_stage_authorization_v09(
    receipt: Mapping,
    *,
    action: str,
    scope: str,
    protocol_sha256: str,
    prerequisite_sha256: Mapping,
    executable_tree_sha256: str,
    worktree_root: str | Path,
    output_root: str,
) -> dict:
    """Reject any receipt field, prerequisite, or executable binding drift."""
    if not isinstance(receipt, Mapping) or scope not in _SCOPE_SPECS:
        raise ValueError("stage authorization receipt or scope is invalid")
    if action != "training":
        raise ValueError("formal training receipts cannot authorize another action")
    spec = _SCOPE_SPECS[scope]
    expected_keys = {
        "schema",
        "status",
        "receipt_id",
        "action",
        "scope",
        "maximum_attempts",
        "allowed_runs",
        "protocol_sha256",
        "prerequisite_sha256",
        "executable_tree_sha256",
        "git_commit",
        "worktree_root",
        "output_root",
        "approval",
        "created_utc",
        "formal_prediction_generation_authorized",
        "official_scoring_authorized",
    }
    if set(receipt) != expected_keys:
        raise ValueError("stage authorization receipt schema drift")
    prerequisites = _validated_prerequisites(scope, prerequisite_sha256)
    approval_text = spec["approval_text"]
    approval = receipt.get("approval")
    fixed = {
        "schema": "historical_multiscale_formal_v09_stage_authorization_v1",
        "status": "authorized_once",
        "receipt_id": spec["receipt_id"],
        "action": "training",
        "scope": scope,
        "maximum_attempts": 1,
        "allowed_runs": list(spec["allowed_runs"]),
        "protocol_sha256": _require_sha256(protocol_sha256, "protocol SHA-256"),
        "prerequisite_sha256": prerequisites,
        "executable_tree_sha256": _require_sha256(executable_tree_sha256, "executable tree SHA-256"),
        "worktree_root": str(Path(worktree_root).resolve()),
        "output_root": _resolved_output_root(worktree_root, output_root),
        "approval": {
            "text": approval_text,
            "sha256": hashlib.sha256(approval_text.encode("utf-8")).hexdigest(),
        },
        "formal_prediction_generation_authorized": False,
        "official_scoring_authorized": False,
    }
    for key, value in fixed.items():
        if receipt.get(key) != value:
            raise ValueError(f"stage authorization field drift: {key}")
    if not isinstance(receipt.get("git_commit"), str) or len(receipt["git_commit"]) != 40:
        raise ValueError("stage authorization Git commit drift")
    if not isinstance(receipt.get("created_utc"), str) or not receipt["created_utc"]:
        raise ValueError("stage authorization creation time drift")
    if not isinstance(approval, Mapping):
        raise ValueError("stage authorization approval drift")
    return dict(receipt)


def consume_stage_authorization_v09(
    authorization_path: str | Path,
    *,
    receipt: Mapping,
    worktree_root: str | Path,
    process_id: int,
    hostname: str,
    consumed_utc: str,
    memory_snapshot: Mapping,
) -> dict:
    """Exclusively consume a validated receipt immediately before execution."""
    authorization_path = Path(authorization_path).resolve()
    expected_authorization, consumption_path = stage_authorization_paths_v09(
        receipt.get("scope"),
        worktree_root=worktree_root,
    )
    if authorization_path != expected_authorization.resolve():
        raise ValueError("stage authorization file is outside its canonical path")
    if receipt.get("worktree_root") != str(Path(worktree_root).resolve()):
        raise ValueError("stage authorization worktree binding drift")
    recorded = json.loads(authorization_path.read_text(encoding="utf-8"))
    if recorded != dict(receipt):
        raise ValueError("stage authorization file differs from the validated receipt")
    result = {
        "schema": "historical_multiscale_formal_v09_stage_authorization_consumption_v1",
        "status": "consumed_once",
        "receipt_id": receipt["receipt_id"],
        "scope": receipt["scope"],
        "authorization_file_sha256": sha256_file(authorization_path),
        "authorization_canonical_sha256": canonical_sha256(receipt),
        "protocol_sha256": receipt["protocol_sha256"],
        "prerequisite_sha256": dict(receipt["prerequisite_sha256"]),
        "executable_tree_sha256": receipt["executable_tree_sha256"],
        "git_commit": receipt["git_commit"],
        "output_root": receipt["output_root"],
        "process_id": int(process_id),
        "hostname": str(hostname),
        "consumed_utc": str(consumed_utc),
        "memory_snapshot": dict(memory_snapshot),
    }
    consumption_path.parent.mkdir(parents=True, exist_ok=True)
    with consumption_path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(result, handle, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False)
        handle.write("\n")
    return result
