#!/usr/bin/env bash
# zhenjiang gauge failure study :: status plus a card-type probe on two more partitions
#
# The ladder is starved on hgpu2p. Before widening it to hgpu2 and hgpu4 the cards
# there have to be checked, because the trainer pins the card model, capability and
# driver and will refuse to run on anything else. Two thirty-second probes settle it.
# Widening only happens inside this script if both probes match; nothing is forced.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
QUAL=/data1/home/sunyiq/zhenjiang_oyv_qual_20260819

echo "=== A. LADDER 206431 ==="
echo "completed_task_dirs=$(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l) of 960"
sacct -j 206431 -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c | head -8 || true
squeue -j 206431 -h -o '%.14i %.9T %.8M %.20R' 2>/dev/null | head -4 || true
echo "--- any failed or timed out ---"
sacct -j 206431 -X --format=JobID%16,NodeList%9,State%14,ExitCode%8 --noheader 2>/dev/null \
    | grep -vE 'COMPLETED|PENDING|RUNNING' | head -10 || echo "(none)"

echo "=== B. AUDIT 206419 ==="
sacct -j 206419 -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10 2>&1 | sed -n '3p' || true
grep -E '"audit_status"|"mismatch_count"|"reinference_count"' \
    "$ROOT/independent_audit_r3/independent_audit_summary.json" 2>/dev/null || true

echo "=== C. CARD PROBE ON hgpu2 AND hgpu4 ==="
cd "$QUAL/repo" || { echo "QUAL_REPO_MISSING"; exit 1; }
sed -i 's/\r$//' qualification/submit_node_sweep.slurm
P1=$(sbatch --parsable -p hgpu2 --nodelist=ngu003 qualification/submit_node_sweep.slurm 2>&1)
P2=$(sbatch --parsable -p hgpu4 --nodelist=ngu101 qualification/submit_node_sweep.slurm 2>&1)
echo "probe_hgpu2_ngu003=$P1"
echo "probe_hgpu4_ngu101=$P2"

echo "=== D. WAIT FOR PROBES (max 12 min) ==="
for i in $(seq 1 72); do
    LEFT=$(( $(squeue -j "$P1" -h -o "%i" 2>/dev/null | wc -l) + $(squeue -j "$P2" -h -o "%i" 2>/dev/null | wc -l) ))
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done
for J in "$P1" "$P2"; do
    sacct -j "$J" -X --format=JobID%10,NodeList%9,State%12,ExitCode%8,Elapsed%9 2>&1 | sed -n '3p' || true
done

echo "=== E. CARD IDENTITY ON THOSE NODES ==="
MATCH=$(PYTHONPATH="$QUAL/pysite" python - "$QUAL/reports" <<'PY'
import json
from pathlib import Path
import sys

PIN = {
    "graphics_processor_name": "NVIDIA GeForce RTX 3090",
    "graphics_processor_capability": [8, 6],
    "graphics_processor_driver_version": "580.76.05",
    "operating_system": "Linux-5.14.0-503.14.1.el9_5.x86_64-x86_64-with-glibc2.34",
    "torch_version": "2.4.0",
    "cudnn_version": 90100,
    "normalised_threadpool_configuration_sha256":
        "bd2d2073fc6f948a7af98ab30ed5debfafd2e0c5ceb02688141c56ad6e308a46",
}
rows = []
for path in sorted(Path(sys.argv[1]).glob("nodesweep_ngu003_*.json")) + \
            sorted(Path(sys.argv[1]).glob("nodesweep_ngu101_*.json")):
    d = json.loads(path.read_text(encoding="utf-8"))
    ident = d.get("runtime_identity", {})
    bad = {k: [v, ident.get(k)] for k, v in PIN.items() if ident.get(k) != v}
    rows.append({
        "node": ident.get("node_name"),
        "gpu": ident.get("graphics_processor_name"),
        "driver": ident.get("graphics_processor_driver_version"),
        "state_sha256": (d.get("training_first") or {}).get("state_sha256"),
        "matches_pin": not bad,
        "differing": bad,
    })
print(json.dumps(rows, indent=2, sort_keys=True))
ok = bool(rows) and all(r["matches_pin"] for r in rows) and len(rows) >= 2
print("ALL_MATCH=%s" % ("yes" if ok else "no"))
PY
)
echo "$MATCH"

echo "=== F. WIDEN THE LADDER ONLY IF BOTH MATCH ==="
if printf '%s' "$MATCH" | grep -q 'ALL_MATCH=yes'; then
    scontrol update jobid=206431 partition=hgpu2p,hgpu2,hgpu4 2>&1 && echo "partition_widened=yes"
    squeue -j 206431 -h -o '%.14i %.16P %.9T %.20R' 2>/dev/null | head -3 || true
else
    echo "partition_widened=no, the probe did not match the pinned environment"
fi

echo "=== G. QUEUE ==="
squeue -u "$USER" -h -o '%.12i %.14j %.9T %.10M %.22R' 2>/dev/null | head -12 || true
echo "=== END ==="
