#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -I - <<'SHARED_RELEASE_VERIFIED_PY'
"""Standard-library compute bootstrap with authenticated, descriptor-bound logs.

The reviewed submission script embeds this verified source and fixed deployment
identity. Slurm itself writes only to /dev/null, never to an experiment path.
"""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import re
import runpy
import stat
import sys
import traceback

REMOTE_ROOT = "/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001"
CORE_REL = "runtime/inbox/zhenjiang-six-source-four-target-ukf/shared_base_20260916_001"
STAGES = ("preflight", "train", "evaluate")
LOG_LIMIT = 65536

def safe_name(name):
    if (not isinstance(name, str) or name.startswith("/") or "\\" in name or ":" in name
            or any(p in ("", ".", "..") for p in name.split("/"))):
        raise ValueError("fixed relative source name required")
    return name.split("/")

class Root:
    def __init__(self, root, expected):
        self.root = Path(root)
        self.root_fd = self.parent_fd = None
        self.authenticated = False
        if str(self.root) != REMOTE_ROOT or type(expected) is not dict or set(expected) != {
                "schema", "deployment_token", "root_binding", "metadata_sha256"}:
            raise ValueError("fixed compute root and deployment required")
        stable = expected["root_binding"]
        if (expected["schema"] != "cross-node-deployment-v1" or type(stable) is not dict
                or set(stable) != {"inode", "uid", "mode"}
                or any(type(v) is not int for v in stable.values())
                or stable["inode"] <= 0 or stable["uid"] < 0 or stable["mode"] != 0o700
                or not re.fullmatch("[0-9a-f]{32}", expected.get("deployment_token", ""))
                or not re.fullmatch("[0-9a-f]{64}", expected.get("metadata_sha256", ""))):
            raise ValueError("compute deployment identity schema differs")
        self.expected = expected
        self.safe(self.root)
        self.root_meta = self.root.stat()
        self.parent_meta = self.root.parent.stat()
        if (not stat.S_ISDIR(self.root_meta.st_mode) or
                {"inode": self.root_meta.st_ino, "uid": self.root_meta.st_uid,
                 "mode": stat.S_IMODE(self.root_meta.st_mode)} != stable):
            raise ValueError("compute root inode, owner or mode differs")
        if os.name == "posix":
            flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
            self.parent_fd = os.open("/", flags)
            try:
                for part in self.root.parent.parts[1:]:
                    child = os.open(part, flags, dir_fd=self.parent_fd)
                    os.close(self.parent_fd)
                    self.parent_fd = child
                self.root_fd = os.open(self.root.name, flags, dir_fd=self.parent_fd)
                self.check()
            except BaseException:
                self.close()
                raise

    def safe(self, path):
        for item in (path, *path.parents):
            value = item.lstat()
            if stat.S_ISLNK(value.st_mode) or getattr(value, "st_file_attributes", 0) & 0x400:
                raise ValueError("linked compute path")

    def check(self):
        self.safe(self.root)
        for path, saved, fd in ((self.root, self.root_meta, self.root_fd),
                                (self.root.parent, self.parent_meta, self.parent_fd)):
            visible = path.stat()
            if (visible.st_dev, visible.st_ino) != (saved.st_dev, saved.st_ino):
                raise ValueError("local compute root or parent changed")
            if fd is not None:
                opened = os.fstat(fd)
                if (opened.st_dev, opened.st_ino) != (saved.st_dev, saved.st_ino):
                    raise ValueError("local compute directory handle changed")

    def child_fd(self, parts):
        fd = os.dup(self.root_fd)
        try:
            for part in parts:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                os.close(fd)
                fd = child
            return fd
        except BaseException:
            os.close(fd)
            raise

    def read(self, name, maximum=2000000, expected=None):
        parts = safe_name(name)
        self.check()
        self.safe(self.root / name)
        parent_fd = self.child_fd(parts[:-1]) if self.root_fd is not None else None
        try:
            target = parts[-1] if parent_fd is not None else self.root / name
            extra = {"dir_fd": parent_fd} if parent_fd is not None else {}
            fd = os.open(target, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
                         | getattr(os, "O_BINARY", 0), **extra)
            with os.fdopen(fd, "rb", buffering=0) as handle:
                before = os.fstat(handle.fileno())
                if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or not 0 < before.st_size <= maximum:
                    raise ValueError("compute source size or type differs")
                raw = handle.read(maximum + 1)
                after = os.fstat(handle.fileno())
            self.check()
            self.safe(self.root / name)
            visible = (self.root / name).stat()
            if ((visible.st_dev, visible.st_ino) != (before.st_dev, before.st_ino)
                    or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) !=
                    (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                    or len(raw) != before.st_size):
                raise ValueError("compute source changed while reading")
            if parent_fd is not None:
                shown, opened = (self.root / name).parent.stat(), os.fstat(parent_fd)
                if (shown.st_dev, shown.st_ino) != (opened.st_dev, opened.st_ino):
                    raise ValueError("compute source parent changed")
            if expected is not None and (len(raw) != expected["bytes"] or
                    hashlib.sha256(raw).hexdigest() != expected["sha256"]):
                raise ValueError("compute source content differs")
            return raw
        finally:
            if parent_fd is not None:
                os.close(parent_fd)

    def log(self, stage, job, raw):
        if (not self.authenticated or stage not in STAGES or not re.fullmatch("[1-9][0-9]*", job)
                or not 0 < len(raw) <= LOG_LIMIT):
            raise ValueError("bounded authenticated compute log required")
        self.check()
        directory = self.root / "slurm"
        self.safe(directory)
        before = directory.stat()
        fd = self.child_fd(["slurm"]) if self.root_fd is not None else None
        try:
            def check_log_directory():
                self.check()
                self.safe(directory)
                shown = directory.stat()
                if (shown.st_dev, shown.st_ino) != (before.st_dev, before.st_ino):
                    raise ValueError("compute log directory changed")
                if fd is not None:
                    opened = os.fstat(fd)
                    if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
                        raise ValueError("compute log handle changed")
            check_log_directory()
            name = stage + "-" + job + ".out"
            target = name if fd is not None else directory / name
            extra = {"dir_fd": fd} if fd is not None else {}
            output = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                             0o600, **extra)
            with os.fdopen(output, "wb") as handle:
                check_log_directory()
                handle.write(raw)
                handle.flush()
                os.fsync(handle.fileno())
            check_log_directory()
        finally:
            if fd is not None:
                os.close(fd)

    def close(self):
        for name in ("root_fd", "parent_fd"):
            fd = getattr(self, name, None)
            if fd is not None:
                os.close(fd)
                setattr(self, name, None)

