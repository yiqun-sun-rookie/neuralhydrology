"""Resource snapshots and hard gates for bounded local experiments."""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path

import psutil


@dataclass(frozen=True)
class ResourceSnapshot:
    timestamp: str
    total_memory_gib: float
    available_memory_gib: float
    available_memory_fraction: float
    cpu_load_percent: float
    logical_processors: int
    disk_free_gib: float
    gpu_name: str | None
    gpu_memory_total_mib: float | None
    gpu_memory_free_mib: float | None
    gpu_utilization_percent: float | None
    process_rss_gib: float | None = None
    process_peak_working_set_gib: float | None = None

    def to_dict(self) -> dict:
        return asdict(self)


class ResourceGateError(RuntimeError):
    """Raised when a frozen resource threshold is not satisfied."""


def _gpu_snapshot() -> tuple[str | None, float | None, float | None, float | None]:
    command = [
        "nvidia-smi",
        "--query-gpu=name,memory.total,memory.free,utilization.gpu",
        "--format=csv,noheader,nounits",
    ]
    try:
        completed = subprocess.run(command, check=True, capture_output=True, text=True, timeout=5)
        first = completed.stdout.strip().splitlines()[0]
        name, total, free, utilization = (part.strip() for part in first.split(","))
        return name, float(total), float(free), float(utilization)
    except (FileNotFoundError, IndexError, subprocess.SubprocessError, ValueError):
        return None, None, None, None


def capture_resource_snapshot(path: Path) -> ResourceSnapshot:
    memory = psutil.virtual_memory()
    disk = shutil.disk_usage(Path(path).resolve())
    gpu_name, gpu_total, gpu_free, gpu_utilization = _gpu_snapshot()
    gib = 1024.0**3
    process_memory = psutil.Process().memory_info()
    peak_working_set = getattr(process_memory, "peak_wset", None)
    return ResourceSnapshot(
        timestamp=datetime.now().astimezone().isoformat(),
        total_memory_gib=memory.total / gib,
        available_memory_gib=memory.available / gib,
        available_memory_fraction=memory.available / memory.total,
        cpu_load_percent=psutil.cpu_percent(interval=0.1),
        logical_processors=int(psutil.cpu_count(logical=True) or 1),
        disk_free_gib=disk.free / gib,
        gpu_name=gpu_name,
        gpu_memory_total_mib=gpu_total,
        gpu_memory_free_mib=gpu_free,
        gpu_utilization_percent=gpu_utilization,
        process_rss_gib=process_memory.rss / gib,
        process_peak_working_set_gib=None if peak_working_set is None else peak_working_set / gib,
    )


def enforce_resource_gate(
    snapshot: ResourceSnapshot,
    estimated_peak_gib: float,
    estimated_output_gib: float,
) -> None:
    if snapshot.available_memory_fraction < 0.15:
        raise ResourceGateError("available memory is below 15% of physical memory")
    if estimated_peak_gib > 0.70 * snapshot.available_memory_gib:
        raise ResourceGateError("estimated peak memory exceeds 70% of currently available memory")
    observed_peak = snapshot.process_peak_working_set_gib or snapshot.process_rss_gib
    if observed_peak is not None and observed_peak > 0.70 * snapshot.available_memory_gib:
        raise ResourceGateError("observed process peak memory exceeds 70% of currently available memory")
    required_disk = max(20.0, 2.0 * estimated_output_gib)
    if snapshot.disk_free_gib < required_disk:
        raise ResourceGateError(
            f"free disk is {snapshot.disk_free_gib:.3f} GiB; at least {required_disk:.3f} GiB is required"
        )
    if snapshot.logical_processors < 2:
        raise ResourceGateError("at least two logical processors are required to reserve one")


def recommended_worker_count(
    snapshot: ResourceSnapshot,
    requested: int,
    estimated_peak_per_worker_gib: float,
) -> int:
    if requested <= 0 or estimated_peak_per_worker_gib <= 0.0:
        raise ValueError("requested workers and per-worker peak memory must be positive")
    processor_limit = max(snapshot.logical_processors - 1, 0)
    memory_limit = int((0.70 * snapshot.available_memory_gib) // estimated_peak_per_worker_gib)
    recommended = min(requested, processor_limit, memory_limit)
    if recommended < 1:
        raise ResourceGateError("no worker fits while preserving memory headroom and one logical processor")
    return recommended
