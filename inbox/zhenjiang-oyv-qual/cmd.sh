#!/usr/bin/env bash
# zhenjiang gauge failure study :: read-only status
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. LADDER 206431 ==="
echo "completed_task_dirs=$(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l) of 960"
sacct -j 206431 -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c | head -8 || true
squeue -j 206431 -h -o '%.14i %.9T %.8M %.20R' 2>/dev/null | head -4 || true
echo "--- failed, timed out or node failed ---"
sacct -j 206431 -X --format=JobID%16,NodeList%9,State%14,ExitCode%8 --noheader 2>/dev/null \
    | grep -vE 'COMPLETED|PENDING|RUNNING' | head -10 || echo "(none)"
echo "--- nodes used ---"
sacct -j 206431 -X --format=NodeList%10 --noheader 2>/dev/null | tr -d ' ' | grep -v '^None' | sort | uniq -c | head || true
echo "--- condition coverage so far ---"
ls -1 "$ROOT/ladder_tasks" 2>/dev/null | sed 's/.*__\(zhenjiang\|jiangyin\)__//; s/__seed_.*//' | sort | uniq -c || true

echo "=== B. AUDIT (settled) ==="
grep -E '"audit_status"|"mismatch_count"|"reinference_count"' \
    "$ROOT/independent_audit_r3/independent_audit_summary.json" 2>/dev/null || true

echo "=== C. QUEUE ==="
squeue -u "$USER" -h -o '%.12i %.14j %.9T %.10M %.22R' 2>/dev/null | head -8 || true
echo "total_entries=$(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"
echo "=== D. DISK ==="
du -sh "$ROOT/ladder_tasks" 2>/dev/null || true
df -h /data1 2>&1 | tail -1
echo "=== END ==="
