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

"""Pure exploratory high-water aggregates; no disk, network or model access."""
import csv
from datetime import datetime, timedelta, timezone
import hashlib
from io import BytesIO, StringIO

import numpy as np

METHODS = ('no_update', 'rolling_encoder', 'differentiable_filter')
STATIONS = ('nanjing', 'zhenjiang', 'jiangyin', 'xuliujing', 'wusongkou')
SHAPE = (151, 48, 23, 5)
BEIJING = timezone(timedelta(hours=8))
IDENTITIES = {
    'target_sha256': '9124782f2e6cae610a907c4fd37ad99115fad9e3b03a963fda12fe8fb2835827',
    'origin_sha256': 'ceb3a478459ef10dc5efc3473d17d0a4061db39f994c6003063c837984ceddab',
    'scale_sha256': '6fd883d4927dec405c2962c4c543a27edd4848206157f66ec26502d56febfc37',
}


def array_hash(array):
    a = np.ascontiguousarray(array)
    header = (str(a.dtype) + ':' + repr(a.shape) + ':').encode('ascii')
    return hashlib.sha256(header + a.tobytes()).hexdigest()


def select_training(rows):
    """Validate pairs and select finite 2017-2021 observations; no weighting."""
    values, counts = [], {str(y): 0 for y in range(2017, 2022)}
    for time, value in rows:
        if time.year not in range(2017, 2023):
            raise ValueError('unauthorized year')
        if np.isinf(value):
            raise ValueError('infinite observation')
        if time.year <= 2021 and np.isfinite(value):
            values.append(value)
            counts[str(time.year)] += 1
    if len(values) < 2:
        raise ValueError('insufficient training observations')
    a = np.sort(np.asarray(values, dtype=np.float64))
    position = 0.9 * (len(a) - 1)
    low, high = int(np.floor(position)), int(np.ceil(position))
    threshold = float(np.quantile(a, 0.9, method='linear'))
    independent = float(a[low] + (position - low) * (a[high] - a[low]))
    if abs(threshold - independent) > 1e-12:
        raise ValueError('quantile interpolation disagrees')
    return {'threshold_m': threshold, 'training_valid_count': len(a),
            'valid_count_by_year': counts, 'quantile': 0.9, 'method': 'linear',
            'order_position_zero_based': position,
            'lower_order_index_zero_based': low, 'upper_order_index_zero_based': high,
            'lower_order_statistic_m': float(a[low]),
            'upper_order_statistic_m': float(a[high])}


