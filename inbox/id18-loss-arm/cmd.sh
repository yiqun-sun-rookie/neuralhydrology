#!/bin/bash
# ID18 seq=8: read-only status and log check for smoke job 202067.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
JOB_ID=202067

echo "=== SQUEUE ==="
squeue -j "$JOB_ID" -o "%.10i %.24j %.10P %.9T %.11M %.6D %R" 2>&1
echo "=== SACCT ==="
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,Elapsed,ExitCode,AllocCPUS,AllocTRES%40 -P 2>&1
echo "=== STDOUT_TAIL ==="
if test -f "$TARGET/logs/smoke-${JOB_ID}.out"; then
    tail -80 "$TARGET/logs/smoke-${JOB_ID}.out"
else
    echo "stdout not created"
fi
echo "=== STDERR_TAIL ==="
if test -f "$TARGET/logs/smoke-${JOB_ID}.err"; then
    tail -80 "$TARGET/logs/smoke-${JOB_ID}.err"
else
    echo "stderr not created"
fi
