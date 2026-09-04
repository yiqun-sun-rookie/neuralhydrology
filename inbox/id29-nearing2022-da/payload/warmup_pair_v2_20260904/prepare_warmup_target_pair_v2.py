"""Prepare one paired warmup-target arm after the complete version-2 replacement gate passes."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any, Iterable


PROTOCOL_SHA256 = "16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1"
AMENDMENT_SHA256 = "a21bae28a26f5797e96232628fdc139f5ffd1e54e31ee2032a7805acb0785ef5"
SUBMISSION_RECEIPT_SHA256 = "18e6aeeee3321427d0f851d68d2cbbfb02f8d13e477f6f96dd5f22eed1d4d2a1"
REPLACEMENT_VERIFIER_SHA256 = "0bcabc96f9e702f2317464f1f0123c29d49d5f7f0f972a10ea3e01bbf18fe987"

FORMAL_RELATIVE = Path("results/29_nearing2022_da_ar/formal_closure")
DIAGNOSTICS_RELATIVE = FORMAL_RELATIVE / "diagnostics"
DATA_AUDIT_RELATIVE = DIAGNOSTICS_RELATIVE / "author_v13_training_data_port_all531_v2"
MASK_AUDIT_RELATIVE = DIAGNOSTICS_RELATIVE / "author_v13_warmup_isolation_all531_v2"
REPLACEMENT_VERIFIER_RELATIVE = Path(
    "src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py"
)
LEGACY_PREPARER_RELATIVE = Path("src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py")


def _sha256_file(path: Path) -> str:
    hasher = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise TypeError(f"Expected a JSON object in {path}")
    return payload


def _require_equal(mapping: dict[str, Any], key: str, expected: Any, label: str) -> None:
    actual = mapping.get(key)
    if actual != expected:
        raise ValueError(f"{label}.{key}: expected {expected!r}, got {actual!r}")


def _require_hash(path: Path, expected: str, label: str) -> None:
    path = Path(path)
    if not path.is_file() or path.is_symlink():
        raise FileNotFoundError(f"Missing regular {label}: {path}")
    actual = _sha256_file(path)
    if actual != expected:
        raise ValueError(f"{label} SHA-256 mismatch: expected {expected}, got {actual}")


def _load_module(path: Path, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _validate_joint_gate(
    verification_dir: Path,
    fresh_artifact_verification: dict[str, Any],
    verifier_sha256: str,
) -> dict[str, Any]:
    verification_dir = Path(verification_dir)
    joint_path = verification_dir / "joint_gate.json"
    scheduler_path = verification_dir / "scheduler_gate.json"
    artifact_1_path = verification_dir / "artifact_verification_1.json"
    artifact_2_path = verification_dir / "artifact_verification_2.json"
    for path in (joint_path, scheduler_path, artifact_1_path, artifact_2_path):
        if not path.is_file() or path.is_symlink():
            raise FileNotFoundError(f"Missing regular replacement-verification artifact: {path}")

    joint = _load_json(joint_path)
    scheduler = _load_json(scheduler_path)
    artifact_1 = _load_json(artifact_1_path)
    artifact_2 = _load_json(artifact_2_path)

    _require_equal(joint, "schema", "nearing2022-warmup-target-replacement-joint-gate-v1", "joint")
    _require_equal(joint, "joint_entry_gate_passed", True, "joint")
    _require_equal(joint, "artifact_reproduction_byte_identical", True, "joint")
    _require_equal(joint, "replacement_job_ids", ["202510", "202511"], "joint")
    _require_equal(joint, "pair_runner_adaptation_permitted", True, "joint")
    _require_equal(joint, "pair_training_submission_permitted", False, "joint")
    _require_equal(joint, "registered_matrix_modified", False, "joint")
    _require_equal(joint, "verifier_sha256", verifier_sha256, "joint")
    _require_equal(joint, "scheduler_gate_sha256", _sha256_file(scheduler_path), "joint")
    _require_equal(joint, "artifact_verification_sha256", _sha256_file(artifact_1_path), "joint")

    _require_equal(
        scheduler,
        "schema",
        "nearing2022-warmup-target-replacement-scheduler-gate-v1",
        "scheduler",
    )
    _require_equal(scheduler, "scheduler_gate_passed", True, "scheduler")
    _require_equal(scheduler, "required_submission_dependency", "afterok:202511", "scheduler")
    _require_equal(scheduler, "registered_matrix_modified", False, "scheduler")
    jobs = scheduler.get("jobs")
    if not isinstance(jobs, list) or [row.get("job_id") for row in jobs] != ["202510", "202511"]:
        raise ValueError(f"scheduler.jobs: unexpected replacement jobs {jobs!r}")
    for row in jobs:
        _require_equal(row, "state", "COMPLETED", f"scheduler.jobs[{row.get('job_id')}]")
        _require_equal(row, "exit_code", "0:0", f"scheduler.jobs[{row.get('job_id')}]")

    if artifact_1 != artifact_2:
        raise ValueError("The two published replacement artifact verifications are not identical")
    if artifact_1 != fresh_artifact_verification:
        raise ValueError("Fresh replacement-chain verification differs from the published joint-gate input")
    _require_equal(artifact_1, "entry_artifact_gate_passed", True, "artifact")
    _require_equal(artifact_1, "scheduler_gate_checked", False, "artifact")
    _require_equal(artifact_1, "registered_matrix_modified", False, "artifact")
    _require_equal(artifact_1, "data_job_id", "202510", "artifact")
    _require_equal(artifact_1, "mask_job_id", "202511", "artifact")
    _require_equal(artifact_1, "basins", 531, "artifact")
    _require_equal(artifact_1, "current_finite_author_missing_targets", 193284, "artifact")
    _require_equal(artifact_1, "direct_common_raw_target_maximum_difference", 0.0, "artifact")
    _require_equal(artifact_1, "single_mask_exact_restoration", True, "artifact")

    return {
        "schema": "nearing2022-warmup-target-pair-entry-gates-v2",
        "joint_gate_sha256": _sha256_file(joint_path),
        "scheduler_gate_sha256": _sha256_file(scheduler_path),
        "artifact_verification_sha256": _sha256_file(artifact_1_path),
        "verification_job_id": joint.get("verification_job_id"),
        "replacement_job_ids": ["202510", "202511"],
        "basins": 531,
        "current_finite_author_missing_targets": 193284,
        "author_finite_current_missing_targets": 0,
        "direct_common_raw_target_maximum_difference": 0.0,
        "direct_common_raw_targets_bitwise_identical": True,
        "single_mask_exact_restoration": True,
        "registered_matrix_modified": False,
    }


def validate_entry_gates(
    repo_root: Path,
    protocol_path: Path,
    amendment_path: Path,
    submission_receipt_path: Path,
    data_audit_dir: Path,
    mask_audit_dir: Path,
    replacement_verification_dir: Path,
) -> dict[str, Any]:
    """Validate the immutable G01-G10 artifact and scheduler prerequisites without preparing an arm."""
    repo_root = Path(repo_root).resolve()
    protocol_path = Path(protocol_path).resolve()
    amendment_path = Path(amendment_path).resolve()
    submission_receipt_path = Path(submission_receipt_path).resolve()
    data_audit_dir = Path(data_audit_dir).resolve()
    mask_audit_dir = Path(mask_audit_dir).resolve()
    replacement_verification_dir = Path(replacement_verification_dir).resolve()

    _require_hash(protocol_path, PROTOCOL_SHA256, "paired protocol")
    _require_hash(amendment_path, AMENDMENT_SHA256, "protocol amendment")
    _require_hash(submission_receipt_path, SUBMISSION_RECEIPT_SHA256, "replacement submission receipt")
    expected_data = (repo_root / DATA_AUDIT_RELATIVE).resolve()
    expected_mask = (repo_root / MASK_AUDIT_RELATIVE).resolve()
    if data_audit_dir != expected_data:
        raise ValueError(f"Data audit directory must be {expected_data}, got {data_audit_dir}")
    if mask_audit_dir != expected_mask:
        raise ValueError(f"Mask audit directory must be {expected_mask}, got {mask_audit_dir}")

    verifier_path = (repo_root / REPLACEMENT_VERIFIER_RELATIVE).resolve()
    _require_hash(verifier_path, REPLACEMENT_VERIFIER_SHA256, "replacement-chain verifier")
    verifier = _load_module(verifier_path, "nearing2022_replacement_verifier_for_pair_v2")
    fresh = verifier.verify_replacement_chain(repo_root)
    gates = _validate_joint_gate(replacement_verification_dir, fresh, REPLACEMENT_VERIFIER_SHA256)
    gates.update({
        "protocol_sha256": PROTOCOL_SHA256,
        "amendment_sha256": AMENDMENT_SHA256,
        "replacement_submission_receipt_sha256": SUBMISSION_RECEIPT_SHA256,
        "replacement_verifier_sha256": REPLACEMENT_VERIFIER_SHA256,
        "data_audit_dir": str(data_audit_dir),
        "mask_audit_dir": str(mask_audit_dir),
    })
    return gates


def prepare_arm(repo_root: Path, protocol_path: Path, arm: str, work_root: Path) -> dict[str, Any]:
    """Reuse the frozen arm constructor without invoking its obsolete version-1 entry gate."""
    legacy_path = Path(repo_root).resolve() / LEGACY_PREPARER_RELATIVE
    legacy = _load_module(legacy_path, "nearing2022_legacy_pair_constructor_for_v2")
    return legacy.prepare_arm(repo_root, protocol_path, arm, work_root)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--amendment", type=Path, required=True)
    parser.add_argument("--submission-receipt", type=Path, required=True)
    parser.add_argument("--data-audit-dir", type=Path, required=True)
    parser.add_argument("--mask-audit-dir", type=Path, required=True)
    parser.add_argument("--replacement-verification-dir", type=Path, required=True)
    parser.add_argument("--arm", choices=("control", "masked"), required=True)
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.receipt.exists():
        raise FileExistsError(f"Refusing to overwrite preparation receipt: {args.receipt}")
    gates = validate_entry_gates(
        args.repo_root,
        args.protocol,
        args.amendment,
        args.submission_receipt,
        args.data_audit_dir,
        args.mask_audit_dir,
        args.replacement_verification_dir,
    )
    prepared = prepare_arm(args.repo_root, args.protocol, args.arm, args.work_root)
    prepared["schema"] = "nearing2022-warmup-target-prepared-arm-v2"
    prepared["entry_gates"] = gates
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(
        json.dumps(prepared, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(json.dumps(prepared, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
