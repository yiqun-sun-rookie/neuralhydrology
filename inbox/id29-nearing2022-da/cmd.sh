set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== FAILURES AND TIMEOUTS (never truncate) ==="
sacct -X -n -P -S $(date -d '7 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo '  none'
echo "=== ANY WARMPAIR* JOBS LAST 14 DAYS ==="
sacct -X -n -P -S $(date -d '14 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'warmpair|warmana' || echo '  none'
echo "=== WARMPAIR ARM DIRS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for A in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$A" ] && echo "  PRESENT $A" || echo "  MISSING $A"; done
echo "=== LOG IDLE SECONDS PER RUNNING JOB ==="
for J in $(squeue -u sunyiq -h -t RUNNING -o '%i %j' 2>/dev/null | grep -E 'N22-' | awk '{print $1}'); do
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
  [ -n "$SO" ] && [ -f "$SO" ] && printf '  %-14s idle=%ss\n' "$J" "$(( $(date +%s) - $(stat -c %Y "$SO") ))"
done
echo "=== GATE ARTIFACTS ==="
for F in aggregation/evaluations/time_split_vs_author.csv aggregation/evaluations/basin_split_vs_author.csv aggregation/hyperparameters/scores.csv aggregation/final_reproduction_gate.json; do
  P="$ROOT/closure_20260810/$F"; [ -f "$P" ] && echo "  PRESENT $F" || echo "  MISSING $F"; done
echo "=== PREPARE SCRIPT LINE 94 (blocker check) ==="
sed -n '90,96p' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null || true
exit 0
