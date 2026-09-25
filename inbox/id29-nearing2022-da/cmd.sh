set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== FAILURES 7d ==="
sacct -X -n -P -S $(date -d '7 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' | grep -E '\|(TIMEOUT|FAILED|NODE_FAIL|OUT_OF_MEMORY|CANCELLED)' || echo '  none'
echo "=== 219423 ==="
sacct -j 219423 -X -n -P --format=JobID,State,ExitCode,End 2>/dev/null || true
echo "=== ARTIFACTS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for X in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$X" ] && echo "  PRESENT $X" || echo "  MISSING $X"; done
for F in aggregation/evaluations/time_split_vs_author.csv aggregation/evaluations/basin_split_vs_author.csv aggregation/hyperparameters/scores.csv aggregation/final_reproduction_gate.json; do
  P="$ROOT/closure_20260810/$F"; [ -f "$P" ] && echo "  PRESENT $F ($(stat -c %s "$P") bytes)" || echo "  MISSING $F"
done
echo "=== ENTRY GATE LINES ==="
grep -n 'slurm_job_id' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null || true
exit 0
