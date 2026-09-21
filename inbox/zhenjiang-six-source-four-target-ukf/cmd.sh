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

"""Pure NSE aggregation for one authenticated seed prediction archive."""
from io import BytesIO
import hashlib

import numpy as np

METHODS = ("no_update", "rolling_encoder", "differentiable_filter")
STATIONS = ("南京", "镇江", "江阴", "徐六泾", "吴淞口")
LEADS = 23
EXPECTED_WINDOWS = 151
ORIGINS_PER_WINDOW = 48
EXPECTED_ORIGINS = EXPECTED_WINDOWS * ORIGINS_PER_WINDOW
EXPECTED_KEYS = set(METHODS) | {"targets", "origins", "scale"}


def _array_hash(value):
    array = np.ascontiguousarray(value)
    header = (str(array.dtype) + ":" + repr(array.shape) + ":").encode("ascii")
    return hashlib.sha256(header + array.tobytes()).hexdigest()


def compute_archive(raw):
    """Return sufficient statistics; never return predictions or targets."""
    if not isinstance(raw, bytes) or not raw:
        raise ValueError("non-empty archive bytes required")
    with np.load(BytesIO(raw), allow_pickle=False) as archive:
        if set(archive.files) != EXPECTED_KEYS:
            raise ValueError("prediction archive keys differ")
        targets_native = np.asarray(archive["targets"])
        origins = np.asarray(archive["origins"])
        scale = np.asarray(archive["scale"])
        expected_shape = (
            EXPECTED_WINDOWS,
            ORIGINS_PER_WINDOW,
            LEADS,
            len(STATIONS),
        )
        if targets_native.shape != expected_shape or origins.shape != (
                EXPECTED_WINDOWS, ORIGINS_PER_WINDOW):
            raise ValueError("target or origin shape differs")
        if scale.shape != (len(STATIONS),) or not np.issubdtype(
                targets_native.dtype, np.number):
            raise ValueError("scale or target dtype differs")
        targets = targets_native.astype(np.float64, copy=False)
        scale64 = scale.astype(np.float64, copy=False)
        if (not np.isfinite(targets).all() or not np.isfinite(scale64).all()
                or np.any(scale64 <= 0)):
            raise ValueError("target or scale is not finite and positive")
        target_mean = targets.mean(axis=(0, 1))
        sst = np.square(targets - target_mean[None, None]).sum(
            axis=(0, 1), dtype=np.float64)
        if not np.isfinite(sst).all() or np.any(sst <= 0):
            raise ValueError("NSE denominator is not finite and positive")
        squared_error_sums = []
        nse = []
        for method in METHODS:
            prediction_native = np.asarray(archive[method])
            if (prediction_native.shape != expected_shape
                    or not np.issubdtype(prediction_native.dtype, np.number)):
                raise ValueError("prediction shape or dtype differs: " + method)
            prediction = prediction_native.astype(np.float64, copy=False)
            if not np.isfinite(prediction).all():
                raise ValueError("prediction is not finite: " + method)
            sse = np.square(prediction - targets).sum(
                axis=(0, 1), dtype=np.float64)
            score = 1.0 - sse / sst
            if not np.isfinite(score).all():
                raise ValueError("NSE is not finite: " + method)
            squared_error_sums.append(sse.tolist())
            nse.append(score.tolist())
    return {
        "shape": list(expected_shape),
        "target_sha256": _array_hash(targets_native),
        "origin_sha256": _array_hash(origins),
        "scale_sha256": _array_hash(scale),
        "target_sst": sst.tolist(),
        "squared_error_sums": squared_error_sums,
        "nse": nse,
    }


