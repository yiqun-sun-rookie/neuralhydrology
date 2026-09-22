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

"""Pure same-sample astronomical-tide comparison; no file or network access."""
from datetime import datetime, timedelta, timezone
from io import BytesIO

import numpy as np


def calculate(raw, norm, thresholds, frozen, identities, tide_predictor, array_hash):
    """Aggregate one frozen archive without returning any observations or forecasts."""
    with np.load(BytesIO(raw), allow_pickle=False) as archive:
        if set(archive.files) != {
                'targets', 'origins', 'scale', 'no_update', 'rolling_encoder',
                'differentiable_filter'}:
            raise ValueError('archive members differ')
        targets, origins, stored_scale = (archive[k] for k in ('targets', 'origins', 'scale'))
        observed = dict(zip(identities, (array_hash(x) for x in
                                         (targets, origins, stored_scale))))
        if observed != identities or targets.shape != (151, 48, 23, 5):
            raise ValueError('frozen target or origin identity differs')
        if (origins.shape != (151, 48) or origins.dtype.kind not in 'iu'
                or origins.min() < 0 or origins.max() + 23 >= 8784
                or targets.dtype.kind != 'f' or not np.isfinite(targets).all()):
            raise ValueError('2024 calendar or target support differs')
        scale = np.asarray(norm['std_m'], dtype=np.float64)
        mean = np.asarray(norm['mean_m'], dtype=np.float64)
        cutoff = ((np.asarray(thresholds, dtype=np.float64) - mean) / scale).astype(targets.dtype)
        if (scale.shape != (5,) or mean.shape != (5,) or not np.isfinite(scale).all()
                or not np.isfinite(mean).all() or np.any(scale <= 0)
                or not np.array_equal(stored_scale, scale)
                or cutoff.astype(float).tolist() != frozen['encoded_threshold']):
            raise ValueError('normalization or encoded threshold differs')
        mask = targets >= cutoff
        if array_hash(mask) != frozen['mask_sha256']:
            raise ValueError('same high-water sample mask differs')
        counts_all = mask.sum(axis=(0, 1), dtype=np.int64).tolist()
        if counts_all != frozen['counts']:
            raise ValueError('high-water sample counts differ')

        target = targets[..., 4].astype(np.float64) * scale[4] + mean[4]
        selected = mask[..., 4]
        hours = origins[..., None] + np.arange(1, 24, dtype=np.int64)
        unique_hours, reverse = np.unique(hours, return_inverse=True)
        start = datetime(2024, 1, 1, tzinfo=timezone(timedelta(hours=8)))
        times = [start + timedelta(hours=int(hour)) for hour in unique_hours]
        tide_unique = np.asarray(tide_predictor(times))
        if (tide_unique.shape != unique_hours.shape or tide_unique.dtype != np.dtype('float64')
                or not np.isfinite(tide_unique).all()):
            raise ValueError('frozen tide forecast shape or precision differs')
        tide = tide_unique[reverse].reshape(hours.shape)
        err = tide - target
        count, sae, sse, means, sst = [], [], [], [], []
        for lead in range(23):
            chosen = selected[:, :, lead]
            y = target[:, :, lead][chosen]
            e = err[:, :, lead][chosen]
            n = int(y.size)
            if n != frozen['counts'][lead][4] or n < 2:
                raise ValueError('per-lead high-water sample count differs')
            ym = float(y.mean(dtype=np.float64))
            denominator = float(np.sum((y - ym) ** 2, dtype=np.float64))
            expected = float(frozen['target_sst_m2'][lead][4])
            if abs(denominator - expected) > 1e-9 * max(1.0, expected):
                raise ValueError('per-lead observed variation differs')
            if denominator <= 0:
                raise ValueError('non-positive observed variation')
            count.append(n)
            sae.append(float(np.sum(np.abs(e), dtype=np.float64)))
            sse.append(float(np.sum(e ** 2, dtype=np.float64)))
            means.append(ym)
            sst.append(denominator)
        return {
            'count': count, 'absolute_error_sum_m': sae,
            'squared_error_sum_m2': sse, 'target_mean_m': means,
            'target_sst_m2': sst,
            'mae_mm': [1000 * a / n for a, n in zip(sae, count)],
            'nse': [1 - a / b for a, b in zip(sse, sst)],
            'unique_target_hours': int(len(unique_hours)),
            'unique_high_target_hours': int(len(np.unique(hours[selected]))),
            'target_sha256': observed['target_sha256'],
            'origin_sha256': observed['origin_sha256'],
            'scale_sha256': observed['scale_sha256'],
            'mask_sha256': frozen['mask_sha256'],
        }

