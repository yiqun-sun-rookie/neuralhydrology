#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
target="$parent/three_method_analysis_002"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/three_method_analysis_002.tar
payload_sha=${1:-}
manifest_sha=${2:-}
if [ "$#" -ne 2 ] || ! [[ "$payload_sha" =~ ^[0-9a-f]{64}$ ]] || ! [[ "$manifest_sha" =~ ^[0-9a-f]{64}$ ]]; then echo INVALID_PACKAGE_OR_MANIFEST_PIN; exit 64; fi
for path in "$target" "$parent/three_method_analysis_jobid_002.txt"; do
  if [ -e "$path" ] || [ -L "$path" ]; then echo "REFUSE_EXISTING=$path"; exit 64; fi
done
active=$(squeue -h -u sunyiq -o '%i|%j|%T|%Z' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}')
if [ -n "$active" ]; then printf 'REFUSE_ACTIVE_TASK_JOBS\n%s\n' "$active"; exit 64; fi
printf '%s  %s\n' "$payload_sha" "$payload" | sha256sum --strict --check -
tar -tf "$payload" | LC_ALL=C sort > /dev/null
# The externally pinned archive is assembled and its exact regular-file members
# independently checked locally before publishing this command.
tar --keep-old-files -xf "$payload" -C "$parent"
test -d "$target"
test ! -L "$target"
cd "$target"
sha256sum --strict --check package_files.sha256
printf '%s  %s\n' "$manifest_sha" "$target/analysis_manifest_003.json" | sha256sum --strict --check -
test -s independent_code_review.md
test -s independent_repair_review_001.md
test -s proofs/analysis_admission_002.json
test ! -e submission_attempted
( set -o noclobber; : > submission_attempted )
if submission=$(sbatch --chdir="$target/code" "$target/code/launch_three_methods.slurm" "$target/analysis_manifest_003.json" "$manifest_sha" 2>&1); then status=0; else status=$?; fi
printf '%s\n' "$submission"
( set -o noclobber; printf '%s\n' "$submission" > submission_receipt.txt )
test "$status" -eq 0
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo SUBMISSION_PARSE_FAILED_NO_RETRY; exit 65; fi
( set -o noclobber; printf '%s\n' "$job" > "$parent/three_method_analysis_jobid_002.txt" )
echo "THREE_METHOD_SAVED_STATISTICS_SUBMITTED=$job"
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
