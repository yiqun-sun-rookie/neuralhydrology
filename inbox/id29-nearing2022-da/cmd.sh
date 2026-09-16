set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== RECENT N22 sacct (3 days, non-pending) ==="
sacct -X -n -P -S $(date -d '3 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' | grep -vE '\|PENDING\|' || echo '  none'
echo "=== WARMPAIR DIRS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for X in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$X" ] && echo "  PRESENT $X" || echo "  MISSING $X"; done
echo "=== GATE ==="
grep -o '"released_code_numerical_status": "[A-Z_]*"' "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json" 2>/dev/null || echo '  gate missing'
echo "=== prepare_warmup_target_pair.py hardcoded job ids ==="
grep -n '_require_equal(.*slurm_job_id' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null || echo '  n/a'
echo "=== git head on HPC ==="
cd "$ROOT" && git log -1 --format='%h %ci %s' 2>/dev/null || echo '  n/a'
exit 0
