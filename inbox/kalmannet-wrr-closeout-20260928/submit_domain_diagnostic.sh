#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
code="$parent/domain_diagnostic_001"
output="$parent/domain_diagnostic_output_001"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/domain_diagnostic_001.tar
payload_sha=${1:-}
if [ "$#" -ne 1 ] || ! [[ "$payload_sha" =~ ^[0-9a-f]{64}$ ]]; then echo INVALID_PACKAGE_PIN; exit 64; fi
for target in "$code" "$output" "$parent/domain_diagnostic_jobid_001.txt"; do
  if [ -e "$target" ] || [ -L "$target" ]; then echo "REFUSE_EXISTING=$target"; exit 64; fi
done
active=$(squeue -h -u sunyiq -o '%i|%j|%T|%Z' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}')
if [ -n "$active" ]; then printf 'REFUSE_ACTIVE_TASK_JOBS\n%s\n' "$active"; exit 64; fi
sacct -n -X -P -j 230259 -o JobID,State,ExitCode,Elapsed,NodeList
test -f "$parent/completed_ten_array_review_001/arrays/failure.json"
printf '%s  %s\n' 6334833e5f2ba2a8d15105914c12786540ed7140c6993641ac8c620cd43462f1 "$parent/completed_ten_array_review_001/arrays/failure.json" "$payload_sha" "$payload" | sha256sum --strict --check -
tar --keep-old-files -xf "$payload" -C "$parent"
cd "$code"
sha256sum --strict --check package_files.sha256
test -s independent_review.md
( set -o noclobber; : > submission_attempted )
if submission=$(sbatch --chdir="$code" "$code/diagnose_domain.slurm" 2>&1); then status=0; else status=$?; fi
printf '%s\n' "$submission"
( set -o noclobber; printf '%s\n' "$submission" > submission_receipt.txt )
test "$status" -eq 0
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo SUBMISSION_PARSE_FAILED_NO_RETRY; exit 65; fi
( set -o noclobber; printf '%s\n' "$job" > "$parent/domain_diagnostic_jobid_001.txt" )
echo "FOUR_SAVED_ARRAY_DOMAIN_DIAGNOSTIC_SUBMITTED=$job"
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