class Capture(io.StringIO):
    def write(self, value):
        if len(self.getvalue().encode()) + len(value.encode()) > LOG_LIMIT:
            raise ValueError("bounded compute stream exceeded")
        return super().write(value)

def authenticate(guard, release_sha, expected):
    deployed_raw = guard.read("deployment.json", 20000)
    deployed = json.loads(deployed_raw)
    if (hashlib.sha256(deployed_raw).hexdigest() != expected["metadata_sha256"]
            or deployed.get("schema") != "shared-base-deployment-v2"
            or deployed.get("release_sha256") != release_sha
            or deployed.get("deployment_token") != expected["deployment_token"]
            or deployed.get("root_binding") != expected["root_binding"]):
        raise ValueError("caller-fixed deployment differs before imports")
    guard.authenticated = True
    raw = guard.read("release_manifest.json")
    manifest = json.loads(raw)
    if hashlib.sha256(raw).hexdigest() != release_sha or manifest.get("remote_root") != str(guard.root):
        raise ValueError("manifest differs before compute imports")
    rows = manifest.get("files")
    if type(rows) is not list or not rows or len(rows) > 60:
        raise ValueError("compute release member count differs")
    seen = set()
    for row in rows:
        if type(row) is not dict or set(row) != {"path", "bytes", "sha256"}:
            raise ValueError("compute release member fields differ")
        name = row["path"]
        safe_name(name)
        if (name in seen or not name.endswith((".py", ".json"))
                or type(row["bytes"]) is not int or not 0 < row["bytes"] <= 2000000
                or not isinstance(row["sha256"], str) or not re.fullmatch("[0-9a-f]{64}", row["sha256"])):
            raise ValueError("unexpected compute release member")
        seen.add(name)
        guard.read(name, expected=row)
    if not {"execution/execute_stage.py", "execution/remote_actions.py", "execution/execution_io.py",
            "execution/release_runtime.py", "execution/compute_bootstrap.py",
            "contracts/execution_contract.json"} <= seen:
        raise ValueError("incomplete compute release")
    guard.check()
    return manifest

