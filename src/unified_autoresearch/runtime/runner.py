"""Execute one candidate mode through the fixed restricted bootstrap."""

from __future__ import annotations

import json
import os
import subprocess
import sysconfig
from dataclasses import dataclass
from pathlib import Path

import psutil

from .adapter import build_candidate_command
from .checkpoints import CheckpointRecord, mount_verified_checkpoint, promote_staged_checkpoint
from .dependencies import DependencyEnvironmentError, assess_dependency_environment
from .descriptor import CandidateDescriptor
from .layout import RunLayout
from .monitor import MonitorTarget, publish_monitor_target, start_resource_monitor
from .outputs import assess_output_contract
from .resources import (
    ResourceCapacityError,
    ResourceRequest,
    ResourceSnapshot,
    assess_resource_fit,
    capture_resource_snapshot,
)


RESOURCE_POLICY_PATH = Path(__file__).resolve().parents[1] / "protocols" / "resource_safety_v3.json"
_DEFAULT_SYSTEM_TIMEZONE_ROOTS = (
    "/usr/share/zoneinfo",
    "/usr/lib/zoneinfo",
    "/usr/share/lib/zoneinfo",
    "/etc/zoneinfo",
)


@dataclass(frozen=True)
class RuntimeResult:
    exit_code: int
    process_exit_code: int
    status: str
    denied_event_count: int
    output_contract_valid: bool
    access_log_path: Path
    stdout_path: Path
    stderr_path: Path
    result_path: Path
    checkpoint_path: Path | None
    resume_checkpoint_path: Path | None
    dependency_preflight_path: Path
    resource_preflight_path: Path


