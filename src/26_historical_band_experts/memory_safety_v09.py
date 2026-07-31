"""Version-09 compatibility imports for the shared task-specific memory gate."""
from pathlib import Path
import sys


WORKTREE_SRC = Path(__file__).resolve().parent.parent
if str(WORKTREE_SRC) not in sys.path:
    sys.path.insert(0, str(WORKTREE_SRC))

from fair_benchmark.task_memory_v09 import (
    GIB,
    MIB,
    HostMemorySnapshot,
    MemorySafetyError,
    MemorySafetyGate,
    MemorySafetyPolicy,
    TaskLeaseError,
    TaskMemoryLease,
    build_file_peak_estimate_v09,
    build_peak_estimate_v09,
    exclusive_high_load_lease_v09,
    sample_host_memory,
    validate_peak_estimate_v09,
)


__all__ = [
    "GIB",
    "MIB",
    "HostMemorySnapshot",
    "MemorySafetyError",
    "MemorySafetyGate",
    "MemorySafetyPolicy",
    "TaskLeaseError",
    "TaskMemoryLease",
    "build_file_peak_estimate_v09",
    "build_peak_estimate_v09",
    "exclusive_high_load_lease_v09",
    "sample_host_memory",
    "validate_peak_estimate_v09",
]
