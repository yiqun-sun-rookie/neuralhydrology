#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_regional_snowloss_20261013_001
run="$root/runs/RDS02_SNOWLOSS01_s20261012"
jid=$(cat "$root/job_id.txt")
printf 'JOB_ID=%s\n' "$jid"
if squeue -h -j "$jid" -o '%i|%j|%T|%M|%R'; then :; else echo QUEUE_QUERY_NOT_AVAILABLE; fi
sacct -j "$jid" --format=JobIDRaw,JobName,State,ExitCode,Elapsed -n -P
if [ -f "$run/status.json" ]; then cat "$run/status.json"; fi
if [ -f "$root/logs/rds02-$jid.err" ]; then tail -n 8 "$root/logs/rds02-$jid.err"; fi
state=$(sacct -j "$jid" --format=JobIDRaw,State -n -P | awk -F '|' -v j="$jid" '$1==j {print $2}')
if [ "$state" = COMPLETED ] && [ -f "$run/report.json" ]; then
  archive="$root/artifacts/calibration_results_v001.tar.gz"
  if [ ! -f "$archive" ]; then tar -czf "$archive" -C "$root" runs logs job_id.txt submissions.tsv; fi
  printf 'ARCHIVE_SHA256='
  sha256sum "$archive" | cut -d ' ' -f 1
  echo ARTIFACT_BASE64_BEGIN
  base64 "$archive"
  echo ARTIFACT_BASE64_END
fi