def combine_seed_records(records):
    if not isinstance(records, list) or len(records) != 3:
        raise ValueError("exactly three seed records required")
    for field in ("shape", "target_sha256", "origin_sha256", "scale_sha256"):
        if len({repr(record[field]) for record in records}) != 1:
            raise ValueError("seed target identity differs: " + field)
    sst = np.asarray([record["target_sst"] for record in records], dtype=np.float64)
    sse = np.asarray(
        [record["squared_error_sums"] for record in records], dtype=np.float64)
    nse = np.asarray([record["nse"] for record in records], dtype=np.float64)
    if (sst.shape != (3, LEADS, len(STATIONS))
            or sse.shape != (3, len(METHODS), LEADS, len(STATIONS))):
        raise ValueError("seed statistic shape differs")
    rebuilt = 1.0 - sse / sst[:, None]
    if not np.allclose(rebuilt, nse, rtol=0.0, atol=1e-12):
        raise ValueError("reported NSE differs from sufficient statistics")
    mean_station = nse.mean(axis=0)
    macro = mean_station.mean(axis=2)
    pooled_by_seed = 1.0 - sse.sum(axis=3) / sst.sum(axis=2)[:, None]
    pooled = pooled_by_seed.mean(axis=0)
    return {
        "per_seed_method_lead_station_nse": nse.tolist(),
        "per_method_lead_station_nse": mean_station.tolist(),
        "per_method_lead_macro_nse": macro.tolist(),
        "per_method_lead_pooled_nse": pooled.tolist(),
        "per_seed_method_lead_station_sse": sse.tolist(),
        "per_seed_lead_station_sst": sst.tolist(),
    }

binding={'deployment_token': '35eb014766234b74961d73d38ffee3e2', 'metadata_sha256': 'beba9684d5ff495d62e5326531fab6273700c7cf9aa56b4f7dc7a13ba9f48fc0', 'root_binding': {'inode': 10617661454, 'mode': 448, 'uid': 2272}, 'schema': 'cross-node-deployment-v1'}
release_sha='8c29507a7e6d6b2a53f7b3a8ff1f5bcbe4d2bb32d58c1d7fecc7fc9f29a24678'
array_rows=[{'bytes': 7395989, 'path': 'evaluate/arrays/seed_17.npz', 'sha256': 'faf14e7721cf677299f4dd92e8f13df3161b4a128e2a1b1209a5c557cca5d257'}, {'bytes': 7405828, 'path': 'evaluate/arrays/seed_29.npz', 'sha256': 'd17e5da02ccf2cc493e0e5c8945dc683cb03f91a7703679b4f5597b06a9cde14'}, {'bytes': 7416208, 'path': 'evaluate/arrays/seed_43.npz', 'sha256': '31d483c7e48e5f070d8a15292733f8c1e1ff3680c651098102639746971efad7'}]
seed_values=(17, 29, 43)
gate=Root(REMOTE_ROOT,binding)
records=[]
try:
    authenticate(gate,release_sha,binding)
    for row in array_rows:
        raw=gate.read(row['path'],maximum=8000000,expected={'bytes':row['bytes'],'sha256':row['sha256']})
        records.append(compute_archive(raw))
        del raw
    combined=combine_seed_records(records)
    answer={'schema':'nse-by-lead-v2','methods':list(METHODS),'stations':list(STATIONS),'lead_hours':list(range(1,LEADS+1)),'seeds':list(seed_values),'n_windows':EXPECTED_WINDOWS,'origins_per_window':ORIGINS_PER_WINDOW,'n_origins':EXPECTED_ORIGINS,'nse_definition':'1 - sum((prediction-target)^2) / sum((target-mean_target_for_same_lead_and_station)^2)','macro_definition':'equal mean of station NSE, then equal mean of three seeds','pooled_definition':'station-pooled squared-error ratio, then equal mean of three seeds','source_archives':[{'path':REMOTE_ROOT+'/'+row['path'],'bytes':row['bytes'],'sha256':row['sha256']} for row in array_rows],'target_sha256':records[0]['target_sha256'],'origin_sha256':records[0]['origin_sha256'],'scale_sha256':records[0]['scale_sha256'],'source_opens':len(array_rows),'source_read_bytes':sum(row['bytes'] for row in array_rows)}
    answer.update(combined)
    reply=json.dumps(answer,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode('utf-8')
    if len(reply)>500000:
        raise ValueError('NSE aggregate reply exceeds bound')
    gate.check()
finally:
    gate.close()
print(reply.decode('utf-8'))

SHARED_RELEASE_VERIFIED_PY
# corrected read-only NSE aggregation; no remote writes
