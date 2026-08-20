#!/bin/bash
# ID29 seq=287: progress check on the two repair reruns + whole-matrix role counts.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== TIME ==="; date --iso-8601=seconds

echo "=== REPAIR RERUNS ==="
sacct -X -n -P -j 204860,204861 --format=JobID,State,Elapsed,Timelimit,End,NodeList 2>/dev/null || true
for J in 204860_6 204861_7; do
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
  if [ -n "$SO" ] && [ -f "$SO" ]; then
    printf -- '--- %s (running) ---\n' "$J"
    tail -c 120000 "$SO" 2>/dev/null | tr '\r' '\n' | grep -iE '^# Epoch' | tail -1 || true
  else
    printf -- '--- %s (no live record; check checkpoints) ---\n' "$J"
  fi
done

echo "=== CHECKPOINTS OF THE TWO RERUN COORDINATES ==="
for C in lead_2_holdout_0.75_seed_0 lead_2_holdout_1.0_seed_0; do
  D=$(find "$ROOT/closure_20260810/time_split/autoregression" -maxdepth 1 -type d -name "*${C}*" 2>/dev/null | tail -1)
  if [ -n "$D" ]; then
    printf '%s -> epoch30=%s  latest=%s\n' "$C" \
      "$([ -f "$D/model_epoch030.pt" ] && echo YES || echo no)" \
      "$(ls "$D"/model_epoch*.pt 2>/dev/null | tail -1 | xargs -r basename)"
  else
    echo "$C -> run dir not found"
  fi
done

echo "=== ROLE COUNTS ==="
source ~/miniconda3/etc/profile.d/conda.sh && conda activate nh_final 2>/dev/null
cd "$ROOT"
python - <<'PY' 2>/dev/null || echo "recount unavailable"
import json, sys
from pathlib import Path
root = Path('/data1/home/sunyiq/nearing2022_da')
sys.path.insert(0, str(root / 'src/29_nearing2022_da_ar/scripts'))
from verify_registered_closure import audit_registered_closure
reg = root / 'src/29_nearing2022_da_ar/registry'
agg = root / 'closure_20260810/aggregation'
c = audit_registered_closure(root, reg/'experiment_registry.csv', reg/'evaluation_registry.csv',
                             reg/'assimilation_hyperparameter_registry.csv', agg/'evaluations', agg/'hyperparameters')
m = {}
for row in c['missing']:
    m[row['coordinate_type']] = m.get(row['coordinate_type'], 0) + 1
print(json.dumps({'missing_by_type': m, 'missing_total': len(c['missing'])}, sort_keys=True))
PY

echo "=== ARRAY TALLIES ==="
printf '202215 (time train): '; sacct -X -n -P -j 202215 --format=State 2>/dev/null | sort | uniq -c | tr '\n' ' '; echo
printf '202228 (hyper): '; sacct -X -n -P -j 202228 --format=State 2>/dev/null | sort | uniq -c | tr '\n' ' '; echo

echo "=== MY QUEUE ==="
squeue -u sunyiq -h -o '%.12i %.14j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22|retime' | head -12 || echo 'no N22 jobs in queue'

echo "=== END seq=287 ==="; date --iso-8601=seconds
exit 0
