#!/bin/bash
# ID29: are all 46 training coordinates complete? If so, what exactly blocks 202226?
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== TIME ==="; date --iso-8601=seconds
source ~/miniconda3/etc/profile.d/conda.sh && conda activate nh_final 2>/dev/null
cd "$ROOT"

echo "=== TRAINING COMPLETENESS DETAIL ==="
python - <<'PY' 2>&1 | head -40
import json, sys
from pathlib import Path
root = Path('/data1/home/sunyiq/nearing2022_da')
sys.path.insert(0, str(root / 'src/29_nearing2022_da_ar/scripts'))
from verify_registered_closure import audit_registered_closure
reg = root / 'src/29_nearing2022_da_ar/registry'
agg = root / 'closure_20260810/aggregation'
c = audit_registered_closure(root, reg/'experiment_registry.csv', reg/'evaluation_registry.csv',
                             reg/'assimilation_hyperparameter_registry.csv', agg/'evaluations', agg/'hyperparameters')
tr = [r for r in c['missing'] if r['coordinate_type'] == 'training']
print('training missing roles:', len(tr))
seen = {}
for r in tr:
    seen.setdefault(r['coordinate_id'], []).append(r.get('role', '?'))
for k, v in sorted(seen.items()):
    print(f'  {k}: {sorted(v)}')
ev = [r for r in c['missing'] if r['coordinate_type'] == 'evaluation']
evc = sorted({r['coordinate_id'] for r in ev})
print('evaluation missing coordinates:', len(evc), '(first 5)', evc[:5])
PY

echo "=== THE THREE REPAIR CHECKPOINTS ==="
AR="$ROOT/closure_20260810/time_split/autoregression"
for P in lead2_holdout0.75 lead2_holdout1.0 lead1_holdout0.5; do
  f=$(find "$AR" -maxdepth 2 -path "*${P}_seed0*" -name 'model_epoch030.pt' -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort | tail -1)
  printf '  %-18s %s\n' "$P" "${f:-MISSING}"
done

echo "=== 202226 BLOCK DETAIL ==="
scontrol show job 202226 2>/dev/null | tr ' ' '\n' | grep -E '^(JobId|ArrayTaskId|Dependency|Reason|Command|TimeLimit|Partition)=' || echo 'no record'
echo "--- upstream states it waits on ---"
sacct -X -n -P -j 202214 --format=JobID,State 2>/dev/null || true
sacct -X -n -P -j 202215 --format=JobID,State 2>/dev/null | grep -vE '\|COMPLETED' || echo '  202215: all COMPLETED'

echo "=== EVAL BATCH FILE FOR 202226 ==="
B="$ROOT/src/29_nearing2022_da_ar/registry/time_split_pending_source_evaluation_batch.txt"
[ -f "$B" ] && { echo "lines=$(wc -l < "$B")  sha256=$(sha256sum "$B" | cut -d' ' -f1)"; head -3 "$B"; } || echo 'batch file missing'

echo "=== END ==="; date --iso-8601=seconds
exit 0
