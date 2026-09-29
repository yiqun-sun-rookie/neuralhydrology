#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
code="$parent/completed_ten_audit_001"
output="$parent/completed_ten_array_review_001"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/completed_ten_audit_001.tar
payload_sha=${1:-}
if ! [[ "$payload_sha" =~ ^[0-9a-f]{64}$ ]]; then echo MISSING_PINNED_PACKAGE_HASH; exit 64; fi
for target in "$code" "$output" "$parent/completed_ten_audit_jobid_001.txt"; do
  if [ -e "$target" ] || [ -L "$target" ]; then echo "REFUSE_EXISTING=$target"; exit 64; fi
done
test -d "$parent/logs"
active=$(squeue -h -u sunyiq -o '%i|%j|%T|%Z' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}')
if [ -n "$active" ]; then printf 'REFUSE_ACTIVE_TASK_JOBS\n%s\n' "$active"; exit 64; fi
# Do not infer completion from an empty queue: independently bind all source jobs.
states=$(sacct -n -X -P -j 229398,229399,229400,229401,229402,229403,229404,229405,229426 -o JobID,State,ExitCode)
printf '%s\n' "$states"
for source_job in 229398 229399 229400 229401 229402 229403 229404 229405 229426; do
  record=$(printf '%s\n' "$states" | awk -F'|' -v id="$source_job" '$1==id {print $1"|"$2"|"$3}')
  if [ "$record" != "$source_job|COMPLETED|0:0" ]; then echo "REFUSE_SOURCE_JOB=$source_job"; exit 64; fi
done
printf '%s  %s\n' "$payload_sha" "$payload" | sha256sum --strict --check -
tar --keep-old-files -xf "$payload" -C "$parent"
( cd "$code"; sha256sum --strict --check package_files.sha256 )
( set -o noclobber; : > "$code/submission_attempted" )
cd "$code"
if submission=$(sbatch "$code/completed_ten.slurm" 2>&1); then :; else
  submission_status=$?
  printf '%s\n' "$submission"
  ( set -o noclobber; printf '%s\n' "$submission" > "$code/submission_receipt.txt" )
  exit "$submission_status"
fi
printf '%s\n' "$submission"
( set -o noclobber; printf '%s\n' "$submission" > "$code/submission_receipt.txt" )
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo SUBMISSION_PARSE_FAILED_NO_RETRY; exit 65; fi
( set -o noclobber; printf '%s\n' "$job" > "$parent/completed_ten_audit_jobid_001.txt" )
echo "CPU_ONLY_SAVED_RESULT_AUDIT_SUBMITTED=$job"
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
