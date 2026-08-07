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


@dataclass(frozen=True)
class AggregateHeadroom:
    """Capacity withheld from a parallel launch because the supervisor would stop inside it."""

    memory_headroom_gb: float
    disk_headroom_gb: float


@dataclass(frozen=True)
class AggregateAssessment:
    task_count: int
    snapshot: ResourceSnapshot
    headroom: AggregateHeadroom
    cpu_cores_required: int
    gpu_count_required: int
    memory_required_gb: float
    disk_required_gb: float
    memory_available_gb: float
    disk_available_gb: float
    cpu_fit: bool
    gpu_fit: bool
    memory_fit: bool
    disk_fit: bool
    decision: str

    def as_dict(self) -> dict:
        return {
            "schema_version": "resource_aggregate_preflight_v1",
            "task_count": self.task_count,
            "snapshot": asdict(self.snapshot),
            "headroom": asdict(self.headroom),
            "cpu_cores_required": self.cpu_cores_required,
            "gpu_count_required": self.gpu_count_required,
            "memory_required_gb": self.memory_required_gb,
            "disk_required_gb": self.disk_required_gb,
            "memory_available_gb": self.memory_available_gb,
            "disk_available_gb": self.disk_available_gb,
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


def resolve_aggregate_headroom(protocol: dict, *, total_memory_gb: float, total_disk_gb: float) -> AggregateHeadroom:
    """Resolve the protocol's headroom to absolute capacity, exactly as the stop floors do."""
    rules = protocol["parallel_launch"]
    for value in (total_memory_gb, total_disk_gb):
        if not _finite_nonnegative(value):
            raise ValueError("total capacities must be finite nonnegative values")
    return AggregateHeadroom(
        memory_headroom_gb=max(float(rules["memory_headroom_gb"]), float(rules["memory_headroom_fraction"]) * total_memory_gb),
        disk_headroom_gb=max(float(rules["disk_headroom_gb"]), float(rules["disk_headroom_fraction"]) * total_disk_gb),
    )


def assess_aggregate_resource_fit(
    requests: "list[ResourceRequest]",
    snapshot: ResourceSnapshot,
    *,
    margins: AggregateHeadroom,
) -> AggregateAssessment:
    """Judge everything launched at once on the sum, not one task at a time."""
    if not requests:
        raise ValueError("an aggregate launch requires at least one task")
    for request in requests:
        # Reuse the single-task validation so a malformed request cannot slip through the sum.
        assess_resource_fit(request, snapshot)
    if not all(_finite_nonnegative(value) for value in (margins.memory_headroom_gb, margins.disk_headroom_gb)):
        raise ValueError("aggregate headroom must be finite nonnegative values")

    cpu_required = sum(request.cpu_cores for request in requests)
    gpu_required = sum(request.gpu_count for request in requests)
    memory_required = sum(request.estimated_peak_memory_gb + request.memory_safety_reserve_gb for request in requests)
    disk_required = sum(request.estimated_output_gb + request.disk_safety_reserve_gb for request in requests)
    memory_available = snapshot.available_memory_gb - margins.memory_headroom_gb
    disk_available = snapshot.free_disk_gb - margins.disk_headroom_gb

    cpu_fit = cpu_required <= snapshot.available_cpu_cores
    gpu_fit = gpu_required <= snapshot.available_gpu_count
    memory_fit = memory_required <= memory_available
    disk_fit = disk_required <= disk_available
    return AggregateAssessment(
        task_count=len(requests),
        snapshot=snapshot,
        headroom=margins,
        cpu_cores_required=cpu_required,
        gpu_count_required=gpu_required,
        memory_required_gb=memory_required,
        disk_required_gb=disk_required,
        memory_available_gb=memory_available,
        disk_available_gb=disk_available,
        cpu_fit=cpu_fit,
        gpu_fit=gpu_fit,
        memory_fit=memory_fit,
        disk_fit=disk_fit,
        decision="launch" if cpu_fit and gpu_fit and memory_fit and disk_fit else "deny",
    )


def plan_parallel_batches(
    requests: "list[ResourceRequest]",
    snapshot: ResourceSnapshot,
    *,
    margins: AggregateHeadroom,
    max_parallel: int,
) -> list[list[int]]:
    """Pack tasks into sequential batches that each pass the aggregate gate, in declared order."""
    if not isinstance(max_parallel, int) or isinstance(max_parallel, bool) or max_parallel < 1:
        raise ValueError("parallel ceiling must be at least one")

    batches: list[list[int]] = []
    current: list[int] = []
    for index, request in enumerate(requests):
        alone = assess_aggregate_resource_fit([request], snapshot, margins=margins)
        if alone.decision != "launch":
            # Deferring it would hide a task this machine can never run.
            raise ResourceCapacityError(alone)
        proposed = current + [index]
        fits = len(proposed) <= max_parallel and assess_aggregate_resource_fit(
            [requests[position] for position in proposed], snapshot, margins=margins
        ).decision == "launch"
        if fits:
            current = proposed
            continue
        batches.append(current)
        current = [index]
    if current:
        batches.append(current)
    return batches


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
