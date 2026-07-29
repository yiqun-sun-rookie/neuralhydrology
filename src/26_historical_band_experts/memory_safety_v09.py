"""Fail-closed physical-memory protection for formal version 09 work."""
from __future__ import annotations

from dataclasses import dataclass
import math
import os
from typing import Sequence

import numpy as np
import psutil


GIB = 2**30
MIB = 2**20


class MemorySafetyError(RuntimeError):
    """Raised before this task can put the host near physical-memory exhaustion."""


@dataclass(frozen=True)
class HostMemorySnapshot:
    """Physical-memory and current-process usage at one decision point."""

    total_bytes: int
    available_bytes: int
    process_rss_bytes: int

    def __post_init__(self) -> None:
        if self.total_bytes <= 0:
            raise ValueError("total_bytes must be positive")
        if not 0 <= self.available_bytes <= self.total_bytes:
            raise ValueError("available_bytes must be within physical memory")
        if self.process_rss_bytes < 0:
            raise ValueError("process_rss_bytes must be nonnegative")


@dataclass(frozen=True)
class MemorySafetyPolicy:
    """Host-size-specific thresholds derived from the frozen version 09 policy."""

    total_bytes: int
    runtime_reserve_bytes: int
    long_job_start_available_bytes: int
    process_rss_limit_bytes: int
    single_allocation_limit_bytes: int

    @classmethod
    def from_total(cls, total_bytes: int) -> "MemorySafetyPolicy":
        total_bytes = int(total_bytes)
        if total_bytes <= 0:
            raise ValueError("total_bytes must be positive")
        return cls(
            total_bytes=total_bytes,
            runtime_reserve_bytes=max(8 * GIB, math.ceil(0.25 * total_bytes)),
            long_job_start_available_bytes=max(12 * GIB, math.ceil(0.40 * total_bytes)),
            process_rss_limit_bytes=min(6 * GIB, math.floor(0.20 * total_bytes)),
            single_allocation_limit_bytes=min(512 * MIB, math.floor(0.02 * total_bytes)),
        )


def sample_host_memory() -> HostMemorySnapshot:
    """Measure current physical-memory availability and this process's resident set."""
    virtual_memory = psutil.virtual_memory()
    resident = psutil.Process(os.getpid()).memory_info().rss
    return HostMemorySnapshot(
        total_bytes=int(virtual_memory.total),
        available_bytes=int(virtual_memory.available),
        process_rss_bytes=int(resident),
    )


class MemorySafetyGate:
    """Apply start, runtime, and planned-allocation checks without allocating data."""

    def __init__(self, policy: MemorySafetyPolicy) -> None:
        self.policy = policy

    @classmethod
    def from_snapshot(cls, snapshot: HostMemorySnapshot) -> "MemorySafetyGate":
        return cls(MemorySafetyPolicy.from_total(snapshot.total_bytes))

    def _validate_snapshot(self, snapshot: HostMemorySnapshot) -> None:
        if snapshot.total_bytes != self.policy.total_bytes:
            raise MemorySafetyError("host physical-memory total changed after the policy was created")

    def assert_start_safe(
        self,
        snapshot: HostMemorySnapshot,
        estimated_peak_bytes: int,
        *,
        long_running: bool,
    ) -> dict:
        """Require enough memory before a lightweight or long-running action starts."""
        self._validate_snapshot(snapshot)
        estimated_peak_bytes = int(estimated_peak_bytes)
        if estimated_peak_bytes < 0:
            raise ValueError("estimated_peak_bytes must be nonnegative")
        if snapshot.process_rss_bytes > self.policy.process_rss_limit_bytes:
            raise MemorySafetyError(
                "process resident memory already exceeds the version 09 limit: "
                f"{snapshot.process_rss_bytes} > {self.policy.process_rss_limit_bytes}"
            )
        if long_running and snapshot.available_bytes < self.policy.long_job_start_available_bytes:
            raise MemorySafetyError(
                "long-job start available memory is below the required threshold: "
                f"{snapshot.available_bytes} < {self.policy.long_job_start_available_bytes}"
            )
        remaining = snapshot.available_bytes - estimated_peak_bytes
        if remaining < self.policy.runtime_reserve_bytes:
            raise MemorySafetyError(
                "estimated peak would cross the runtime reserve: "
                f"{remaining} < {self.policy.runtime_reserve_bytes}"
            )
        return {
            "safe": True,
            "long_running": bool(long_running),
            "estimated_peak_bytes": estimated_peak_bytes,
            "available_after_estimated_peak_bytes": remaining,
            "runtime_reserve_bytes": self.policy.runtime_reserve_bytes,
        }

    def assert_runtime_safe(self, snapshot: HostMemorySnapshot) -> dict:
        """Stop between chunks or batches before reserve or process limits are crossed."""
        self._validate_snapshot(snapshot)
        if snapshot.available_bytes < self.policy.runtime_reserve_bytes:
            raise MemorySafetyError(
                "available physical memory is below the runtime reserve: "
                f"{snapshot.available_bytes} < {self.policy.runtime_reserve_bytes}"
            )
        if snapshot.process_rss_bytes > self.policy.process_rss_limit_bytes:
            raise MemorySafetyError(
                "process resident memory exceeds the version 09 limit: "
                f"{snapshot.process_rss_bytes} > {self.policy.process_rss_limit_bytes}"
            )
        return {
            "safe": True,
            "available_bytes": snapshot.available_bytes,
            "process_rss_bytes": snapshot.process_rss_bytes,
        }

    def assert_allocation_safe(
        self,
        snapshot: HostMemorySnapshot,
        shape: Sequence[int],
        dtype,
        *,
        copies: int = 1,
    ) -> dict:
        """Reject a planned dense allocation before NumPy or PyTorch receives it."""
        self.assert_runtime_safe(snapshot)
        dimensions = tuple(int(value) for value in shape)
        if not dimensions or any(value < 0 for value in dimensions):
            raise ValueError("shape must contain nonnegative dimensions")
        copies = int(copies)
        if copies <= 0:
            raise ValueError("copies must be positive")
        element_count = math.prod(dimensions)
        allocation_bytes = element_count * np.dtype(dtype).itemsize * copies
        if allocation_bytes > self.policy.single_allocation_limit_bytes:
            raise MemorySafetyError(
                "planned single allocation exceeds the version 09 limit: "
                f"{allocation_bytes} > {self.policy.single_allocation_limit_bytes}"
            )
        if snapshot.available_bytes - allocation_bytes < self.policy.runtime_reserve_bytes:
            raise MemorySafetyError("planned allocation would cross the runtime reserve")
        return {
            "safe": True,
            "shape": dimensions,
            "dtype": np.dtype(dtype).name,
            "copies": copies,
            "allocation_bytes": allocation_bytes,
        }
