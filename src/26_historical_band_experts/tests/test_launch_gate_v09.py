import json
from pathlib import Path
import subprocess
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG = IDEA_ROOT / "configs/formal_v09_protocol.json"
sys.path.insert(0, str(IDEA_ROOT))

GIB = 2**30


def _config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def _estimate(estimated_peak_bytes: int, method: str) -> dict:
    from memory_safety_v09 import build_peak_estimate_v09

    if method == "analytical_chunk_working_set_v1":
        assert estimated_peak_bytes % (8 * 256) == 0
        evidence_fields = {
            "formula": "chunk_rows * seed_count * 256",
            "chunk_rows": estimated_peak_bytes // (8 * 256),
            "seed_count": 8,
            "bytes_per_seed_row_upper_bound": 256,
        }
    else:
        evidence_fields = {"test_vector": True}
    return build_peak_estimate_v09(
        method=method,
        estimated_peak_bytes=estimated_peak_bytes,
        evidence_fields=evidence_fields,
    )


def test_v09_launch_gate_allows_only_safe_lightweight_synthetic_tests():
    from launch_gate_v09 import assert_launch_allowed_v09
    from memory_safety_v09 import HostMemorySnapshot

    snapshot = HostMemorySnapshot(32 * GIB, 10 * GIB, 256 * 2**20, 20 * GIB)
    report = assert_launch_allowed_v09(
        _config(),
        action="synthetic_test",
        peak_estimate=_estimate(512 * 2**20, "synthetic_bound_v1"),
        snapshot=snapshot,
    )

    assert report["status"] == "launch_allowed"
    assert report["action"] == "synthetic_test"
    assert report["memory"]["long_running"] is False


@pytest.mark.parametrize(
    "action",
    (
        "formal_target_bundle_generation",
        "training",
        "formal_prediction_generation",
        "official_scoring",
    ),
)
def test_v09_launch_gate_refuses_every_unapproved_formal_action(action):
    from launch_gate_v09 import LaunchAuthorizationError, assert_launch_allowed_v09
    from memory_safety_v09 import HostMemorySnapshot

    snapshot = HostMemorySnapshot(32 * GIB, 24 * GIB, 256 * 2**20, 40 * GIB)
    with pytest.raises(LaunchAuthorizationError, match="not authorized"):
        assert_launch_allowed_v09(
            _config(),
            action=action,
            peak_estimate=_estimate(1 * GIB, "analytical_chunk_working_set_v1"),
            snapshot=snapshot,
        )


def test_v09_dynamic_gate_allows_ten_gib_when_analytical_peak_and_reserves_fit(tmp_path):
    from launch_gate_v09 import assert_launch_allowed_v09
    from memory_safety_v09 import HostMemorySnapshot, exclusive_high_load_lease_v09

    config = _config()
    config["authorization"]["training"] = True
    snapshot = HostMemorySnapshot(32 * GIB, 10 * GIB, 256 * 2**20, 20 * GIB)

    with exclusive_high_load_lease_v09(lock_path=tmp_path / "v09.lock") as lease:
        with pytest.raises(ValueError, match="authorization"):
            assert_launch_allowed_v09(
                config,
                action="training",
                peak_estimate=_estimate(2 * GIB, "analytical_chunk_working_set_v1"),
                snapshot=snapshot,
                lease=lease,
            )

    config["authorization"]["training"] = False
    from memory_safety_v09 import MemorySafetyGate

    with exclusive_high_load_lease_v09(lock_path=tmp_path / "v09.lock") as lease:
        report = MemorySafetyGate.from_snapshot(snapshot).assert_start_safe(
            snapshot,
            _estimate(2 * GIB, "analytical_chunk_working_set_v1"),
            long_running=True,
            lease=lease,
        )
    assert report["safe"] is True
    assert report["available_after_guarded_peak_bytes"] == int(7.5 * GIB)


