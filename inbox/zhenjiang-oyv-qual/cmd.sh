#!/usr/bin/env bash
# zhenjiang out-of-year validation :: qualification step 4
# Pull the updated bundle, then run one identical qualification job on every
# usable hgpu2p node. Two questions are settled in one round:
#   1. is the normalised threadpool digest equal across a heterogeneous cluster
#   2. does the bitwise model state digest hold across all eight nodes, not two
# Settings match array job 205525 exactly so the digests are comparable.
# Touches nothing outside /data1/home/sunyiq/zhenjiang_oyv_qual_20260819.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_qual_20260819
NODES="ngu001 ngu004 ngu005 ngu006 ngu007 ngu008 ngu010 ngu011"

echo "=== A. UPDATE BUNDLE ==="
cd "$ROOT/repo" || { echo "REPO_MISSING"; exit 1; }
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -3
timeout 60 git reset -q --hard refs/remotes/origin/main
echo "bundle_commit=$(git rev-parse HEAD)"
sed -i 's/\r$//' qualification/submit_node_sweep.slurm

echo "=== B. SUBMIT ONE JOB PER NODE ==="
JIDS=""
for N in $NODES; do
    J=$(sbatch --parsable --nodelist="$N" qualification/submit_node_sweep.slurm 2>&1)
    case "$J" in
        ''|*[!0-9]*) echo "submit_failed node=$N detail=$J" ;;
        *) echo "submitted node=$N jobid=$J"; JIDS="$JIDS $J" ;;
    esac
done
echo "submitted_ids=$JIDS"

echo "=== C. WAIT (max 15 min) ==="
for i in $(seq 1 90); do
    LEFT=0
    for J in $JIDS; do
        S=$(squeue -j "$J" -h -o "%i" 2>/dev/null | wc -l)
        LEFT=$((LEFT + S))
    done
    [ $((i % 6)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== D. SACCT ==="
for J in $JIDS; do
    sacct -j "$J" -X --format=JobID%10,NodeList%9,State%12,ExitCode%8,Elapsed%9 2>&1 | sed -n '3p' || true
done

echo "=== E. CROSS NODE DIGEST COMPARISON ==="
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
        "gpu": identity.get("graphics_processor_name"),
        "capability": identity.get("graphics_processor_capability"),
        "driver": identity.get("graphics_processor_driver_version"),
        "gpu_uuid": identity.get("graphics_processor_unique_identifier"),
        "os": identity.get("operating_system"),
        "raw_tp": identity.get("raw_threadpool_configuration_sha256"),
        "norm_tp": identity.get("normalised_threadpool_configuration_sha256"),
        "tp_libs": identity.get("threadpool_libraries"),
        "state": first.get("state_sha256"),
        "prediction": first.get("prediction_sha256"),
        "seconds": first.get("elapsed_seconds"),
        "passed": payload.get("qualification_passed"),
        "numpy_ok": payload.get("numpy_direction_check", {}).get(
            "direction_rule_matches_local"
        ),
    })


def distinct(key):
    return sorted({json.dumps(row.get(key), sort_keys=True) for row in rows})


print(json.dumps({
    "node_count": len(rows),
    "nodes": [row["node"] for row in rows],
    "distinct_state_digests": distinct("state"),
    "distinct_prediction_digests": distinct("prediction"),
    "distinct_normalised_threadpool_digests": distinct("norm_tp"),
    "distinct_raw_threadpool_digests": distinct("raw_tp"),
    "distinct_threadpool_libraries": distinct("tp_libs"),
    "distinct_gpu_names": distinct("gpu"),
    "distinct_capabilities": distinct("capability"),
    "distinct_drivers": distinct("driver"),
    "distinct_operating_systems": distinct("os"),
    "all_passed": all(row["passed"] for row in rows) if rows else False,
    "all_numpy_ok": all(row["numpy_ok"] for row in rows) if rows else False,
    "state_digest_identical_across_nodes": len(distinct("state")) == 1,
    "normalised_threadpool_identical_across_nodes": len(distinct("norm_tp")) == 1,
    "rows": rows,
}, indent=2, sort_keys=True))
PY

echo "=== F. FOOTPRINT ==="
du -sh "$ROOT" 2>/dev/null || true
echo "=== END ==="
