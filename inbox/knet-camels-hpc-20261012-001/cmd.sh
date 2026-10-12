#!/bin/bash
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/knet_camels_hpc_20261012_001
printf 'TIME_UTC='; date -u +%FT%TZ
squeue -j 241332 -h -o '%i|%j|%T|%P|%C|%R'
sacct -j 241332 -n -P --format=JobID,JobName,State,ExitCode,Elapsed,MaxRSS,AllocCPUS,Partition,NodeList
scontrol show job 241332
squeue -j 241332 --start -h -o '%i|%S|%R'
if [ -f "$TASK_ROOT/receipts/compatibility_probe_241332.json" ]; then
 printf 'PROBE_RESULT_BEGIN
'; cat "$TASK_ROOT/receipts/compatibility_probe_241332.json"; printf '
PROBE_RESULT_END
'
else
 printf 'PROBE_RESULT_NOT_YET_PRESENT
'
fi
for f in "$TASK_ROOT/logs/compatibility-241332.out" "$TASK_ROOT/logs/compatibility-241332.err"; do
 if [ -f "$f" ]; then printf 'LOG=%s
' "$f"; tail -n 25 "$f"; fi
done
