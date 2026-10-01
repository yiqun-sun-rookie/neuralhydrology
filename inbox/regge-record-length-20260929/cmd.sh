#!/bin/bash
set -eo pipefail
sequence=45
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
export PYTHONDONTWRITEBYTECODE=1
"$ROOT/runtime_probe_005/bin/python" -B - <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
state = Path("/data1/home/sunyiq/regge_record_length_20260929_001/return_transfer_private_001")
observation = {"schema":"regge_private_return_observation_v01", "formal_attempt":"20260930-005", "sequence":45, "observed_utc":datetime.now(timezone.utc).isoformat(), "state_directory":str(state), "receipts":{}}
for name in ("launch.requested.json", "launch.complete.json", "launch.failed.json", "worker.started.json", "upload.complete.json", "upload.failed.json"):
    path = state / name
    if path.exists():
        if path.is_symlink() or path.stat().st_size > 65536:
            raise RuntimeError("untrusted_private_transfer_receipt")
        data = path.read_bytes()
        try:
            value = json.loads(data)
        except (ValueError, UnicodeError):
            observation["receipts"][name] = {"status":"not_yet_complete", "bytes":len(data)}
        else:
            observation["receipts"][name] = {"sha256":hashlib.sha256(data).hexdigest(), "value":value}
events = state / "events.jsonl"
if events.exists():
    if events.is_symlink() or events.stat().st_size > 1048576:
        raise RuntimeError("untrusted_private_transfer_events")
    observation["events"] = []
    for line in events.read_text().splitlines()[-20:]:
        try:
            observation["events"].append(json.loads(line))
        except ValueError:
            observation["event_write_not_yet_complete"] = True
launched = observation["receipts"].get("launch.complete.json", {}).get("value", {})
pid = launched.get("pid")
if type(pid) is int and pid > 1:
    proc = Path("/proc") / str(pid) / "cmdline"
    observation["worker_pid"] = pid
    observation["worker_pid_exists"] = proc.exists()
    if proc.exists():
        command = proc.read_bytes().split(b"\0")
        observation["worker_identity_matches"] = str(state / "encrypted_upload.py").encode() in command and b"--worker" in command
print("PRIVATE_RETURN_OBSERVATION_BEGIN")
print(json.dumps(observation,separators=(",",":")))
print("PRIVATE_RETURN_OBSERVATION_END")
PY
echo FIFTH_ATTEMPT_PRIVATE_RETURN_OBSERVATION_COMPLETE
