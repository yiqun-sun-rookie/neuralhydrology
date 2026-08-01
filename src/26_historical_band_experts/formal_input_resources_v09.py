"""Task-specific host resource gate for streaming formal version 09 input sealing."""
from __future__ import annotations

from collections.abc import Callable, Mapping
import math
from pathlib import Path
import tempfile
from typing import Any

from artifact_v09 import canonical_sha256
from memory_safety_v09 import (
    GIB,
    MIB,
    HostMemorySnapshot,
    MemorySafetyError,
    TaskMemoryLease,
    exclusive_high_load_lease_v09,
    sample_host_memory,
)


_FIXED_OVERHEAD_BYTES = 384 * MIB
_MAURER_SOURCE_ROWS_PER_BASIN = 10_593
_MAURER_ROW_BYTES_UPPER_BOUND = 1_024
_TARGET_ROW_BYTES_UPPER_BOUND = 512
_STATIC_COPY_COUNT = 6
_HASH_BUFFER_BYTES = MIB
_SERIALIZATION_BUFFER_BYTES = 64 * MIB
_SAFETY_FACTOR = 1.25
_PHYSICAL_RESERVE_BYTES = 2 * GIB
_COMMIT_RESERVE_BYTES = 2 * GIB
_PRODUCTION_CAPABILITY_TOKEN = object()


def formal_input_lock_path_v09() -> Path:
    return (
        Path(tempfile.gettempdir())
        / "neuralhydrology_historical_multiscale_v09_high_load.lock"
    ).resolve()


def build_input_seal_peak_estimate_v09(contract: Mapping) -> dict:
    static_bytes = int(contract["basin_count"]) * len(contract["static_columns"]) * 8
    evidence = {
        "method": "analytical_input_seal_working_set_v1",
        "contract_sha256": contract["contract_sha256"],
        "formula": (
            "fixed_overhead + maurer_rows_per_basin*maurer_row_bytes_upper_bound + "
            "target_rows_per_basin*target_row_bytes_upper_bound + static_bytes*static_copy_count + "
            "hash_buffer + serialization_buffer"
        ),
        "fixed_overhead_bytes": _FIXED_OVERHEAD_BYTES,
        "maurer_rows_per_basin": _MAURER_SOURCE_ROWS_PER_BASIN,
        "maurer_row_bytes_upper_bound": _MAURER_ROW_BYTES_UPPER_BOUND,
        "target_rows_per_basin": int(contract["target_shape"][1]),
        "target_row_bytes_upper_bound": _TARGET_ROW_BYTES_UPPER_BOUND,
        "static_bytes": static_bytes,
        "static_copy_count": _STATIC_COPY_COUNT,
        "hash_buffer_bytes": _HASH_BUFFER_BYTES,
        "serialization_buffer_bytes": _SERIALIZATION_BUFFER_BYTES,
        "memory_mapped_full_arrays_counted_as_resident": False,
    }
    peak = (
        evidence["fixed_overhead_bytes"]
        + evidence["maurer_rows_per_basin"] * evidence["maurer_row_bytes_upper_bound"]
        + evidence["target_rows_per_basin"] * evidence["target_row_bytes_upper_bound"]
        + evidence["static_bytes"] * evidence["static_copy_count"]
        + evidence["hash_buffer_bytes"]
        + evidence["serialization_buffer_bytes"]
    )
    return {
        "method": evidence["method"],
        "estimated_peak_bytes": peak,
        "evidence_sha256": canonical_sha256(evidence),
        "evidence": evidence,
    }


def validate_input_seal_peak_estimate_v09(contract: Mapping, estimate: Mapping) -> dict:
    expected = build_input_seal_peak_estimate_v09(contract)
    if dict(estimate) != expected:
        raise MemorySafetyError("formal input seal peak estimate differs from its exact analytical evidence")
    return expected


def assert_input_seal_start_safe_v09(
    contract: Mapping,
    estimate: Mapping,
    snapshot: HostMemorySnapshot,
    *,
    lease: TaskMemoryLease | None = None,
) -> dict:
    validate_input_seal_peak_estimate_v09(contract, estimate)
    if lease is None or not lease.is_valid():
        raise MemorySafetyError("formal input seal requires a live serial lease")
    guarded = math.ceil(int(estimate["estimated_peak_bytes"]) * _SAFETY_FACTOR)
    physical_remaining = snapshot.available_bytes - guarded
    commit_remaining = snapshot.commit_headroom_bytes - guarded
    if physical_remaining < _PHYSICAL_RESERVE_BYTES:
        raise MemorySafetyError("guarded input-seal estimate would cross the physical-memory reserve")
    if commit_remaining < _COMMIT_RESERVE_BYTES:
        raise MemorySafetyError("guarded input-seal estimate would cross the committed-memory reserve")
    return {
        "safe": True,
        "estimated_peak_bytes": estimate["estimated_peak_bytes"],
        "guarded_estimated_peak_bytes": guarded,
        "available_after_guarded_peak_bytes": physical_remaining,
        "commit_headroom_after_guarded_peak_bytes": commit_remaining,
        "physical_reserve_bytes": _PHYSICAL_RESERVE_BYTES,
        "commit_headroom_reserve_bytes": _COMMIT_RESERVE_BYTES,
        "serial_lease": {"held": lease is not None, "lock_path": lease.lock_path if lease is not None else None},
    }


