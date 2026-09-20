set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== FAILURES (7d) ==="
sacct -X -n -P -S $(date -d '7 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo '  none'
echo "=== WARMPAIR JOBS (30d) ==="
sacct -X -n -P -S $(date -d '30 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'warm' || echo '  none'
echo "=== WARMPAIR DIRS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for X in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$X" ] && echo "  PRESENT $X" || echo "  MISSING $X"; done
echo "=== PREPARE SCRIPT LINE 94 ==="
sed -n '94p' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null || true
echo "=== GATE ARTIFACT ==="
P="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
[ -f "$P" ] && echo "  PRESENT ($(stat -c %s "$P") bytes)" || echo "  MISSING"
exit 0
