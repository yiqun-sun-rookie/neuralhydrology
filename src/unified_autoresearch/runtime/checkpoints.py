"""Validate and atomically publish candidate-staged checkpoints."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Any


CHECKPOINT_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
REQUEST_FIELDS = {
    "schema_version",
    "checkpoint_id",
    "candidate_id",
    "mode",
    "parent_checkpoint_id",
    "files",
}
_UNSET = object()


def _strip_windows_extended_prefix(value: str) -> str:
    if value.startswith("\\\\?\\UNC\\"):
        return "\\\\" + value[8:]
    if value.startswith("\\\\?\\"):
        return value[4:]
    return value


def _path_for_io(path: str | Path, *, reserved_suffix_characters: int = 0) -> Path:
    """Return a Windows extended path before the legacy limit can affect child I/O."""
    raw = str(path)
    if os.name == "nt" and raw.startswith("\\\\?\\"):
        return Path(raw)
    absolute = str(Path(path).resolve())
    if os.name != "nt" or len(absolute) + reserved_suffix_characters < 260:
        return Path(absolute)
    if absolute.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + absolute[2:])
    return Path("\\\\?\\" + absolute)


@dataclass(frozen=True)
class CheckpointRecord:
    checkpoint_id: str
    candidate_id: str
    mode: str
    parent_checkpoint_id: str | None
    root_sha256: str
    path: Path


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False
    ).encode("utf-8")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_relative_path(value: str) -> Path:
    path = Path(value)
    if not value or path.is_absolute() or ".." in path.parts or path == Path("."):
        raise ValueError(f"checkpoint payload path is unsafe: {value!r}")
    return path


def _load_and_validate_request(root: Path) -> dict[str, Any]:
    request_path = root / "CHECKPOINT_REQUEST.json"
    if not request_path.is_file():
        raise ValueError("checkpoint request is missing")
    try:
        request = json.loads(request_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("checkpoint request is unreadable") from error
    if not isinstance(request, dict) or set(request) != REQUEST_FIELDS:
        raise ValueError("checkpoint request fields are invalid")
    if request["schema_version"] != "checkpoint_request_v1":
        raise ValueError("checkpoint request schema mismatch")
    if (
        not isinstance(request["checkpoint_id"], str)
        or CHECKPOINT_ID_PATTERN.fullmatch(request["checkpoint_id"]) is None
    ):
        raise ValueError("checkpoint identifier is invalid")
    if request["mode"] not in {"train", "predict"}:
        raise ValueError("checkpoint mode is invalid")
    if not isinstance(request["files"], dict) or not request["files"]:
        raise ValueError("checkpoint payload manifest is empty")
    expected_paths: dict[str, str] = {}
    for name, digest in request["files"].items():
        if not isinstance(name, str) or not isinstance(digest, str) or len(digest) != 64:
            raise ValueError("checkpoint payload manifest is invalid")
        relative = _safe_relative_path(name)
        expected_paths[relative.as_posix()] = digest
    physical_paths = {
        path.relative_to(root).as_posix(): path
        for path in root.rglob("*")
        if path.is_file() and path.name not in {"CHECKPOINT_REQUEST.json", "CHECKPOINT_VERIFIED.json"}
    }
    if set(physical_paths) != set(expected_paths):
        raise ValueError("checkpoint payload manifest does not match staged files")
    for name, path in physical_paths.items():
        if path.is_symlink():
            raise ValueError("checkpoint payload cannot contain symbolic links")
        if _sha256_file(path) != expected_paths[name]:
            raise ValueError(f"checkpoint payload hash mismatch: {name}")
    request["files"] = expected_paths
    return request


def _record_from_request(path: Path, request: dict[str, Any]) -> CheckpointRecord:
    root_sha256 = hashlib.sha256(
        _canonical_bytes(
            {
                "schema_version": "checkpoint_verified_v1",
                "checkpoint_id": request["checkpoint_id"],
                "candidate_id": request["candidate_id"],
                "mode": request["mode"],
                "parent_checkpoint_id": request["parent_checkpoint_id"],
                "files": request["files"],
            }
        )
    ).hexdigest()
    return CheckpointRecord(
        checkpoint_id=request["checkpoint_id"],
        candidate_id=request["candidate_id"],
        mode=request["mode"],
        parent_checkpoint_id=request["parent_checkpoint_id"],
        root_sha256=root_sha256,
        path=Path(_strip_windows_extended_prefix(str(path))).resolve(),
    )


def _write_verified_record(path: Path, record: CheckpointRecord, files: dict[str, str]) -> None:
    value = {
        "schema_version": "checkpoint_verified_v1",
        "checkpoint_id": record.checkpoint_id,
        "candidate_id": record.candidate_id,
        "mode": record.mode,
        "parent_checkpoint_id": record.parent_checkpoint_id,
        "files": files,
        "root_sha256": record.root_sha256,
    }
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(_canonical_bytes(value) + b"\n")
        stream.flush()
        os.fsync(stream.fileno())


def promote_staged_checkpoint(
    staging_root: str | Path,
    checkpoints_root: str | Path,
    *,
    expected_candidate_id: str | None = None,
    expected_mode: str | None = None,
    expected_parent_checkpoint_id: str | None | object = _UNSET,
) -> CheckpointRecord:
    """Validate a stopped candidate's staging tree and publish it once."""
    staging = _path_for_io(staging_root, reserved_suffix_characters=len("CHECKPOINT_VERIFIED.json") + 1)
    checkpoints = Path(checkpoints_root).resolve()
    request = _load_and_validate_request(staging)
    if expected_candidate_id is not None and request["candidate_id"] != expected_candidate_id:
        raise ValueError("checkpoint candidate identity mismatch")
    if expected_mode is not None and request["mode"] != expected_mode:
        raise ValueError("checkpoint mode mismatch")
    if (
        expected_parent_checkpoint_id is not _UNSET
        and request["parent_checkpoint_id"] != expected_parent_checkpoint_id
    ):
        raise ValueError("checkpoint parent reference mismatch")
    target = _path_for_io(
        checkpoints / request["checkpoint_id"],
        reserved_suffix_characters=len("CHECKPOINT_VERIFIED.json") + 1,
    )
    publication_guard = _path_for_io(checkpoints / f".{request['checkpoint_id']}.publishing")
    guard_descriptor = os.open(publication_guard, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(guard_descriptor)
    try:
        if os.path.exists(target):
            raise FileExistsError(f"checkpoint version already exists: {target}")
        record = _record_from_request(target, request)
        _write_verified_record(staging / "CHECKPOINT_VERIFIED.json", record, request["files"])
        os.replace(staging, target)
        for path in target.rglob("*"):
            if path.is_file():
                path.chmod(stat.S_IREAD)
        return record
    finally:
        publication_guard.unlink(missing_ok=True)


def verify_checkpoint(path: str | Path, *, expected_candidate_id: str | None = None) -> CheckpointRecord:
    """Recompute a published checkpoint's request, payload hashes, and verified record."""
    root = _path_for_io(path, reserved_suffix_characters=len("CHECKPOINT_VERIFIED.json") + 1)
    request = _load_and_validate_request(root)
    record = _record_from_request(root, request)
    if expected_candidate_id is not None and record.candidate_id != expected_candidate_id:
        raise ValueError("checkpoint candidate identity mismatch")
    verified_path = root / "CHECKPOINT_VERIFIED.json"
    if not verified_path.is_file():
        raise ValueError("checkpoint verified record is missing")
    verified = json.loads(verified_path.read_text(encoding="utf-8"))
    expected = {
        "schema_version": "checkpoint_verified_v1",
        "checkpoint_id": record.checkpoint_id,
        "candidate_id": record.candidate_id,
        "mode": record.mode,
        "parent_checkpoint_id": record.parent_checkpoint_id,
        "files": request["files"],
        "root_sha256": record.root_sha256,
    }
    if verified != expected:
        raise ValueError("checkpoint verified record mismatch")
    return record


def mount_verified_checkpoint(
    run_root: str | Path,
    checkpoint_path: str | Path,
    *,
    expected_candidate_id: str,
) -> CheckpointRecord:
    """Copy one verified checkpoint into a new run root as a read-only resume input."""
    source_record = verify_checkpoint(checkpoint_path, expected_candidate_id=expected_candidate_id)
    target_logical = Path(run_root).resolve() / "resume_checkpoint"
    target = _path_for_io(
        target_logical,
        reserved_suffix_characters=len("CHECKPOINT_VERIFIED.json") + 1,
    )
    if os.path.exists(target):
        raise FileExistsError(f"resume checkpoint mount already exists: {target}")
    source = _path_for_io(
        source_record.path,
        reserved_suffix_characters=len("CHECKPOINT_VERIFIED.json") + 1,
    )
    shutil.copytree(source, target)
    mounted_record = verify_checkpoint(target_logical, expected_candidate_id=expected_candidate_id)
    if mounted_record.root_sha256 != source_record.root_sha256:
        raise ValueError("mounted resume checkpoint root hash mismatch")
    for path in target.rglob("*"):
        if path.is_file():
            path.chmod(stat.S_IREAD)
    return mounted_record
