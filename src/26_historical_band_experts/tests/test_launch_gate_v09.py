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
