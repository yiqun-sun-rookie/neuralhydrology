import hashlib
import json
import os
import shutil
from pathlib import Path

import pytest


def _write_checkpoint_request(
    staging_root: Path,
    *,
    checkpoint_id: str = "checkpoint-0001",
    candidate_id: str = "candidate-001",
    mode: str = "train",
    payload: bytes = b"model-state",
    recorded_digest: str | None = None,
) -> dict:
    staging_root.mkdir(parents=True, exist_ok=True)
    (staging_root / "model.bin").write_bytes(payload)
    request = {
        "schema_version": "checkpoint_request_v1",
        "checkpoint_id": checkpoint_id,
        "candidate_id": candidate_id,
        "mode": mode,
        "parent_checkpoint_id": None,
        "files": {
            "model.bin": recorded_digest or hashlib.sha256(payload).hexdigest(),
        },
    }
    (staging_root / "CHECKPOINT_REQUEST.json").write_text(
        json.dumps(request, sort_keys=True), encoding="utf-8"
    )
    return request


def test_checkpoint_promotion_rejects_missing_request_without_publishing(tmp_path):
    from unified_autoresearch.runtime.checkpoints import promote_staged_checkpoint

    staging = tmp_path / "checkpoint_staging"
    staging.mkdir()
    (staging / "model.bin").write_bytes(b"partial")
    checkpoints = tmp_path / "checkpoints"
    checkpoints.mkdir()

    with pytest.raises(ValueError, match="checkpoint request is missing"):
        promote_staged_checkpoint(staging, checkpoints)

    assert staging.is_dir()
    assert list(checkpoints.iterdir()) == []


def test_checkpoint_promotion_rejects_hash_mismatch_without_publishing(tmp_path):
    from unified_autoresearch.runtime.checkpoints import promote_staged_checkpoint

    staging = tmp_path / "checkpoint_staging"
    _write_checkpoint_request(staging, recorded_digest="0" * 64)
    checkpoints = tmp_path / "checkpoints"
    checkpoints.mkdir()

    with pytest.raises(ValueError, match="checkpoint payload hash mismatch"):
        promote_staged_checkpoint(staging, checkpoints)

    assert staging.is_dir()
    assert list(checkpoints.iterdir()) == []


def test_checkpoint_promotion_is_atomic_nonoverwriting_and_verifiable(tmp_path):
    from unified_autoresearch.runtime.checkpoints import promote_staged_checkpoint, verify_checkpoint

    staging = tmp_path / "checkpoint_staging"
    request = _write_checkpoint_request(staging)
    checkpoints = tmp_path / "checkpoints"
    checkpoints.mkdir()

    record = promote_staged_checkpoint(staging, checkpoints)

    assert record.checkpoint_id == request["checkpoint_id"]
    assert record.path == checkpoints / request["checkpoint_id"]
    assert not staging.exists()
    assert (record.path / "CHECKPOINT_REQUEST.json").is_file()
    assert (record.path / "CHECKPOINT_VERIFIED.json").is_file()
    assert verify_checkpoint(record.path, expected_candidate_id="candidate-001") == record

    _write_checkpoint_request(staging)
    with pytest.raises(FileExistsError, match="checkpoint version already exists"):
        promote_staged_checkpoint(staging, checkpoints)
    assert verify_checkpoint(record.path, expected_candidate_id="candidate-001") == record


def test_checkpoint_promotion_preserves_every_immutable_version(tmp_path):
    from unified_autoresearch.runtime.checkpoints import promote_staged_checkpoint, verify_checkpoint

    staging = tmp_path / "checkpoint_staging"
    checkpoints = tmp_path / "checkpoints"
    checkpoints.mkdir()
    records = []

    for index in range(1, 4):
        checkpoint_id = f"checkpoint-{index:04d}"
        _write_checkpoint_request(
            staging,
            checkpoint_id=checkpoint_id,
            payload=f"model-state-{index}".encode("ascii"),
        )
        records.append(promote_staged_checkpoint(staging, checkpoints))

    assert sorted(path.name for path in checkpoints.iterdir()) == [
        "checkpoint-0001",
        "checkpoint-0002",
        "checkpoint-0003",
    ]
    for record in records:
        assert verify_checkpoint(record.path, expected_candidate_id="candidate-001") == record


@pytest.mark.skipif(os.name != "nt", reason="Windows extended-length paths are Windows-specific")
def test_checkpoint_verification_and_mount_support_paths_at_the_legacy_260_character_limit(tmp_path):
    from unified_autoresearch.runtime.checkpoints import (
        mount_verified_checkpoint,
        promote_staged_checkpoint,
        verify_checkpoint,
    )

    staging = tmp_path / "short-staging"
    checkpoints = tmp_path / "short-checkpoints"
    checkpoints.mkdir()
    _write_checkpoint_request(staging)
    published = promote_staged_checkpoint(staging, checkpoints)

    suffix = Path("checkpoint-0001") / "CHECKPOINT_VERIFIED.json"
    filler_length = 260 - len(str(tmp_path)) - 2 - len(str(suffix))
    assert filler_length > 0
    deep_parent = tmp_path / ("x" * filler_length)
    deep_checkpoint = deep_parent / "checkpoint-0001"
    os.makedirs("\\\\?\\" + str(deep_parent.resolve()))
    shutil.copytree(
        "\\\\?\\" + str(published.path.resolve()),
        "\\\\?\\" + str(deep_checkpoint.resolve()),
    )
    assert len(str(deep_checkpoint / "CHECKPOINT_VERIFIED.json")) == 260

    verified = verify_checkpoint(deep_checkpoint, expected_candidate_id="candidate-001")
    assert verified.root_sha256 == published.root_sha256

    resume_run = tmp_path / ("r" * filler_length)
    os.makedirs("\\\\?\\" + str(resume_run.resolve()))
    mounted = mount_verified_checkpoint(
        resume_run,
        deep_checkpoint,
        expected_candidate_id="candidate-001",
    )
    assert mounted.root_sha256 == published.root_sha256


def test_controlled_stop_request_is_exclusive_and_auditable(tmp_path):
    from unified_autoresearch.runtime.control import request_controlled_stop

    control_root = tmp_path / "control"
    control_root.mkdir()

    path = request_controlled_stop(control_root, request_id="stop-0001", reason="resource safety check")

    value = json.loads(path.read_text(encoding="utf-8"))
    assert value["schema_version"] == "controlled_stop_request_v1"
    assert value["request_id"] == "stop-0001"
    assert value["reason"] == "resource safety check"
    assert value["created_at_utc"].endswith("+00:00")
    original = path.read_bytes()
    with pytest.raises(FileExistsError):
        request_controlled_stop(control_root, request_id="stop-0002", reason="must not overwrite")
    assert path.read_bytes() == original
