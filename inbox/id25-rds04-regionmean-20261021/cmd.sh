#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
date -Is
for rel in job_id.txt submissions.tsv; do echo "FILE=$rel"; if test -f "$root/$rel"; then cat "$root/$rel"; fi; done
if test -f "$root/job_id.txt"; then
 job=$(cat "$root/job_id.txt")
 timeout 30 squeue -h -j "$job" -o '%i|%j|%T|%M|%R'
 timeout 30 sacct -n -X -j "$job" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -P
fi
for rel in runtime.json output/status.json output/selection.json report.json; do
 echo "FILE=$rel"; if test -f "$root/$rel"; then cat "$root/$rel"; fi
done
if test -f "$root/output/metrics.jsonl"; then tail -n 2 "$root/output/metrics.jsonl"; fi
for f in "$root"/logs/*.out "$root"/logs/*.err; do if test -f "$f"; then echo "LOG=$f"; tail -n 12 "$f"; fi; done
