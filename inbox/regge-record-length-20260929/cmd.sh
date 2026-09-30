#!/bin/bash
set -eo pipefail
sequence=40
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
PACKAGE=$ROOT/transport_package_005
CAPSULE=$ROOT/deploy/formal_calibration_capsule_005
PYTHON=$ROOT/runtime_probe_005/bin/python
export PYTHONDONTWRITEBYTECODE=1
date -Is
squeue -j 233430 -o '%.18i %.24j %.9P %.10T %.30R' || true
sacct -j 233430 --format=JobIDRaw,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,MaxRSS,NCPUS,NodeList -P
"$PYTHON" -B - "$ROOT" "$PACKAGE" <<'PY'
import base64
from collections import deque
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
root, package = map(Path, sys.argv[1:])
def read(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None
def tail(path):
    if not path.is_file():
        return None
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        return list(deque(stream, maxlen=40))
manifest = package / "transport_manifest.json"
signature = package / "transport_manifest.sig"
files = {p.name:dict(bytes=p.stat().st_size,mtime_unix=p.stat().st_mtime) for p in package.iterdir() if p.is_file()} if package.is_dir() else {}
observation = dict(schema="regge_record_length_package_observation_v01", observed_utc=datetime.now(timezone.utc).isoformat(),
 formal_attempt="20260930-005", calibration_job_id="233416", package_job_id="233430", package_root=str(package),
 package_directory_exists=package.is_dir(), files=files, manifest=read(manifest),
 signature_base64=base64.b64encode(signature.read_bytes()).decode("ascii") if signature.is_file() else None,
 submission_receipt=read(root / "submission_receipts/package_005-233430.json"),
 wrapper_failed=read(root / "wrapper_receipts/package_005-233430.failed.json"),
 submission_failed=read(root / "submission_receipts/package_005-seq39.failed.json"),
 stdout_tail=tail(root / "logs/package_005-233430.out"),
 stderr_tail=tail(root / "logs/package_005-233430.err"))
print("PACKAGE_OBSERVATION_BEGIN")
print(json.dumps(observation, separators=(",", ":")))
print("PACKAGE_OBSERVATION_END")
PY
sha256sum "$CAPSULE/capsule_manifest.json" "$CAPSULE/calibration_authorization.json"
echo FIFTH_ATTEMPT_PACKAGE_STATUS_READ_COMPLETE
