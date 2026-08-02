import json
from pathlib import Path
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _prerequisites(scope: str) -> dict[str, str]:
    keys = [
        "input_seal",
        "input_artifact_external_audit",
        "trusted_target_external_audit",
        "legacy_checkpoint_bridge_external_audit",
        "training_resource_preflight_external_audit",
    ]
    if scope == "FORMAL-MAIN-24":
        keys.extend([
            "strict_nesting_run_seal",
            "strict_nesting_external_audit",
            "state_diagnostics_preregistration",
        ])
    return {key: str(index + 1) * 64 for index, key in enumerate(keys)}


def test_strict_receipt_requires_exact_scope_text_and_single_run(tmp_path):
    from stage_authorization_v09 import (
        STRICT_NESTING_APPROVAL_TEXT,
        create_stage_authorization_v09,
    )

    receipt = create_stage_authorization_v09(
        approval_text=STRICT_NESTING_APPROVAL_TEXT,
        scope="R09-NEST-S100",
        protocol_sha256="a" * 64,
        prerequisite_sha256=_prerequisites("R09-NEST-S100"),
        executable_tree_sha256="b" * 64,
        git_commit="c" * 40,
        worktree_root=tmp_path,
        output_root="results/26_historical_band_experts/formal_v09/strict_nesting/seed_100",
        created_utc="2026-08-02T00:00:00Z",
    )

    assert receipt["allowed_runs"] == ["R09-NEST-S100"]
    assert receipt["maximum_attempts"] == 1
    assert receipt["formal_prediction_generation_authorized"] is False
    assert receipt["official_scoring_authorized"] is False


def test_main_receipt_rejects_missing_or_extra_prerequisite_keys(tmp_path):
    from stage_authorization_v09 import (
        MAIN_TRAINING_APPROVAL_TEXT,
        create_stage_authorization_v09,
    )

    prerequisites = _prerequisites("FORMAL-MAIN-24")
    prerequisites.pop("strict_nesting_external_audit")
    with pytest.raises(ValueError, match="prerequisite"):
        create_stage_authorization_v09(
            approval_text=MAIN_TRAINING_APPROVAL_TEXT,
            scope="FORMAL-MAIN-24",
            protocol_sha256="a" * 64,
            prerequisite_sha256=prerequisites,
            executable_tree_sha256="b" * 64,
            git_commit="c" * 40,
            worktree_root=tmp_path,
            output_root="results/26_historical_band_experts/formal_v09",
            created_utc="2026-08-02T00:00:00Z",
        )


def test_validation_rejects_protocol_tree_output_and_receipt_tampering(tmp_path):
    from stage_authorization_v09 import (
        STRICT_NESTING_APPROVAL_TEXT,
        create_stage_authorization_v09,
        validate_stage_authorization_v09,
    )

    prerequisites = _prerequisites("R09-NEST-S100")
    receipt = create_stage_authorization_v09(
        approval_text=STRICT_NESTING_APPROVAL_TEXT,
        scope="R09-NEST-S100",
        protocol_sha256="a" * 64,
        prerequisite_sha256=prerequisites,
        executable_tree_sha256="b" * 64,
        git_commit="c" * 40,
        worktree_root=tmp_path,
        output_root="results/26_historical_band_experts/formal_v09/strict_nesting/seed_100",
        created_utc="2026-08-02T00:00:00Z",
    )
    validate_stage_authorization_v09(
        receipt,
        action="training",
        scope="R09-NEST-S100",
        protocol_sha256="a" * 64,
        prerequisite_sha256=prerequisites,
        executable_tree_sha256="b" * 64,
        worktree_root=tmp_path,
        output_root="results/26_historical_band_experts/formal_v09/strict_nesting/seed_100",
    )

    for field, value in (
        ("protocol_sha256", "d" * 64),
        ("executable_tree_sha256", "e" * 64),
        ("output_root", "elsewhere"),
        ("maximum_attempts", 2),
    ):
        drift = dict(receipt)
        drift[field] = value
        with pytest.raises(ValueError):
            validate_stage_authorization_v09(
                drift,
                action="training",
                scope="R09-NEST-S100",
                protocol_sha256="a" * 64,
                prerequisite_sha256=prerequisites,
                executable_tree_sha256="b" * 64,
                worktree_root=tmp_path,
                output_root="results/26_historical_band_experts/formal_v09/strict_nesting/seed_100",
            )


def test_consumption_is_exclusive_and_cannot_be_replayed(tmp_path):
    from stage_authorization_v09 import (
        STRICT_NESTING_APPROVAL_TEXT,
        consume_stage_authorization_v09,
        create_stage_authorization_v09,
        stage_authorization_paths_v09,
    )

    prerequisites = _prerequisites("R09-NEST-S100")
    receipt = create_stage_authorization_v09(
        approval_text=STRICT_NESTING_APPROVAL_TEXT,
        scope="R09-NEST-S100",
        protocol_sha256="a" * 64,
        prerequisite_sha256=prerequisites,
        executable_tree_sha256="b" * 64,
        git_commit="c" * 40,
        worktree_root=tmp_path,
        output_root="results/26_historical_band_experts/formal_v09/strict_nesting/seed_100",
        created_utc="2026-08-02T00:00:00Z",
    )
    authorization_path, consumed_path = stage_authorization_paths_v09("R09-NEST-S100", worktree_root=tmp_path)
    authorization_path.parent.mkdir(parents=True)
    authorization_path.write_text(json.dumps(receipt), encoding="utf-8")

    consumed = consume_stage_authorization_v09(
        authorization_path,
        receipt=receipt,
        worktree_root=tmp_path,
        process_id=123,
        hostname="test-host",
        consumed_utc="2026-08-02T01:00:00Z",
        memory_snapshot={"available_bytes": 10},
    )
    assert consumed["status"] == "consumed_once"
    with pytest.raises(FileExistsError):
        consume_stage_authorization_v09(
            authorization_path,
            receipt=receipt,
            worktree_root=tmp_path,
            process_id=124,
            hostname="test-host",
            consumed_utc="2026-08-02T02:00:00Z",
            memory_snapshot={"available_bytes": 10},
        )

    copied = tmp_path / "copied-authorization.json"
    copied.write_text(json.dumps(receipt), encoding="utf-8")
    with pytest.raises(ValueError, match="canonical path"):
        consume_stage_authorization_v09(
            copied,
            receipt=receipt,
            worktree_root=tmp_path,
            process_id=125,
            hostname="test-host",
            consumed_utc="2026-08-02T03:00:00Z",
            memory_snapshot={"available_bytes": 10},
        )


def test_stage_authorization_paths_reject_reparse_directory_before_resolve(tmp_path, monkeypatch):
    import artifact_v09
    from stage_authorization_v09 import stage_authorization_paths_v09

    authorization_directory = (
        tmp_path / "results/26_historical_band_experts/formal_v09/authorizations")
    authorization_directory.mkdir(parents=True)
    original = artifact_v09.is_reparse_point
    monkeypatch.setattr(
        artifact_v09,
        "is_reparse_point",
        lambda path: Path(path) == authorization_directory or original(path),
    )
    with pytest.raises(ValueError, match="reparse point"):
        stage_authorization_paths_v09("R09-NEST-S100", worktree_root=tmp_path)
