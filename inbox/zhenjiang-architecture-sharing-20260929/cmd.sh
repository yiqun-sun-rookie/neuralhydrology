#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_ARCH_SUBMIT'
"""Template for one bounded 114-task cluster array submission.

The builder replaces both placeholders after a verified deployment receipt.
This command never retries an ambiguous scheduler response.
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


RECEIPT_BASE64 = "eyJjb25kaXRpb25hbF9ydW5zX25vdF9zY2hlZHVsZWQiOjI0LCJleHBlcmltZW50X2lkIjoiemhlbmppYW5nX2FyY2hpdGVjdHVyZV9zaGFyaW5nXzIwMjYwOTI5XzAwMSIsImpvYl9zaGEyNTYiOiJiODUyYTZlNTdiMjliYTc5YjkxZTkxYjVjNGNiMjFjZmRkZDhhMzU2YmU5OTRiY2E2MmYxZWQ3Y2MyYmQ5ZTJkIiwibWFuZGF0b3J5X3J1bnMiOjExNCwibWFuaWZlc3Rfc2hhMjU2IjoiMzIwYTQ1NTYyZDFmMmNlZDZiOGJhZjE2NWE3Nzc0MTU1OTZkMmVjZjFlNzAzMWM2NDcxMWRmMmY1ZjAyYTA2YyIsIm1lbWJlcnMiOjE2NywicGF5bG9hZF9ieXRlcyI6MTc0ODg1LCJwYXlsb2FkX2luZGV4X3NoYTI1NiI6IjVjNzFkNjRhYzkzYjRlZWVjOTcyOWE1MTU3ZDYyMTcyMWI1OGU4MzljZTI4NGViZTMzOGYxYTA5ZGEwNGVmNzAiLCJwYXlsb2FkX3NoYTI1NiI6ImYyOTI1ODBiOTEyN2Q4MjJhYzBhNzE1NjU3MzM5NjBiMWRkNmRjOGY0YmU0NTJmNGNhNWI2ZDRiNWJjZWY0ODciLCJwcm90b2NvbF9zaGEyNTYiOiIxYzllMGUxMTZmZWE0OGViZWRlZjc2NjcwZTgyMzYxYjI3YjE2MTg4OWMzNjFjYmEzODk3Yzc5NWZhMTUwMzc4IiwicmVnaXN0cnlfc2hhMjU2IjoiYmJiMDdhZjkwNDczYmExMTM2MDQzZWNlYWE1YTA5YmI2ZDA4NWRiMTcyZDdlMzdlMWZlOWExODVlMTExNzliZiIsInJlbW90ZV9yb290IjoiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19hcmNoaXRlY3R1cmVfc2hhcmluZ18yMDI2MDkyOV8wMDEiLCJzb3VyY2VfZGF0YV9maWxlcyI6MTAsInN0YXR1cyI6IlNFQUxFRF9MT0NBTF9OT1RfREVQTE9ZRURfTk9UX1NVQk1JVFRFRCJ9"
EXPECTED_DEPLOYMENT_SHA = "f4d409049b4b13d03cf76ac1026d5514da9acbab5cd44d6c082e6ce7398905ac"
REMOTE = "/data1/home/sunyiq/zhenjiang_architecture_sharing_20260929_001"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"), allow_nan=False).encode()


def write_new(path, raw):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    handle = os.open(path, flags, 0o600)
    with os.fdopen(handle, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def main():
    receipt = json.loads(base64.b64decode(RECEIPT_BASE64, validate=True))
    root = Path(REMOTE)
    deployment = root / "deploy/deployment.json"
    registry_path = root / "registry_frozen.json"
    manifest_path = root / "reports/training_manifest.json"
    job = root / "deploy/job.sh"
    if (receipt["remote_root"] != REMOTE or root.is_symlink() or not root.is_dir()
            or os.path.lexists(root / "submission")
            or os.path.lexists(root / "runs")
            or not (root / "slurm").is_dir()
            or shutil.which("sbatch") is None):
        raise ValueError("exclusive one-submission precondition differs")
    raw = deployment.read_bytes()
    deployed = json.loads(raw)
    binding = {"device": root.stat().st_dev, "inode": root.stat().st_ino,
               "uid": root.stat().st_uid,
               "mode": stat.S_IMODE(root.stat().st_mode)}
    if (sha(raw) != EXPECTED_DEPLOYMENT_SHA
            or deployed["status"] != "DEPLOYED_NO_TRAINING"
            or deployed["root"] != REMOTE
            or deployed["root_binding"] != binding
            or binding["mode"] != 0o700
            or deployed["payload_sha256"] != receipt["payload_sha256"]
            or deployed["protocol_sha256"] != receipt["protocol_sha256"]
            or deployed["registry_sha256"] != receipt["registry_sha256"]
            or deployed["manifest_sha256"] != receipt["manifest_sha256"]
            or deployed["job_sha256"] != receipt["job_sha256"]
            or sha(registry_path.read_bytes()) != receipt["registry_sha256"]
            or sha(manifest_path.read_bytes()) != receipt["manifest_sha256"]
            or sha(job.read_bytes()) != receipt["job_sha256"]):
        raise ValueError("deployed training package identity differs")
    registry = json.loads(registry_path.read_bytes())
    manifest = json.loads(manifest_path.read_bytes())
    if (registry["experiment_id"] != receipt["experiment_id"]
            or manifest["experiment_id"] != receipt["experiment_id"]
            or registry["status"] != "FROZEN_FOR_SINGLE_SUBMISSION"
            or registry["execution_ready"] is not True
            or registry["mandatory_runs"] != 114
            or registry["expected_epoch_records_including_initial_state"] != 11514
            or len(registry["runs"]) != 114
            or registry["training_years"] != [2017, 2018, 2019, 2020, 2021]
            or registry["selection_year"] != 2022
            or registry["epochs_per_run"] != 100
            or registry["seeds"] != [17, 29, 43]
            or len(registry["training_sources"]) != 10):
        raise ValueError("scientific experiment protocol differs")
    partition = subprocess.run(["scontrol", "show", "partition", "hgpu2p", "-o"],
                               capture_output=True, text=True, timeout=15, check=False)
    if partition.returncode != 0 or "PartitionName=hgpu2p" not in partition.stdout:
        raise ValueError("intended GPU partition is unavailable")

    # Reservation happens before sbatch, so an ambiguous reply cannot trigger
    # another submission into this root.
    submission = root / "submission"
    submission.mkdir(mode=0o700)
    attempt = {"status": "RESERVED_NO_RETRY", "root": REMOTE,
               "root_binding": binding,
               "deployment_sha256": EXPECTED_DEPLOYMENT_SHA,
               "registry_sha256": receipt["registry_sha256"],
               "manifest_sha256": receipt["manifest_sha256"],
               "job_sha256": receipt["job_sha256"],
               "planned_tasks": 114,
               "maximum_simultaneous_gpu_tasks": 2,
               "time_limit_per_task": "02:00:00"}
    attempt_raw = canonical(attempt)
    write_new(submission / "attempt.json", attempt_raw)
    # The campus sbatch wrapper can silently decline command-line options.
    # Every scheduler option is bound in the audited job script instead.
    command = ["sbatch", str(job)]
    write_new(submission / "command.json", canonical({
        "argv": command, "attempt_sha256": sha(attempt_raw)}))
    clean_environment = {key: value for key, value in os.environ.items()
                         if not key.upper().startswith("SBATCH_")}
    try:
        response = subprocess.run(command, capture_output=True, text=True,
                                  encoding="utf-8", errors="replace", timeout=30,
                                  check=False, env=clean_environment)
        if len(response.stdout.encode()) + len(response.stderr.encode()) > 8192:
            raise ValueError("scheduler reply exceeds bound")
        write_new(submission / "scheduler_reply.json", canonical({
            "returncode": response.returncode,
            "stdout": response.stdout, "stderr": response.stderr}))
        matches = re.findall(r"Submitted batch job ([1-9][0-9]*)",
                             response.stdout)
        if response.returncode != 0 or len(matches) != 1:
            raise ValueError("scheduler submission uncertain; no retry")
        success = {**attempt, "status": "SUBMITTED_ONCE",
                   "job_id": matches[0],
                   "attempt_sha256": sha(attempt_raw)}
        write_new(submission / "submitted.json", canonical(success))
        print(json.dumps({"status": "SUBMITTED_ONCE", "job_id": matches[0],
                          "root": REMOTE, "planned_tasks": 114,
                          "maximum_simultaneous_gpu_tasks": 2}), flush=True)
    except BaseException as error:
        write_new(submission / "failure.json", canonical({
            "status": "STOPPED_NO_RETRY", "submission_uncertain": True,
            "error": str(error)[:2000]}))
        raise


if __name__ == "__main__":
    main()

ZJ_ARCH_SUBMIT
