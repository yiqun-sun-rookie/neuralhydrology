"""Build a non-overwritable milestone evidence package and audit snapshot."""

from __future__ import annotations

import hashlib
import json
import os
import stat
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Iterable, Sequence

import psutil

from .registry.fingerprint import build_fingerprint, validate_fingerprint
from .registry.scheduler_lock import SchedulerLock
from .registry.store import Registry


def _canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


def _io_path(path: Path) -> str:
    absolute = str(path.resolve())
    if os.name != "nt" or absolute.startswith("\\\\?\\"):
        return absolute
    if absolute.startswith("\\\\"):
        return "\\\\?\\UNC\\" + absolute[2:]
    return "\\\\?\\" + absolute


def _path_from_io_path(path: str) -> Path:
    if os.name != "nt":
        return Path(path)
    if path.startswith("\\\\?\\UNC\\"):
        return Path("\\\\" + path[8:])
    if path.startswith("\\\\?\\"):
        return Path(path[4:])
    return Path(path)


def _walk_tree_long_path_safe(root: Path) -> tuple[list[Path], list[Path]]:
    files: list[Path] = []
    directories: list[Path] = []
    for directory, names, filenames in os.walk(_io_path(root)):
        directories.append(_path_from_io_path(directory))
        directories.extend(_path_from_io_path(os.path.join(directory, name)) for name in names)
        files.extend(_path_from_io_path(os.path.join(directory, name)) for name in filenames)
    return files, list(dict.fromkeys(directories))


def _snapshot_write_protection() -> dict[str, str]:
    if os.name != "nt":
        return {"mechanism": "posix_read_execute_modes", "identity": "process_user"}
    identity = subprocess.run(["whoami"], check=True, capture_output=True, text=True).stdout.strip()
    return {"mechanism": "windows_inheritable_deny_write_acl", "identity": identity}


