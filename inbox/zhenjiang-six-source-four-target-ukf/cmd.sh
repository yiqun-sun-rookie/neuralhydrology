#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'REVIEWED_DIAGNOSTIC_PY'
"""Read only this isolated diagnostic's registered metadata and log."""
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import hashlib

ROOT = Path("/data1/home/sunyiq/zhenjiang_root_identity_diagnostic_20260917_001")

def read(name, maximum=20000, expected_root=None):
    if name not in ("submitted.json", "login_snapshot.json") and not re.fullmatch(r"probe-[1-9][0-9]*\.out", name):
        raise ValueError("fixed diagnostic metadata name required")
    path = ROOT / name
    for item in (ROOT, *ROOT.parents):
        if stat.S_ISLNK(item.lstat().st_mode):
            raise ValueError("linked diagnostic root")
    root_meta = ROOT.stat()
    if expected_root is not None and (root_meta.st_dev, root_meta.st_ino) != expected_root:
        raise ValueError("diagnostic query root changed before read")
    try:
        before = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or not 0 <= before.st_size <= maximum:
        raise ValueError("diagnostic output type/size differs")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb", buffering=0) as handle:
        opened = os.fstat(handle.fileno())
        if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns) != (
                before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns):
            raise ValueError("diagnostic metadata changed before read")
        raw = handle.read(maximum + 1)
        after = os.fstat(handle.fileno())
    current = ROOT.stat()
    if (len(raw) != before.st_size or (current.st_dev, current.st_ino) != (root_meta.st_dev, root_meta.st_ino)
            or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) !=
            (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)):
        raise ValueError("diagnostic metadata changed")
    return raw

def query(job, submitted_sha, login_sha):
    if not re.fullmatch("[1-9][0-9]*", job):
        raise ValueError("exact diagnostic job required")
    root_meta = ROOT.stat()
    root_id = root_meta.st_dev, root_meta.st_ino
    submitted_raw = read("submitted.json", expected_root=root_id)
    login_raw = read("login_snapshot.json", expected_root=root_id)
    if (hashlib.sha256(submitted_raw).hexdigest() != submitted_sha
            or hashlib.sha256(login_raw).hexdigest() != login_sha):
        raise ValueError("exact submitted/login snapshot identities differ")
    submitted = json.loads(submitted_raw)
    login = json.loads(login_raw)
    if submitted.get("job_id") != job or submitted.get("root") != str(ROOT):
        raise ValueError("diagnostic job differs")
    if submitted.get("login_snapshot") != login:
        raise ValueError("diagnostic login snapshot binding differs")
    log = read("probe-" + job + ".out", expected_root=root_id)
    result = {"job_id": job, "login": login,
              "log": None if log is None else log.decode("utf-8", errors="strict"), "scheduler": {}}
    for name, argv in (
        ("queue", ["squeue", "--noheader", "--jobs", job, "--format=%i|%T|%R"]),
        ("accounting", ["sacct", "--noheader", "--parsable2", "--jobs", job,
                        "--format=JobIDRaw,State,ExitCode,ElapsedRaw,NodeList,Partition"]),
    ):
        value = subprocess.run(argv, capture_output=True, text=True, timeout=15, check=False)
        stdout, stderr = value.stdout or "", value.stderr or ""
        if len(stdout.encode()) + len(stderr.encode()) > 32768:
            raise ValueError("bounded scheduler output exceeded")
        if value.returncode == 0:
            for line in stdout.splitlines():
                actual = line.split("|", 1)[0].strip()
                if actual and actual != job and not actual.startswith(job + "."):
                    raise ValueError("unrelated scheduler job")
        result["scheduler"][name] = {"returncode": value.returncode, "stdout": stdout, "stderr": stderr}
    current = ROOT.stat()
    if (current.st_dev, current.st_ino) != root_id:
        raise ValueError("diagnostic query root changed")
    return result

print(json.dumps(query('226226','970f7e63639e4374efffce7dcde671fc0a4e2ba74782b442cfc788f6a6c6429a','b6944e8ee18f3e49c63390818d64370ec51926b4ce001e843b6f6c8cc1d26b6b'),sort_keys=True,separators=(',',':')))

REVIEWED_DIAGNOSTIC_PY
