#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_daily_lstm_matched_20261015_001
jid=$(cat "$root/job_id.txt")
printf 'JOB_ID=%s\n' "$jid"
cat "$root/submissions.tsv"
squeue -h -u sunyiq -n id25_lstm_m_261015 -o '%i|%j|%T|%M|%R'
sacct -j "$jid" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -n -P
for file in "$root/output/status.json" "$root/output/interface_check.json" "$root/output/selection.json" "$root/output/report.json"; do
  if [ -f "$file" ]; then printf '\nFILE=%s\n' "$file"; cat "$file"; fi
done
if [ -f "$root/output/metrics.jsonl" ]; then echo LAST_METRICS; tail -n 2 "$root/output/metrics.jsonl"; fi
for file in "$root/logs/b03-$jid.out" "$root/logs/b03-$jid.err"; do
  if [ -f "$file" ]; then printf '\nLOG=%s\n' "$file"; tail -n 20 "$file"; fi
done
