set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== FAILURES (7d) ==="
sacct -X -n -P -S $(date -d '7 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo '  none'
echo "=== WARMPAIR ANY (14d) ==="
sacct -X -n -P -S $(date -d '14 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'warm' || echo '  none'
echo "=== WARMPAIR ARTIFACTS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for S in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$S" ] && echo "  PRESENT $S" || echo "  MISSING $S"; done
echo "=== PREPARE SCRIPT HARDCODE LINE ==="
grep -n '2025' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null | head -5 || true
echo "=== GATE ==="
[ -f "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json" ] && python3 -c "import json;d=json.load(open('$ROOT/closure_20260810/aggregation/final_reproduction_gate.json'));print(d.get('released_code_numerical_status'))" 2>/dev/null || echo MISSING
exit 0
