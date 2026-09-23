set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== WARM* JOBS 30d ==="
sacct -X -n -P -S $(date -d '30 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -iE 'warm' || echo '  none'
echo "=== WARMPAIR DIRS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for X in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$X" ] && echo "  PRESENT $X" || echo "  MISSING $X"; done
echo "=== ARTIFACTS ==="
for F in aggregation/evaluations/time_split_vs_author.csv aggregation/evaluations/basin_split_vs_author.csv aggregation/hyperparameters/scores.csv aggregation/final_reproduction_gate.json; do
  P="$ROOT/closure_20260810/$F"; [ -f "$P" ] && echo "  PRESENT $F" || echo "  MISSING $F"
done
echo "=== prepare_warmup_target_pair.py slurm_job_id checks ==="
grep -n 'slurm_job_id' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" 2>/dev/null || true
exit 0
