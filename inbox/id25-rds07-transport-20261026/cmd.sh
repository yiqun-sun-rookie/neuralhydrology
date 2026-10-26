#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_transport_rds07_20261026_001
job=$(cat "$root/job_id.txt")
test "$job" = 247722
date -Is
echo JOB_ID=$job
echo EXACT_ACCOUNTING
timeout 30 sacct -n -j "$job" --format=JobIDRaw,JobName%40,User,State,ExitCode,Elapsed,NodeList,MaxRSS -P
echo LIVE_QUEUE_IF_PRESENT
if ! timeout 30 squeue -h -j "$job" -o '%i|%j|%T|%M|%R'; then echo NO_LIVE_QUEUE_RECORD_USE_ACCOUNTING; fi
for file in runtime.json status.json report.json transport/initial.json transport/status.json transport/selection.json direct_history/status.json direct_history/selection.json; do
  if test -f "$root/output/$file"; then echo FILE=$file; cat "$root/output/$file"; fi
done
echo OUTPUT_FILE_METADATA
find "$root/output" -maxdepth 2 -type f -printf '%P %s bytes\n'
for arm in transport direct_history; do
  if test -f "$root/output/$arm/metrics.jsonl"; then echo METRICS=$arm; tail -n 2 "$root/output/$arm/metrics.jsonl"; fi
done
for file in "$root"/logs/*; do
  if test -f "$file"; then echo LOG=$file; tail -n 20 "$file"; fi
done