def run(root, stage, release_sha, expected, nonce, core_rel):
    job = os.environ.get("SLURM_JOB_ID", "")
    if (stage not in STAGES or core_rel != CORE_REL or not re.fullmatch("[1-9][0-9]*", job)
            or not re.fullmatch("[0-9a-f]{64}", release_sha)
            or not re.fullmatch("[0-9a-f]{32}", nonce)):
        raise ValueError("fixed compute job arguments required")
    guard = Root(root, expected)
    capture = Capture()
    try:
        authenticate(guard, release_sha, expected)
        sys.path[:0] = [str(guard.root / "execution"), str(guard.root / core_rel),
                       str(guard.root / "scripts/modeling"), str(guard.root / "scripts/astronomical_tide")]
        sys.argv = [str(guard.root / "execution/execute_stage.py"), "--stage", stage,
                    "--release-sha", release_sha, "--nonce", nonce,
                    "--deployment-identity", json.dumps(expected, sort_keys=True, separators=(",", ":"))]
        with contextlib.redirect_stdout(capture), contextlib.redirect_stderr(capture):
            guard.check()
            runpy.run_path(sys.argv[0], run_name="__main__")
        guard.check()
        raw = capture.getvalue().encode() or json.dumps({"status": "compute_bootstrap_complete",
                                                       "stage": stage, "job_id": job}).encode()
        guard.log(stage, job, raw)
    except BaseException as error:
        raw = (capture.getvalue() + "".join(traceback.format_exception(type(error), error, error.__traceback__))).encode()
        if guard.authenticated:
            try:
                guard.log(stage, job, raw[:LOG_LIMIT])
            except (ValueError, FileExistsError, FileNotFoundError):
                pass
        raise
    finally:
        guard.close()

def control(root, action, stage, release_sha, expected, core_rel):
    """Lightweight login-node control; no allocation, data or model execution."""
    if (action not in ("submit", "status") or core_rel != CORE_REL
            or not re.fullmatch("[0-9a-f]{64}", release_sha)
            or action == "submit" and stage not in ("train", "evaluate")
            or action == "status" and stage is not None):
        raise ValueError("fixed subsequent-stage control arguments required")
    guard = Root(root, expected)
    try:
        authenticate(guard, release_sha, expected)
        sys.path[:0] = [str(guard.root / "execution"), str(guard.root / core_rel),
                       str(guard.root / "scripts/modeling"), str(guard.root / "scripts/astronomical_tide")]
        sys.argv = [str(guard.root / "execution/remote_actions.py"), "--action", action,
                    "--release-sha", release_sha, "--deployment-identity",
                    json.dumps(expected, sort_keys=True, separators=(",", ":"))]
        if action == "submit":
            sys.argv += ["--stage", stage]
        guard.check()
        runpy.run_path(sys.argv[0], run_name="__main__")
        guard.check()
    finally:
        guard.close()

status_stream=io.StringIO()
with contextlib.redirect_stdout(status_stream):
    control('/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001','status',None,'8c29507a7e6d6b2a53f7b3a8ff1f5bcbe4d2bb32d58c1d7fecc7fc9f29a24678',{'deployment_token': '35eb014766234b74961d73d38ffee3e2', 'metadata_sha256': 'beba9684d5ff495d62e5326531fab6273700c7cf9aa56b4f7dc7a13ba9f48fc0', 'root_binding': {'inode': 10617661454, 'mode': 448, 'uid': 2272}, 'schema': 'cross-node-deployment-v1'},'runtime/inbox/zhenjiang-six-source-four-target-ukf/shared_base_20260916_001')
status_text=status_stream.getvalue()
if len(status_text.encode())>2000000 or len(status_text.splitlines())!=1:
    raise ValueError('status output form differs')
report=json.loads(status_text)
fixed_guard=Root('/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001',{'deployment_token': '35eb014766234b74961d73d38ffee3e2', 'metadata_sha256': 'beba9684d5ff495d62e5326531fab6273700c7cf9aa56b4f7dc7a13ba9f48fc0', 'root_binding': {'inode': 10617661454, 'mode': 448, 'uid': 2272}, 'schema': 'cross-node-deployment-v1'})
try:
    authenticate(fixed_guard,'8c29507a7e6d6b2a53f7b3a8ff1f5bcbe4d2bb32d58c1d7fecc7fc9f29a24678',{'deployment_token': '35eb014766234b74961d73d38ffee3e2', 'metadata_sha256': 'beba9684d5ff495d62e5326531fab6273700c7cf9aa56b4f7dc7a13ba9f48fc0', 'root_binding': {'inode': 10617661454, 'mode': 448, 'uid': 2272}, 'schema': 'cross-node-deployment-v1'})
    try:
        epoch_raw=fixed_guard.read('train/seed_17/common_process/epoch_1.json',maximum=16384)
    except FileNotFoundError:
        epoch_raw=None
    if epoch_raw is not None:
        report['epoch_1']={'value':json.loads(epoch_raw),'spec':{'path':REMOTE_ROOT+'/train/seed_17/common_process/epoch_1.json','bytes':len(epoch_raw),'sha256':hashlib.sha256(epoch_raw).hexdigest()}}
    fixed_guard.check()
finally:
    fixed_guard.close()
reply=json.dumps(report,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
if len(reply)>2000000:
    raise ValueError('status reply bound exceeded')
print(reply.decode())

SHARED_RELEASE_VERIFIED_PY
