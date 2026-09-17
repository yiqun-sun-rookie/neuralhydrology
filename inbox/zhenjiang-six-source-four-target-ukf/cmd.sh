#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'REVIEWED_DIAGNOSTIC_PY'
"""One fresh two-minute metadata-only Slurm diagnostic; no old-root mutations."""
import json
import os
from pathlib import Path
import stat
import subprocess
import hashlib

ROOT = Path("/data1/home/sunyiq/zhenjiang_root_identity_diagnostic_20260917_001")
PYTHON = "/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python"

class Writer:
    def __init__(self):
        # Windows branch is used only by local synthetic controller tests.
        # Production Linux always uses the pinned directory descriptors below.
        if os.name == "nt":
            self.windows_root = ROOT
            ROOT.mkdir(mode=0o700, exist_ok=False)
            self.windows_id = (ROOT.stat().st_dev, ROOT.stat().st_ino)
            self.windows_parent = (ROOT.parent.stat().st_dev, ROOT.parent.stat().st_ino)
            self.root_fd = self.parent_fd = None
            self.check()
            return
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        self.parent_fd = os.open("/", flags)
        self.root_fd = None
        try:
            for part in ROOT.parent.parts[1:]:
                child = os.open(part, flags, dir_fd=self.parent_fd)
                os.close(self.parent_fd)
                self.parent_fd = child
            self.parent_meta = os.fstat(self.parent_fd)
            os.mkdir(ROOT.name, 0o700, dir_fd=self.parent_fd)
            self.root_fd = os.open(ROOT.name, flags, dir_fd=self.parent_fd)
            self.root_meta = os.fstat(self.root_fd)
            self.check()
        except BaseException:
            self.close()
            raise

    def check(self):
        for item in (ROOT, *ROOT.parents):
            value = item.lstat()
            if stat.S_ISLNK(value.st_mode):
                raise ValueError("linked diagnostic path")
        if os.name == "nt":
            if ((ROOT.stat().st_dev, ROOT.stat().st_ino) != self.windows_id
                    or (ROOT.parent.stat().st_dev, ROOT.parent.stat().st_ino) != self.windows_parent):
                raise ValueError("diagnostic root or parent changed")
            return
        for path, saved, fd in ((ROOT, self.root_meta, self.root_fd),
                                (ROOT.parent, self.parent_meta, self.parent_fd)):
            visible, opened = path.stat(), os.fstat(fd)
            if (visible.st_dev, visible.st_ino) != (saved.st_dev, saved.st_ino) or (
                    opened.st_dev, opened.st_ino) != (saved.st_dev, saved.st_ino):
                raise ValueError("diagnostic root or parent changed")

    def put(self, name, raw):
        if name not in ("attempt.json", "login_snapshot.json", "job.sh", "submitted.json", "failure.json"):
            raise ValueError("unknown diagnostic output")
        self.check()
        target = ROOT / name if os.name == "nt" else name
        extra = {} if os.name == "nt" else {"dir_fd": self.root_fd}
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, **extra)
        with os.fdopen(fd, "wb") as handle:
            self.check()
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        self.check()

    def close(self):
        for name in ("root_fd", "parent_fd"):
            fd = getattr(self, name, None)
            if fd is not None:
                os.close(fd)
                setattr(self, name, None)

