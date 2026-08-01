"""Independent resource supervision for one owned candidate process.

The supervisor is a separate process. It only ever acts on a target whose process
identifier, creation time, executable path, and run identifier all match; a foreign
process is never sampled and never stopped. Samples are appended as complete JSON lines
so an interrupted supervisor can never corrupt an earlier record.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass  # noqa: F401
from pathlib import Path

import psutil

from .control import request_controlled_stop


GIBIBYTE = 1024**3
CREATE_TIME_TOLERANCE_SECONDS = 1e-3
CANDIDATE_MEMORY_STOP_REASON = "candidate memory exceeded its declared envelope for consecutive samples"
SYSTEM_MEMORY_STOP_REASON = "system memory below the near-out-of-memory floor for consecutive samples"
DISK_STOP_REASON = "free disk below the stop floor for new writes"


@dataclass(frozen=True)
class MonitorTarget:
    process_id: int
    create_time: float
    executable_path: str
    run_id: str
    declared_memory_budget_gb: float = math.inf


def _same_executable(left: str, right: str) -> bool:
    return os.path.normcase(os.path.normpath(left)) == os.path.normcase(os.path.normpath(right))


def verify_process_ownership(target: MonitorTarget) -> bool:
    """Confirm all four ownership fields before the supervisor acts on a process."""
    try:
        handle = psutil.Process(target.process_id)
        create_time = handle.create_time()
        executable_path = handle.exe()
    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
        return False
    if abs(create_time - target.create_time) > CREATE_TIME_TOLERANCE_SECONDS:
        return False
    return _same_executable(executable_path, target.executable_path)


def _memory_stop_condition(sample: dict, stop_policy: dict, declared_memory_budget_gb: float) -> str | None:
    """Classify one sample as a task-relative memory danger, or None when it is safe.

    A candidate is only stopped for memory when it can relieve the danger itself -- its own
    footprint has grown past the envelope it reserved -- or when free system memory has fallen
    below a genuine near-out-of-memory floor set below the machine's normal fluctuation band.
    External pressure that a tiny candidate did not cause is never a reason to stop it.
    """
    process_gb = float(sample.get("process_memory_gb") or 0.0)
    envelope_multiple = float(stop_policy["candidate_memory"]["stop_when_process_gb_exceeds_envelope_times"])
    # When no budget is declared (an infinite envelope), the candidate-relative brake has no
    # envelope to judge against and is intentionally inert; supervision then degrades to the
    # system near-out-of-memory floor below, never to no supervision at all.
    if math.isfinite(declared_memory_budget_gb) and process_gb > declared_memory_budget_gb * envelope_multiple:
        return "candidate"
    critical = stop_policy["system_memory_critical"]
    available = float(sample["system_available_memory_gb"])
    total = float(sample.get("system_memory_total_gb") or 0.0)
    fraction = available / total if total > 0 else 1.0
    if available < float(critical["stop_free_gb_floor"]) or fraction < float(critical["stop_free_fraction_floor"]):
        return "system"
    return None


def evaluate_stop_reason(
    samples: list[dict], *, policy: dict, declared_memory_budget_gb: float = math.inf
) -> str | None:
    """Return the controlled-stop reason implied by the samples, or None to keep running."""
    if not samples:
        return None
    stop = policy["runtime_stop"]
    disk = stop["disk"]
    latest = samples[-1]
    free_disk = float(latest["free_disk_gb"])
    disk_total = float(latest.get("disk_total_gb") or 0.0)
    disk_fraction = free_disk / disk_total if disk_total > 0 else 1.0
    if free_disk < float(disk["stop_new_writes_free_gb_floor"]) or disk_fraction < float(
        disk["stop_new_writes_free_fraction_floor"]
    ):
        return DISK_STOP_REASON
    consecutive = 0
    latest_condition: str | None = None
    for sample in reversed(samples):
        condition = _memory_stop_condition(sample, stop, declared_memory_budget_gb)
        if condition is None:
            break
        if latest_condition is None:
            latest_condition = condition
        consecutive += 1
    if consecutive >= int(stop["consecutive_low_samples"]):
        return CANDIDATE_MEMORY_STOP_REASON if latest_condition == "candidate" else SYSTEM_MEMORY_STOP_REASON
    return None


def append_resource_sample(log_path: str | Path, *, target: MonitorTarget, sample_index: int, sample: dict) -> dict:
    """Append one complete sample line without rewriting any earlier byte."""
    path = Path(log_path)
    record = {
        "schema_version": "resource_sample_v1",
        "process_id": target.process_id,
        "create_time": target.create_time,
        "executable_path": target.executable_path,
        "run_id": target.run_id,
        "sample_index": sample_index,
        **sample,
    }
    line = (json.dumps(record, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND)
    try:
        os.write(descriptor, line)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    return record


def collect_sample(target: MonitorTarget, *, disk_path: str | Path) -> dict:
    """Measure system memory, free disk, and the owned process footprint."""
    memory = psutil.virtual_memory()
    usage = shutil.disk_usage(Path(disk_path).resolve())
    try:
        process_memory = psutil.Process(target.process_id).memory_info().rss / GIBIBYTE
    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
        process_memory = 0.0
    return {
        "monotonic_seconds": time.monotonic(),
        "process_memory_gb": process_memory,
        "system_available_memory_gb": memory.available / GIBIBYTE,
        "system_memory_total_gb": memory.total / GIBIBYTE,
        "free_disk_gb": usage.free / GIBIBYTE,
        "disk_total_gb": usage.total / GIBIBYTE,
    }


def supervise(
    *,
    target: MonitorTarget,
    log_path: str | Path,
    control_root: str | Path,
    policy: dict,
    sample_interval_seconds: float,
    max_samples: int | None = None,
) -> dict:
    """Sample an owned process until it exits, a limit trips, or the sample budget ends."""
    summary = {
        "schema_version": "resource_monitor_summary_v1",
        "run_id": target.run_id,
        "ownership_verified": False,
        "sample_count": 0,
        "stopped": False,
        "stop_reason": None,
    }
    if not verify_process_ownership(target):
        return summary
    summary["ownership_verified"] = True

    samples: list[dict] = []
    index = 0
    while max_samples is None or index < max_samples:
        if not verify_process_ownership(target):
            break
        sample = collect_sample(target, disk_path=Path(log_path).parent)
        append_resource_sample(log_path, target=target, sample_index=index, sample=sample)
        samples.append(sample)
        index += 1
        reason = evaluate_stop_reason(
            samples, policy=policy, declared_memory_budget_gb=target.declared_memory_budget_gb
        )
        if reason is not None:
            request_controlled_stop(control_root, request_id=f"resource-monitor-{target.run_id}", reason=reason)
            summary["stopped"] = True
            summary["stop_reason"] = reason
            break
        time.sleep(sample_interval_seconds)
    summary["sample_count"] = index
    return summary


def publish_monitor_target(target_path: str | Path, target: MonitorTarget) -> Path:
    """Hand the supervisor the ownership identity of the process it may act on."""
    path = Path(target_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {"schema_version": "monitor_target_v1", **asdict(target)}
    if not math.isfinite(record["declared_memory_budget_gb"]):
        # Serialize an undeclared budget as strict-JSON null rather than the non-standard
        # ``Infinity`` token; await_monitor_target maps a null/missing budget back to infinity.
        record["declared_memory_budget_gb"] = None
    content = json.dumps(record, sort_keys=True, allow_nan=False) + "\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    return path


def await_monitor_target(target_path: str | Path, *, timeout_seconds: float, poll_seconds: float) -> MonitorTarget | None:
    """Wait for the runner to publish the ownership identity, or give up."""
    path = Path(target_path)
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if path.is_file():
            value = json.loads(path.read_text(encoding="utf-8"))
            raw_budget = value.get("declared_memory_budget_gb")
            return MonitorTarget(
                process_id=int(value["process_id"]),
                create_time=float(value["create_time"]),
                executable_path=str(value["executable_path"]),
                run_id=str(value["run_id"]),
                declared_memory_budget_gb=math.inf if raw_budget is None else float(raw_budget),
            )
        time.sleep(poll_seconds)
    return None


def start_resource_monitor(
    *,
    target_path: str | Path,
    log_path: str | Path,
    control_root: str | Path,
    policy_path: str | Path,
    sample_interval_seconds: float,
) -> subprocess.Popen:
    """Launch the supervisor as an independent process before the candidate is created."""
    package_parent = str(Path(__file__).resolve().parents[2])
    environment = dict(os.environ)
    existing = environment.get("PYTHONPATH", "")
    environment["PYTHONPATH"] = package_parent + (os.pathsep + existing if existing else "")
    command = [
        sys.executable,
        "-m",
        "unified_autoresearch.runtime.monitor",
        "--target-path",
        str(target_path),
        "--log-path",
        str(log_path),
        "--control-root",
        str(control_root),
        "--policy-path",
        str(policy_path),
        "--sample-interval-seconds",
        repr(sample_interval_seconds),
    ]
    return subprocess.Popen(
        command,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        shell=False,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-path", type=Path, required=True)
    parser.add_argument("--log-path", type=Path, required=True)
    parser.add_argument("--control-root", type=Path, required=True)
    parser.add_argument("--policy-path", type=Path, required=True)
    parser.add_argument("--sample-interval-seconds", type=float, required=True)
    parser.add_argument("--target-timeout-seconds", type=float, default=120.0)
    arguments = parser.parse_args(argv)

    target = await_monitor_target(
        arguments.target_path,
        timeout_seconds=arguments.target_timeout_seconds,
        poll_seconds=0.02,
    )
    if target is None:
        print(json.dumps({"schema_version": "resource_monitor_summary_v1", "ownership_verified": False}))
        return 0
    summary = supervise(
        target=target,
        log_path=arguments.log_path,
        control_root=arguments.control_root,
        policy=json.loads(arguments.policy_path.read_text(encoding="utf-8")),
        sample_interval_seconds=arguments.sample_interval_seconds,
    )
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
