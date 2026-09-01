set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs'
echo "=== GATE JSON ==="
cat "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json" 2>/dev/null || echo MISSING
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
