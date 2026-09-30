#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_ARCH_SUBMIT'
"""Template for one bounded 24-task cluster array submission.

The builder replaces both placeholders after a verified deployment receipt.
This command never retries an ambiguous scheduler response.
"""
from __future__ import annotations

import base64
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess


RECEIPT_BASE64 = "eyJjb25kaXRpb25hbF9ydW5zX25vdF9zY2hlZHVsZWQiOjAsImV4cGVjdGVkX2Vwb2NoX3JlY29yZHMiOjI0MjQsImV4cGVyaW1lbnRfaWQiOiJ6aGVuamlhbmdfdGFyZ2V0X3N0YXRlX2RpYWdub3N0aWNfMjAyNjA5MzBfMDAxIiwiam9iX3NoYTI1NiI6IjYxYTY0YmFmMzI1NTYwZDMxZGU3OTBlMTgyOWRmZmU4ZmIxOGVjZTVkZjBlNzFkOTdmYmI4M2Y5OTg0MjQ2MTUiLCJtYW5kYXRvcnlfcnVucyI6MjQsIm1hbmlmZXN0X3NoYTI1NiI6ImNkMDViMzc1NWU5ZmE2NzVlMWM2ZDQ5OTVmMDAxNmU2NWQyNzcyODdhOTdjMjhlODJmMmQ0MmJjYjM2ZGNiYjkiLCJtZW1iZXJzIjo3NywicGF5bG9hZF9ieXRlcyI6MTU3MjI0LCJwYXlsb2FkX2luZGV4X3NoYTI1NiI6ImMzODBiYzUzMTZkODhkOTNjMTU3YjZjZjdhMTQ2NDgyNGU0MGY2ZjI2OWIzZTk1NmRlM2VlOTkyMGYyYTZkZGIiLCJwYXlsb2FkX3NoYTI1NiI6ImQ4YWViYzNiZWVmMDgxMjE4NGQzNTFmZjBlYmVjOTk0YjdhMjFhZTgwMzYwM2EwYjk3YWVmMzBiZTJlMDViMDEiLCJwcm90b2NvbF9zaGEyNTYiOiJmY2EwODgwYmRlMjRkMzM5MmNmZTJmMjhkZjdjZTdkMTc5N2U0YTE1Mzk2NjJjNmQxNTljNTBkZDYyNTEyN2ZhIiwicmVnaXN0cnlfc2hhMjU2IjoiODRjNzA3ZmQ0MGYzN2Q5NTU0MTdhZGQwYTViZDA4YzdlYzg1MTJlYzI2NmY4MjUxMDQzM2IwOTRjMTE4NThhZCIsInJlbW90ZV9yb290IjoiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ190YXJnZXRfc3RhdGVfZGlhZ25vc3RpY18yMDI2MDkzMF8wMDEiLCJzb3VyY2VfZGF0YV9maWxlcyI6MTAsInN0YXR1cyI6IlNFQUxFRF9MT0NBTF9OT1RfREVQTE9ZRURfTk9UX1NVQk1JVFRFRCJ9"
EXPECTED_DEPLOYMENT_SHA = "83cd01d71fb6d85a816a0eb839c65558023b52442b4f0cecb9c2456deebc672f"
REMOTE = "/data1/home/sunyiq/zhenjiang_target_state_diagnostic_20260930_001"


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
            or registry["mandatory_runs"] != 24
            or registry["expected_epoch_records_including_initial_state"] != 2424
            or len(registry["runs"]) != 24
            or registry["training_years"] != [2017, 2018, 2019, 2020, 2021]
            or registry["selection_year"] != 2022
            or registry["epochs_per_run"] != 100
            or registry["seeds"] != [17, 29, 43]
            or len(registry["training_sources"]) != 10):
        raise ValueError("scientific experiment protocol differs")
    expected_matrix = set(itertools.product(("available", "ideal_observed"),
                         ("nanjing", "zhenjiang", "jiangyin", "xuliujing"), (17, 29, 43)))
    if {(row["information_arm"], row["training_target"], row["seed"])
            for row in registry["runs"]} != expected_matrix:
        raise ValueError("diagnostic run matrix differs")
    for row in registry["runs"]:
        if (row["model_implementation"] != "single_explicit_target_state_with_eight_channel_history"
                or row["allocated_trainable_parameters"] != 4911
                or row["output_dimensions"] != 1 or row["state_or_hidden_width"] != 33
                or row["epochs"] != 100):
            raise ValueError("diagnostic model definition differs")
    for relative, expected in manifest["files"].items():
        path = root / relative
        if (path.is_symlink() or not path.is_file()
                or path.stat().st_size != expected["bytes"]
                or sha(path.read_bytes()) != expected["sha256"]):
            raise ValueError("sealed source changed before submission: " + relative)
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
               "planned_tasks": 24,
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
                          "root": REMOTE, "planned_tasks": 24,
                          "maximum_simultaneous_gpu_tasks": 2}), flush=True)
    except BaseException as error:
        write_new(submission / "failure.json", canonical({
            "status": "STOPPED_NO_RETRY", "submission_uncertain": True,
            "error": str(error)[:2000]}))
        raise


if __name__ == "__main__":
    main()

ZJ_ARCH_SUBMIT
