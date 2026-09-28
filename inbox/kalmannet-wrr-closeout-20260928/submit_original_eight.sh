#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
plain="$parent/plain_preflight_v1"
launch="$parent/remaining_original_launch_001"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/original_eight_launch_001.tar
models=(main_seed43 main_seed44 compact_seed42 compact_seed43 compact_seed44 learned_noise hand_tuned adaptive)
if [ -e "$launch" ] || [ -L "$launch" ]; then echo REFUSE_EXISTING_LAUNCH; exit 64; fi
for model in "${models[@]}"; do
  output="$plain/numerical_impact/runs/${model}__original_outlet_original_states__formal_attempt01"
  if [ -e "$output" ] || [ -L "$output" ]; then echo "REFUSE_EXISTING=$output"; exit 64; fi
done
prepare_job=$(cat "$parent/adaptive_prepare_jobid.txt")
if ! [[ "$prepare_job" =~ ^[0-9]+$ ]]; then echo INVALID_PREPARE_JOB; exit 64; fi
active=$(squeue -h -u sunyiq -o '%i|%Z' | awk -F'|' -v known="$prepare_job" '$2 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" && $1 != known {print}')
if [ -n "$active" ]; then printf 'REFUSE_OTHER_ACTIVE_TASK_JOBS\n%s\n' "$active"; exit 64; fi
prepare_state=$(sacct -n -X -P -j "$prepare_job" -o State | head -n 1 | cut -d'|' -f1)
case "$prepare_state" in
  COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE) previous= ;;
  PENDING|RUNNING|CONFIGURING|COMPLETING) previous="$prepare_job" ;;
  *) echo "UNKNOWN_PREPARE_STATE=$prepare_state"; exit 64 ;;
esac
echo "PREPARE_STATE=$prepare_job:$prepare_state"
echo '8a9c725c5621d70e0cbb4d204e8a6c6dc82c221cf46460494ca5bca64b7a6340  '"$payload" | sha256sum --strict --check -
tar --keep-old-files -xf "$payload" -C "$parent"
mkdir "$launch/logs"
cd "$plain"
sha256sum --strict --check "$launch/launch_files.sha256"
sha256sum --strict --check "$plain/package_files.sha256"
sha256sum --strict --check "$plain/formal_launch_001/launch_files.sha256"
test -s "$launch/task-3-independent-review.md"
( set -o noclobber; : > "$launch/submission_attempted" )
job_list=
for model in "${models[@]}"; do
  if [ -n "$previous" ]; then
    if submission=$(sbatch --dependency="afterany:$previous" --job-name="knet-orig-$model" "$launch/original_one.slurm" "$model" 2>&1); then :; else submission_status=$?; printf '%s\n' "$submission"; exit "$submission_status"; fi
  else
    if submission=$(sbatch --job-name="knet-orig-$model" "$launch/original_one.slurm" "$model" 2>&1); then :; else submission_status=$?; printf '%s\n' "$submission"; exit "$submission_status"; fi
  fi
  printf '%s\n' "$submission"
  ( set -o noclobber; printf '%s\n' "$submission" > "$launch/${model}.submission_receipt.txt" )
  job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
  if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo SUBMISSION_PARSE_FAILED_NO_RETRY; exit 65; fi
  ( set -o noclobber; printf '%s\n' "$job" > "$launch/${model}.jobid" )
  echo "ORIGINAL_INDIVIDUAL_SUBMISSION=$model:$job:afterany=${previous:-none}"
  previous="$job"
  job_list="${job_list:+$job_list,}$job"
done
( set -o noclobber; printf '%s\n' "$job_list" > "$launch/all_jobids.txt" )
sacct -n -X -P -j "$job_list" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -j "$job_list" -o '%i|%j|%T|%Z|%R|%E'
