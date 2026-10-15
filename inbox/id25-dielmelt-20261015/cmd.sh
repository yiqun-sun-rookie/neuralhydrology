#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_dielmelt_20261015_001
jid=$(cat "$root/job_id.txt")
printf 'JOB_ID=%s\n' "$jid"
cat "$root/submissions.tsv"
squeue -h -u sunyiq -n id25_diel_261015 -o '%i|%j|%T|%M|%R'
sacct -j "$jid" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -n -P
for file in "$root/output/status.json" "$root/output/selection.json" "$root/output/report.json"; do
  if [ -f "$file" ]; then printf '\nFILE=%s\n' "$file"; cat "$file"; fi
done
for file in "$root/logs/dielmelt-$jid.out" "$root/logs/dielmelt-$jid.err"; do
  if [ -f "$file" ]; then printf '\nLOG=%s\n' "$file"; tail -n 20 "$file"; fi
done
