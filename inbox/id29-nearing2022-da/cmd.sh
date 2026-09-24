set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== WARMPAIR JOBS 7d ==="
sacct -X -n -P -S $(date -d '7 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' || echo '  none in 7d'
echo "=== 219423 ==="
sacct -j 219423 -X -n -P --format=JobID,State,ExitCode,End 2>/dev/null || true
echo "=== ARTIFACTS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for F in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$F" ] && echo "  PRESENT $F" || echo "  MISSING $F"; done
P="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"; [ -f "$P" ] && echo "  PRESENT gate ($(stat -c %s "$P") bytes)" || echo "  MISSING gate"
echo "=== ENTRY GATE LINES ==="
grep -n '"2025' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null | head -5 || true
exit 0
