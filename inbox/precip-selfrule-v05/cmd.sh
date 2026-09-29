#!/bin/bash
# precip-selfrule-v05 seq=12: read-only progress after scheduler-wrapper repair.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r03
OUT="$ROOT/technical_8/run01"

date "+wallclock %F %T %z"
echo "=== SQUEUE ==="
squeue -j 231259,231273 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
echo "=== SACCT ==="
sacct -j 231259,231273 --format=JobID,JobName%24,State,ExitCode,Elapsed,AllocTRES%40,MaxRSS,NodeList%14 -P || true
echo "=== RECORDS ==="
for basin in 02137727 02245500 09404450 09512280 01054200 01142500 01144000 01169000; do
  if test -f "$OUT/fit/$basin.json"; then
    python - "$OUT/fit/$basin.json" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
print(p['basin'], p.get('technical_complete'), p.get('peak_gpu_bytes'),
      p['rain']['rain_intensity']['fit'].get('elapsed_seconds'),
      p['rain']['rain_season']['fit'].get('elapsed_seconds'))
PY
  else
    echo "$basin PENDING"
  fi
done