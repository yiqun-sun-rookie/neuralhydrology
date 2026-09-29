#!/bin/bash
# precip-selfrule-v05 seq=13: compact read-only technical progress.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r03
OUT="$ROOT/technical_8/run01"
date "+wallclock %F %T %z"
squeue -j 231273 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
sacct -j 231273 --format=JobID,State,ExitCode,Elapsed,MaxRSS,NodeList%14 -P || true
printf 'COMPLETE_RECORDS='
python - "$OUT" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])/'fit'
records=[]
for path in sorted(root.glob('*.json')) if root.exists() else []:
    try:
        data=json.loads(path.read_text())
    except Exception:
        continue
    if data.get('technical_complete') is True:
        records.append((data['basin'], data.get('peak_gpu_bytes')))
print(len(records), records)
PY