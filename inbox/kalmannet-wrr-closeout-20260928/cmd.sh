#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
adaptive="$parent/adaptive_preflight_v1"
launch="$parent/remaining_launch_001"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/adaptive_prepare_launch_001.tar
for target in "$launch" "$parent/adaptive_prepare_jobid.txt" "$adaptive/adaptive_comparison/selection_attempt01" "$adaptive/adaptive_comparison/runs/matched_fixed_test__preflight_attempt01" "$adaptive/adaptive_comparison/runs/matched_selected_test__preflight_attempt01"; do
  if [ -e "$target" ] || [ -L "$target" ]; then echo "REFUSE_EXISTING=$target"; exit 64; fi
done
active=$(squeue -h -u sunyiq -o '%i|%Z' | awk -F'|' '$2 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}')
if [ -n "$active" ]; then printf 'REFUSE_ACTIVE_TASK_JOBS\n%s\n' "$active"; exit 64; fi
echo '542b001e8d6dcf6867e5e94caf10e074ab1b9105d821b41016ff9376221c1408  '"$payload" | sha256sum --strict --check -
tar --keep-old-files -xf "$payload" -C "$parent"
sha256sum --strict --check "$launch/launch_inputs.sha256"
( cd "$adaptive"; sha256sum --strict --check package_files.sha256 )
test -s "$launch/task-1-independent-review.md"
( set -o noclobber; : > "$launch/submission_attempted" )
cd "$adaptive"
if submission=$(sbatch "$launch/adaptive_prepare.slurm" 2>&1); then
  printf '%s\n' "$submission"
else
  submission_status=$?
  printf '%s\n' "$submission"
  exit "$submission_status"
fi
( set -o noclobber; printf '%s\n' "$submission" > "$launch/submission_receipt.txt" )
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo SUBMISSION_PARSE_FAILED_NO_RETRY; exit 65; fi
( set -o noclobber; printf '%s\n' "$job" > "$parent/adaptive_prepare_jobid.txt" )
echo "ADAPTIVE_PREPARE_SINGLE_SUBMISSION=$job"
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -j "$job" -o '%i|%j|%T|%Z|%R'
