#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZHENJIANG_BUDGET_SINGLE_COMMAND'
"""Reserve and invoke exactly one scheduler submission for the isolated run.

Inputs: sealed deployed root, submitted proof nonce and resource availability.
Outputs: submission/attempt.json before sbatch, then one scheduler receipt.
Example: this body is delivered inside the dedicated mailbox cmd.sh.
"""
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


ROOT = Path("/data1/home/sunyiq/zhenjiang_update_budget_20260922_001")
PYTHON = Path("/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python")
RECEIPT_B64 = "eyJqb2JfYnl0ZXMiOjY2Miwiam9iX3NoYTI1NiI6IjE3ODY3M2VlODlhZDllZDRjMWM4N2Y3NzYyYTY0M2VlZjZkNWY5YTZkYWI5ZjU5YjE5ZDYyMDI0Nzk1NTY2YTMiLCJtYW5pZmVzdF9maWxlcyI6MzQsIm1hbmlmZXN0X3NoYTI1NiI6IjMxN2ZlZmVmM2Y5YWJkODk4NmM3YTkzNDQ5ZjUxOWYyODcyODBmZDQyMTE1MTYwNDg2NDM1NjU0YTU5MzI5YjEiLCJwYXlsb2FkX2J5dGVzIjoxMDg5ODIsInBheWxvYWRfc2hhMjU2IjoiOGJlYzg1MzU0NmE5YjViMzI1MDQ4NWVlOTQzYWNiYjIxOTQ0N2QxZjZhMTY0YTE1NTgyNWUyODRhZmNiMGJmOSIsInByb3RvY29sX3NoYTI1NiI6IjhkZjQ5M2JlNmQxOGQyY2M2YWYzZjBiOTA2NGNjM2I3ZDA2YmU0OTU5ZWJiYzY3YTg2MTQ2ZTI1NmU5YzQwNjEiLCJzY2hlbWEiOiJidWRnZXQtc2VhbC12MSJ9"
NONCE = "60987b95b37519bfbbbd23074ec89f9d"
EXPECTED_DEPLOYMENT_SHA = "1298811046869286b0b7d3f29cb54a7e01559bdec3258e7e9d17f6ec473b0678"
EXPECTED_BINDING_B64 = "eyJpbm9kZSI6NzM1NTQwMzI3OSwibW9kZSI6NDQ4LCJ1aWQiOjIyNzJ9"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      allow_nan=False).encode("utf-8")


def exclusive_write(path, raw):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "wb", buffering=0) as handle:
        handle.write(raw)
        os.fsync(handle.fileno())


def checked_read(path, maximum):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > maximum:
        raise ValueError("deployed input type or size differs: " + str(path))
    return path.read_bytes()


