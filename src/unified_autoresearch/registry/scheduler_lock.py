"""Single-owner scheduler lock with conservative stale-lock recovery."""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import sys
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import psutil


class LockHeldError(RuntimeError):
    """Raised when another scheduler owns the lock."""


@contextmanager
def _exclusive_file_guard(path: Path):
    """Serialize all cooperative lock creation and recovery without stale guard state."""
    path.parent.mkdir(parents=True, exist_ok=True)
    stream = path.open("a+b")
    try:
        if path.stat().st_size == 0:
            stream.write(b"\0")
            stream.flush()
            os.fsync(stream.fileno())
        stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise LockHeldError("scheduler lock recovery is already in progress") from error
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
    finally:
        stream.close()


def _normalized_path(value: str | Path) -> str:
    return os.path.normcase(os.path.abspath(str(value)))


def _live_matching_process(metadata: dict[str, Any]) -> bool:
    try:
        process = psutil.Process(int(metadata["process_id"]))
        same_time = abs(process.create_time() - float(metadata["create_time"])) < 0.001
        same_executable = _normalized_path(process.exe()) == _normalized_path(metadata["executable_path"])
        return same_time and same_executable
    except (KeyError, TypeError, ValueError, psutil.Error, OSError):
        return False


class SchedulerLock:
    """Atomically create one lock and only remove the exact lock this object owns."""

    def __init__(self, path: str | Path, *, run_id: str, recover_stale: bool = False):
        self.path = Path(path).resolve()
        self.run_id = run_id
        self.recover_stale = recover_stale
        self._token: str | None = None

    def _metadata(self, token: str) -> dict[str, Any]:
        process = psutil.Process()
        return {
            "process_id": process.pid,
            "create_time": process.create_time(),
            "executable_path": process.exe() or sys.executable,
            "run_id": self.run_id,
            "token": token,
        }

    def _create(self, metadata: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
                json.dump(metadata, stream, indent=2, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
        except Exception:
            self.path.unlink(missing_ok=True)
            raise

    def acquire(self) -> dict[str, Any]:
        if self._token is not None:
            raise RuntimeError("scheduler lock instance is already acquired")
        token = secrets.token_hex(32)
        metadata = self._metadata(token)
        for _ in range(3):
            guard_path = self.path.with_name(f"{self.path.name}.recovery.guard")
            with _exclusive_file_guard(guard_path):
                try:
                    self._create(metadata)
                    self._token = token
                    return metadata
                except FileExistsError:
                    try:
                        existing_text = self.path.read_text(encoding="utf-8")
                        existing = json.loads(existing_text)
                    except (OSError, json.JSONDecodeError):
                        existing = {}
                        existing_text = ""
                    if not self.recover_stale:
                        raise LockHeldError("scheduler lock is held") from None
                    if _live_matching_process(existing):
                        raise LockHeldError("scheduler lock is held by a live matching process") from None
                    try:
                        if self.path.read_text(encoding="utf-8") != existing_text:
                            continue
                    except OSError:
                        continue
                    archive = self.path.with_name(f"{self.path.name}.stale.{uuid.uuid4().hex}.json")
                    try:
                        os.replace(self.path, archive)
                    except FileNotFoundError:
                        continue
                    try:
                        archived_text = archive.read_text(encoding="utf-8")
                        archived = json.loads(archived_text)
                    except (OSError, json.JSONDecodeError):
                        archived_text = ""
                        archived = {}
                    if archived_text != existing_text or _live_matching_process(archived):
                        if not self.path.exists():
                            os.replace(archive, self.path)
                        raise LockHeldError("scheduler lock changed during stale recovery")
        raise LockHeldError("scheduler lock changed repeatedly during stale recovery")

    def ownership_proof(self) -> dict[str, Any]:
        """Return a non-secret proof only while this object owns the live lock file."""
        if self._token is None:
            raise PermissionError("scheduler lock is not owned by this lock instance")
        try:
            metadata = json.loads(self.path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError) as error:
            raise PermissionError("owned scheduler lock is missing or corrupt") from error
        if metadata.get("token") != self._token or metadata.get("run_id") != self.run_id:
            raise PermissionError("scheduler lock identity no longer matches its owner")
        if not _live_matching_process(metadata):
            raise PermissionError("scheduler lock process identity no longer matches its owner")
        return {
            "lock_path": str(self.path),
            "process_id": int(metadata["process_id"]),
            "create_time": float(metadata["create_time"]),
            "executable_path": str(metadata["executable_path"]),
            "run_id": str(metadata["run_id"]),
            "token_sha256": hashlib.sha256(self._token.encode("ascii")).hexdigest(),
        }

    def release(self) -> None:
        self.ownership_proof()
        self.path.unlink()
        self._token = None

    def __enter__(self) -> "SchedulerLock":
        self.acquire()
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self.release()
