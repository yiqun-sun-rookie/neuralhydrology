#!/usr/bin/env bash
# zhenjiang gauge failure study :: status check
# Read only. No submission, no computation, nothing written outside the report.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. LADDER ARRAY 206431 ==="
echo "completed_task_dirs=$(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l) of 960"
echo "queue_entries=$(squeue -j 206431 -h -o '%i' 2>/dev/null | wc -l)"
sacct -j 206431 -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c | head -8 || true
echo "--- running now ---"
squeue -j 206431 -h -o '%.14i %.9T %.8M %.10R' 2>/dev/null | head -6 || true
echo "--- any non completed ---"
sacct -j 206431 -X --format=JobID%16,NodeList%9,State%14,ExitCode%8,Elapsed%10 --noheader 2>/dev/null \
    | grep -vE 'COMPLETED|PENDING|RUNNING' | head -10 || true

echo "=== B. INDEPENDENT AUDIT 206419 ==="
sacct -j 206419 -X --format=JobID%10,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | sed -n '3p' || true
squeue -j 206419 -h -o '%.10i %.9T %.8M %.20R' 2>/dev/null || echo "not in queue"
if [ -f "$ROOT/independent_audit_r3/independent_audit_summary.json" ]; then
    echo "--- audit r3 summary ---"
    cat "$ROOT/independent_audit_r3/independent_audit_summary.json"
    echo "--- mismatch kinds ---"
    tail -n +2 "$ROOT/independent_audit_r3/mismatches.csv" 2>/dev/null | cut -d, -f1 | sort | uniq -c | head || echo "(no rows)"
else
    echo "audit r3 has not produced a summary yet"
fi

echo "=== C. WHOLE QUEUE FOR THIS USER ==="
squeue -u "$USER" -h -o '%.12i %.14j %.9T %.10M %.20R' 2>/dev/null | head -14 || true
echo "total_entries=$(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"

echo "=== D. PARTITION ==="
sinfo -p hgpu2p -o '%.10P %.6a %.6D %.28N %.10T' 2>&1 | head -8 || true

echo "=== E. IMPACT ARTIFACTS ALREADY ON DISK ==="
ls -1 "$ROOT/removal_impact" 2>/dev/null || echo "(absent)"
echo "=== END ==="
