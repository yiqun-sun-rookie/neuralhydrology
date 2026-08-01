"""Task-specific resource fit checks without global launch thresholds."""

from __future__ import annotations

import math
import shutil
from dataclasses import asdict, dataclass
from functools import lru_cache
from pathlib import Path

import psutil


@dataclass(frozen=True)
class ResourceRequest:
    cpu_cores: int
    gpu_count: int
    estimated_peak_memory_gb: float
    memory_safety_reserve_gb: float
    estimated_output_gb: float
    disk_safety_reserve_gb: float
    independent_monitor_enabled: bool
    monitor_reason: str


@dataclass(frozen=True)
class ResourceSnapshot:
    available_cpu_cores: int
    available_gpu_count: int
    available_memory_gb: float
    free_disk_gb: float


@dataclass(frozen=True)
class ResourceAssessment:
    request: ResourceRequest
    snapshot: ResourceSnapshot
    memory_required_gb: float
    disk_required_gb: float
    cpu_fit: bool
    gpu_fit: bool
    memory_fit: bool
    disk_fit: bool
    decision: str

    def as_dict(self) -> dict:
        return {
            "schema_version": "resource_preflight_v2",
            "request": asdict(self.request),
            "snapshot": asdict(self.snapshot),
            "memory_required_gb": self.memory_required_gb,
            "disk_required_gb": self.disk_required_gb,
            "cpu_fit": self.cpu_fit,
            "gpu_fit": self.gpu_fit,
            "memory_fit": self.memory_fit,
            "disk_fit": self.disk_fit,
            "decision": self.decision,
        }


class ResourceCapacityError(RuntimeError):
    """Raised before launch when the current machine cannot cover the declared task."""

    def __init__(self, assessment: ResourceAssessment):
        super().__init__("current resources cannot cover the task estimate and task-specific reserve")
        self.assessment = assessment


def _finite_nonnegative(value: float) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0


def assess_resource_fit(request: ResourceRequest, snapshot: ResourceSnapshot) -> ResourceAssessment:
    """Compare one task's declared estimate and reserve with a current snapshot."""
    values = (
        request.estimated_peak_memory_gb,
        request.memory_safety_reserve_gb,
        request.estimated_output_gb,
        request.disk_safety_reserve_gb,
        snapshot.available_memory_gb,
        snapshot.free_disk_gb,
    )
    if not all(_finite_nonnegative(value) for value in values):
        raise ValueError("resource estimates and capacities must be finite nonnegative values")
    integer_values = (request.cpu_cores, request.gpu_count, snapshot.available_cpu_cores, snapshot.available_gpu_count)
    if not all(isinstance(value, int) and not isinstance(value, bool) and value >= 0 for value in integer_values):
        raise ValueError("processor requests and capacities must be nonnegative integers")
    if request.cpu_cores < 1:
        raise ValueError("a candidate must request at least one CPU core")
    if not request.monitor_reason.strip():
        raise ValueError("resource monitor decision requires a reason")
    memory_required = request.estimated_peak_memory_gb + request.memory_safety_reserve_gb
    disk_required = request.estimated_output_gb + request.disk_safety_reserve_gb
    cpu_fit = request.cpu_cores <= snapshot.available_cpu_cores
    gpu_fit = request.gpu_count <= snapshot.available_gpu_count
    memory_fit = memory_required <= snapshot.available_memory_gb
    disk_fit = disk_required <= snapshot.free_disk_gb
    return ResourceAssessment(
        request=request,
        snapshot=snapshot,
        memory_required_gb=memory_required,
        disk_required_gb=disk_required,
        cpu_fit=cpu_fit,
        gpu_fit=gpu_fit,
        memory_fit=memory_fit,
        disk_fit=disk_fit,
        decision="launch" if cpu_fit and gpu_fit and memory_fit and disk_fit else "deny",
    )


def require_resource_fit(request: ResourceRequest, snapshot: ResourceSnapshot) -> ResourceAssessment:
    """Return a launch assessment or raise before creating a candidate process."""
    assessment = assess_resource_fit(request, snapshot)
    if assessment.decision != "launch":
        raise ResourceCapacityError(assessment)
    return assessment


@lru_cache(maxsize=1)
def _available_gpu_count() -> int:
    try:
        import torch

        return int(torch.cuda.device_count())
    except (ImportError, OSError, RuntimeError):
        return 0


def capture_resource_snapshot(path: str | Path) -> ResourceSnapshot:
    """Capture current processors, memory, and free disk for the target run volume."""
    gibibyte = 1024**3
    return ResourceSnapshot(
        available_cpu_cores=int(psutil.cpu_count(logical=True) or 0),
        available_gpu_count=_available_gpu_count(),
        available_memory_gb=psutil.virtual_memory().available / gibibyte,
        free_disk_gb=shutil.disk_usage(Path(path).resolve()).free / gibibyte,
    )