def submit(probe_code, worker_code):
    writer = Writer()
    try:
        writer.put("attempt.json", b'{"action":"directory_metadata_only","maximum_submissions":1,"seconds":120}')
        namespace = {"__name__": "_diagnostic_probe", "__file__": "<reviewed-inline-probe>"}
        exec(compile(probe_code, "<reviewed-inline-probe>", "exec"), namespace)
        snapshot = namespace["probe"]()
        snapshot_raw = json.dumps(snapshot, sort_keys=True, separators=(",", ":")).encode()
        writer.put("login_snapshot.json", snapshot_raw)
        expected_root = {name: snapshot["diagnostic_root"][name] for name in ("inode", "uid", "mode")}
        compute = (worker_code + "\nPROBE_CODE=" + repr(probe_code) + "\nEXPECTED_ROOT=" + repr(expected_root)
                   + "\nLOGIN_SHA=" + repr(hashlib.sha256(snapshot_raw).hexdigest())
                   + "\nrun(PROBE_CODE,EXPECTED_ROOT,LOGIN_SHA)\n")
        compile(compute, "<reviewed-compute-diagnostic>", "exec")
        script = ("#!/bin/bash\nset -euo pipefail\nexport PYTHONDONTWRITEBYTECODE=1\n"
                  + PYTHON + " -B -I - <<'DIRECTORY_METADATA_ONLY_PY'\n"
                  + compute + "\nDIRECTORY_METADATA_ONLY_PY\n")
        writer.put("job.sh", script.encode())
        command = ["sbatch", "--parsable", "--partition=hgpu2p", "--nodes=1", "--ntasks=1",
                   "--cpus-per-task=4", "--gres=gpu:1", "--no-requeue", "--time=00:02:00",
                   "--job-name=zhenjiang-directory-metadata", "--output=/dev/null", "--error=/dev/null"]
        env = {key: value for key, value in os.environ.items() if not key.upper().startswith("SBATCH_")}
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        writer.check()
        result = subprocess.run(command, input=script, capture_output=True, text=True, timeout=30, env=env, check=False)
        stdout, stderr = result.stdout or "", result.stderr or ""
        if len(stdout.encode()) + len(stderr.encode()) > 32768:
            raise ValueError("scheduler reply exceeds bound")
        job = stdout.strip()
        if result.returncode or not job.isdigit() or int(job) <= 0:
            raise ValueError("submission uncertain, do not retry")
        record = {"job_id": job, "root": str(ROOT), "argv": command, "login_snapshot": snapshot}
        writer.check()
        writer.put("submitted.json", json.dumps(record, sort_keys=True, separators=(",", ":")).encode())
        return record
    except BaseException as error:
        try:
            writer.check()
            writer.put("failure.json", json.dumps({"error_type": type(error).__name__, "message": str(error)[:1000],
                                           "retry_allowed": False}).encode())
        except (ValueError, FileNotFoundError):
            pass
        raise
    finally:
        writer.close()

