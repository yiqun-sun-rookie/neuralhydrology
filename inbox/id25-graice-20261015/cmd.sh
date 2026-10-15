#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_lstmnosif_20261015_001
jid=$(cat "$root/job_id.txt")
printf 'JOB_ID=%s
' "$jid"
cat "$root/submissions.tsv"
if q=$(squeue -h -j "$jid" -o '%i|%j|%T|%M|%R' 2>&1); then printf '%s\n' "$q"; else printf 'NOT_IN_ACTIVE_QUEUE: %s\n' "$q"; fi
sacct -j "$jid" --format=JobIDRaw,JobName,State,ExitCode,Elapsed -n -P
for name in status.json interface_check.json failure.json report.json; do
  if [ -f "$root/$name" ]; then printf '
FILE=%s
' "$name"; cat "$root/$name"; fi
done
if [ -f "$root/logs/graice-$jid.out" ]; then tail -n 3 "$root/logs/graice-$jid.out"; fi
if [ -f "$root/logs/graice-$jid.err" ]; then tail -n 12 "$root/logs/graice-$jid.err"; fi
