#!/bin/bash
# ID29 seq=285: read-only progress check on the two repair reruns and the whole matrix.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
CL="$ROOT/closure_20260810"

echo "=== TIME ==="; date --iso-8601=seconds

echo "=== REPAIR RERUNS 204860 / 204861 ==="
sacct -X -n -P -j 204860,204861 --format=JobID,JobName,State,Timelimit,Elapsed,NodeList 2>/dev/null || true
for J in 204860_6 204861_7; do
  echo "--- $J ---"
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
  if [ -n "$SO" ] && [ -f "$SO" ]; then
    echo "  log_bytes=$(stat -c %s "$SO")"
    tail -c 200000 "$SO" 2>/dev/null | tr '\r' '\n' | grep -iE 'epoch|it/s|%\|' | tail -3 || echo "  (no progress line yet)"
  else
    echo "  (no stdout yet)"
  fi
done

echo "=== ALL RUNNING / PENDING ==="
squeue -u sunyiq -o '%.12i %.9P %.14j %.9T %.12M %.12L %R' 2>/dev/null || true

echo "=== ROLE COUNTS ==="
source ~/miniconda3/etc/profile.d/conda.sh && conda activate nh_final 2>/dev/null
cd "$ROOT"
python - <<'PY' 2>/dev/null || echo "role recount unavailable"
import json, sys
from pathlib import Path
root = Path('/data1/home/sunyiq/nearing2022_da')
sys.path.insert(0, str(root / 'src/29_nearing2022_da_ar/scripts'))
from verify_registered_closure import audit_registered_closure
reg = root / 'src/29_nearing2022_da_ar/registry'
agg = root / 'closure_20260810/aggregation'
c = audit_registered_closure(root, reg/'experiment_registry.csv', reg/'evaluation_registry.csv',
                             reg/'assimilation_hyperparameter_registry.csv', agg/'evaluations', agg/'hyperparameters')
missing = {}
for row in c['missing']:
    missing[row['coordinate_type']] = missing.get(row['coordinate_type'], 0) + 1
print(json.dumps({'missing_by_type': missing, 'missing_total': len(c['missing']),
                  'registered_matrix_complete': c['complete']}, sort_keys=True))
PY

echo "=== TRAINING ARRAY 202215 STATE TALLY ==="
sacct -X -n -P -j 202215 --format=State 2>/dev/null | sort | uniq -c || true
echo "=== HYPER ARRAY 202228 STATE TALLY ==="
sacct -X -n -P -j 202228 --format=State 2>/dev/null | sort | uniq -c || true

echo "=== END seq=285 ==="; date --iso-8601=seconds
exit 0
