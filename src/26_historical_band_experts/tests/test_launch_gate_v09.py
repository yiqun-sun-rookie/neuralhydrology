import json
from pathlib import Path
import sys

import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG = IDEA_ROOT / "configs/formal_v09_protocol.json"
sys.path.insert(0, str(IDEA_ROOT))

GIB = 2**30


def _config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def test_v09_launch_gate_allows_only_safe_lightweight_synthetic_tests():
    from launch_gate_v09 import assert_launch_allowed_v09
    from memory_safety_v09 import HostMemorySnapshot

    snapshot = HostMemorySnapshot(32 * GIB, 10 * GIB, 256 * 2**20)
    report = assert_launch_allowed_v09(
        _config(),
        action="synthetic_test",
        estimated_peak_bytes=512 * 2**20,
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

    snapshot = HostMemorySnapshot(32 * GIB, 24 * GIB, 256 * 2**20)
    with pytest.raises(LaunchAuthorizationError, match="not authorized"):
        assert_launch_allowed_v09(
            _config(),
            action=action,
            estimated_peak_bytes=1 * GIB,
            snapshot=snapshot,
        )


def test_v09_launch_gate_would_still_block_low_memory_after_training_authorization():
    from launch_gate_v09 import assert_launch_allowed_v09
    from memory_safety_v09 import HostMemorySnapshot, MemorySafetyError

    config = _config()
    config["authorization"]["training"] = True
    snapshot = HostMemorySnapshot(32 * GIB, 10 * GIB, 256 * 2**20)

    with pytest.raises(ValueError, match="authorization"):
        assert_launch_allowed_v09(
            config,
            action="training",
            estimated_peak_bytes=2 * GIB,
            snapshot=snapshot,
        )

    config["authorization"]["training"] = False
    with pytest.raises(MemorySafetyError, match="start available"):
        from memory_safety_v09 import MemorySafetyGate

        MemorySafetyGate.from_snapshot(snapshot).assert_start_safe(
            snapshot,
            estimated_peak_bytes=2 * GIB,
            long_running=True,
        )
