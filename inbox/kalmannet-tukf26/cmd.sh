#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf26_20260831
echo "=== ANCHOR JOB 217266 ==="
sacct -j 217266 -X -n -P --format=State,ExitCode,Elapsed 2>/dev/null || true
echo "=== ANCHOR GATE VERDICT ==="
if [ -f $ROOT/results/anchor_gate_verdict.json ]; then
python3 - <<'PYEOF'
import json
v=json.load(open("/data1/home/sunyiq/kalmannet_tukf26_20260831/results/anchor_gate_verdict.json"))
d=v["anchor_deltas"]
print("pass:",v["pass"],"passed:",v["passed_count"],"/",v["required"])
if d: print("max_delta:",max(d.values()))
PYEOF
else
  echo "VERDICT_NOT_READY"; tail -5 $ROOT/logs/tukf26_anchor_*.out 2>/dev/null || true; exit 0
fi
echo "=== SBATCH TIMING CELL (y6 joint, 6 updates, this platform) ==="
if squeue -u $USER -h -o "%j" 2>/dev/null | grep -q tukf26_timing; then echo QUEUED_ALREADY
else
  out=$(sbatch $ROOT/slurm/tukf26_timing.slurm 2>&1); echo "$out"
  echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
fi
echo "SEQ2_OK"
