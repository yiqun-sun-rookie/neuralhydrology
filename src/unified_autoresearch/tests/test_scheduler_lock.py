import json
import os
import sys
from pathlib import Path

import psutil
import pytest


def test_only_one_scheduler_can_hold_the_lock_and_foreign_release_is_rejected(tmp_path):
    from unified_autoresearch.registry.scheduler_lock import LockHeldError, SchedulerLock

    path = tmp_path / "scheduler.lock"
    owner = SchedulerLock(path, run_id="run-owner")
    owner.acquire()
    metadata = json.loads(path.read_text(encoding="utf-8"))
    assert metadata["process_id"] == os.getpid()
    assert metadata["run_id"] == "run-owner"
    assert Path(metadata["executable_path"]).resolve() == Path(sys.executable).resolve()
    assert metadata["create_time"] == pytest.approx(psutil.Process().create_time())

    contender = SchedulerLock(path, run_id="run-contender")
    with pytest.raises(LockHeldError, match="scheduler lock is held"):
        contender.acquire()
    with pytest.raises(PermissionError, match="not owned by this lock instance"):
        contender.release()
    assert path.exists()

    owner.release()
    assert not path.exists()


def test_stale_lock_is_archived_before_automatic_recovery(tmp_path):
    from unified_autoresearch.registry.scheduler_lock import SchedulerLock

    path = tmp_path / "scheduler.lock"
    stale = {
        "process_id": 999999,
        "create_time": 0.0,
        "executable_path": "C:/missing/python.exe",
        "run_id": "stale-run",
        "token": "stale-token",
    }
    path.write_text(json.dumps(stale), encoding="utf-8")

    recovered = SchedulerLock(path, run_id="new-run", recover_stale=True)
    recovered.acquire()
    archives = list(tmp_path.glob("scheduler.lock.stale.*.json"))
    assert len(archives) == 1
    assert json.loads(archives[0].read_text(encoding="utf-8")) == stale
    assert json.loads(path.read_text(encoding="utf-8"))["run_id"] == "new-run"
    recovered.release()


def test_live_matching_process_lock_is_never_automatically_recovered(tmp_path):
    from unified_autoresearch.registry.scheduler_lock import LockHeldError, SchedulerLock

    process = psutil.Process()
    path = tmp_path / "scheduler.lock"
    path.write_text(
        json.dumps({
            "process_id": process.pid,
            "create_time": process.create_time(),
            "executable_path": process.exe(),
            "run_id": "other-live-run",
            "token": "other-token",
        }),
        encoding="utf-8",
    )

    with pytest.raises(LockHeldError, match="scheduler lock is held by a live matching process"):
        SchedulerLock(path, run_id="new-run", recover_stale=True).acquire()
    assert json.loads(path.read_text(encoding="utf-8"))["token"] == "other-token"


def test_stale_recovery_does_not_archive_a_live_lock_inserted_at_the_replace_boundary(tmp_path, monkeypatch):
    import unified_autoresearch.registry.scheduler_lock as scheduler_lock_module
    from unified_autoresearch.registry.scheduler_lock import LockHeldError, SchedulerLock

    path = tmp_path / "scheduler.lock"
    path.write_text(
        json.dumps({
            "process_id": 999999,
            "create_time": 0.0,
            "executable_path": "C:/missing/python.exe",
            "run_id": "stale-run",
            "token": "stale-token",
        }),
        encoding="utf-8",
    )
    process = psutil.Process()
    live = {
        "process_id": process.pid,
        "create_time": process.create_time(),
        "executable_path": process.exe(),
        "run_id": "live-run",
        "token": "live-token",
    }
    real_replace = os.replace
    injected = False

    def replace_with_boundary_injection(source, destination):
        nonlocal injected
        if not injected and Path(source) == path and ".stale." in Path(destination).name:
            injected = True
            replacement = tmp_path / "live-replacement.json"
            replacement.write_text(json.dumps(live), encoding="utf-8")
            real_replace(replacement, path)
        return real_replace(source, destination)

    monkeypatch.setattr(scheduler_lock_module.os, "replace", replace_with_boundary_injection)
    with pytest.raises(LockHeldError, match="changed during stale recovery"):
        SchedulerLock(path, run_id="recovering-run", recover_stale=True).acquire()

    assert injected
    assert json.loads(path.read_text(encoding="utf-8")) == live