def _write_json_exclusive(path: Path, value: dict) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def _access_events(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def _system_timezone_read_paths() -> list[str]:
    raw_value = sysconfig.get_config_var("TZPATH")
    configured_roots = [] if not isinstance(raw_value, str) else raw_value.split(os.pathsep)
    trusted_paths: set[str] = set()
    for value in [*configured_roots, *_DEFAULT_SYSTEM_TIMEZONE_ROOTS]:
        root = Path(value)
        if not root.is_absolute():
            continue
        resolved_root = root.resolve()
        if resolved_root == Path(resolved_root.anchor) or not resolved_root.is_dir():
            continue
        for marker in (resolved_root / "UTC", resolved_root / "Etc" / "UTC"):
            if marker.is_file():
                trusted_paths.add(str(marker.resolve()))
    return sorted(trusted_paths)


def _append_parent_denial(path: Path, *, process_exit_code: int) -> dict:
    event = {
        "event": "bootstrap.contract_failure",
        "decision": "deny",
        "reason": "child contract failure had no intact child denial record",
        "process_exit_code": process_exit_code,
        "recorder": "parent",
    }
    os.chmod(path, 0o600)
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_APPEND)
        with os.fdopen(descriptor, "a", encoding="utf-8", newline="\n") as stream:
            json.dump(event, stream, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        os.chmod(path, 0o444)
    return event


def _run_supervised_candidate(
    command: list[str],
    *,
    descriptor: CandidateDescriptor,
    layout: RunLayout,
    mode: str,
    environment: dict,
    stdout,
    stderr,
    monitor_log_path: Path,
    sample_interval_seconds: float | None,
) -> int:
    """Launch the candidate and attach the independent supervisor before returning control."""
    policy = json.loads(RESOURCE_POLICY_PATH.read_text(encoding="utf-8"))
    interval = float(policy["sample_interval_seconds"] if sample_interval_seconds is None else sample_interval_seconds)
    target_path = layout.control_root / "MONITOR_TARGET.json"
    try:
        monitor = start_resource_monitor(
            target_path=target_path,
            log_path=monitor_log_path,
            control_root=layout.control_root,
            policy_path=RESOURCE_POLICY_PATH,
            sample_interval_seconds=interval,
        )
    except Exception as error:
        raise RuntimeError("independent resource monitor is required but did not start") from error

    try:
        process = subprocess.Popen(
            command,
            cwd=layout.root,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=stdout,
            stderr=stderr,
            shell=False,
        )
        handle = psutil.Process(process.pid)
        declared_memory_budget_gb = float(descriptor.resources["estimated_peak_memory_gb"]) + float(
            descriptor.resources["memory_safety_reserve_gb"]
        )
        publish_monitor_target(
            target_path,
            MonitorTarget(
                process_id=process.pid,
                create_time=handle.create_time(),
                executable_path=handle.exe(),
                run_id=f"{descriptor.candidate_id}-{mode}",
                declared_memory_budget_gb=declared_memory_budget_gb,
            ),
        )
        return process.wait()
    finally:
        monitor.terminate()
        try:
            monitor.wait(timeout=30)
        except subprocess.TimeoutExpired:
            monitor.kill()


def run_candidate(
    *,
    descriptor: CandidateDescriptor,
    layout: RunLayout,
    mode: str,
    resume_checkpoint: str | Path | None = None,
    resource_snapshot: ResourceSnapshot | None = None,
    monitor_sample_interval_seconds: float | None = None,
) -> RuntimeResult:
    """Run a candidate once and standardize contract and runtime failures."""
    if mode not in {"train", "predict"}:
        raise ValueError(f"unsupported candidate mode: {mode!r}")
    resume_record: CheckpointRecord | None = None
    if resume_checkpoint is not None:
        if descriptor.resume.get("supported") is not True:
            raise ValueError("candidate does not support checkpoint resume")
        resume_record = mount_verified_checkpoint(
            layout.root,
            resume_checkpoint,
            expected_candidate_id=descriptor.candidate_id,
        )
    policy_path = layout.log_root / "runtime-policy.json"
    dependency_preflight_path = layout.log_root / "dependency-preflight.json"
    resource_preflight_path = layout.log_root / "resource-preflight.json"
    access_log_path = layout.log_root / "access.jsonl"
    stdout_path = layout.log_root / "stdout.txt"
    stderr_path = layout.log_root / "stderr.txt"
    result_path = layout.log_root / "runtime-result.json"
    dependency_assessment = assess_dependency_environment(descriptor.dependencies)
    _write_json_exclusive(dependency_preflight_path, dependency_assessment.as_dict())
    if dependency_assessment.decision != "launch":
        raise DependencyEnvironmentError(dependency_assessment)
    resource_request = ResourceRequest(
        cpu_cores=int(descriptor.resources["cpu_cores"]),
        gpu_count=int(descriptor.resources["gpu_count"]),
        estimated_peak_memory_gb=float(descriptor.resources["estimated_peak_memory_gb"]),
        memory_safety_reserve_gb=float(descriptor.resources["memory_safety_reserve_gb"]),
        estimated_output_gb=float(descriptor.resources["estimated_output_gb"]),
        disk_safety_reserve_gb=float(descriptor.resources["disk_safety_reserve_gb"]),
        independent_monitor_enabled=bool(descriptor.resources["independent_monitor_enabled"]),
        monitor_reason=str(descriptor.resources["monitor_reason"]),
    )
    actual_snapshot = resource_snapshot or capture_resource_snapshot(layout.root)
    resource_assessment = assess_resource_fit(resource_request, actual_snapshot)
    _write_json_exclusive(resource_preflight_path, resource_assessment.as_dict())
    if resource_assessment.decision != "launch":
        raise ResourceCapacityError(resource_assessment)
    interpreter_read_roots = sorted(
        {
            str(Path(value).resolve())
            for key, value in sysconfig.get_paths().items()
            if key in {"stdlib", "platstdlib"} and value
        }
    )
    restricted_site_package_roots = sorted(
        {
            str(Path(value).resolve())
            for key, value in sysconfig.get_paths().items()
            if key in {"purelib", "platlib"} and value
        }
    )
    policy = {
        "schema_version": "runtime_policy_v1",
        "read_roots": [
            str(layout.candidate_root),
            str(layout.input_root),
            str(layout.control_root),
            *([] if resume_record is None else [str(resume_record.path)]),
            *interpreter_read_roots,
        ],
        "write_roots": [str(layout.output_root), str(layout.checkpoint_staging_root)],
        "candidate_root": str(layout.candidate_root),
        "allowed_dependency_imports": [
            dependency.split("==", 1)[0].replace("-", "_") for dependency in descriptor.dependencies
        ],
        "restricted_site_package_roots": restricted_site_package_roots,
        "dependency_initialization_read_roots": list(dependency_assessment.initialization_read_roots),
        "dependency_initialization_system_read_paths": _system_timezone_read_paths(),
    }
    _write_json_exclusive(policy_path, policy)
    command = build_candidate_command(
        policy_path=policy_path,
        access_log_path=access_log_path,
        entrypoint=layout.candidate_root / descriptor.entrypoint[mode],
        mode=mode,
    )
    environment = {
        key: value
        for key, value in os.environ.items()
        if key.upper() in {"PATH", "PATHEXT", "SYSTEMROOT", "WINDIR", "TEMP", "TMP"}
    }
    environment.update(
        {
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONNOUSERSITE": "1",
            "UNIFIED_CANDIDATE_ROOT": str(layout.candidate_root),
            "UNIFIED_INPUT_ROOT": str(layout.input_root),
            "UNIFIED_OUTPUT_ROOT": str(layout.output_root),
            "UNIFIED_CHECKPOINT_STAGING_ROOT": str(layout.checkpoint_staging_root),
            "UNIFIED_STOP_REQUEST": str(layout.control_root / "STOP_REQUEST.json"),
            "UNIFIED_MODE": mode,
            "UNIFIED_SEED": str(descriptor.seed),
        }
    )
    if resume_record is not None:
        environment["UNIFIED_RESUME_CHECKPOINT"] = str(resume_record.path)
    monitor_required = bool(descriptor.resources["independent_monitor_enabled"])
    monitor_log_path = layout.log_root / "resource-monitor.jsonl"
    with stdout_path.open("xb") as stdout, stderr_path.open("xb") as stderr:
        if not monitor_required:
            process_exit_code = subprocess.run(
                command,
                cwd=layout.root,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=stdout,
                stderr=stderr,
                shell=False,
                check=False,
            ).returncode
        else:
            process_exit_code = _run_supervised_candidate(
                command,
                descriptor=descriptor,
                layout=layout,
                mode=mode,
                environment=environment,
                stdout=stdout,
                stderr=stderr,
                monitor_log_path=monitor_log_path,
                sample_interval_seconds=monitor_sample_interval_seconds,
            )
    events = _access_events(access_log_path)
    denied_count = sum(event.get("decision") == "deny" for event in events)
    if process_exit_code == 2 and denied_count == 0:
        events.append(_append_parent_denial(access_log_path, process_exit_code=process_exit_code))
        denied_count = 1
    output_contract = assess_output_contract(descriptor, layout, mode)
    checkpoint: CheckpointRecord | None = None
    if denied_count or process_exit_code == 2:
        exit_code, status = 2, "contract_failure"
    elif process_exit_code == 75:
        try:
            checkpoint = promote_staged_checkpoint(
                layout.checkpoint_staging_root,
                layout.checkpoints_root,
                expected_candidate_id=descriptor.candidate_id,
                expected_mode=mode,
                expected_parent_checkpoint_id=None if resume_record is None else resume_record.checkpoint_id,
            )
        except (FileExistsError, OSError, ValueError):
            exit_code, status = 2, "contract_failure"
        else:
            exit_code, status = 75, "checkpointed"
    elif process_exit_code == 0:
        if output_contract.valid:
            exit_code, status = 0, "succeeded"
        else:
            exit_code, status = 2, "contract_failure"
    else:
        exit_code, status = 1, "runtime_failure"
    _write_json_exclusive(
        result_path,
        {
            "schema_version": "runtime_result_v1",
            "candidate_id": descriptor.candidate_id,
            "mode": mode,
            "process_exit_code": process_exit_code,
            "normalized_exit_code": exit_code,
            "status": status,
            "denied_event_count": denied_count,
            "required_outputs_complete": output_contract.valid,
            "output_contract": output_contract.as_dict(),
            "checkpoint_id": None if checkpoint is None else checkpoint.checkpoint_id,
            "checkpoint_root_sha256": None if checkpoint is None else checkpoint.root_sha256,
            "resume_checkpoint_id": None if resume_record is None else resume_record.checkpoint_id,
            "resume_checkpoint_root_sha256": None if resume_record is None else resume_record.root_sha256,
            "dependency_preflight_decision": dependency_assessment.decision,
            "resource_preflight_decision": resource_assessment.decision,
        },
    )
    return RuntimeResult(
        exit_code=exit_code,
        process_exit_code=process_exit_code,
        status=status,
        denied_event_count=denied_count,
        output_contract_valid=output_contract.valid,
        access_log_path=access_log_path,
        stdout_path=stdout_path,
        stderr_path=stderr_path,
        result_path=result_path,
        checkpoint_path=None if checkpoint is None else checkpoint.path,
        resume_checkpoint_path=None if resume_record is None else resume_record.path,
        dependency_preflight_path=dependency_preflight_path,
        resource_preflight_path=resource_preflight_path,
    )
