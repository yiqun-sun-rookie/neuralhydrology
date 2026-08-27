#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== JOB STATE ==="
sacct -j 215261 --format=JobID,State,Elapsed,ExitCode 2>/dev/null | head -6 || true
echo "=== ANCHOR LOG TAIL ==="
tail -3 $ROOT/logs/tukf24_anchor_215261*.out 2>/dev/null || true
echo "=== ANCHOR RECORDS ==="
python3 - <<'PYEOF'
import json, glob
root = "/data1/home/sunyiq/kalmannet_tukf24_20260827"
files = sorted(glob.glob(f"{root}/results/anchor/*.json"))
worst = 0.0; fails = 0
for f in files:
    d = json.load(open(f))
    delta = d["anchor_delta"]; worst = max(worst, delta)
    ok = delta <= d["tolerance"]
    fails += 0 if ok else 1
    print(f'{d["basin_id"]} {delta:.6e} {"OK" if ok else "FAIL"}')
print(f"basins={len(files)} fails={fails} worst={worst:.6e}")
PYEOF
