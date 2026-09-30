#!/bin/bash
set -eo pipefail

sequence=38
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
OUTPUT=$ROOT/formal_calibration_005
CAPSULE=$ROOT/deploy/formal_calibration_capsule_005
PYTHON=$ROOT/runtime_probe_005/bin/python
export PYTHONDONTWRITEBYTECODE=1

date -Is
squeue -j 233416 -o '%.18i %.24j %.9P %.10T %.30R' || true
sacct -j 233416 --format=JobIDRaw,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,MaxRSS,NCPUS,NodeList -P
sstat -j 233416.batch --format=JobID,AveCPU,MaxRSS -P || true

"$PYTHON" -B - "$OUTPUT" "$ROOT" <<'PY'
from collections import Counter, deque
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

output, root = map(Path, sys.argv[1:])
def read_receipt(path):
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))
def log_tail(path, count=10):
    if not path.is_file():
        return None
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        return list(deque(stream, maxlen=count))
def event_summary(path):
    if not path.is_file():
        return None
    events = deque(maxlen=16)
    counts = Counter()
    stages = Counter()
    latest_progress = {}
    unique_failures = set()
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                events.append({"unparsed_tail": line[-200:]})
                continue
            counts[event.get("event", "unknown")] += 1
            if event.get("event", "").endswith("_progress"):
                latest_progress[event["event"]] = event
            if event.get("event") == "candidate_failure":
                stages[event.get("stage", "unknown")] += 1
                unique_failures.add((event.get("stage"), event.get("parameter_id"), event.get("noise_id")))
            events.append(event)
    return {"count_by_event": dict(counts), "candidate_failures_by_stage": dict(stages), "unique_stage_parameter_noise_failures": len(unique_failures), "latest_progress": latest_progress, "last_events": list(events)}
ids = ["RL-E1-M06", "RL-E1-M12", "RL-E2-M06", "RL-E2-M12", "RL-E3-M06", "RL-E3-M12"]
workers = []
for exp_id in ids:
    directory = output / "calibration" / exp_id
    files = {path.name: {"bytes": path.stat().st_size, "mtime_unix": path.stat().st_mtime}
             for path in directory.iterdir() if path.is_file()} if directory.is_dir() else {}
    workers.append({
        "exp_id": exp_id,
        "directory_exists": directory.is_dir(),
        "files": files,
        "receipt": read_receipt(directory / "receipt.json"),
        "process": read_receipt(directory / "process.json"),
        "events": event_summary(directory / "events.jsonl"),
        "stdout_tail": log_tail(output / "calibration_process_logs" / f"{exp_id}.stdout.log"),
        "stderr_tail": log_tail(output / "calibration_process_logs" / f"{exp_id}.stderr.log"),
    })
print("MONITOR_JSON_BEGIN")
print(json.dumps({
    "observed_utc": datetime.now(timezone.utc).isoformat(),
    "job_id": "233416",
    "formal_attempt": "20260930-005",
    "batch_started": read_receipt(output / "batch_started.json"),
    "batch_failed": read_receipt(output / "batch_failed.json"),
    "batch_receipt": read_receipt(output / "batch_receipt.json"),
    "wrapper_failed": read_receipt(root / "wrapper_receipts/formal_calibration_005-233416.failed.json"),
    "batch_events": event_summary(output / "events.jsonl"),
    "slurm_stdout_tail": log_tail(root / "logs/formal_calibration_005-233416.out"),
    "slurm_stderr_tail": log_tail(root / "logs/formal_calibration_005-233416.err"),
    "workers": workers,
}, separators=(",", ":")))
print("MONITOR_JSON_END")
PY

sha256sum "$CAPSULE/capsule_manifest.json" "$CAPSULE/calibration_authorization.json"
echo FIFTH_ATTEMPT_STATUS_READ_COMPLETE