def training_quantile(raw):
    expected = ('TIME', 'TARGET_STAGE', 'time_beijing', 'time_utc', 'is_missing_for_target')
    reader = csv.DictReader(StringIO(raw.decode('utf-8'), newline=''))
    if tuple(reader.fieldnames or ()) != expected:
        raise ValueError('CSV columns differ')
    start = datetime(2017, 1, 1, tzinfo=BEIJING)
    end = datetime(2023, 1, 1, tzinfo=BEIJING)
    parsed = []
    for row in reader:
        if set(row) != set(expected) or any(v is None for v in row.values()):
            raise ValueError('CSV width differs')
        time = datetime.fromisoformat(row['time_beijing'])
        utc = datetime.fromisoformat(row['time_utc'])
        if (time.utcoffset() != timedelta(hours=8) or utc.utcoffset() != timedelta(0)
                or row['TIME'] != row['time_beijing'] or time.astimezone(timezone.utc) != utc):
            raise ValueError('timestamp pair differs')
        if time != start + timedelta(hours=len(parsed)) or not start <= time < end:
            raise ValueError('timeline differs or unauthorized year')
        flag, cell = row['is_missing_for_target'], row['TARGET_STAGE']
        if flag == 'True' and cell == '':
            value = float('nan')
        elif flag == 'False' and cell != '' and np.isfinite(float(cell)):
            value = float(cell)
        else:
            raise ValueError('missing flag/value differs')
        parsed.append((time, value))
    if len(parsed) != int((end - start).total_seconds() // 3600):
        raise ValueError('incomplete six-year timeline')
    result = select_training(parsed)
    result['source_hour_count'] = len(parsed)
    result['training_missing_count'] = 43824 - result['training_valid_count']
    return result


def nullable(a):
    value = np.asarray(a)
    return np.where(np.isfinite(value), value, None).tolist()


def derive(sae, sse, counts, sst):
    sae, sse = np.asarray(sae, dtype=float), np.asarray(sse, dtype=float)
    counts, sst = np.asarray(counts), np.asarray(sst, dtype=float)
    mae = np.full(sae.shape, np.nan)
    nse = np.full(sse.shape, np.nan)
    np.divide(1000 * sae, counts, out=mae, where=counts > 0)
    np.divide(sse, sst, out=nse, where=(counts >= 2) & (sst > 0))
    nse = 1 - nse
    return {'mae_mm': nullable(mae), 'nse': nullable(nse)}


def high_statistics(targets, predictions, origins, scale, mean, thresholds):
    targets = np.asarray(targets)
    scale, mean, thresholds = (np.asarray(x, dtype=np.float64) for x in (scale, mean, thresholds))
    if (targets.ndim != 4 or targets.dtype.kind != 'f'
            or np.asarray(origins).shape != targets.shape[:2]
            or any(a.shape != (targets.shape[-1],) for a in (scale, mean, thresholds))
            or any(not np.isfinite(a).all() for a in (targets, scale, mean, thresholds))
            or np.any(scale <= 0) or set(predictions) != set(METHODS)):
        raise ValueError('array shape, finite values or scale differs')
    cutoff = ((thresholds - mean) / scale).astype(targets.dtype)
    mask = targets >= cutoff
    physical = targets.astype(np.float64) * scale + mean
    counts = mask.sum(axis=(0, 1), dtype=np.int64)
    target_sum = np.where(mask, physical, 0).sum(axis=(0, 1), dtype=np.float64)
    average = np.zeros(counts.shape, dtype=np.float64)
    np.divide(target_sum, counts, out=average, where=counts > 0)
    sst = np.where(mask, (physical - average) ** 2, 0).sum(axis=(0, 1), dtype=np.float64)
    # Exact constancy, not an arbitrary near-zero tolerance: physical conversion
    # and summation can otherwise invent a tiny positive denominator.
    high_min = np.where(mask, targets, np.inf).min(axis=(0, 1))
    high_max = np.where(mask, targets, -np.inf).max(axis=(0, 1))
    sst[(counts > 0) & (high_min == high_max)] = 0.0
    sae, sse = [], []
    for name in METHODS:
        p = np.asarray(predictions[name])
        if p.shape != targets.shape or p.dtype.kind != 'f' or not np.isfinite(p).all():
            raise ValueError('prediction shape or finite value differs')
        error = (p.astype(np.float64) - targets.astype(np.float64)) * scale
        sae.append(np.where(mask, np.abs(error), 0).sum(axis=(0, 1), dtype=np.float64))
        sse.append(np.where(mask, error ** 2, 0).sum(axis=(0, 1), dtype=np.float64))
    hours = np.asarray(origins)[..., None] + np.arange(1, targets.shape[2] + 1)
    unique = [len(np.unique(hours[mask[..., station]])) for station in range(targets.shape[-1])]
    result = {
        'counts': counts.tolist(), 'target_mean_m': nullable(np.where(counts > 0, average, np.nan)),
        'target_sst_m2': sst.tolist(), 'absolute_error_sum_m': np.asarray(sae).tolist(),
        'squared_error_sum_m2': np.asarray(sse).tolist(),
        'encoded_threshold': cutoff.astype(float).tolist(),
        'encoded_threshold_roundtrip_error_m': (cutoff.astype(float) * scale + mean - thresholds).tolist(),
        'mask_sha256': array_hash(mask), 'unique_high_target_hours_across_leads': unique,
        'windows_with_high_by_lead_station': mask.any(axis=1).sum(axis=0).tolist(),
    }
    result.update(derive(sae, sse, counts, sst))
    return result


def compute_high_archive(raw, scale, mean, thresholds):
    with np.load(BytesIO(raw), allow_pickle=False) as archive:
        if set(archive.files) != set(METHODS) | {'targets', 'origins', 'scale'}:
            raise ValueError('archive members differ')
        targets, origins, stored_scale = (archive[k] for k in ('targets', 'origins', 'scale'))
        identities = dict(zip(IDENTITIES, (array_hash(a) for a in (targets, origins, stored_scale))))
        if identities != IDENTITIES or targets.shape != SHAPE or not np.array_equal(stored_scale, scale):
            raise ValueError('frozen arrays or scale identity differs')
        result = high_statistics(targets, {m: archive[m] for m in METHODS}, origins, scale, mean, thresholds)
        result.update(identities)
        return result

"""Descriptor-bound, allowlisted, one-read training source reader (Linux)."""
import hashlib
import os
from pathlib import PurePosixPath
import stat


class TrainingReader:
    def __init__(self, rows):
        self.rows = {r['path']: dict(r) for r in rows}
        if len(rows) != 5 or len(self.rows) != 5:
            raise ValueError('exact five training sources required')
        self.used = []

    def read(self, row):
        if self.rows.get(row['path']) != row or row['path'] in [r['path'] for r in self.used]:
            raise ValueError('source unregistered or duplicate')
        path = PurePosixPath(row['path'])
        prefix = '/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022/retrospective_targets/'
        if (not str(path).startswith(prefix) or '..' in path.parts or not path.is_absolute()
                or not 0 < row['bytes'] <= 5000000 or path.suffix != '.csv'):
            raise ValueError('source path or bound differs')
        self.used.append(dict(row))
        directories = []
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        try:
            directories.append(os.open('/', flags))
            for part in path.parts[1:-1]:
                directories.append(os.open(part, flags, dir_fd=directories[-1]))
            fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directories[-1])
            with os.fdopen(fd, 'rb', buffering=0) as handle:
                before = os.fstat(handle.fileno())
                if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size != row['bytes']:
                    raise ValueError('training source size or type differs')
                raw = handle.read(row['bytes'] + 1)
                after = os.fstat(handle.fileno())
                identity = lambda m: (m.st_dev, m.st_ino, m.st_size, m.st_mtime_ns)
                if (identity(before) != identity(after) or len(raw) != row['bytes']
                        or hashlib.sha256(raw).hexdigest() != row['sha256']
                        or identity(os.stat(path.name, dir_fd=directories[-1], follow_symlinks=False)) != identity(after)):
                    raise ValueError('training source changed')
            for index, part in enumerate(path.parts[1:-1]):
                linked = os.stat(part, dir_fd=directories[index], follow_symlinks=False)
                pinned = os.fstat(directories[index + 1])
                if (linked.st_dev, linked.st_ino) != (pinned.st_dev, pinned.st_ino):
                    raise ValueError('training ancestor changed')
            return raw
        finally:
            for fd in reversed(directories):
                os.close(fd)