request={'array': {'bytes': 7395989, 'path': '/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001/evaluate/arrays/seed_17.npz', 'sha256': 'faf14e7721cf677299f4dd92e8f13df3161b4a128e2a1b1209a5c557cca5d257'}, 'preparation': {'bytes': 10525, 'path': '/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001/preflight/preparation.json', 'sha256': '5a4be84658540e57a000a50a94179630f60bd88e5af060dc94aa25fe8cc5d8e9'}, 'preparation_sha256': 'c4453b4a9b70e8884a53a4bb66083d7bfd433f1f99953a9936a0b506dd2baea4', 'normalization': {'ddof': 0, 'mean_m': [5.400405236226313, 4.6402023945551205, 3.320065825425991, 2.759381737791283, 2.238691191812825], 'normalization_sha256': 'b79ff31ade01a53484038f51995ecf5b9d04e52c9dbf30282423e0cbca16f406', 'role': 'explicit_stage', 'station_order': ['nanjing', 'zhenjiang', 'jiangyin', 'xuliujing', 'wusongkou'], 'std_m': [1.5813798323932793, 1.2406226087623022, 0.870605641869221, 0.8872664836969456, 0.889800898572366], 'unique_timestamp_count': 40258, 'unique_timestamp_manifest_sha256': 'd9f4462b82040837241678886ca4a254d7906e662df34bab82e64558a070b2e2'}, 'thresholds_m': [7.47, 6.244, 4.46, 3.96, 3.46], 'frozen_high': {'encoded_threshold': [1.3087271451950073, 1.2927360534667969, 1.3093576431274414, 1.3531653881072998, 1.3725641965866089], 'mask_sha256': '63c8ece984300555a37cbfec5a17bc6720e5f69b4d3ea7d859b9b52b75206ddf', 'counts': [[975, 982, 809, 849, 834], [975, 982, 806, 846, 834], [975, 982, 802, 844, 836], [975, 982, 800, 844, 837], [975, 982, 798, 846, 840], [975, 982, 795, 849, 842], [975, 980, 796, 852, 843], [975, 978, 799, 854, 843], [975, 977, 802, 856, 843], [975, 977, 804, 856, 843], [975, 977, 806, 856, 842], [975, 977, 808, 856, 840], [975, 977, 808, 856, 840], [975, 977, 807, 854, 840], [975, 977, 805, 853, 841], [975, 977, 803, 855, 841], [975, 977, 803, 855, 840], [975, 977, 802, 856, 841], [975, 976, 801, 858, 841], [975, 975, 802, 861, 841], [975, 975, 804, 861, 841], [975, 975, 806, 861, 839], [975, 975, 808, 860, 835]], 'target_sst_m2': [[364.7211155452521, 229.53109857652254, 112.36996526344456, 97.65495909226179, 82.82348357848659], [364.91916113340716, 229.85485133050076, 112.02323734762273, 97.48556640910921, 82.81934449753794], [365.059616463363, 229.96088617616974, 111.73339225513297, 97.43330174441367, 83.0214769389502], [365.12517247571157, 229.88501687598773, 111.65679693140581, 97.57301224055722, 83.03508579926162], [364.9838358714927, 229.71787840271733, 111.60675154107763, 97.7591324425626, 83.06381476351574], [364.6914973093924, 229.5690274450686, 111.18735026030984, 97.88248422200054, 83.06464940127726], [364.2819054095427, 228.62216631261998, 111.02727545049855, 98.0536642176148, 83.13523818963999], [363.8586597874439, 227.65980637026476, 111.36460383360637, 98.06710622309281, 83.13523818963999], [363.4285625064532, 227.22741648593527, 111.95880707192673, 98.1821348032826, 83.13523818963999], [363.05994691370535, 227.49289089979465, 112.09635910258648, 98.1821348032826, 83.13523818963999], [362.70076800983765, 227.79443356018567, 112.12066293652641, 98.1821348032826, 82.98642995276177], [362.3970902027448, 228.14659567232064, 112.25974037121763, 98.1821348032826, 82.94476848388206], [362.09856248828356, 228.54102580477542, 112.27903503990302, 98.1821348032826, 83.00619765249195], [361.86239664775815, 228.8667466518166, 112.23631538728459, 98.17315398280388, 82.87329509974171], [361.6597773854582, 229.01795287825206, 112.09763020948658, 98.13244934806096, 82.73530590984824], [361.4013526673212, 229.01399599411928, 111.91465842777183, 98.26410893101885, 82.64949148557028], [361.0415395443592, 228.87024446650886, 112.1146967744151, 98.02673134670894, 82.4154382791909], [360.54826009366946, 228.70553423463863, 112.0703586611325, 98.22257223191697, 82.4715405077759], [359.96603981578863, 228.01297678613895, 112.03878869820257, 98.38815052846469, 82.4715405077759], [359.31863274375524, 227.52683274675564, 112.0703586611325, 98.85625988220978, 82.4715405077759], [358.6434516710279, 227.59759521265053, 112.17935916709008, 98.85625988220978, 82.4715405077759], [357.9496888839768, 227.76348937972116, 112.2017339582648, 98.85625988220978, 82.31482947751967], [357.2996805129706, 227.9519688566741, 112.31879156957358, 98.77169753926374, 82.11596763255916]]}, 'identities': {'target_sha256': '9124782f2e6cae610a907c4fd37ad99115fad9e3b03a963fda12fe8fb2835827', 'origin_sha256': 'ceb3a478459ef10dc5efc3473d17d0a4061db39f994c6003063c837984ceddab', 'scale_sha256': '6fd883d4927dec405c2962c4c543a27edd4848206157f66ec26502d56febfc37'}, 'high_result': {'bytes': 107671, 'sha256': '6c53a0054dc7cac547ce39e426202a74d44582d129f95e2b0f6b46fcf9b492fa'}, 'authentication_opens': 28, 'authentication_max_bytes': 393996, 'additional_opens': 2, 'additional_bytes': 7406514}
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
        self.read_log.append({'path': name, 'bytes': len(raw),
                              'sha256': hashlib.sha256(raw).hexdigest()})
        return raw

