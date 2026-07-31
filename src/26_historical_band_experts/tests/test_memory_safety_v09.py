import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import numpy as np
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

GIB = 2**30
MIB = 2**20


def _snapshot(*, available_gib: float, commit_headroom_gib: float) -> object:
    from memory_safety_v09 import HostMemorySnapshot

    return HostMemorySnapshot(
        total_bytes=32 * GIB,
        available_bytes=int(available_gib * GIB),
        process_rss_bytes=1 * GIB,
        commit_headroom_bytes=int(commit_headroom_gib * GIB),
    )


def _estimate(
    estimated_peak_bytes: int,
    *,
    method: str = "analytical_chunk_working_set_v1",
) -> dict:
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


def test_memory_policy_uses_task_estimate_and_small_reserves():
    from memory_safety_v09 import MemorySafetyPolicy

    policy = MemorySafetyPolicy.from_total(32 * GIB)

    assert policy.estimated_peak_safety_factor == 1.25
    assert policy.physical_reserve_bytes == 2 * GIB
    assert policy.commit_headroom_reserve_bytes == 2 * GIB


def test_long_job_is_allowed_with_ten_gib_when_analytical_peak_fits(tmp_path):
    from memory_safety_v09 import MemorySafetyGate, exclusive_high_load_lease_v09

    snapshot = _snapshot(available_gib=10, commit_headroom_gib=20)
    gate = MemorySafetyGate.from_snapshot(snapshot)
    with exclusive_high_load_lease_v09(lock_path=tmp_path / "v09.lock") as lease:
        report = gate.assert_start_safe(
            snapshot,
            _estimate(2 * GIB),
            long_running=True,
            lease=lease,
        )

    assert report["safe"] is True
    assert report["guarded_estimated_peak_bytes"] == int(2.5 * GIB)
    assert report["available_after_guarded_peak_bytes"] == int(7.5 * GIB)


def test_lightweight_job_passes_when_reserve_remains():
    from memory_safety_v09 import MemorySafetyGate

    snapshot = _snapshot(available_gib=10, commit_headroom_gib=20)
    gate = MemorySafetyGate.from_snapshot(snapshot)
    report = gate.assert_start_safe(
        snapshot,
        _estimate(512 * MIB, method="synthetic_bound_v1"),
        long_running=False,
    )

    assert report["safe"] is True
    assert report["guarded_estimated_peak_bytes"] == 640 * MIB
    assert report["available_after_guarded_peak_bytes"] == 10 * GIB - 640 * MIB


@pytest.mark.parametrize(
    ("available_gib", "commit_headroom_gib", "message"),
    [
        (2 - 1 / GIB, 20, "physical memory"),
        (20, 2 - 1 / GIB, "committed-memory"),
    ],
)
def test_runtime_gate_stops_before_either_reserve_is_crossed(
    available_gib,
    commit_headroom_gib,
    message,
):
    from memory_safety_v09 import MemorySafetyError, MemorySafetyGate

    gate = MemorySafetyGate.from_snapshot(_snapshot(available_gib=20, commit_headroom_gib=20))
    with pytest.raises(MemorySafetyError, match=message):
        gate.assert_runtime_safe(
            _snapshot(
                available_gib=available_gib,
                commit_headroom_gib=commit_headroom_gib,
            )
        )


@pytest.mark.parametrize(
    ("available_gib", "commit_headroom_gib", "message"),
    [
        (4.49, 20, "physical-memory reserve"),
        (20, 4.49, "committed-memory reserve"),
    ],
)
def test_estimated_peak_is_blocked_when_guarded_peak_crosses_a_reserve(
    available_gib,
    commit_headroom_gib,
    message,
    tmp_path,
):
    from memory_safety_v09 import (
        MemorySafetyError,
        MemorySafetyGate,
        exclusive_high_load_lease_v09,
    )

    snapshot = _snapshot(
        available_gib=available_gib,
        commit_headroom_gib=commit_headroom_gib,
    )
    gate = MemorySafetyGate.from_snapshot(snapshot)
    with exclusive_high_load_lease_v09(lock_path=tmp_path / "v09.lock") as lease:
        with pytest.raises(MemorySafetyError, match=message):
            gate.assert_start_safe(
                snapshot,
                _estimate(2 * GIB),
                long_running=True,
                lease=lease,
            )


