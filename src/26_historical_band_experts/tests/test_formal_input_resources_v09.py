from pathlib import Path
import sys

import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))
GIB = 2**30
MIB = 2**20


def _contract():
    return {
        "contract_sha256": "a" * 64,
        "forcing_shape": [531, 10501, 5],
        "target_shape": [531, 3288],
        "basin_count": 531,
        "static_columns": [f"s{index}" for index in range(27)],
    }


def _snapshot(available=16 * GIB, commit=24 * GIB):
    from memory_safety_v09 import HostMemorySnapshot

    return HostMemorySnapshot(32 * GIB, available, 200 * MIB, commit)


def test_estimate_is_recomputable_and_guard_uses_125_factor_and_two_reserves(tmp_path):
    from formal_input_resources_v09 import (
        assert_input_seal_start_safe_v09,
        build_input_seal_peak_estimate_v09,
        validate_input_seal_peak_estimate_v09,
    )
    from memory_safety_v09 import MemorySafetyError, exclusive_high_load_lease_v09

    estimate = build_input_seal_peak_estimate_v09(_contract())
    validate_input_seal_peak_estimate_v09(_contract(), estimate)
    with pytest.raises(MemorySafetyError, match="live serial lease"):
        assert_input_seal_start_safe_v09(_contract(), estimate, _snapshot())
    with exclusive_high_load_lease_v09(lock_path=tmp_path / "lock") as lease:
        report = assert_input_seal_start_safe_v09(_contract(), estimate, _snapshot(), lease=lease)
    assert report["guarded_estimated_peak_bytes"] == (estimate["estimated_peak_bytes"] * 5 + 3) // 4
    assert report["physical_reserve_bytes"] == 2 * GIB
    assert report["commit_headroom_reserve_bytes"] == 2 * GIB


def test_tampered_estimate_and_unsafe_host_are_rejected(tmp_path):
    from formal_input_resources_v09 import (
        assert_input_seal_start_safe_v09,
        build_input_seal_peak_estimate_v09,
        validate_input_seal_peak_estimate_v09,
    )
    from memory_safety_v09 import MemorySafetyError, exclusive_high_load_lease_v09

    estimate = build_input_seal_peak_estimate_v09(_contract())
    drift = dict(estimate)
    drift["estimated_peak_bytes"] += 1
    with pytest.raises(MemorySafetyError):
        validate_input_seal_peak_estimate_v09(_contract(), drift)
    with exclusive_high_load_lease_v09(lock_path=tmp_path / "lock") as lease:
        with pytest.raises(MemorySafetyError, match="physical-memory reserve"):
            assert_input_seal_start_safe_v09(
                _contract(),
                estimate,
                _snapshot(available=2 * GIB, commit=24 * GIB),
                lease=lease,
            )


def test_runtime_requires_live_serial_lease_and_checks_reserves(tmp_path):
    from formal_input_resources_v09 import _run_input_seal_runtime_v09
    from memory_safety_v09 import MemorySafetyError

    seen = []
    result = _run_input_seal_runtime_v09(
        _contract(),
        callback=lambda runtime: seen.append(runtime.checkpoint()) or "done",
        host_sampler=_snapshot,
        lock_path=tmp_path / "lock",
    )
    assert result["result"] == "done"
    assert seen[0]["safe"] is True
    assert result["runtime"].is_valid() is False
    assert result["runtime"].is_formal_production_capability() is False

    snapshots = iter([_snapshot(), _snapshot(), _snapshot(available=GIB, commit=24 * GIB)])
    with pytest.raises(MemorySafetyError, match="runtime reserve"):
        _run_input_seal_runtime_v09(
            _contract(),
            callback=lambda runtime: runtime.checkpoint(),
            host_sampler=lambda: next(snapshots),
            lock_path=tmp_path / "other-lock",
        )