gate = RecordedRoot(REMOTE_ROOT, binding)
try:
    authenticate(gate, release_sha, binding)
    auth_reads = list(gate.read_log)
    if (len(auth_reads) != request['authentication_opens'] or
            sum(row['bytes'] for row in auth_reads) > request['authentication_max_bytes']):
        raise ValueError('authentication read budget differs')
    prep = request['preparation']
    raw_prep = gate.read(prep['path'][len(REMOTE_ROOT)+1:], maximum=20000,
                         expected={'bytes':prep['bytes'],'sha256':prep['sha256']})
    preparation = json.loads(raw_prep)
    payload = dict(preparation)
    if payload.pop('preparation_sha256', None) != request['preparation_sha256'] or hashlib.sha256(
            json.dumps(payload, ensure_ascii=False, sort_keys=True,
                       separators=(',', ':'), allow_nan=False).encode()).hexdigest() != request['preparation_sha256']:
        raise ValueError('preparation document identity differs')
    sys.path.insert(0, str(gate.root / 'execution'))
    import tide_adapter
    if Path(tide_adapter.__file__).resolve() != gate.root / 'execution/tide_adapter.py':
        raise ValueError('frozen tide adapter source differs')
    predictor = tide_adapter.restore_tide(preparation['tide'])
    array = request['array']
    raw_array = gate.read(array['path'][len(REMOTE_ROOT)+1:], maximum=8000000,
                          expected={'bytes':array['bytes'],'sha256':array['sha256']})
    record = calculate(raw_array, request['normalization'], request['thresholds_m'],
                       request['frozen_high'], request['identities'],
                       predictor.predict_float64, array_hash)
    if len(gate.read_log) != request['authentication_opens'] + request['additional_opens'] or sum(
            row['bytes'] for row in gate.read_log[len(auth_reads):]) != request['additional_bytes']:
        raise ValueError('data read budget differs')
    answer = {'schema':'wusongkou-high-water-tide-only-v1','year':2024,
              'leads':list(range(1,24)), 'station':'wusongkou',
              'threshold_m':request['thresholds_m'][4],
              'tide_document_sha256':preparation['tide']['document_sha256'],
              'preparation_sha256':request['preparation_sha256'],
              'record':record, 'authentication_reads':auth_reads,
              'data_reads':gate.read_log[len(auth_reads):],
              'numpy_version':np.__version__, 'remote_experiment_writes':0}
    reply = json.dumps(answer, ensure_ascii=False, sort_keys=True,
                       separators=(',',':'), allow_nan=False).encode()
    if len(reply) > 100000:
        raise ValueError('tide-only aggregate reply too large')
    gate.check()
finally:
    gate.close()
print(reply.decode())

SHARED_RELEASE_VERIFIED_PY
# read-only Wusongkou tide-only aggregation seq=144
