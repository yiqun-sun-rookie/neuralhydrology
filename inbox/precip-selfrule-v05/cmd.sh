#!/bin/bash
# precip-selfrule-v05 seq=24: preflight reference source inventory and Slurm accounting fields.
set -eo pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_concurrency4_probe_20260929
REF=/data1/home/sunyiq/precip_input_selfrule_time_v05_batch384_probe_20260929/reference_batch128/run01/RUN_MANIFEST.json

date "+wallclock %F %T %z"
test ! -e "$ROOT" || { echo "PROBE_ROOT_ALREADY_EXISTS=$ROOT"; exit 1; }
python - "$REF" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
keys = []
for entry in payload["source_files"]:
    value = str(entry["path"]).replace("\\", "/")
    if any(token in value for token in ("concurrency", "formal96", "finalize")):
        keys.append(value)
print("REFERENCE_SOURCE_COUNT", len(payload["source_files"]))
print("REFERENCE_RELEVANT_SOURCE_COUNT", len(keys))
for value in keys:
    print(value)
PY
echo "=== SACCT FIELD SHAPE ==="
sacct -j 231258 --noheader --parsable2 --format=JobIDRaw,State,ExitCode,ElapsedRaw
echo "=== CURRENT USER JOBS (READ ONLY) ==="
squeue -u "$USER" -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
