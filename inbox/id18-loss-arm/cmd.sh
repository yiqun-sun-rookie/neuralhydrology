#!/bin/bash
# ID18 seq=9: wait for exact smoke job 202067, then report its final state and logs.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
JOB_ID=202067

while squeue -h -j "$JOB_ID" 2>/dev/null | grep -q .; do
    sleep 20
done

echo "=== FINAL_SACCT ==="
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,Elapsed,ExitCode,AllocCPUS,AllocTRES%40 -P 2>&1
echo "=== STDOUT ==="
test -f "$TARGET/logs/smoke-${JOB_ID}.out"
cat "$TARGET/logs/smoke-${JOB_ID}.out"
echo "=== STDERR ==="
test -f "$TARGET/logs/smoke-${JOB_ID}.err"
cat "$TARGET/logs/smoke-${JOB_ID}.err"

STATE=$(sacct -n -X -j "$JOB_ID" --format=State -P | head -1 | cut -d'|' -f1 | xargs)
test "$STATE" = "COMPLETED"
grep -Fxq "E04_SMOKE_PASS" "$TARGET/logs/smoke-${JOB_ID}.out"
echo "E04_SMOKE_FINAL_PASS job_id=$JOB_ID"
