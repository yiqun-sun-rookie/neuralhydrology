#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -X utf8 -B - <<'READ_ONLY_EXPORT'
import argparse, base64, gzip, hashlib, io, json, subprocess, tarfile
from pathlib import Path
PHASE = Path("/data1/home/sunyiq/kalmannet_original_noise_multiday_20261007_attempt1")
RESULT = PHASE / "results"
def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))
def export(start, stop, chunk):
    label = f"batch_{start:03d}_{stop:03d}"
    submission = read_json(PHASE / "submissions" / (label + ".json"))
    receipt_path = RESULT / "control" / (label + "_execution_receipt.json")
    receipt = read_json(receipt_path) if receipt_path.exists() else None
    job = submission["job_id"]
    queued = subprocess.run(["squeue", "--user=sunyiq", "--name=original-noise-multiday", "--noheader", "--format=%i %t"],
                            check=True, capture_output=True, text=True, timeout=45).stdout.strip()
    accounting = subprocess.run(["sacct", "-X", "-n", "-P", "-j", job, "-o", "JobID,State,ExitCode"],
                                check=True, capture_output=True, text=True, timeout=45).stdout.strip()
    rows = [line.split("|") for line in accounting.splitlines() if line.split("|")[0] == job]
    terminal = {"COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL", "PREEMPTED"}
    if queued or len(rows) != 1 or rows[0][1].split()[0] not in terminal:
        raise RuntimeError("Only an independently confirmed inactive terminal job may be exported")
    contract = read_json(RESULT / "control/contract_v4.json")
    paths = []
    complete = receipt is not None and receipt["exit_code"] == 0 and receipt["stop_reason"] is None and rows[0][1] == "COMPLETED" and rows[0][2] == "0:0"
    for basin in contract["basins"][start:stop]:
        row_path = RESULT / "basins" / (basin + ".json")
        if not row_path.exists() or read_json(row_path)["status"] != "COMPUTED_PENDING_INDEPENDENT_REVIEW":
            complete = False
        for suffix in (".json", ".npz", ".failure.json"):
            path = RESULT / "basins" / (basin + suffix)
            if path.exists():
                paths.append(path)
    paths.extend((RESULT / "control").glob(label + "_*"))
    paths.extend((PHASE / "submissions").glob(label + "*.json"))
    paths.extend((PHASE / "logs").glob("job-" + submission["job_id"] + ".*"))
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as archive:
            for path in sorted(paths):
                archive.add(path, arcname=path.relative_to(PHASE).as_posix(), recursive=False)
    data = buffer.getvalue()
    width = 8 * 1024 * 1024
    count = (len(data) + width - 1) // width
    if not 0 <= chunk < count:
        raise RuntimeError("Export chunk outside range")
    segment = data[chunk * width:(chunk + 1) * width]
    metadata = {"batch": [start, stop], "chunk": chunk, "chunks": count, "bytes": len(data),
                "batch_result_status": "COMPLETE" if complete else "FAILED_OR_PARTIAL", "accounting": accounting,
                "sha256": hashlib.sha256(data).hexdigest(), "chunk_bytes": len(segment),
                "chunk_sha256": hashlib.sha256(segment).hexdigest()}
    print("EXPORT_JSON=" + json.dumps(metadata), flush=True)
    print("EXPORT_BASE64=" + base64.b64encode(segment).decode("ascii"), flush=True)
print("DIAGNOSIS_JSON=" + json.dumps({"failed_basin": read_json(RESULT / "basins/01031500.json"), "failed_reference": read_json(RESULT / "inputs/metadata/01031500.json")["historical_record"], "completed_basin": read_json(RESULT / "basins/01022500.json")}))
export(0, 195, 0)
READ_ONLY_EXPORT
