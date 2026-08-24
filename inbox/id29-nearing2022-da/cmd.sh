set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.14j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22|retime|re214' || echo 'no N22 jobs in queue'
echo "=== RECENT TERMINAL STATES ==="
sacct -X -n -P -S $(date -d '3 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22|retime|re214' | grep -vE '\|(RUNNING|PENDING)\|' | tail -20 || true
echo "=== RUNNING PROGRESS ==="
for J in $(squeue -u sunyiq -h -o '%i %j' 2>/dev/null | grep -E 'N22-(time|retime|re214)' | awk '{print $1}'); do
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
  [ -n "$SO" ] && [ -f "$SO" ] && { printf -- '--- %s log=%s ---\n' "$J" "$(stat -c %s "$SO")"; tail -c 120000 "$SO" 2>/dev/null | tr '\r' '\n' | grep -iE '^# Epoch' | tail -1 || true; }
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
exit 0
