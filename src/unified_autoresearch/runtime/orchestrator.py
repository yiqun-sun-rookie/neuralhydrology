"""Bind one real candidate execution to its run-scoped registry and fingerprint."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

from unified_autoresearch.registry.fingerprint import build_fingerprint, validate_fingerprint
from unified_autoresearch.registry.scheduler_lock import SchedulerLock
from unified_autoresearch.registry.store import Registry

from .descriptor import CandidateDescriptor
from .layout import RunLayout
from .resources import ResourceSnapshot
from .runner import RuntimeResult, run_candidate


@dataclass(frozen=True)
class RegisteredRuntimeResult:
    run_id: str
    runtime_result: RuntimeResult
    fingerprint: dict[str, Any]
    fingerprint_path: Path
    registry_path: Path
    scheduler_lock_path: Path
    receipt_dir: Path


def _write_json_exclusive(path: Path, value: dict[str, Any]) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def _write_bytes_exclusive(path: Path, value: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(value)
        stream.flush()
        os.fsync(stream.fileno())


def _capture_git_state(repo: Path, log_root: Path) -> tuple[Path, Path]:
    diff_path = log_root / "git-diff.bin"
    status_path = log_root / "git-status.bin"
    diff = subprocess.run(
        ["git", "diff", "--binary", "HEAD", "--", "."],
        cwd=repo,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    status = subprocess.run(
        ["git", "status", "--porcelain", "-z", "--untracked-files=all"],
        cwd=repo,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    _write_bytes_exclusive(diff_path, diff)
    _write_bytes_exclusive(status_path, status)
    return diff_path, status_path


def _inside(root: Path, path: Path) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise ValueError(f"registered run path is outside repository root: {resolved}") from error
    return resolved


def _build_and_record_fingerprint(
    *,
    repo: Path,
    registry: Registry,
    descriptor: CandidateDescriptor,
    layout: RunLayout,
    run_id: str,
    fingerprint_path: Path,
    code_paths: Iterable[str | Path],
    configuration_paths: Iterable[str | Path],
    dependency_paths: Iterable[str | Path],
    data_manifest_paths: Iterable[str | Path],
) -> dict[str, Any]:
    code_paths = tuple(code_paths)
    configuration_paths = tuple(configuration_paths)
    dependency_paths = tuple(dependency_paths)
    data_manifest_paths = tuple(data_manifest_paths)
    runtime_input_paths = [layout.input_root]
    resume_root = layout.root / "resume_checkpoint"
    if resume_root.is_dir():
        runtime_input_paths.append(resume_root)
    git_diff_path, git_status_path = _capture_git_state(repo, layout.log_root)
    scoped_untracked_paths = [
        *code_paths,
        layout.candidate_root,
        *configuration_paths,
        layout.descriptor_path,
        *dependency_paths,
        *data_manifest_paths,
        *runtime_input_paths,
    ]
    fingerprint = build_fingerprint(
        repo_root=repo,
        code_paths=[*code_paths, layout.candidate_root],
        configuration_paths=[*configuration_paths, layout.descriptor_path],
        dependency_paths=dependency_paths,
        data_manifest_paths=[*data_manifest_paths, *runtime_input_paths],
        random_seeds=[descriptor.seed],
        artifact_paths=[layout.output_root, layout.log_root, layout.checkpoints_root],
        git_diff_path=git_diff_path,
        git_status_path=git_status_path,
        untracked_scope_paths=scoped_untracked_paths,
    )
    validate_fingerprint(fingerprint)
    _write_json_exclusive(fingerprint_path, fingerprint)
    registry.append_fingerprint(f"{run_id}/final", fingerprint)
    return fingerprint


def run_registered_candidate(
    *,
    repo_root: str | Path,
    descriptor: CandidateDescriptor,
    layout: RunLayout,
    mode: str,
    run_id: str,
    code_paths: Iterable[str | Path],
    configuration_paths: Iterable[str | Path],
    dependency_paths: Iterable[str | Path],
    data_manifest_paths: Iterable[str | Path],
    resume_checkpoint: str | Path | None = None,
    resource_snapshot: ResourceSnapshot | None = None,
    monitor_sample_interval_seconds: float | None = None,
) -> RegisteredRuntimeResult:
    """Run once under a real scheduler lock and append the complete lifecycle."""
    repo = Path(repo_root).resolve()
    run_root = _inside(repo, layout.root)
    registry_root = run_root / "registry"
    fingerprint_path = run_root / "fingerprint.json"
    if registry_root.exists() or fingerprint_path.exists():
        raise FileExistsError("registered run evidence already exists")

    registry = Registry(
        registry_root / "registry.sqlite",
        scheduler_lock_path=registry_root / "scheduler.lock",
        receipt_dir=registry_root / "receipts",
    )
    descriptor_bytes = layout.descriptor_path.read_bytes()
    candidate_record_id = registry.append_candidate(
        descriptor.candidate_id,
        {
            "candidate_id": descriptor.candidate_id,
            "category": descriptor.category,
            "descriptor": asdict(descriptor),
            "descriptor_sha256": hashlib.sha256(descriptor_bytes).hexdigest(),
        },
    )
    registry.append_experiment(
        run_id,
        {
            "candidate_record_id": candidate_record_id,
            "candidate_id": descriptor.candidate_id,
            "mode": mode,
            "run_root": run_root.relative_to(repo).as_posix(),
            "seed": descriptor.seed,
        },
    )
    registry.transition(run_id, expected_from=None, to_state="registered", reason="run definition appended")
    registry.transition(run_id, expected_from="registered", to_state="validated", reason="runtime contract valid")
    registry.transition(run_id, expected_from="validated", to_state="queued", reason="ready for scheduler")

    scheduler = SchedulerLock(registry.scheduler_lock_path, run_id=run_id)
    with scheduler:
        registry.transition(
            run_id,
            expected_from="queued",
            to_state="running",
            reason="real scheduler lock acquired for candidate execution",
            scheduler_lock=scheduler,
        )
        try:
            runtime_result = run_candidate(
                descriptor=descriptor,
                layout=layout,
                mode=mode,
                resume_checkpoint=resume_checkpoint,
                resource_snapshot=resource_snapshot,
                monitor_sample_interval_seconds=monitor_sample_interval_seconds,
            )
        except Exception as error:
            _write_json_exclusive(
                layout.log_root / "orchestration-error.json",
                {
                    "schema_version": "registered_run_error_v1",
                    "error_type": type(error).__name__,
                    "error_message": str(error),
                    "run_id": run_id,
                },
            )
            _build_and_record_fingerprint(
                repo=repo,
                registry=registry,
                descriptor=descriptor,
                layout=layout,
                run_id=run_id,
                fingerprint_path=fingerprint_path,
                code_paths=code_paths,
                configuration_paths=configuration_paths,
                dependency_paths=dependency_paths,
                data_manifest_paths=data_manifest_paths,
            )
            registry.transition(
                run_id,
                expected_from="running",
                to_state="failed",
                reason=f"candidate orchestration raised {type(error).__name__}; logs fingerprinted",
                scheduler_lock=scheduler,
            )
            raise
        terminal_state = {
            "succeeded": "succeeded",
            "checkpointed": "checkpointed",
            "runtime_failure": "failed",
            "contract_failure": "failed",
        }.get(runtime_result.status)
        if terminal_state is None:
            raise RuntimeError(f"unsupported registered runtime status: {runtime_result.status!r}")
        fingerprint = _build_and_record_fingerprint(
            repo=repo,
            registry=registry,
            descriptor=descriptor,
            layout=layout,
            run_id=run_id,
            fingerprint_path=fingerprint_path,
            code_paths=code_paths,
            configuration_paths=configuration_paths,
            dependency_paths=dependency_paths,
            data_manifest_paths=data_manifest_paths,
        )
        registry.transition(
            run_id,
            expected_from="running",
            to_state=terminal_state,
            reason=f"candidate status {runtime_result.status}; outputs and logs fingerprinted",
            scheduler_lock=scheduler,
        )

    verification = registry.verify()
    if verification != {"record_count": 8, "failure_count": 0, "failures": []}:
        raise RuntimeError(f"registered run verification failed: {verification}")
    return RegisteredRuntimeResult(
        run_id=run_id,
        runtime_result=runtime_result,
        fingerprint=fingerprint,
        fingerprint_path=fingerprint_path,
        registry_path=registry.path,
        scheduler_lock_path=registry.scheduler_lock_path,
        receipt_dir=registry.receipt_dir,
    )