request={'training_sources': [{'path': '/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022/retrospective_targets/nanjing_retrospective_targets.csv', 'bytes': 4674734, 'sha256': '9e0d1bdd950326bc1c11e05bfcc26ecf6ac847a2e15d01c7cdc49d79644c14b4'}, {'path': '/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022/retrospective_targets/zhenjiang_retrospective_targets.csv', 'bytes': 4703632, 'sha256': '17d897dea5b3599717b1ad2bfd9520ae7e1900d1c9247e27b4d542f2701de937'}, {'path': '/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022/retrospective_targets/jiangyin_retrospective_targets.csv', 'bytes': 4674038, 'sha256': '922157f3294822f86a58d1f590cd0c54eb3b7529beeb957bc53192126b211891'}, {'path': '/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022/retrospective_targets/xuliujing_retrospective_targets.csv', 'bytes': 4674687, 'sha256': '4344b95978c5308cb22bbd3b39e703e9ac6f8daf7973d2a4089c54ef212eb9f8'}, {'path': '/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022/retrospective_targets/wusongkou_retrospective_targets.csv', 'bytes': 4671875, 'sha256': 'ecba8ddbb6f1fca085194794c55041f45166975fb467074188c9acabb7056d78'}], 'array_sources': [{'bytes': 7395989, 'path': '/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001/evaluate/arrays/seed_17.npz', 'sha256': 'faf14e7721cf677299f4dd92e8f13df3161b4a128e2a1b1209a5c557cca5d257'}, {'bytes': 7405828, 'path': '/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001/evaluate/arrays/seed_29.npz', 'sha256': 'd17e5da02ccf2cc493e0e5c8945dc683cb03f91a7703679b4f5597b06a9cde14'}, {'bytes': 7416208, 'path': '/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001/evaluate/arrays/seed_43.npz', 'sha256': '31d483c7e48e5f070d8a15292733f8c1e1ff3680c651098102639746971efad7'}], 'normalization': {'ddof': 0, 'mean_m': [5.400405236226313, 4.6402023945551205, 3.320065825425991, 2.759381737791283, 2.238691191812825], 'normalization_sha256': 'b79ff31ade01a53484038f51995ecf5b9d04e52c9dbf30282423e0cbca16f406', 'role': 'explicit_stage', 'station_order': ['nanjing', 'zhenjiang', 'jiangyin', 'xuliujing', 'wusongkou'], 'std_m': [1.5813798323932793, 1.2406226087623022, 0.870605641869221, 0.8872664836969456, 0.889800898572366], 'unique_timestamp_count': 40258, 'unique_timestamp_manifest_sha256': 'd9f4462b82040837241678886ca4a254d7906e662df34bab82e64558a070b2e2'}, 'training_opens': 5, 'training_read_bytes': 23398966, 'array_opens': 3, 'array_read_bytes': 22218025, 'authentication_opens': 28, 'authentication_max_bytes': 393996}
binding={'deployment_token': '35eb014766234b74961d73d38ffee3e2', 'metadata_sha256': 'beba9684d5ff495d62e5326531fab6273700c7cf9aa56b4f7dc7a13ba9f48fc0', 'root_binding': {'inode': 10617661454, 'mode': 448, 'uid': 2272}, 'schema': 'cross-node-deployment-v1'}
release_sha='8c29507a7e6d6b2a53f7b3a8ff1f5bcbe4d2bb32d58c1d7fecc7fc9f29a24678'