class InputSealRuntimeV09:
    """Non-constructible capability that is valid only while the serial lock is held."""

    __slots__ = (
        "contract",
        "estimate",
        "lease",
        "host_sampler",
        "total_bytes",
        "start_report",
        "entry_report",
        "production_token",
    )

    def __init__(self, *args, **kwargs) -> None:
        raise TypeError("InputSealRuntimeV09 is created only by the resource-gated runner")

    def is_valid(self) -> bool:
        return self.lease.is_valid()

    def checkpoint(self) -> dict:
        if not self.is_valid():
            raise MemorySafetyError("formal input seal runtime lost its serial lease")
        snapshot = self.host_sampler()
        if snapshot.total_bytes != self.total_bytes:
            raise MemorySafetyError("host physical-memory total changed during input sealing")
        if snapshot.available_bytes < _PHYSICAL_RESERVE_BYTES or snapshot.commit_headroom_bytes < _COMMIT_RESERVE_BYTES:
            raise MemorySafetyError("formal input seal runtime reserve was crossed")
        return {
            "safe": True,
            "available_bytes": snapshot.available_bytes,
            "commit_headroom_bytes": snapshot.commit_headroom_bytes,
        }

    def is_formal_production_capability(self) -> bool:
        return (
            self.is_valid()
            and self.production_token is _PRODUCTION_CAPABILITY_TOKEN
            and self.lease.lock_path == str(formal_input_lock_path_v09())
        )


def _runtime(
    contract: Mapping,
    estimate: Mapping,
    lease: TaskMemoryLease,
    sampler: Callable[[], HostMemorySnapshot],
    total: int,
    start_report: Mapping,
    production_token: object | None,
) -> InputSealRuntimeV09:
    runtime = object.__new__(InputSealRuntimeV09)
    runtime.contract = contract
    runtime.estimate = estimate
    runtime.lease = lease
    runtime.host_sampler = sampler
    runtime.total_bytes = total
    runtime.start_report = dict(start_report)
    runtime.entry_report = None
    runtime.production_token = production_token
    return runtime


def _execute_input_seal_runtime_v09(
    contract: Mapping,
    *,
    callback: Callable[[InputSealRuntimeV09], Any],
    host_sampler: Callable[[], HostMemorySnapshot],
    lock_path: str | Path,
    production_token: object | None,
) -> dict:
    estimate = build_input_seal_peak_estimate_v09(contract)
    resolved_lock = Path(lock_path).resolve()
    if production_token is not None and (
        production_token is not _PRODUCTION_CAPABILITY_TOKEN
        or resolved_lock != formal_input_lock_path_v09()
    ):
        raise MemorySafetyError("formal input production requires the unique global lock path")
    with exclusive_high_load_lease_v09(lock_path=resolved_lock) as lease:
        initial = host_sampler()
        start = assert_input_seal_start_safe_v09(contract, estimate, initial, lease=lease)
        runtime = _runtime(
            contract,
            estimate,
            lease,
            host_sampler,
            initial.total_bytes,
            start,
            production_token,
        )
        entry = assert_input_seal_start_safe_v09(contract, estimate, host_sampler(), lease=lease)
        runtime.entry_report = dict(entry)
        result = callback(runtime)
        return {"result": result, "estimate": estimate, "start": start, "entry": entry, "runtime": runtime}


def _run_input_seal_runtime_v09(
    contract: Mapping,
    *,
    callback: Callable[[InputSealRuntimeV09], Any],
    host_sampler: Callable[[], HostMemorySnapshot],
    lock_path: str | Path,
) -> dict:
    """Synthetic-test runner; capabilities created here can never publish formally."""
    return _execute_input_seal_runtime_v09(
        contract,
        callback=callback,
        host_sampler=host_sampler,
        lock_path=lock_path,
        production_token=None,
    )


def run_input_seal_runtime_v09(
    contract: Mapping,
    *,
    callback: Callable[[InputSealRuntimeV09], Any],
) -> dict:
    """Run one formal input callback under live host checks and the global serial lock."""
    return _execute_input_seal_runtime_v09(
        contract,
        callback=callback,
        host_sampler=sample_host_memory,
        lock_path=formal_input_lock_path_v09(),
        production_token=_PRODUCTION_CAPABILITY_TOKEN,
    )
