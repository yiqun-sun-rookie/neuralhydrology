set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 RUNNING/PENDING (non-legacy) ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %R' 2>/dev/null | grep -E 'N22' | grep -vE '202229|202294|202315|202507|202293' || echo '  none'
echo "=== warmpair-family sacct (14d) ==="
sacct -X -n -P -S $(date -d '14 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'warm' || echo '  none'
echo "=== pair dirs ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for X in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$X" ] && echo "  PRESENT $X" || echo "  MISSING $X"; done
echo "=== prepare script slurm_job_id lines + last commit touching it ==="
F="$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py"
grep -n 'slurm_job_id' "$F" || true
cd "$ROOT" && git log -1 --format='%h %ci %s' -- "$F" 2>/dev/null || true
echo "=== gate artifact ==="
[ -f "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json" ] && echo "  PRESENT final_reproduction_gate.json" || echo "  MISSING"
exit 0
