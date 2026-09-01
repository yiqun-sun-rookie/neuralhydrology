#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf26_20260831
echo "=== TIMING JOB 217271 ==="
sacct -j 217271 -X -n -P --format=State,ExitCode,Elapsed 2>/dev/null || true
LOG=$(ls -t $ROOT/logs/tukf26_timing_*.out 2>/dev/null | head -1)
[ -n "$LOG" ] && tail -3 "$LOG"
STATE=$(sacct -j 217271 -X -n -P --format=State 2>/dev/null | head -1)
[ "$STATE" = "COMPLETED" ] || { echo "TIMING_NOT_DONE state=$STATE"; exit 0; }
echo "=== SELF-CHECK + LAUNCH DECISION ==="
python3 - <<'PYEOF'
import json, re, sys, glob
log = sorted(glob.glob("/data1/home/sunyiq/kalmannet_tukf26_20260831/logs/tukf26_timing_*.out"))[-1]
txt = open(log).read()
m = re.search(r'\{.*"timing_probe".*\}', txt)
if not m:
    print("NO_TIMING_JSON"); sys.exit(1)
rec = json.loads(m.group(0))
up = rec["timing_probe"]["update_s"]; q = rec["timing_probe"]["selection_query_s"]
rss = rec.get("peak_rss_mb") or 0
est_min = (up*192 + q*49)/60
print(f"per_update_s={up:.1f} per_query_s={q:.1f} peak_rss_mb={rss:.0f} est_y6_cell_min={est_min:.0f}")
ok = up < 60 and (rss == 0 or rss < 5000)
print("LAUNCH_OK" if ok else "LAUNCH_BLOCKED")
sys.exit(0 if ok else 1)
PYEOF
[ $? -eq 0 ] || { echo "BLOCKED: timing/memory outside safe envelope"; exit 1; }
echo "=== SBATCH TRAIN ARRAY 135 ==="
if squeue -u $USER -h -o "%j" 2>/dev/null | grep -q tukf26_train; then echo QUEUED_ALREADY
else
  out=$(sbatch $ROOT/slurm/tukf26_train.slurm 2>&1); echo "$out"
  echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
fi
squeue -u $USER 2>/dev/null | grep -c tukf26 || true
echo "SEQ3_OK"
