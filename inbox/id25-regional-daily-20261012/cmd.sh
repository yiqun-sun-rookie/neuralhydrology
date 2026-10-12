#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/id25_regional_daily_storage_20261012_001
[ -f "$root/CAMPAIGN_OWNER" ] && [ "$(cat "$root/CAMPAIGN_OWNER")" = 'id25-regional-daily-20261012' ] || exit 1
jobid=$(cat "$root/job_id.txt")
[[ "$jobid" =~ ^[0-9]+$ ]] || exit 1
date -u
printf 'JOB_ID=%s\n' "$jobid"
squeue -j "$jobid" -h -o '%i|%j|%T|%P|%R'
sacct -j "$jobid" --format=JobID,JobName%30,State,ExitCode,Elapsed,NodeList -P -n
for name in "$root/logs/rds01-$jobid.out" "$root/logs/rds01-$jobid.err"; do
 if [ -f "$name" ]; then printf 'LOG=%s\n' "$name"; tail -n 4 "$name"; fi
done
run="$root/runs/RDS01_s20261012"
if [ -f "$run/status.json" ]; then cat "$run/status.json"; fi
if [ -f "$run/last.pt" ]; then stat -c 'CHECKPOINT_BYTES=%s MODIFIED=%y' "$run/last.pt"; fi