def _deny_snapshot_writes(snapshot_root: Path, protection: dict[str, str]) -> None:
    if os.name != "nt":
        return
    result = subprocess.run(
        [
            "icacls",
            str(snapshot_root),
            "/deny",
            f"{protection['identity']}:(OI)(CI)(WD,AD,WEA,WA)",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"failed to apply snapshot write-deny ACL: {result.stdout}{result.stderr}")


def _write_bytes_exclusive(path: Path, content: bytes) -> None:
    os.makedirs(_io_path(path.parent), exist_ok=True)
    descriptor = os.open(_io_path(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        try:
            os.unlink(_io_path(path))
        except FileNotFoundError:
            pass
        raise


def _write_json_exclusive(path: Path, value: Any) -> None:
    _write_bytes_exclusive(path, _canonical_json(value))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(_io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _copy_file_exclusive(source: Path, destination: Path) -> None:
    os.makedirs(_io_path(destination.parent), exist_ok=True)
    descriptor = os.open(_io_path(destination), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    try:
        with open(_io_path(source), "rb") as input_stream, os.fdopen(descriptor, "wb") as output_stream:
            for block in iter(lambda: input_stream.read(1024 * 1024), b""):
                output_stream.write(block)
            output_stream.flush()
            os.fsync(output_stream.fileno())
    except Exception:
        try:
            os.unlink(_io_path(destination))
        except FileNotFoundError:
            pass
        raise


def _git(repo_root: Path, *args: str) -> bytes:
    return subprocess.run(
        ["git", *args], cwd=repo_root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout


def _inside(root: Path, path: Path) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise ValueError(f"path must be inside repository root: {resolved}") from error
    return resolved


def _expand_test_command(command: Sequence[str], *, junitxml: Path, artifact_root: Path) -> list[str]:
    replacements = {"junitxml": str(junitxml), "artifact_root": str(artifact_root)}
    return [argument.format(**replacements) for argument in command]


def _resource_snapshot(repo_root: Path, code_paths: Iterable[str | Path]) -> dict[str, Any]:
    code_bytes = 0
    for raw_path in code_paths:
        path = Path(raw_path)
        candidates = [path] if path.is_file() else path.rglob("*")
        code_bytes += sum(candidate.stat().st_size for candidate in candidates if candidate.is_file())
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage(str(repo_root))
    return {
        "schema_version": "resource_preflight_v1",
        "task_classification": "lightweight_tests_hashing_sqlite_and_copy",
        "fixed_memory_threshold_used": False,
        "source_bytes": code_bytes,
        "available_memory_bytes": memory.available,
        "disk_free_bytes": disk.free,
        "disk_total_bytes": disk.total,
        "decision": "execute",
        "decision_basis": "work consists of small tests, streaming SHA-256, SQLite records, and file copies",
    }


def _run_tests_before_final_root(
    *, repo_root: Path, test_command: Sequence[str], resource_snapshot: dict[str, Any]
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="unified-autoresearch-m1-repair1-") as temporary:
        staging = Path(temporary)
        staging_artifacts = staging / "artifacts"
        staging_artifacts.mkdir()
        junitxml = staging_artifacts / "test-results.xml"
        expanded = _expand_test_command(test_command, junitxml=junitxml, artifact_root=staging_artifacts)
        completed = subprocess.run(expanded, cwd=repo_root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if completed.returncode != 0:
            raise subprocess.CalledProcessError(
                completed.returncode, expanded, output=completed.stdout, stderr=completed.stderr
            )
        if not junitxml.is_file():
            raise RuntimeError("successful test command did not create the requested JUnit XML file")
        return {
            "files": {
                path.relative_to(staging_artifacts): path.read_bytes()
                for path in staging_artifacts.rglob("*")
                if path.is_file()
            },
            "stdout": completed.stdout,
            "stderr": completed.stderr,
            "command": {
                "schema_version": "test_command_v1",
                "template": list(test_command),
                "expanded": expanded,
                "working_directory": str(repo_root),
                "exit_code": completed.returncode,
            },
            "resource_snapshot": resource_snapshot,
        }


def _copy_test_evidence(test_evidence: dict[str, Any], artifact_root: Path) -> None:
    for relative, content in test_evidence["files"].items():
        _write_bytes_exclusive(artifact_root / relative, content)
    _write_bytes_exclusive(artifact_root / "test-stdout.bin", test_evidence["stdout"])
    _write_bytes_exclusive(artifact_root / "test-stderr.bin", test_evidence["stderr"])
    _write_json_exclusive(artifact_root / "test-command.json", test_evidence["command"])
    _write_json_exclusive(artifact_root / "resource-preflight.json", test_evidence["resource_snapshot"])


def _manifest_lines(root: Path, paths: Iterable[Path]) -> bytes:
    entries = []
    for path in sorted({path.resolve() for path in paths}, key=lambda item: item.relative_to(root).as_posix()):
        entries.append(f"{_sha256_file(path)} *{path.relative_to(root).as_posix()}")
    return ("\n".join(entries) + "\n").encode("utf-8")


def _fingerprinted_paths(fingerprint: dict[str, Any], repo_root: Path) -> set[Path]:
    details = fingerprint["details"]
    manifests = [
        details["code"],
        details["configuration"],
        details["data_manifest"],
        details["artifacts"],
        details["dependencies"]["files"],
        details["uncommitted_diff"]["untracked_manifest"],
    ]
    return {repo_root / entry["path"] for manifest in manifests for entry in manifest}


def _verify_manifest_entries(fingerprint: dict[str, Any], repo_root: Path) -> None:
    details = fingerprint["details"]
    manifests = [
        details["code"],
        details["configuration"],
        details["data_manifest"],
        details["artifacts"],
        details["dependencies"]["files"],
        details["uncommitted_diff"]["untracked_manifest"],
    ]
    for manifest in manifests:
        for entry in manifest:
            path = repo_root / entry["path"]
            if os.stat(_io_path(path)).st_size != entry["bytes"] or _sha256_file(path) != entry["sha256"]:
                raise RuntimeError(f"fingerprint manifest mismatch: {entry['path']}")


def write_package_manifest(*, repo_root: str | Path, run_root: str | Path) -> Path:
    """Write one exclusive package manifest from a long-path-safe physical file set."""
    repo = Path(repo_root).resolve()
    run = _inside(repo, Path(run_root))
    package_manifest = run / "PACKAGE_MANIFEST.sha256"
    if package_manifest.exists():
        raise FileExistsError(package_manifest)
    package_files, _ = _walk_tree_long_path_safe(run)
    _write_bytes_exclusive(package_manifest, _manifest_lines(repo, package_files))
    return package_manifest


def _make_snapshot(
    *, repo_root: Path, run_root: Path, snapshot_parent: Path, fingerprint: dict[str, Any]
) -> Path:
    root_sha256 = fingerprint["root_sha256"]
    snapshot_label = run_root.name.replace("milestone1", "m1", 1)
    snapshot_root = snapshot_parent / f"{snapshot_label}_{root_sha256[:16]}_clean"
    snapshot_parent.mkdir(parents=True, exist_ok=True)
    snapshot_root.mkdir(exist_ok=False)

    source_paths = _fingerprinted_paths(fingerprint, repo_root)
    run_files, _ = _walk_tree_long_path_safe(run_root)
    source_paths.update(run_files)
    for source in sorted(source_paths, key=lambda item: item.relative_to(repo_root).as_posix()):
        relative = source.relative_to(repo_root)
        destination = snapshot_root / relative
        _copy_file_exclusive(source, destination)

    package_manifest = run_root / "PACKAGE_MANIFEST.sha256"
    write_protection = _snapshot_write_protection()
    metadata = {
        "schema_version": "audit_snapshot_v2",
        "fingerprint_root_sha256": root_sha256,
        "source_git_commit": fingerprint["details"]["git_commit"],
        "source_run_root": run_root.relative_to(repo_root).as_posix(),
        "copied_file_count": len(source_paths),
        "package_manifest_sha256": _sha256_file(package_manifest),
        "sealed_final_evaluation_mounted": False,
        "write_protection": write_protection,
    }
    _write_json_exclusive(snapshot_root / "SNAPSHOT.json", metadata)
    snapshot_files, _ = _walk_tree_long_path_safe(snapshot_root)
    _write_bytes_exclusive(
        snapshot_root / "SNAPSHOT_MANIFEST.sha256", _manifest_lines(snapshot_root, snapshot_files)
    )

    snapshot_files, snapshot_directories = _walk_tree_long_path_safe(snapshot_root)
    for path in snapshot_files:
        os.chmod(_io_path(path), stat.S_IREAD)
    for path in sorted(snapshot_directories, key=lambda item: len(item.parts), reverse=True):
        os.chmod(_io_path(path), stat.S_IREAD | stat.S_IEXEC)
    os.chmod(_io_path(snapshot_root), stat.S_IREAD | stat.S_IEXEC)
    _deny_snapshot_writes(snapshot_root, write_protection)
    return snapshot_root


def build_milestone1_repair1(
    *,
    repo_root: str | Path,
    run_root: str | Path,
    snapshot_parent: str | Path,
    test_command: Sequence[str],
    code_paths: Iterable[str | Path],
    configuration_paths: Iterable[str | Path],
    dependency_paths: Iterable[str | Path],
    data_manifest_paths: Iterable[str | Path],
    random_seeds: list[int],
    additional_artifact_paths: Iterable[str | Path] = (),
) -> dict[str, str]:
    """Generate the milestone evidence once; never replace a final root or snapshot."""
    repo = Path(repo_root).resolve()
    final_root = _inside(repo, Path(run_root))
    snapshots = _inside(repo, Path(snapshot_parent))
    if final_root.exists():
        raise FileExistsError(final_root)

    code = tuple(code_paths)
    configurations = tuple(configuration_paths)
    dependencies = tuple(dependency_paths)
    data_manifests = tuple(data_manifest_paths)
    additional_artifacts = tuple(_inside(repo, Path(path)) for path in additional_artifact_paths)
    repair_round = final_root.name
    milestone = repair_round.split("_", 1)[0]
    if not milestone.startswith("milestone") or not milestone.removeprefix("milestone").isdigit():
        raise ValueError(f"run root name does not start with a milestone identity: {repair_round}")
    round_id = repair_round.replace("_", "-")
    resource_snapshot = _resource_snapshot(repo, code)
    test_evidence = _run_tests_before_final_root(
        repo_root=repo, test_command=test_command, resource_snapshot=resource_snapshot
    )

    final_root.mkdir(parents=True, exist_ok=False)
    artifact_root = final_root / "artifacts"
    artifact_root.mkdir()
    _copy_test_evidence(test_evidence, artifact_root)

    diff = _git(repo, "diff", "--binary", "HEAD", "--", ".")
    status = _git(repo, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    _write_bytes_exclusive(artifact_root / "git-diff.bin", diff)
    _write_bytes_exclusive(artifact_root / "git-status.bin", status)

    registry_root = final_root / "registry"
    registry = Registry(
        registry_root / "registry.sqlite",
        scheduler_lock_path=registry_root / "scheduler.lock",
        receipt_dir=registry_root / "receipts",
    )
    candidate = registry.append_candidate(
        f"{round_id}-selfcheck",
        {
            "category": "registry_selfcheck",
            "entrypoint": "unified_autoresearch.evidence_package",
            "purpose": f"{repair_round} evidence",
        },
    )
    experiment_id = f"{round_id}-selfcheck-run1"
    registry.append_experiment(
        experiment_id,
        {"candidate_record_id": candidate, "protocol": repair_round, "seed": random_seeds[0]},
    )
    registry.transition(experiment_id, expected_from=None, to_state="registered", reason="definition appended")
    registry.transition(
        experiment_id, expected_from="registered", to_state="validated", reason="evidence contract valid"
    )
    registry.transition(experiment_id, expected_from="validated", to_state="queued", reason="ready for scheduler")

    scheduler = SchedulerLock(registry.scheduler_lock_path, run_id=f"{round_id}-scheduler")
    with scheduler:
        registry.transition(
            experiment_id,
            expected_from="queued",
            to_state="running",
            reason="real scheduler lock acquired",
            scheduler_lock=scheduler,
        )
        _write_json_exclusive(artifact_root / "scheduler-lock-proof.json", scheduler.ownership_proof())
        fingerprint = build_fingerprint(
            repo_root=repo,
            code_paths=code,
            configuration_paths=configurations,
            dependency_paths=dependencies,
            data_manifest_paths=data_manifests,
            random_seeds=random_seeds,
            artifact_paths=[artifact_root, *additional_artifacts],
        )
        registry.append_fingerprint(f"{experiment_id}/final", fingerprint)
        registry.transition(
            experiment_id,
            expected_from="running",
            to_state="succeeded",
            reason="tests and fingerprint completed",
            scheduler_lock=scheduler,
        )

    validate_fingerprint(fingerprint)
    _verify_manifest_entries(fingerprint, repo)
    uncommitted = fingerprint["details"]["uncommitted_diff"]
    if hashlib.sha256(diff).hexdigest() != uncommitted["git_diff_sha256"]:
        raise RuntimeError("saved Git diff bytes do not match fingerprint")
    if hashlib.sha256(status).hexdigest() != uncommitted["git_status_sha256"]:
        raise RuntimeError("saved Git status bytes do not match fingerprint")

    verification = registry.verify()
    if verification != {"record_count": 8, "failure_count": 0, "failures": []}:
        raise RuntimeError(f"registry verification failed: {verification}")
    _write_json_exclusive(final_root / "fingerprint.json", fingerprint)
    _write_json_exclusive(final_root / "registry-verification.json", verification)
    _write_json_exclusive(final_root / "registry-records.json", registry.records())
    _write_json_exclusive(
        final_root / "RUN_METADATA.json",
        {
            "schema_version": f"{milestone}_evidence_run_v1",
            "milestone": milestone,
            "repair_round": repair_round,
            "fingerprint_root_sha256": fingerprint["root_sha256"],
            "experiment_id": experiment_id,
            "artifact_root": artifact_root.relative_to(repo).as_posix(),
            "scheduler_lock_path": registry.scheduler_lock_path.relative_to(repo).as_posix(),
            "receipt_dir": registry.receipt_dir.relative_to(repo).as_posix(),
            "record_count": verification["record_count"],
            "final_state": registry.current_state(experiment_id),
            "final_evaluation_data_read_or_scored": False,
            "fair_benchmark_scoring_program_run": False,
            "formal_basin_search_run": False,
        },
    )
    write_package_manifest(repo_root=repo, run_root=final_root)

    snapshot_root = _make_snapshot(
        repo_root=repo, run_root=final_root, snapshot_parent=snapshots, fingerprint=fingerprint
    )
    return {
        "run_root": str(final_root),
        "snapshot_root": str(snapshot_root),
        "root_sha256": fingerprint["root_sha256"],
    }