PROBE_CODE='"""Read only fixed directory and deployment metadata; no scientific payload."""\nimport hashlib\nimport json\nimport os\nfrom pathlib import Path\nimport socket\nimport stat\n\nOLD = Path("/data1/home/sunyiq/zhenjiang_shared_base_20260916_001")\nDIAG = Path("/data1/home/sunyiq/zhenjiang_root_identity_diagnostic_20260917_001")\nEXPECTED = {\n    "release_manifest.json": (4071, "49a27c4d9ea0f4f1843d581c780adfa554e8dc4498623cdc2c277aed3aa7856a"),\n    "deployment.json": (117, "202a1e8ba2fca8b1998895c9f80d3a3b8c4a53a631927d986415f0320e9c8fd2"),\n}\n\ndef safe(path):\n    if not path.is_absolute() or ".." in path.parts:\n        raise ValueError("unsafe fixed path")\n    for item in (path, *path.parents):\n        value = item.lstat()\n        if stat.S_ISLNK(value.st_mode) or getattr(value, "st_file_attributes", 0) & 0x400:\n            raise ValueError("linked metadata path")\n    return path\n\ndef directory(path):\n    value = safe(path).stat()\n    if not stat.S_ISDIR(value.st_mode):\n        raise ValueError("directory metadata differs")\n    return {"path": str(path), "device": value.st_dev, "inode": value.st_ino,\n            "uid": value.st_uid, "mode": stat.S_IMODE(value.st_mode)}\n\ndef verified_metadata(name):\n    if name not in EXPECTED:\n        raise ValueError("unknown metadata")\n    path = OLD / name\n    root_before = directory(OLD)\n    before = safe(path).stat()\n    size, expected = EXPECTED[name]\n    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size != size:\n        raise ValueError("fixed metadata type/size differs")\n    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0))\n    with os.fdopen(fd, "rb", buffering=0) as handle:\n        opened = os.fstat(handle.fileno())\n        if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns) != (\n                before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns):\n            raise ValueError("metadata changed before open")\n        raw = handle.read(size + 1)\n        after = os.fstat(handle.fileno())\n    if (len(raw) != size or hashlib.sha256(raw).hexdigest() != expected\n            or directory(OLD) != root_before\n            or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) !=\n            (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)):\n        raise ValueError("fixed metadata identity differs")\n    return json.loads(raw)\n\ndef unescape(value):\n    return value.replace("\\\\040", " ").replace("\\\\011", "\\t").replace("\\\\012", "\\n").replace("\\\\134", "\\\\")\n\ndef mount_for_root():\n    # Linux proc metadata only; no experiment/data discovery.\n    with open("/proc/self/mountinfo", "rb", buffering=0) as handle:\n        raw = handle.read(1_000_001)\n    if len(raw) > 1_000_000:\n        raise ValueError("mount metadata exceeds bound")\n    matches = []\n    for line in raw.decode("utf-8", errors="strict").splitlines():\n        left, right = line.split(" - ", 1)\n        a, b = left.split(), right.split()\n        point = unescape(a[4])\n        if str(OLD) == point or str(OLD).startswith(point.rstrip("/") + "/"):\n            matches.append({"mountpoint": point, "device_major_minor": a[2],\n                            "mount_root": unescape(a[3]), "filesystem": b[0], "source": unescape(b[1])})\n    if not matches:\n        raise ValueError("fixed root mount not found")\n    return max(matches, key=lambda value: len(value["mountpoint"]))\n\ndef probe():\n    before = directory(OLD)\n    manifest = verified_metadata("release_manifest.json")\n    deployment = verified_metadata("deployment.json")\n    if manifest.get("remote_root") != str(OLD):\n        raise ValueError("fixed manifest root differs")\n    value = {"host": socket.gethostname(), "job_id": os.environ.get("SLURM_JOB_ID"),\n             "kernel": os.uname().release, "old_root": before,\n             "diagnostic_root": directory(DIAG), "mount": mount_for_root(),\n             "deployment": deployment,\n             "manifest_sha256": EXPECTED["release_manifest.json"][1]}\n    if directory(OLD) != before:\n        raise ValueError("root changed during metadata probe")\n    return value\n\nif __name__ == "__main__":\n    print(json.dumps(probe(), sort_keys=True, separators=(",", ":"), allow_nan=False))\n'
WORKER_CODE='"""Write one bounded metadata result through a verified compute-node directory."""\nimport hashlib\nimport json\nimport os\nfrom pathlib import Path\nimport re\nimport stat\n\nROOT = Path("/data1/home/sunyiq/zhenjiang_root_identity_diagnostic_20260917_001")\nMAXIMUM = 20000\n\nclass Output:\n    def __init__(self, expected):\n        self.root_fd = self.parent_fd = None\n        self.expected = expected\n        self.safe()\n        value = ROOT.stat()\n        if (not stat.S_ISDIR(value.st_mode) or\n                {"inode": value.st_ino, "uid": value.st_uid, "mode": stat.S_IMODE(value.st_mode)} != expected):\n            raise ValueError("compute diagnostic directory binding differs")\n        self.root_meta = value\n        self.parent_meta = ROOT.parent.stat()\n        if os.name == "posix":\n            flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW\n            self.parent_fd = os.open("/", flags)\n            try:\n                for part in ROOT.parent.parts[1:]:\n                    child = os.open(part, flags, dir_fd=self.parent_fd)\n                    os.close(self.parent_fd)\n                    self.parent_fd = child\n                self.root_fd = os.open(ROOT.name, flags, dir_fd=self.parent_fd)\n                self.check()\n            except BaseException:\n                self.close()\n                raise\n\n    def safe(self):\n        for path in (ROOT, *ROOT.parents):\n            value = path.lstat()\n            if stat.S_ISLNK(value.st_mode) or getattr(value, "st_file_attributes", 0) & 0x400:\n                raise ValueError("linked compute diagnostic path")\n\n    def check(self):\n        self.safe()\n        for path, saved, fd in ((ROOT, self.root_meta, self.root_fd),\n                                (ROOT.parent, self.parent_meta, self.parent_fd)):\n            current = path.stat()\n            if (current.st_dev, current.st_ino) != (saved.st_dev, saved.st_ino):\n                raise ValueError("compute diagnostic directory changed")\n            if fd is not None:\n                opened = os.fstat(fd)\n                if (opened.st_dev, opened.st_ino) != (saved.st_dev, saved.st_ino):\n                    raise ValueError("compute diagnostic handle differs")\n\n    def login(self, expected_sha):\n        self.check()\n        target = "login_snapshot.json" if self.root_fd is not None else ROOT / "login_snapshot.json"\n        extra = {"dir_fd": self.root_fd} if self.root_fd is not None else {}\n        fd = os.open(target, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0), **extra)\n        with os.fdopen(fd, "rb", buffering=0) as handle:\n            before = os.fstat(handle.fileno())\n            if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or not 0 < before.st_size <= MAXIMUM:\n                raise ValueError("login snapshot type or size differs")\n            raw = handle.read(MAXIMUM + 1)\n            after = os.fstat(handle.fileno())\n        self.check()\n        if (len(raw) != before.st_size or hashlib.sha256(raw).hexdigest() != expected_sha\n                or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) !=\n                (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)):\n            raise ValueError("exact compute login snapshot differs")\n        snapshot = json.loads(raw)\n        actual = snapshot.get("diagnostic_root", {})\n        if actual.get("path") != str(ROOT) or any(actual.get(k) != v for k, v in self.expected.items()):\n            raise ValueError("login snapshot directory binding differs")\n        return snapshot\n\n    def put(self, job, raw):\n        if not isinstance(job, str) or not re.fullmatch("[1-9][0-9]*", job) or not 0 < len(raw) <= MAXIMUM:\n            raise ValueError("bounded exact diagnostic job output required")\n        self.check()\n        name = "probe-" + job + ".out"\n        target = name if self.root_fd is not None else ROOT / name\n        extra = {"dir_fd": self.root_fd} if self.root_fd is not None else {}\n        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600, **extra)\n        with os.fdopen(fd, "wb") as handle:\n            self.check()\n            handle.write(raw)\n            handle.flush()\n            os.fsync(handle.fileno())\n        self.check()\n\n    def close(self):\n        for name in ("root_fd", "parent_fd"):\n            fd = getattr(self, name, None)\n            if fd is not None:\n                os.close(fd)\n                setattr(self, name, None)\n\ndef run(probe_code, expected_root, login_sha):\n    job = os.environ.get("SLURM_JOB_ID", "")\n    if not re.fullmatch("[1-9][0-9]*", job):\n        raise ValueError("allocated diagnostic job absent")\n    output = Output(expected_root)\n    try:\n        output.login(login_sha)\n        namespace = {"__name__": "_compute_diagnostic_probe", "__file__": "<reviewed-inline-probe>"}\n        exec(compile(probe_code, "<reviewed-inline-probe>", "exec"), namespace)\n        result = namespace["probe"]()\n        output.check()\n        output.put(job, json.dumps(result, sort_keys=True, separators=(",", ":"), allow_nan=False).encode())\n        return result\n    except BaseException as error:\n        try:\n            output.put(job, json.dumps({"status": "diagnostic_failed_no_retry", "job_id": job,\n                "error_type": type(error).__name__, "message": str(error)[:1000]}, sort_keys=True,\n                separators=(",", ":")).encode())\n        except (ValueError, FileNotFoundError, FileExistsError):\n            pass\n        raise\n    finally:\n        output.close()\n'
print(json.dumps(submit(PROBE_CODE,WORKER_CODE),sort_keys=True,separators=(',',':')))

REVIEWED_DIAGNOSTIC_PY
