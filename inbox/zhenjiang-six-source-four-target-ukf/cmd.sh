#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'REVIEWED_DIAGNOSTIC_PY'
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

REMOTE_ROOT = "/data1/home/sunyiq/zhenjiang_shared_base_20260917_002"
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

"""Read existing cost metadata only; bootstrap definitions supplied separately."""
import math

def strict_document(raw):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("duplicate cost metadata key")
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite cost metadata")))

def finite_number(value, *, zero=False):
    if (type(value) not in (int, float) or not math.isfinite(value)
            or value < 0 or not zero and value == 0):
        raise ValueError("invalid measured cost")
    return value

def read_cost(root, release, identity, submitted_spec, failure_spec):
    guard = Root(root, identity)
    try:
        authenticate(guard, release, identity)
        sub_raw = guard.read("submission/preflight/submitted.json", expected=submitted_spec)
        fail_raw = guard.read("preflight/failure.json", expected=failure_spec)
        submitted, failure = strict_document(sub_raw), strict_document(fail_raw)
        if (submitted.get("stage") != "preflight" or submitted.get("status") != "submitted"
                or submitted.get("job_id") != "226232" or submitted.get("release_sha256") != release
                or submitted.get("deployment_identity") != identity
                or failure.get("stage") != "preflight" or failure.get("status") != "stopped_no_retry"
                or failure.get("job_id") != submitted["job_id"] or failure.get("nonce") != submitted["nonce"]
                or failure.get("deployment_identity") != identity or failure.get("release_sha256") != release):
            raise ValueError("existing failure does not match fixed original preflight")
        raw = guard.read("preflight/measurement.json", maximum=400000)
        value = strict_document(raw)
        stages = ("common_process", "rolling_encoder", "differentiable_filter")
        if (type(value) is not dict or value.get("status") != "failed" or value.get("seed") != 17
                or value.get("failure") != "measured_cost_exceeds_locked_stage_cap"
                or value.get("safety_factor") != 1.5 or set(value.get("stages", {})) != set(stages)
                or type(value.get("train_windows")) is not int or value["train_windows"] < 64
                or type(value.get("validate_windows")) is not int or value["validate_windows"] < 1):
            raise ValueError("fixed failed-preflight cost measurement required")
        clean = {name: value[name] for name in ("status", "failure", "seed", "train_windows",
                 "validate_windows", "safety_factor", "estimated_training_seconds", "elapsed_seconds",
                 "preparation_seconds")}
        finite_number(clean["estimated_training_seconds"])
        finite_number(clean["elapsed_seconds"])
        finite_number(clean["preparation_seconds"], zero=True)
        clean["stages"], contributions = {}, {}
        batches = math.ceil(value["train_windows"] / 32)
        total = clean["preparation_seconds"]
        epochs = {"common_process": 30, "rolling_encoder": 20, "differentiable_filter": 20}
        for name in stages:
            stage = value["stages"][name]
            keys = ("batch_seconds", "slowest_batch_seconds", "validation_seconds", "save_verify_seconds",
                    "selected_reload_seconds", "complete_training_batches", "batch_windows", "validation_windows")
            part = {key: stage[key] for key in keys}
            if (part["complete_training_batches"] != 2 or part["batch_windows"] != 32
                    or part["validation_windows"] != value["validate_windows"]
                    or type(part["batch_seconds"]) is not list or len(part["batch_seconds"]) != 2):
                raise ValueError("cost measurement batch/validation coverage differs")
            for duration in part["batch_seconds"]:
                finite_number(duration)
            for key in ("slowest_batch_seconds", "validation_seconds", "save_verify_seconds"):
                finite_number(part[key])
            finite_number(part["selected_reload_seconds"], zero=True)
            if max(part["batch_seconds"]) != part["slowest_batch_seconds"]:
                raise ValueError("cost measurement slowest batch differs")
            clean["stages"][name] = part
            contribution = 3 * (part["slowest_batch_seconds"] * batches * epochs[name]
                + (part["validation_seconds"] + part["save_verify_seconds"]) * (epochs[name] + 1))
            if name == "common_process":
                finite_number(part["selected_reload_seconds"])
                contribution += 3 * part["selected_reload_seconds"]
            contributions[name] = contribution
            total += contribution
        recomputed = total * 1.5
        if not math.isclose(recomputed, clean["estimated_training_seconds"], rel_tol=1e-12, abs_tol=1e-9):
            raise ValueError("existing cost arithmetic differs from frozen formula")
        guard.check()
        return {"status": "read_only_existing_cost_measurement", "root": root, "release_sha256": release,
                "deployment_identity": identity, "job_id": submitted["job_id"], "nonce": submitted["nonce"],
                "submitted_spec": submitted_spec, "failure_spec": failure_spec,
                "measurement_spec": {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()},
                "measurement": clean, "training_budget_seconds": 43200, "preflight_budget_seconds": 1800,
                "cost_before_safety_factor": contributions, "batches_per_epoch": batches,
                "recomputed_training_seconds": recomputed,
                "over_training_budget": clean["estimated_training_seconds"] > 43200,
                "over_preflight_budget": clean["elapsed_seconds"] > 1800}
    finally:
        guard.close()

print(json.dumps(read_cost('/data1/home/sunyiq/zhenjiang_shared_base_20260917_002','32cc34edefc4a125ecac92021454c68f832cc6471a5e9ead056b1987fda4657d',{'deployment_token': '4fc65ea378644eb7afe1efcf093b60fa', 'metadata_sha256': '9c5ec44126fd2766b5e0260f1f15fc785b7fe4fb57bfcd41a5bd608390e89388', 'root_binding': {'inode': 7560066049, 'mode': 448, 'uid': 2272}, 'schema': 'cross-node-deployment-v1'},{'bytes': 894, 'sha256': '27f874c7c11ceda60c8670905eab0bbecba53293a71f43be94cf8dcc694f6aac'},{'bytes': 567, 'sha256': 'f3a9320cee3130837c3cd660b6903ac475edfbced61c09e725292353261c5f2a'}),sort_keys=True,separators=(',',':'),allow_nan=False))

REVIEWED_DIAGNOSTIC_PY
