#!/bin/bash
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/knet_camels_hpc_20261012_001
printf 'TIME_UTC='; date -u +%FT%TZ
sacct -j 241332 -n -P --format=JobID,JobName,State,ExitCode,Elapsed,MaxRSS,AllocCPUS,Partition,NodeList
if [ -f "$TASK_ROOT/receipts/compatibility_probe_241332.json" ]; then
 printf 'PROBE_RESULT_BEGIN
'; cat "$TASK_ROOT/receipts/compatibility_probe_241332.json"; printf '
PROBE_RESULT_END
'
else
 printf 'PROBE_RESULT_NOT_PRESENT
'
fi
for f in "$TASK_ROOT/logs/compatibility-241332.out" "$TASK_ROOT/logs/compatibility-241332.err"; do
 if [ -f "$f" ]; then printf 'LOG=%s
' "$f"; tail -n 35 "$f"; else printf 'LOG_NOT_PRESENT=%s
' "$f"; fi
done
printf 'EXISTING_USER_JOBS
'; squeue -u sunyiq -h -o '%i|%j|%T|%P|%C|%R'
