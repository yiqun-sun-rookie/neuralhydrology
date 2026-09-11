set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== N22 FAILURES 7d ==="
sacct -X -n -P -S $(date -d '7 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo '  none'
echo "=== WARMPAIR JOBS EVER (any name) ==="
sacct -X -n -P -S 2026-09-01 --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -Ei 'warm' || echo '  none'
echo "=== WARMPAIR DIRS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for S in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$S" ] && echo "  PRESENT $S" || echo "  MISSING $S"; done
echo "=== ENTRY GATE EXPECTATION vs RECEIPT ==="
grep -n '202506\|202510' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null || true
grep -rn 'slurm_job_id' "$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_target_paired_retraining_protocol_amendment_01.json" 2>/dev/null | head -5 || true
echo "=== GATE ARTIFACTS ==="
for F in aggregation/evaluations/time_split_vs_author.csv aggregation/evaluations/basin_split_vs_author.csv aggregation/hyperparameters/scores.csv aggregation/final_reproduction_gate.json; do
  P="$ROOT/closure_20260810/$F"; [ -f "$P" ] && echo "  PRESENT $F" || echo "  MISSING $F"; done
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
