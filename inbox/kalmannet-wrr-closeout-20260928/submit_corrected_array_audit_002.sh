#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
target="$parent/corrected_fourteen_audit_002"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/corrected_fourteen_audit_002.tar
payload_sha=${1:-}
if [ "$#" -ne 1 ] || ! [[ "$payload_sha" =~ ^[0-9a-f]{64}$ ]]; then echo INVALID_PACKAGE_PIN; exit 64; fi
for path in "$target" "$parent/corrected_fourteen_audit_jobid_002.txt"; do
  if [ -e "$path" ] || [ -L "$path" ]; then echo "REFUSE_EXISTING=$path"; exit 64; fi
done
active=$(squeue -h -u sunyiq -o '%i|%j|%T|%Z' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}')
if [ -n "$active" ]; then printf 'REFUSE_ACTIVE_TASK_JOBS\n%s\n' "$active"; exit 64; fi
printf '%s  %s\n' "$payload_sha" "$payload" | sha256sum --strict --check -
# The externally pinned archive is assembled and its exact regular-file members
# independently checked locally before publishing this command.
tar --keep-old-files -xf "$payload" -C "$parent"
test -d "$target"
test ! -L "$target"
cd "$target"
sha256sum --strict --check package_files.sha256
printf '%s  %s\n' \
  9c8ab347eb3437b4bcc2f01a5a350a2126209577e77dee3ca796faa309313f34 "$parent/completed_ten_audit_001/audit_saved_statistics.py" \
  ba29ec4bc78eadf4554fc8902c160b5019b16e1829b087d6519d5706087b1297 "$parent/completed_ten_audit_001/audit_completed_ten.py" | sha256sum --strict --check -
test -s independent_code_review.md
test ! -e output_001
test ! -L output_001
( set -o noclobber; : > submission_attempted )
if submission=$(sbatch --chdir="$target" "$target/run_cpu_audit.sh" 2>&1); then status=0; else status=$?; fi
printf '%s\n' "$submission"
( set -o noclobber; printf '%s\n' "$submission" > submission_receipt.txt )
test "$status" -eq 0
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo SUBMISSION_PARSE_FAILED_NO_RETRY; exit 65; fi
( set -o noclobber; printf '%s\n' "$job" > "$parent/corrected_fourteen_audit_jobid_002.txt" )
echo "CORRECTED_FOURTEEN_SAVED_ARRAY_AUDIT_SUBMITTED=$job"
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
