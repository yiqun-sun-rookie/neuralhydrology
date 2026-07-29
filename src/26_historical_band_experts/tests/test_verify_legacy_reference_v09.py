from pathlib import Path
import hashlib
import sys

import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def _protocol(config_content: bytes, checkpoint_content: bytes) -> dict:
    return {
        "legacy_reference": {
            "recorded_code_commit_prefix": "1f9804e",
            "runs": [
                {
                    "seed": 100,
                    "run_id": "classic_s100",
                    "config_sha256": _sha256(config_content),
                    "checkpoint_epoch030_sha256": _sha256(checkpoint_content),
                }
            ],
        }
    }


def _write_run(root: Path, config_content: bytes, checkpoint_content: bytes) -> None:
    run_dir = root / "classic_s100"
    run_dir.mkdir(parents=True)
    (run_dir / "config.yml").write_bytes(config_content)
    (run_dir / "model_epoch030.pt").write_bytes(checkpoint_content)


def test_verify_legacy_reference_accepts_exact_files_and_metadata(tmp_path):
    from verify_legacy_reference_v09 import verify_legacy_reference_v09

    config = b"commit_hash: 1f9804e\nseed: 100\n"
    checkpoint = b"synthetic checkpoint"
    _write_run(tmp_path, config, checkpoint)

    report = verify_legacy_reference_v09(_protocol(config, checkpoint), tmp_path)

    assert report == {
        "verified": True,
        "run_count": 1,
        "file_count": 2,
        "seeds": [100],
        "recorded_code_commit_prefix": "1f9804e",
    }


def test_verify_legacy_reference_rejects_checkpoint_hash_drift(tmp_path):
    from verify_legacy_reference_v09 import (
        LegacyReferenceVerificationError,
        verify_legacy_reference_v09,
    )

    config = b"commit_hash: 1f9804e\nseed: 100\n"
    checkpoint = b"synthetic checkpoint"
    _write_run(tmp_path, config, checkpoint + b" drift")

    with pytest.raises(LegacyReferenceVerificationError, match="checkpoint SHA-256"):
        verify_legacy_reference_v09(_protocol(config, checkpoint), tmp_path)


def test_verify_legacy_reference_rejects_semantic_seed_drift_even_with_matching_hash(tmp_path):
    from verify_legacy_reference_v09 import (
        LegacyReferenceVerificationError,
        verify_legacy_reference_v09,
    )

    config = b"commit_hash: 1f9804e\nseed: 999\n"
    checkpoint = b"synthetic checkpoint"
    _write_run(tmp_path, config, checkpoint)

    with pytest.raises(LegacyReferenceVerificationError, match="seed"):
        verify_legacy_reference_v09(_protocol(config, checkpoint), tmp_path)
