#!/usr/bin/env bash
# zhenjiang gauge failure study :: status, plus two pieces of tidying
#
# 205548 is my own node probe from yesterday's qualification phase. It has been
# stuck 24 hours behind a --nodelist pin and its purpose, node coverage, was long
# since served by the 480 task run touching six nodes. Cancelling it removes queue
# clutter. Nothing belonging to another experiment is touched.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
QUAL=/data1/home/sunyiq/zhenjiang_oyv_qual_20260819

echo "=== A. LADDER 206431 ==="
DONE=$(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l)
echo "completed_task_dirs=$DONE of 960"
sacct -j 206431 -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c | head -8 || true
squeue -j 206431 -h -o '%.14i %.9T %.8M %.20R' 2>/dev/null | head -5 || true
echo "--- any failed, timed out or node failed ---"
sacct -j 206431 -X --format=JobID%16,NodeList%9,State%14,ExitCode%8 --noheader 2>/dev/null \
    | grep -vE 'COMPLETED|PENDING|RUNNING' | head -10 || echo "(none)"
echo "--- nodes used so far ---"
sacct -j 206431 -X --format=NodeList%10 --noheader 2>/dev/null | tr -d ' ' | grep -v '^None' | sort | uniq -c | head -10 || true

echo "=== B. AUDIT 206419 (settled) ==="
grep -E '"audit_status"|"mismatch_count"|"reinference_count"' \
    "$ROOT/independent_audit_r3/independent_audit_summary.json" 2>/dev/null || true

echo "=== C. TIDY MY OWN STALE PROBE ==="
sacct -j 205548 -X --format=JobID%10,State%12 --noheader 2>/dev/null | sed -n '1p' || true
scancel 205548 2>&1 && echo "cancelled_205548=yes" || echo "cancelled_205548=already_gone"

echo "=== D. hgpu4 PROBE 206565 ==="
sacct -j 206565 -X --format=JobID%10,NodeList%9,State%12,ExitCode%8,Elapsed%9 2>&1 | sed -n '3p' || true
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
for path in sorted(Path(sys.argv[1]).glob("nodesweep_ngu101_*.json")):
    d = json.loads(path.read_text(encoding="utf-8"))
    ident = d.get("runtime_identity", {})
    bad = {k: [v, ident.get(k)] for k, v in PIN.items() if ident.get(k) != v}
    rows.append({"node": ident.get("node_name"), "gpu": ident.get("graphics_processor_name"),
                 "driver": ident.get("graphics_processor_driver_version"),
                 "os": ident.get("operating_system"),
                 "state_sha256": (d.get("training_first") or {}).get("state_sha256"),
                 "matches_pin": not bad, "differing": bad})
print(json.dumps(rows, indent=2, sort_keys=True) if rows else "[] (no ngu101 report yet)")
print("HGPU4_MATCH=%s" % ("yes" if rows and all(r["matches_pin"] for r in rows) else "no"))
PY
)
echo "$MATCH"

echo "=== E. WIDEN TO hgpu4 ONLY IF IT MATCHES ==="
if printf '%s' "$MATCH" | grep -q 'HGPU4_MATCH=yes'; then
    scontrol update jobid=206431 partition=hgpu2p,hgpu4 2>&1 && echo "partition_widened=yes"
    squeue -j 206431 -h -o '%.14i %.16P %.9T %.20R' 2>/dev/null | head -3 || true
else
    echo "partition_widened=no"
fi

echo "=== F. QUEUE ==="
squeue -u "$USER" -h -o '%.12i %.14j %.9T %.10M %.22R' 2>/dev/null | head -12 || true
echo "total_entries=$(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"
echo "=== END ==="
