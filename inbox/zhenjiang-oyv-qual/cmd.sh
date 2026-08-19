#!/usr/bin/env bash
# zhenjiang out-of-year validation :: qualification step 5
# Collect whatever the six still-queued per-node jobs have produced, so the
# normalised threadpool digest and the bitwise state digest are confirmed on at
# least three distinct nodes. READ-ONLY: no submission, no install, no delete.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_qual_20260819

echo "=== A. PER NODE JOB STATES ==="
for J in 205548 205549 205550 205551 205552 205553 205554 205555; do
    sacct -j "$J" -X --format=JobID%10,NodeList%9,State%12,ExitCode%8,Elapsed%9 2>&1 | sed -n '3p' || true
done

echo "=== B. STILL QUEUED ==="
squeue -u "$USER" -h -o '%.10i %.10P %.12j %.9T %.11M %.20R' 2>&1 | grep zj_oyv || echo "none of ours queued"

echo "=== C. CROSS NODE COMPARISON ==="
PYTHONPATH="$ROOT/pysite" python - "$ROOT/reports" <<'PY'
import json
from pathlib import Path
import sys

rows = []
for path in sorted(Path(sys.argv[1]).glob("nodesweep_*.json")):
    payload = json.loads(path.read_text(encoding="utf-8"))
    identity = payload.get("runtime_identity", {})
    first = payload.get("training_first") or {}
    rows.append({
        "node": identity.get("node_name"),
        "gpu_uuid": identity.get("graphics_processor_unique_identifier"),
        "driver": identity.get("graphics_processor_driver_version"),
        "os": identity.get("operating_system"),
        "norm_tp": identity.get("normalised_threadpool_configuration_sha256"),
        "raw_tp": identity.get("raw_threadpool_configuration_sha256"),
        "state": first.get("state_sha256"),
        "seconds": first.get("elapsed_seconds"),
        "passed": payload.get("qualification_passed"),
    })

def distinct(key):
    return sorted({str(row.get(key)) for row in rows})

print(json.dumps({
    "node_count": len({row["node"] for row in rows}),
    "nodes": sorted({str(row["node"]) for row in rows}),
    "distinct_state_digests": distinct("state"),
    "distinct_normalised_threadpool_digests": distinct("norm_tp"),
    "distinct_raw_threadpool_digests": distinct("raw_tp"),
    "distinct_operating_systems": distinct("os"),
    "distinct_gpu_uuids": distinct("gpu_uuid"),
    "all_passed": all(row["passed"] for row in rows) if rows else False,
    "state_identical": len(distinct("state")) == 1,
    "normalised_threadpool_identical": len(distinct("norm_tp")) == 1,
    "seconds": [row["seconds"] for row in rows],
}, indent=2, sort_keys=True))
PY
echo "=== END ==="
