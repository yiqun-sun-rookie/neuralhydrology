#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/id25_regional_daily_storage_20261012_001
payload=$HOME/hpc_mailbox/inbox/id25-regional-daily-20261012/payload/payload_v001.tar.gz
expected=550f382b2b1fc2fcc43cb34bfb361a2166f635eb842cc0739110c19304c25c0c
actual=$(sha256sum "$payload" | awk '{print $1}')
[ "$actual" = "$expected" ] || { printf 'PAYLOAD_HASH_MISMATCH
'; exit 1; }
if [ ! -e "$root" ]; then
 mkdir "$root"
 printf '%s
' 'id25-regional-daily-20261012' > "$root/CAMPAIGN_OWNER"
 tar -xzf "$payload" -C "$root"
 mkdir -p "$root/logs" "$root/runs"
 printf '%s
' "$expected" > "$root/deployed_payload.sha256"
else
 [ -f "$root/CAMPAIGN_OWNER" ] && [ "$(cat "$root/CAMPAIGN_OWNER")" = 'id25-regional-daily-20261012' ] || { printf 'ROOT_NOT_OWNED
'; exit 1; }
 [ -f "$root/deployed_payload.sha256" ] && [ "$(cat "$root/deployed_payload.sha256")" = "$expected" ] || { printf 'DEPLOYMENT_INCOMPLETE
'; exit 1; }
fi
if [ -f "$root/job_id.txt" ]; then
 printf 'ALREADY_SUBMITTED '; cat "$root/job_id.txt"
 squeue -j "$(cat "$root/job_id.txt")" -h -o '%i|%T|%R'
 exit 0
fi
active=$(squeue -u "$USER" -h -n id25_rds01_261012 -o '%i')
[ -z "$active" ] || { printf 'EXISTING_CAMPAIGN_JOB %s
' "$active"; exit 0; }
mkdir "$root/.submit_lock" || { printf 'SUBMIT_IN_FLIGHT
'; exit 1; }
trap 'rmdir "$root/.submit_lock"' EXIT
out=$(sbatch "$root/train.slurm" 2>&1)
printf '%s
' "$out"
jobid=$(printf '%s
' "$out" | awk '/Submitted batch job [0-9]+/{print $4}')
[[ "$jobid" =~ ^[0-9]+$ ]] || { printf 'SUBMIT_FAILED
'; exit 1; }
printf '%s
' "$jobid" > "$root/job_id.txt"
printf '%s|%s|%s
' "$(date -u +%FT%TZ)" "$jobid" 'attempt_001' >> "$root/submissions.tsv"
printf 'JOB_ID=%s
ROOT=%s
' "$jobid" "$root"
squeue -j "$jobid" -h -o '%i|%j|%T|%P|%R'
