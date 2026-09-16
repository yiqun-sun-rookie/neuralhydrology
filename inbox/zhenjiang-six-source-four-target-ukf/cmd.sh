#!/usr/bin/env bash
# Registered mailbox observation sequence 113
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'TEMPORAL_REMOTE_PY'
import base64, gzip, hashlib, json, os, re, stat, subprocess
from pathlib import Path
MAX_PLAIN_TAR = 20000000
def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode()

def document(raw):
    def unique(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                raise ValueError("duplicate JSON key")
            out[key] = value
        return out
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("nonfinite JSON")))

def safe_path(path):
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("absolute non-traversing path required")
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("symlink path rejected")
    if path.exists() and not (path.is_file() or path.is_dir()):
        raise ValueError("special path rejected")
    return path

def read_regular(path, maximum=MAX_PLAIN_TAR):
    path = safe_path(path)
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or before.st_size > maximum or before.st_nlink != 1:
        raise ValueError("nonregular, multiply linked or oversized file")
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if (info.st_dev, info.st_ino, info.st_size) != (before.st_dev, before.st_ino, before.st_size):
            raise ValueError("file identity changed during open")
        raw = handle.read(maximum + 1)
    if len(raw) != before.st_size:
        raise ValueError("file size changed during read")
    return raw

def collect_status(root, job, run=None):
    """Read a fixed set once; no polling loop, mutation, arrays or checkpoints."""
    root = safe_path(root)
    if not re.fullmatch("[1-9][0-9]*", job):
        raise ValueError("numeric bound job required")
    submission = document(read_regular(root / "evidence/submission/attempt_001/submission_receipt.json", 10000))
    if submission["job_id"] != job or submission["remote_root"] != str(root) or submission["status"] != "submitted":
        raise ValueError("bound submitted job differs")
    run = subprocess.run if run is None else run
    reply = {"job_id": job, "remote_root": str(root), "submission": submission, "files": {}}

    def scheduler(command):
        try:
            process = run(command, capture_output=True, check=False, timeout=10)
            return {"returncode": process.returncode, "stdout": process.stdout[:16000].decode(errors="replace"),
                    "stderr": process.stderr[:2000].decode(errors="replace")}
        except (OSError, subprocess.TimeoutExpired) as error:
            return {"unavailable": type(error).__name__}

    reply["scheduler"] = {
        "queue": scheduler(["squeue", "-h", "-j", job, "-o", "%i|%T|%M|%R"]),
        "accounting": scheduler(["sacct", "-n", "-P", "-j", job, "--format=JobID,State,ExitCode,Elapsed"]),
    }

    def artifact(name):
        path = safe_path(root / name)
        if path.exists():
            raw = read_regular(path, 12000000)
            document(raw)
            reply["files"][name] = {"sha256": sha(raw), "size_bytes": len(raw), "raw_utf8": raw.decode("utf-8")}

    artifact("results/evaluation_2024/completion.json")
    artifact("results/evaluation_2024/summary.json")
    artifact("results/evaluation_2024/block_statistics.json")
    artifact("evidence/runner_exit_status.json")
    artifact("evidence/evaluation_attempt_001/failure.json")
    reply["completion_artifact_present"] = "results/evaluation_2024/completion.json" in reply["files"]
    reply["scientific_success_inferred"] = False

    def log_tail(suffix):
        path = safe_path(root / ("logs/slurm-" + job + "." + suffix))
        if not path.exists():
            return None
        info = path.stat()
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(fd, "rb") as handle:
            actual = os.fstat(handle.fileno())
            if not stat.S_ISREG(actual.st_mode) or (info.st_dev, info.st_ino) != (actual.st_dev, actual.st_ino):
                raise ValueError("log identity/type differs")
            handle.seek(max(0, actual.st_size - 16000))
            return handle.read(16000).decode(errors="replace")

    if not reply["completion_artifact_present"]:
        reply["logs"] = {"out": log_tail("out"), "err": log_tail("err")}
    return reply


if __name__ == '__main__':
    reply = collect_status(Path('/data1/home/sunyiq/zhenjiang_temporal_validation_2024_20260915_001'), '225969')
    raw = canonical(reply)
    if len(raw) > 40000000: raise ValueError('status JSON bounds')
    encoded = base64.b64encode(gzip.compress(raw, mtime=0)).decode()
    if len(encoded) > 11900000: raise ValueError('status receipt bounds')
    print('TEMPORAL_STATUS_GZIP_BASE64_BEGIN')
    print(encoded)
    print('TEMPORAL_STATUS_GZIP_BASE64_END')

TEMPORAL_REMOTE_PY
