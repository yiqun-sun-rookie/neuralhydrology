#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_transport_rds07_20261026_001
job=$(cat "$root/job_id.txt")
case "$job" in ''|*[!0-9]*) exit 1 ;; esac
date -Is
echo JOB_ID=$job
timeout 30 squeue -h -j "$job" -o '%i|%j|%T|%M|%R'
timeout 30 sacct -n -X -j "$job" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -P
for file in runtime.json status.json report.json transport/status.json direct_history/status.json; do
  if test -f "$root/output/$file"; then echo FILE=$file; cat "$root/output/$file"; fi
done
for file in "$root"/logs/*; do
  if test -f "$file"; then echo LOG=$file; tail -n 5 "$file"; fi
done
