#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_transport_rds07_20261026_001
date -Is
echo SCOPED_ROOT_FILES
find "$root" -maxdepth 2 -type f -printf '%P %s bytes\n'
for file in submission_intent.initial submission_intent.memory_default_v002 job_id.txt pre_repair_sacct_v002.txt submissions.tsv output/status.json output/runtime.json resource_adaptation_v002/receipt.json; do
  if test -f "$root/$file"; then echo FILE=$file; cat "$root/$file"; fi
done
echo EXACT_NAME_QUEUE
timeout 30 squeue -h -u sunyiq -n id25_rds07_261026 -o '%i|%j|%T|%M|%R'
echo EXACT_NAME_ACCOUNTING
timeout 30 sacct -n -X -u sunyiq -S 2026-10-26 --format=JobIDRaw,JobName%40,State,ExitCode -P | awk -F'|' '$2=="id25_rds07_261026" {print}'
echo SCOPED_LOG_TAIL
for file in "$root"/logs/*; do
  if test -f "$file"; then echo LOG=$file; tail -n 12 "$file"; fi
done
