import math
from pathlib import Path
import sys

import numpy as np
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

GIB = 2**30
MIB = 2**20


def test_memory_policy_uses_conservative_dynamic_thresholds():
    from memory_safety_v09 import MemorySafetyPolicy

    policy = MemorySafetyPolicy.from_total(32 * GIB)

    assert policy.runtime_reserve_bytes == 8 * GIB
    assert policy.long_job_start_available_bytes == math.ceil(0.40 * 32 * GIB)
    assert policy.process_rss_limit_bytes == 6 * GIB
    assert policy.single_allocation_limit_bytes == 512 * MIB


def test_long_job_is_blocked_with_only_ten_gib_available():
    from memory_safety_v09 import HostMemorySnapshot, MemorySafetyError, MemorySafetyGate

    snapshot = HostMemorySnapshot(total_bytes=32 * GIB, available_bytes=10 * GIB, process_rss_bytes=1 * GIB)
    gate = MemorySafetyGate.from_snapshot(snapshot)

    with pytest.raises(MemorySafetyError, match="start available"):
        gate.assert_start_safe(snapshot, estimated_peak_bytes=2 * GIB, long_running=True)


def test_lightweight_job_passes_when_reserve_remains():
    from memory_safety_v09 import HostMemorySnapshot, MemorySafetyGate

    snapshot = HostMemorySnapshot(total_bytes=32 * GIB, available_bytes=10 * GIB, process_rss_bytes=256 * MIB)
    gate = MemorySafetyGate.from_snapshot(snapshot)
    report = gate.assert_start_safe(snapshot, estimated_peak_bytes=512 * MIB, long_running=False)

    assert report["safe"] is True
    assert report["available_after_estimated_peak_bytes"] == 10 * GIB - 512 * MIB


def test_runtime_gate_stops_before_reserve_or_process_limit_is_crossed():
    from memory_safety_v09 import HostMemorySnapshot, MemorySafetyError, MemorySafetyGate

    gate = MemorySafetyGate.from_snapshot(
        HostMemorySnapshot(total_bytes=32 * GIB, available_bytes=20 * GIB, process_rss_bytes=1 * GIB)
    )
    with pytest.raises(MemorySafetyError, match="runtime reserve"):
        gate.assert_runtime_safe(
            HostMemorySnapshot(total_bytes=32 * GIB, available_bytes=8 * GIB - 1, process_rss_bytes=1 * GIB)
        )
    with pytest.raises(MemorySafetyError, match="process resident"):
        gate.assert_runtime_safe(
            HostMemorySnapshot(total_bytes=32 * GIB, available_bytes=12 * GIB, process_rss_bytes=6 * GIB + 1)
        )


def test_full_training_window_expansion_is_blocked_but_one_batch_is_safe():
    from memory_safety_v09 import HostMemorySnapshot, MemorySafetyError, MemorySafetyGate

    snapshot = HostMemorySnapshot(total_bytes=32 * GIB, available_bytes=20 * GIB, process_rss_bytes=1 * GIB)
    gate = MemorySafetyGate.from_snapshot(snapshot)

    with pytest.raises(MemorySafetyError, match="single allocation"):
        gate.assert_allocation_safe(snapshot, (1_745_928, 3_562, 5), np.float32)

    report = gate.assert_allocation_safe(snapshot, (256, 3_562, 5), np.float32)
    assert report["safe"] is True
    assert report["allocation_bytes"] == 256 * 3_562 * 5 * 4


def test_memory_snapshot_from_host_has_consistent_values():
    from memory_safety_v09 import sample_host_memory

    snapshot = sample_host_memory()

    assert snapshot.total_bytes > 0
    assert 0 < snapshot.available_bytes <= snapshot.total_bytes
    assert 0 < snapshot.process_rss_bytes < snapshot.total_bytes
