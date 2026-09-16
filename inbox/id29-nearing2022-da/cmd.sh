set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== RECENT N22 sacct (3 days) ==="
sacct -X -n -P -S $(date -d '3 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' || echo '  none'
echo "=== WARMPAIR DIRS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for S in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$S" ] && echo "  PRESENT $S" || echo "  MISSING $S"; done
echo "=== GATE ==="
P="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
[ -f "$P" ] && grep -o '"released_code_numerical_status": *"[A-Z_]*"' "$P" || echo "  MISSING gate"
echo "=== prepare_warmup_target_pair.py hardcoded job id (line ~94) ==="
grep -n '2025[01][0-9]' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null | head -5 || true
exit 0