def main():
    os.umask(0o077)
    receipt = json.loads(base64.b64decode(RECEIPT_B64, validate=True))
    if (not ROOT.is_dir() or ROOT.is_symlink()
            or not (ROOT / "slurm").is_dir()
            or os.path.lexists(ROOT / "submission")
            or os.path.lexists(ROOT / "run")
            or not PYTHON.is_file() or shutil.which("sbatch") is None):
        raise ValueError("isolated root or one-submission preconditions differ")
    meta = ROOT.stat()
    root_identity = [meta.st_dev, meta.st_ino]
    stable = {"inode": meta.st_ino, "uid": meta.st_uid,
              "mode": stat.S_IMODE(meta.st_mode)}
    expected_binding = json.loads(base64.b64decode(EXPECTED_BINDING_B64, validate=True))
    deployment_raw = checked_read(ROOT / "deploy" / "deployment.json", 8192)
    deployed = json.loads(deployment_raw)
    if (sha(deployment_raw) != EXPECTED_DEPLOYMENT_SHA
            or deployed.get("schema") != "budget-deployment-v2"
            or deployed.get("login_root_identity") != root_identity
            or stable != expected_binding
            or deployed.get("root_binding") != expected_binding
            or (os.name == "posix" and stable["mode"] != 0o700)
            or any(deployed.get(key) != receipt[key] for key in
                   ("protocol_sha256", "manifest_sha256", "job_sha256", "payload_sha256"))
            or sha(checked_read(ROOT / "protocol.json", 16384)) != receipt["protocol_sha256"]
            or sha(checked_read(ROOT / "source_manifest.json", 16384)) != receipt["manifest_sha256"]
            or sha(checked_read(ROOT / "deploy" / "job.sh", 8192)) != receipt["job_sha256"]):
        raise ValueError("deployed source identity differs")
    protocol = json.loads(checked_read(ROOT / "protocol.json", 16384))
    if (NONCE != protocol["submission_nonce"]
            or deployed.get("deployment_token") != protocol["deployment_token"]
            or protocol["resources"] != {"partition": "hgpu2p", "nodes": 1,
                                          "tasks": 1, "cpus_per_task": 4,
                                          "gpus": 1, "gpu_name_contains": "3090"}
            or protocol["wall_seconds"] != 129600):
        raise ValueError("approved nonce or resource declaration differs")
    partition = subprocess.run(["scontrol", "show", "partition", "hgpu2p", "-o"],
                               capture_output=True, text=True, timeout=15, check=False)
    if (partition.returncode != 0 or "PartitionName=hgpu2p" not in partition.stdout
            or "MaxTime=UNLIMITED" not in partition.stdout):
        raise ValueError("approved partition resource preflight differs")

    # This exclusive record consumes the only submission attempt even if sbatch fails.
    directory = ROOT / "submission"
    directory.mkdir(mode=0o700)
    attempt = {"status": "reserved_no_retry", "nonce": NONCE,
               "protocol_sha256": receipt["protocol_sha256"],
               "manifest_sha256": receipt["manifest_sha256"],
               "root_binding": expected_binding,
               "deployment_token": protocol["deployment_token"],
               "deployment_metadata_sha256": EXPECTED_DEPLOYMENT_SHA,
               "job_sha256": receipt["job_sha256"]}
    attempt_raw = canonical(attempt)
    exclusive_write(directory / "attempt.json", attempt_raw)
    argv = ["sbatch", "--parsable", "--partition=hgpu2p", "--nodes=1",
            "--ntasks=1", "--cpus-per-task=4", "--gres=gpu:1",
            "--no-requeue", "--time=36:00:00", "--output=/dev/null",
            "--error=/dev/null", "--job-name=zhenjiang-update-budget",
            "--export=ALL", str(ROOT / "deploy" / "job.sh")]
    env = {key: value for key, value in os.environ.items()
           if not key.upper().startswith("SBATCH_")}
    env["ZHENJIANG_DEPLOYMENT_SHA"] = EXPECTED_DEPLOYMENT_SHA
    exclusive_write(directory / "command.json", canonical({
        "argv": argv, "attempt_sha256": sha(attempt_raw),
        "job_sha256": receipt["job_sha256"]}))
    invoked = False
    try:
        invoked = True
        result = subprocess.run(argv, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", check=False,
                                timeout=30, env=env)
        if len(result.stdout.encode()) + len(result.stderr.encode()) > 8192:
            raise ValueError("scheduler reply exceeds bound; submission uncertain")
        exclusive_write(directory / "scheduler_reply.json", canonical({
            "returncode": result.returncode, "stdout": result.stdout,
            "stderr": result.stderr}))
        match = re.fullmatch(r"([1-9][0-9]*)(?:;[A-Za-z0-9_.-]+)?",
                             result.stdout.strip())
        if result.returncode != 0 or match is None:
            raise ValueError("scheduler submission uncertain; no retry")
        submitted = {"status": "submitted", "nonce": NONCE,
                     "protocol_sha256": receipt["protocol_sha256"],
                     "manifest_sha256": receipt["manifest_sha256"],
                     "root_binding": expected_binding,
                     "deployment_token": protocol["deployment_token"],
                     "deployment_metadata_sha256": EXPECTED_DEPLOYMENT_SHA,
                     "job_sha256": receipt["job_sha256"],
                     "attempt_sha256": sha(attempt_raw), "job_id": match.group(1)}
        exclusive_write(directory / "submitted.json", canonical(submitted))
        print(json.dumps({"status": "submitted_once", "job_id": match.group(1),
                          "root": str(ROOT), "attempt_sha256": sha(attempt_raw),
                          "job_sha256": receipt["job_sha256"]}, sort_keys=True))
    except BaseException as error:
        exclusive_write(directory / "failure.json", canonical({
            "status": "stopped_no_retry", "sbatch_invoked": invoked,
            "submission_uncertain": invoked,
            "error_type": type(error).__name__, "message": str(error)[:2000]}))
        raise


if __name__ == "__main__":
    main()

ZHENJIANG_BUDGET_SINGLE_COMMAND