def test_long_job_rejects_zero_or_unbound_peak_estimate(tmp_path):
    from memory_safety_v09 import (
        MemorySafetyError,
        MemorySafetyGate,
        exclusive_high_load_lease_v09,
    )

    snapshot = _snapshot(available_gib=20, commit_headroom_gib=40)
    gate = MemorySafetyGate.from_snapshot(snapshot)
    with exclusive_high_load_lease_v09(lock_path=tmp_path / "v09.lock") as lease:
        with pytest.raises(MemorySafetyError, match="positive peak"):
            gate.assert_start_safe(
                snapshot,
                _estimate(0),
                long_running=True,
                lease=lease,
            )
        drifted = _estimate(2 * GIB)
        drifted["estimated_peak_bytes"] = 1
        with pytest.raises(MemorySafetyError, match="differ"):
            gate.assert_start_safe(
                snapshot,
                drifted,
                long_running=True,
                lease=lease,
            )


def test_self_signed_measured_peak_method_is_rejected():
    from memory_safety_v09 import build_peak_estimate_v09

    with pytest.raises(ValueError, match="not permitted"):
        build_peak_estimate_v09(
            method="measured_representative_peak_v1",
            estimated_peak_bytes=1,
            evidence_fields={"probe_executed": False},
        )


def test_chunk_peak_evidence_is_recomputed_before_use(tmp_path):
    from memory_safety_v09 import (
        MemorySafetyError,
        MemorySafetyGate,
        exclusive_high_load_lease_v09,
    )

    snapshot = _snapshot(available_gib=20, commit_headroom_gib=40)
    gate = MemorySafetyGate.from_snapshot(snapshot)
    estimate = _estimate(2 * GIB)
    estimate["evidence"]["chunk_rows"] = 1
    estimate["evidence_sha256"] = hashlib.sha256(
        json.dumps(
            estimate["evidence"],
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    ).hexdigest()
    with exclusive_high_load_lease_v09(lock_path=tmp_path / "v09.lock") as lease:
        with pytest.raises(MemorySafetyError, match="does not match"):
            gate.assert_start_safe(
                snapshot,
                estimate,
                long_running=True,
                lease=lease,
            )


def test_file_peak_evidence_is_recomputed_from_exact_files(tmp_path):
    from memory_safety_v09 import (
        MemorySafetyError,
        build_file_peak_estimate_v09,
        validate_peak_estimate_v09,
    )

    answer_path = tmp_path / "answer.parquet"
    answer_path.write_bytes(b"a" * 20)
    predictions = {}
    for role, size in (
        ("baseline", 10),
        ("capacity_control", 12),
        ("challenger", 14),
    ):
        path = tmp_path / f"{role}.csv"
        path.write_bytes(b"p" * size)
        predictions[role] = path
    estimate = build_file_peak_estimate_v09(
        prediction_paths=predictions,
        answer_path=answer_path,
    )

    assert validate_peak_estimate_v09(estimate, long_running=True)[
        "estimated_peak_bytes"
    ] == 512 * MIB + 8 * 20 + 10 * 14
    predictions["challenger"].write_bytes(b"changed")
    with pytest.raises(MemorySafetyError, match="size evidence drift"):
        validate_peak_estimate_v09(estimate, long_running=True)


def test_long_job_requires_serial_lease():
    from memory_safety_v09 import MemorySafetyError, MemorySafetyGate

    snapshot = _snapshot(available_gib=20, commit_headroom_gib=40)
    gate = MemorySafetyGate.from_snapshot(snapshot)
    with pytest.raises(MemorySafetyError, match="serial lease"):
        gate.assert_start_safe(
            snapshot,
            _estimate(2 * GIB),
            long_running=True,
        )


def test_cross_process_lease_is_nonblocking_and_exclusive(tmp_path):
    from memory_safety_v09 import TaskLeaseError, exclusive_high_load_lease_v09

    lock_path = tmp_path / "v09.lock"
    with exclusive_high_load_lease_v09(lock_path=lock_path) as lease:
        assert lease.held is True
        with pytest.raises(TaskLeaseError, match="owns the serial lease"):
            with exclusive_high_load_lease_v09(lock_path=lock_path):
                pass
    assert lease.is_valid() is False


def test_serial_lease_cannot_be_forged_through_the_public_class():
    from memory_safety_v09 import TaskMemoryLease

    with pytest.raises(TypeError, match="created only by the lease context"):
        TaskMemoryLease("not-held", True, object())

    forged = object.__new__(TaskMemoryLease)
    object.__setattr__(forged, "lock_path", "not-held")
    object.__setattr__(forged, "held", True)
    object.__setattr__(forged, "_registration", object())
    assert forged.is_valid() is False


def test_serial_lease_blocks_a_separate_process(tmp_path):
    from memory_safety_v09 import exclusive_high_load_lease_v09

    lock_path = tmp_path / "v09.lock"
    child_code = (
        "import sys\n"
        "from fair_benchmark.task_memory_v09 import "
        "TaskLeaseError, exclusive_high_load_lease_v09\n"
        "try:\n"
        f"    with exclusive_high_load_lease_v09(lock_path={str(lock_path)!r}):\n"
        "        sys.exit(2)\n"
        "except TaskLeaseError:\n"
        "    sys.exit(0)\n"
    )
    environment = os.environ.copy()
    source_root = str(IDEA_ROOT.parent)
    environment["PYTHONPATH"] = source_root + os.pathsep + environment.get("PYTHONPATH", "")
    with exclusive_high_load_lease_v09(lock_path=lock_path):
        completed = subprocess.run(
            [sys.executable, "-c", child_code],
            env=environment,
            check=False,
            timeout=10,
        )
    assert completed.returncode == 0


def test_full_training_window_expansion_is_blocked_but_one_batch_is_safe():
    from memory_safety_v09 import MemorySafetyError, MemorySafetyGate

    snapshot = _snapshot(available_gib=20, commit_headroom_gib=40)
    gate = MemorySafetyGate.from_snapshot(snapshot)

    with pytest.raises(MemorySafetyError, match="materialization is forbidden"):
        gate.assert_allocation_safe(snapshot, (1_745_928, 3_562, 5), np.float32)

    report = gate.assert_allocation_safe(snapshot, (256, 3_562, 5), np.float32)
    assert report["safe"] is True
    assert report["allocation_bytes"] == 256 * 3_562 * 5 * 4


def test_full_training_window_is_forbidden_even_on_a_huge_host():
    from memory_safety_v09 import HostMemorySnapshot, MemorySafetyError, MemorySafetyGate

    snapshot = HostMemorySnapshot(
        total_bytes=512 * GIB,
        available_bytes=256 * GIB,
        process_rss_bytes=1 * GIB,
        commit_headroom_bytes=512 * GIB,
    )
    gate = MemorySafetyGate.from_snapshot(snapshot)
    with pytest.raises(MemorySafetyError, match="independently of host capacity"):
        gate.assert_allocation_safe(
            snapshot,
            (1_745_928, 3_562, 5),
            np.float32,
        )


def test_memory_snapshot_from_host_has_consistent_values():
    from memory_safety_v09 import sample_host_memory

    snapshot = sample_host_memory()

    assert snapshot.total_bytes > 0
    assert 0 < snapshot.available_bytes <= snapshot.total_bytes
    assert 0 < snapshot.process_rss_bytes < snapshot.total_bytes
    assert snapshot.commit_headroom_bytes > 0
