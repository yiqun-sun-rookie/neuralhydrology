#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_FAIR_SUBMIT'
"""Reserve and invoke one bounded cluster job for twelve separate models."""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess


RECEIPT = "eyJqb2Jfc2hhMjU2IjoiYWZhODc4NTg3YWRmZDdhOGM2Yzk3NGFhYmNmYTk4YTYwMzUzZWQ2YjI2ZjIxMDc2OGFmMWQwMzA2MGViOWZjZiIsImxvY2FsX3Byb3RvY29sX3NoYTI1NiI6IjVkMmNhMWRhZDc3YTQxNmU5MTFkOWU0MTkyODRlYjE3NmU5N2QzNWEwMDYzOWFkNDVmYWJiNjU2MDhhZjViMTkiLCJtZW1iZXJzIjo1NCwicGF5bG9hZF9ieXRlcyI6MTQ3MjA4LCJwYXlsb2FkX2luZGV4X3NoYTI1NiI6IjkwMjUyZDI3NzI4NGM1MTI3MDYyY2M3ZDNiNmZiYTA3YWQ1MDFmMjBlNDljMGM5Y2M1NGI3YzQzOTc0NzcyODUiLCJwYXlsb2FkX3NoYTI1NiI6ImQ3NmZmMmNkZmExYmRiZWZmZGMwZjA3ZmI1OGI5ZDU1M2IxYjYyZjU0OGI0OWU3Mzk2ZmE5NGExMmJmMDhjY2IiLCJyZW1vdGVfbWFuaWZlc3Rfc2hhMjU2IjoiMGVlMmQzMjBjNTZjMTVlYzE2Yjk5ZWJiODk4OTVkYjQ3NzQwZGNiZTA5ZmFiOTMwNGUyNjhkNjhmNWYwOTVhMSIsInJlbW90ZV9wcm90b2NvbF9zaGEyNTYiOiJjMTJhMzA0ZDQyOTI4ZmE4MTlmZTE1MDRkYmM1OWYwMGVlMGJlZjIyNDM2YTk3Njc5ODg2YjA0NDc2Y2Q4MjU0IiwicmVtb3RlX3Jvb3QiOiIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2ZhaXJfY29tcGFyaXNvbl8yMDI2MDkyOF8wMDIiLCJzb3VyY2VfZGF0YV9maWxlcyI6MTB9"
EXPECTED_DEPLOYMENT_SHA = "eea53a2472d8bef9a335d1c6b04492137aa8164bbc2e4293fde2c8b9e27ade0b"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"), allow_nan=False).encode()


def write_new(path, raw):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def main():
    receipt = json.loads(base64.b64decode(RECEIPT, validate=True))
    root = Path(receipt["remote_root"])
    deployment_path = root / "deploy/deployment.json"
    manifest_path = root / "reports/training_manifest.json"
    job_path = root / "deploy/job.sh"
    if (str(root) != "/data1/home/sunyiq/zhenjiang_fair_comparison_20260928_002"
            or root.is_symlink() or not root.is_dir() or
            any(os.path.lexists(root / part) for part in ("submission", "run", "preflight"))
            or not (root / "slurm").is_dir() or shutil.which("sbatch") is None):
        raise ValueError("single submission precondition differs")
    deployment_raw = deployment_path.read_bytes()
    deployed = json.loads(deployment_raw)
    meta = root.stat()
    binding = {"device": meta.st_dev, "inode": meta.st_ino,
               "uid": meta.st_uid, "mode": stat.S_IMODE(meta.st_mode)}
    if (sha(deployment_raw) != EXPECTED_DEPLOYMENT_SHA or
            deployed["status"] != "DEPLOYED_NO_TRAINING" or
            deployed["root_binding"] != binding or binding["mode"] != 0o700 or
            deployed["root"] != str(root) or
            deployed["payload_sha256"] != receipt["payload_sha256"] or
            deployed["protocol_sha256"] != receipt["remote_protocol_sha256"] or
            deployed["manifest_sha256"] != receipt["remote_manifest_sha256"] or
            deployed["job_sha256"] != receipt["job_sha256"] or
            sha((root / "protocol.json").read_bytes()) != receipt["remote_protocol_sha256"] or
            sha(manifest_path.read_bytes()) != receipt["remote_manifest_sha256"] or
            sha(job_path.read_bytes()) != receipt["job_sha256"]):
        raise ValueError("deployed training package identity differs")
    protocol = json.loads((root / "protocol.json").read_bytes())
    manifest = json.loads(manifest_path.read_bytes())
    if (protocol["epochs"] != 100 or protocol["seeds"] != [17, 29, 43] or
            protocol["planned_process_runs"]["separate_available"] != 12 or
            protocol["local_root"] != str(root) or
            manifest["file_count"] != 21):
        raise ValueError("scientific or placement contract differs")
    partition = subprocess.run(["scontrol", "show", "partition", "hgpu2p", "-o"],
                               capture_output=True, text=True, timeout=15, check=False)
    if partition.returncode != 0 or "PartitionName=hgpu2p" not in partition.stdout:
        raise ValueError("cluster partition unavailable")
    # An exclusive attempt record consumes this submission even if the reply is ambiguous.
    submission = root / "submission"
    submission.mkdir(mode=0o700)
    attempt = {"status": "RESERVED_NO_RETRY", "root": str(root),
               "root_binding": binding,
               "protocol_sha256": receipt["remote_protocol_sha256"],
               "manifest_sha256": receipt["remote_manifest_sha256"],
               "job_sha256": receipt["job_sha256"],
               "deployment_sha256": EXPECTED_DEPLOYMENT_SHA}
    attempt_raw = canonical(attempt)
    write_new(submission / "attempt.json", attempt_raw)
    argv = ["sbatch", "--parsable", "--partition=hgpu2p", "--nodes=1",
            "--ntasks=1", "--cpus-per-task=4", "--gres=gpu:1",
            "--no-requeue", "--time=24:00:00", "--output=/dev/null",
            "--error=/dev/null", "--job-name=zj-fair-separate",
            "--export=ALL", str(job_path)]
    write_new(submission / "command.json", canonical({
        "argv": argv, "attempt_sha256": sha(attempt_raw)}))
    env = {key: value for key, value in os.environ.items()
           if not key.upper().startswith("SBATCH_")}
    try:
        result = subprocess.run(argv, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=30,
                                check=False, env=env)
        if len(result.stdout.encode()) + len(result.stderr.encode()) > 8192:
            raise ValueError("scheduler reply exceeds bound")
        write_new(submission / "scheduler_reply.json", canonical({
            "returncode": result.returncode, "stdout": result.stdout,
            "stderr": result.stderr}))
        match = re.fullmatch(r"([1-9][0-9]*)(?:;[A-Za-z0-9_.-]+)?",
                             result.stdout.strip())
        if result.returncode != 0 or match is None:
            raise ValueError("scheduler submission uncertain; no retry")
        submitted = {**attempt, "status": "SUBMITTED_ONCE",
                     "job_id": match.group(1), "attempt_sha256": sha(attempt_raw)}
        write_new(submission / "submitted.json", canonical(submitted))
        print(json.dumps({"status": "SUBMITTED_ONCE", "job_id": match.group(1),
                          "root": str(root), "attempt_sha256": sha(attempt_raw)},
                         sort_keys=True))
    except BaseException as error:
        write_new(submission / "failure.json", canonical({
            "status": "STOPPED_NO_RETRY", "error": str(error)[:2000],
            "submission_uncertain": True}))
        raise


if __name__ == "__main__":
    main()

ZJ_FAIR_SUBMIT