class RecordedRoot(Root):
    def __init__(self, *args):
        self.read_log = []
        super().__init__(*args)
    def read(self, name, maximum=2000000, expected=None):
        if any(row['path'] == name for row in self.read_log):
            raise ValueError('duplicate authenticated root read')
        raw = super().read(name, maximum=maximum, expected=expected)
        self.read_log.append({'path': name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
        return raw
gate = RecordedRoot(REMOTE_ROOT, binding)
try:
    authenticate(gate, release_sha, binding)
    authentication_reads = list(gate.read_log)
    if (len(authentication_reads) != request['authentication_opens']
            or sum(row['bytes'] for row in authentication_reads) > request['authentication_max_bytes']):
        raise ValueError('authentication reads exceed fixed budget')
    training_reader = TrainingReader(request['training_sources'])
    quantiles = [training_quantile(training_reader.read(row)) for row in request['training_sources']]
    thresholds = [row['threshold_m'] for row in quantiles]
    norm = request['normalization']
    records = []
    for row in request['array_sources']:
        raw = gate.read(row['path'][len(REMOTE_ROOT)+1:], maximum=8000000,
                        expected={'bytes': row['bytes'], 'sha256': row['sha256']})
        records.append(compute_high_archive(raw, norm['std_m'], norm['mean_m'], thresholds))
        del raw
    shared = ('counts','target_mean_m','target_sst_m2','encoded_threshold',
              'encoded_threshold_roundtrip_error_m','mask_sha256',
              'unique_high_target_hours_across_leads','windows_with_high_by_lead_station')
    if any(record[key] != records[0][key] for record in records[1:] for key in shared):
        raise ValueError('seed high-water samples differ')
    answer = {'schema': 'high-water-v1', 'year': 2024, 'seeds': [17,29,43],
              'methods': list(METHODS), 'stations': list(STATIONS), 'leads': list(range(1,24)),
              'request': request, 'quantiles': quantiles, 'records': records,
              'training_sources_read': training_reader.used,
              'authentication_reads': authentication_reads,
              'array_reads': gate.read_log[len(authentication_reads):],
              'numpy_version': np.__version__, 'remote_experiment_writes': 0}
    reply = json.dumps(answer, ensure_ascii=False, sort_keys=True, separators=(',',':'), allow_nan=False).encode()
    if len(reply) > 500000:
        raise ValueError('high-water reply too large')
    gate.check()
finally:
    gate.close()
print(reply.decode())

SHARED_RELEASE_VERIFIED_PY
# read-only high-water aggregation seq=143
