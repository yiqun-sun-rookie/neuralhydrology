#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'READ_ONLY_226203_PY'
"""Read-only, fixed-job metadata query. No deployed imports or compute actions."""
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import stat
import subprocess
import time

ROOT = Path("/data1/home/sunyiq/zhenjiang_shared_base_20260916_001")
ROOT_ID = [41, 7011215874]
RELEASE = "49a27c4d9ea0f4f1843d581c780adfa554e8dc4498623cdc2c277aed3aa7856a"
JOB = "226203"
NONCE = "5a56f823f0914963b098660929f6f28a"
ATTEMPT_SHA = "2d4a253aab012cb44de46395cb057c2812a78afc36a2948a51668b60251fb9d3"
METADATA = (
    "deployment.json", "submission/preflight/attempt.json",
    "submission/preflight/submitted.json", "submission/preflight/failure.json",
    "preflight/attempt.json", "preflight/environment.json", "preflight/failure.json",
    "preflight/complete.json", "preflight/result.json", "preflight/measurement.json",
    "preflight/preparation.json", "preflight/data_identity.json",
)
LOG = "slurm/preflight-226203.out"

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def document(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))

def safe(path):
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("unsafe absolute path")
    for item in (path, *path.parents):
        meta = item.lstat()
        if stat.S_ISLNK(meta.st_mode) or getattr(meta, "st_file_attributes", 0) & 0x400:
            raise ValueError("redirected path")
    return path

def identity(path):
    meta = safe(path).stat()
    return [meta.st_dev, meta.st_ino]

class Reader:
    def __init__(self):
        if identity(ROOT) != ROOT_ID:
            raise ValueError("fixed deployment root identity differs")
        self.allowed = {"release_manifest.json": 2_000_000}
        self.seen, self.total = set(), 0

    def read(self, name, maximum=None):
        if name not in self.allowed or name in self.seen:
            raise ValueError("unknown or repeated read")
        if identity(ROOT) != ROOT_ID:
            raise ValueError("root changed before file lookup")
        self.seen.add(name)
        cap = self.allowed[name] if maximum is None else min(maximum, self.allowed[name])
        path = ROOT / name
        try:
            before = safe(path).stat()
        except FileNotFoundError:
            for parent in path.parents:
                try:
                    safe(parent)
                except FileNotFoundError:
                    continue
            if identity(ROOT) != ROOT_ID:
                raise ValueError("root changed during missing-file lookup")
            return None
        if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1
                or not 0 <= before.st_size <= cap or self.total + before.st_size > 8_000_000):
            raise ValueError("file type or read budget differs")
        parent_id = identity(path.parent)
        if identity(ROOT) != ROOT_ID or identity(path.parent) != parent_id:
            raise ValueError("root or parent changed before open")
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0))
        with os.fdopen(fd, "rb", buffering=0) as handle:
            opened = os.fstat(handle.fileno())
            if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns, opened.st_nlink) != (
                    before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, 1):
                raise ValueError("file changed before open")
            parts, remaining = [], before.st_size
            while remaining:
                part = handle.read(remaining)
                if not part:
                    break
                parts.append(part)
                remaining -= len(part)
            raw = b"".join(parts)
            after = os.fstat(handle.fileno())
        visible = safe(path).stat()
        if (remaining or identity(ROOT) != ROOT_ID or identity(path.parent) != parent_id
                or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) !=
                (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                or (visible.st_dev, visible.st_ino) != (before.st_dev, before.st_ino)):
            raise ValueError("file changed during read")
        self.total += len(raw)
        return raw, {"path": str(path), "bytes": len(raw), "sha256": sha(raw)}

    def json(self, name):
        result = self.read(name)
        if result is None:
            return None
        raw, spec = result
        value = document(raw)
        if not isinstance(value, dict):
            raise ValueError("metadata must be a JSON object")
        return {"value": value, "spec": spec}

def verify_sources(reader):
    manifest = reader.json("release_manifest.json")
    if manifest is None or manifest["spec"]["sha256"] != RELEASE:
        raise ValueError("published manifest identity differs")
    value = manifest["value"]
    rows = value.get("files")
    if value.get("remote_root") != str(ROOT) or not isinstance(rows, list) or len(rows) != 25:
        raise ValueError("release root or member count differs")
    names = set()
    for row in rows:
        name = row.get("path")
        if (set(row) != {"path", "bytes", "sha256"} or not isinstance(name, str)
                or name in names or any(part in ("", ".", "..") for part in name.split("/"))
                or "\\" in name or ":" in name or not name.endswith((".py", ".json"))
                or type(row["bytes"]) is not int or not 0 < row["bytes"] <= 2_000_000
                or not re.fullmatch("[0-9a-f]{64}", row["sha256"])):
            raise ValueError("unsafe manifest source")
        names.add(name)
        reader.allowed[name] = row["bytes"]
        result = reader.read(name)
        if result is None or result[1]["bytes"] != row["bytes"] or result[1]["sha256"] != row["sha256"]:
            raise ValueError("published source identity differs")
    return manifest["spec"]