def test_launch_gate_direct_cli_help_is_importable():
    completed = subprocess.run(
        [sys.executable, str(IDEA_ROOT / "launch_gate_v09.py"), "--help"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )

    assert completed.returncode == 0
    assert "--peak-estimate-evidence" in completed.stdout
    assert "--variant" in completed.stdout


def test_formal_action_methods_are_registered_but_authorization_stays_closed():
    from formal_action_resources_v09 import build_formal_action_peak_estimate_v09
    from launch_gate_v09 import LaunchAuthorizationError, assert_launch_allowed_v09
    from memory_safety_v09 import HostMemorySnapshot

    config = _config()
    estimate = build_formal_action_peak_estimate_v09(
        config,
        "formal_target_bundle_generation",
    )
    snapshot = HostMemorySnapshot(32 * GIB, 24 * GIB, 256 * 2**20, 40 * GIB)

    with pytest.raises(LaunchAuthorizationError, match="not authorized"):
        assert_launch_allowed_v09(
            config,
            action="formal_target_bundle_generation",
            peak_estimate=estimate,
            snapshot=snapshot,
        )


def test_training_launch_accepts_only_a_fully_bound_stage_receipt(tmp_path):
    from formal_action_resources_v09 import build_formal_action_peak_estimate_v09
    from launch_gate_v09 import assert_launch_allowed_v09
    from memory_safety_v09 import HostMemorySnapshot, exclusive_high_load_lease_v09
    from stage_authorization_v09 import (
        STRICT_NESTING_APPROVAL_TEXT,
        create_stage_authorization_v09,
    )

    prerequisites = {
        "input_seal": "1" * 64,
        "input_artifact_external_audit": "2" * 64,
        "trusted_target_external_audit": "3" * 64,
        "legacy_checkpoint_bridge_external_audit": "4" * 64,
        "training_resource_preflight_external_audit": "5" * 64,
    }
    receipt = create_stage_authorization_v09(
        approval_text=STRICT_NESTING_APPROVAL_TEXT,
        scope="R09-NEST-S100",
        protocol_sha256="a" * 64,
        prerequisite_sha256=prerequisites,
        executable_tree_sha256="b" * 64,
        git_commit="c" * 40,
        output_root="results/26_historical_band_experts/formal_v09/strict_nesting/seed_100",
        created_utc="2026-08-02T00:00:00Z",
    )
    config = _config()
    estimate = build_formal_action_peak_estimate_v09(
        config,
        "training",
        variant="classic_lstm_256_clean",
    )
    snapshot = HostMemorySnapshot(32 * GIB, 16 * GIB, 256 * 2**20, 30 * GIB)
    bindings = {
        "protocol_sha256": "a" * 64,
        "prerequisite_sha256": prerequisites,
        "executable_tree_sha256": "b" * 64,
        "output_root": receipt["output_root"],
    }

    with exclusive_high_load_lease_v09(lock_path=tmp_path / "v09.lock") as lease:
        report = assert_launch_allowed_v09(
            config,
            action="training",
            peak_estimate=estimate,
            variant="classic_lstm_256_clean",
            snapshot=snapshot,
            lease=lease,
            stage_authorization=receipt,
            authorization_scope="R09-NEST-S100",
            stage_bindings=bindings,
        )
    assert report["authorization_mode"] == "one_use_stage_receipt"

    drift = dict(bindings)
    drift["executable_tree_sha256"] = "d" * 64
    with exclusive_high_load_lease_v09(lock_path=tmp_path / "v09-2.lock") as lease:
        with pytest.raises(ValueError, match="executable"):
            assert_launch_allowed_v09(
                config,
                action="training",
                peak_estimate=estimate,
                variant="classic_lstm_256_clean",
                snapshot=snapshot,
                lease=lease,
                stage_authorization=receipt,
                authorization_scope="R09-NEST-S100",
                stage_bindings=drift,
            )
