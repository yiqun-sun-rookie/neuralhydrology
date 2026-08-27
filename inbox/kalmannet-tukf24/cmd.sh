#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== SMOKE ARRAY STATE ==="
sacct -j 215264 --format=JobID,State,Elapsed,ExitCode 2>/dev/null | head -16 || true
echo "=== COMPLETED TRAIN RECORDS ==="
python3 - <<'PYEOF'
import json, glob
root = "/data1/home/sunyiq/kalmannet_tukf24_20260827"
for f in sorted(glob.glob(f"{root}/results/train/*.json")):
    d = json.load(open(f))
    print(f'{d["basin_id"]}_{d["mode"]} update={d["selected_update"]} '
          f'score={d["selection_score_at_checkpoint"]} seconds={d["seconds"]:.1f}')
PYEOF