def query_scheduler(command):
    """Linux-only query subprocess, 15 seconds and 32768 combined bytes."""
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               stdin=subprocess.DEVNULL, shell=False)
    output, deadline = bytearray(), time.monotonic() + 15
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("scheduler query exceeded 15 seconds")
                events = selector.select(min(remaining, 1))
                for key, _ in events:
                    raw = os.read(key.fileobj.fileno(), 32769 - len(output))
                    if not raw:
                        selector.unregister(key.fileobj)
                    else:
                        output.extend(raw)
                        if len(output) > 32768:
                            raise ValueError("scheduler output exceeds 32768 bytes")
        code = process.wait(timeout=max(.001, deadline-time.monotonic()))
    finally:
        if process.poll() is None:
            process.kill()  # Kills only this squeue/sacct client, never the Slurm job.
            process.wait(timeout=5)
        process.stdout.close()
    return {"argv": command, "returncode": code, "stdout": output.decode("utf-8", errors="replace")}

def run():
    reader = Reader()
    manifest_spec = verify_sources(reader)
    reader.allowed.update({name: 500_000 for name in METADATA})
    reader.allowed[LOG] = 65536
    records = {}
    # Bind root, release, nonce and submitted job before scheduler/log reads.
    for name in METADATA[:3]:
        records[name] = reader.json(name)
        if records[name] is None:
            raise ValueError("required deployment/submission metadata absent")
    deployed = records["deployment.json"]["value"]
    attempt = records["submission/preflight/attempt.json"]
    submitted = records["submission/preflight/submitted.json"]["value"]
    for value in (deployed, attempt["value"], submitted):
        if value.get("release_sha256") != RELEASE or value.get("root_identity") != ROOT_ID:
            raise ValueError("metadata release or root differs")
    if (attempt["spec"]["sha256"] != ATTEMPT_SHA or attempt["spec"]["bytes"] != 236
            or submitted.get("status") != "submitted" or submitted.get("stage") != "preflight"
            or submitted.get("job_id") != JOB or submitted.get("nonce") != NONCE
            or submitted.get("attempt_spec") != attempt["spec"]
            or submitted.get("script_spec") != {"path": str(ROOT / "submission/preflight/job.sh"),
                "bytes": 4662, "sha256": "46f7c06b4f3f4880221669c550f831f7eeab64bcbf83a75cf58d807c36bf27b7"}):
        raise ValueError("exact submitted preflight job binding differs")
    for name in METADATA[3:]:
        records[name] = reader.json(name)
    complete = records["preflight/complete.json"]
    for name in ("preflight/failure.json", "preflight/complete.json"):
        row = records[name]
        if row is not None and (row["value"].get("stage") != "preflight"
                or row["value"].get("job_id") != JOB or row["value"].get("release_sha256") != RELEASE):
            raise ValueError("preflight record belongs to another job")
    if complete is not None:
        value = complete["value"]
        if value.get("status") != "complete" or value.get("root_identity") != ROOT_ID:
            raise ValueError("complete root/status differs")
        for field, name in (("result_spec", "preflight/result.json"), ("preparation_spec", "preflight/preparation.json")):
            if records[name] is None or value.get(field) != records[name]["spec"]:
                raise ValueError("completed artifact pointer differs")
    preparation = records["preflight/preparation.json"]
    if preparation is not None:
        prep = preparation["value"]
        payload = dict(prep)
        if payload.pop("preparation_sha256", None) != sha(canonical(payload)):
            raise ValueError("preparation self identity differs")
        tide = dict(prep["tide"])
        if tide.pop("document_sha256", None) != sha(canonical(tide)):
            raise ValueError("tide self identity differs")
        # Dates, counts, diagnostics and identities only; coefficients not transferred.
        tide.pop("constituents")
        preparation["value"] = {"preparation_sha256": prep["preparation_sha256"],
                                "tide": tide, "normalization": prep["normalization"]}
    scheduler = {}
    for name, command in (
        ("queue", ["squeue", "--noheader", "--jobs", JOB, "--format=%i|%T|%M|%l|%R"]),
        ("accounting", ["sacct", "--noheader", "--parsable2", "--jobs", JOB,
                        "--format=JobIDRaw,State,ExitCode,ElapsedRaw,AllocTRES"]),
    ):
        reply = query_scheduler(command)
        if reply["returncode"] == 0:
            for line in reply["stdout"].splitlines():
                if line.strip():
                    actual = line.split("|", 1)[0].strip()
                    if actual != JOB and not actual.startswith(JOB + "."):
                        raise ValueError("scheduler returned unrelated job")
        scheduler[name] = reply
    log = reader.read(LOG)
    log_value = None if log is None else {"spec": log[1], "text": log[0].decode("utf-8", errors="replace")}
    report = {"status": "read_only_snapshot_not_a_pass_decision", "job_id": JOB,
              "release_spec": manifest_spec, "root_identity": ROOT_ID,
              "records": records, "scheduler": scheduler, "log": log_value,
              "metadata_and_source_read_bytes": reader.total, "read_names": sorted(reader.seen)}
    if identity(ROOT) != ROOT_ID or len(canonical(report)) > 2_000_000:
        raise ValueError("root identity or total output bound differs")
    return report

if __name__ == "__main__":
    print(canonical(run()).decode("utf-8"))

READ_ONLY_226203_PY
