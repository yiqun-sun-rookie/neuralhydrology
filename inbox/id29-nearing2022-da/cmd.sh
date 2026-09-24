set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== FAILURES (7d, full) ==="
sacct -X -n -P -S $(date -d '7 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo '  none'
echo "=== WARMPAIR JOBS ANY NAME (7d) ==="
sacct -X -n -P -S $(date -d '7 days ago' +%Y-%m-%d) --format=JobID,JobName,State,End 2>/dev/null | grep -i 'warm' || echo '  none'
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
echo "=== WARMPAIR DIRS ==="
for X in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$X" ] && echo "  PRESENT $X" || echo "  MISSING $X"; done
echo "=== ARTIFACTS ==="
for F in aggregation/evaluations/time_split_vs_author.csv aggregation/evaluations/basin_split_vs_author.csv aggregation/hyperparameters/scores.csv aggregation/final_reproduction_gate.json; do
  [ -f "$ROOT/closure_20260810/$F" ] && echo "  PRESENT $F" || echo "  MISSING $F"; done
exit 0
