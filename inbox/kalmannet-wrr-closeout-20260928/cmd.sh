#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
adaptive="$parent/adaptive_preflight_v1"
admission="$adaptive/test_formal_admission_001"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/adaptive_test_launch_001.tar
test_source="$parent/plain_preflight_v1/inputs/repo/data/processed/high_flow_aug/test_win800_20090314_14-20110101_01.pt"
test_target="$adaptive/inputs/repo/data/processed/high_flow_aug/test_win800_20090314_14-20110101_01.pt"
for target in "$admission" "$test_target" "$parent/adaptive_test_formal_jobid.txt" "$adaptive/adaptive_comparison/runs/matched_fixed_test__formal_attempt01" "$adaptive/adaptive_comparison/runs/matched_selected_test__formal_attempt01"; do
  if [ -e "$target" ] || [ -L "$target" ]; then echo "REFUSE_EXISTING=$target"; exit 64; fi
done
previous=$(cat "$parent/remaining_original_launch_001/adaptive.jobid")
if [ "$previous" != 229405 ]; then echo ORIGINAL_CHAIN_ID_CHANGED; exit 64; fi
active=$(squeue -h -u sunyiq -o '%i|%Z' | awk -F'|' '$2 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" && $1 !~ /^(229398|229399|229400|229401|229402|229403|229404|229405)$/ {print}')
if [ -n "$active" ]; then printf 'REFUSE_UNEXPECTED_TASK_JOBS\n%s\n' "$active"; exit 64; fi
previous_state=$(sacct -n -X -P -j "$previous" -o State | head -n 1 | cut -d'|' -f1)
case "$previous_state" in
  COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE) dependency= ;;
  PENDING|RUNNING|CONFIGURING|COMPLETING) dependency="$previous" ;;
  *) echo "UNKNOWN_PREDECESSOR_STATE=$previous_state"; exit 64 ;;
esac
if [ -z "$dependency" ]; then
  still_active=$(squeue -h -u sunyiq -o '%i|%Z' | awk -F'|' '$2 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}')
  if [ -n "$still_active" ]; then printf 'REFUSE_TERMINAL_LAST_JOB_WITH_ACTIVE_PREDECESSOR\n%s\n' "$still_active"; exit 64; fi
fi
echo "LAST_ORIGINAL_STATE=$previous:$previous_state"
echo '7de9fe2c2ad170592d78decc4aa5996844d13ae647b765da4e50d7ce5a667401  '"$payload" | sha256sum --strict --check -
tar --keep-old-files -xf "$payload" -C "$adaptive"
( cd "$admission"; sha256sum --strict --check launch_files.sha256 )
echo 'fdcc10d717bd49c6f8314554e8a123ebbb01988971eb44c160478e9b2df4e15b  '"$adaptive/package_files.sha256" | sha256sum --strict --check -
( cd "$adaptive"; sha256sum --strict --check package_files.sha256 )
echo 'df18203c073314c5a15c6df77411cb972a0a3f983d97cc468760ff12dbd6908a  '"$test_source" | sha256sum --strict --check -
# Byte-only transfer after both independent admissions; no tensor deserialization on login.
cp --no-clobber "$test_source" "$test_target"
echo 'df18203c073314c5a15c6df77411cb972a0a3f983d97cc468760ff12dbd6908a  '"$test_target" | sha256sum --strict --check -
( set -o noclobber; sha256sum "$test_target" > "$admission/test_input_delivery.sha256" )
( set -o noclobber; : > "$admission/submission_attempted" )
cd "$adaptive"
if [ -n "$dependency" ]; then
  if submission=$(sbatch --dependency="afterany:$dependency" "$admission/test_two.slurm" 2>&1); then :; else submission_status=$?; printf '%s\n' "$submission"; exit "$submission_status"; fi
else
  if submission=$(sbatch "$admission/test_two.slurm" 2>&1); then :; else submission_status=$?; printf '%s\n' "$submission"; exit "$submission_status"; fi
fi
printf '%s\n' "$submission"
( set -o noclobber; printf '%s\n' "$submission" > "$admission/submission_receipt.txt" )
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo SUBMISSION_PARSE_FAILED_NO_RETRY; exit 65; fi
( set -o noclobber; printf '%s\n' "$job" > "$parent/adaptive_test_formal_jobid.txt" )
echo "MATCHED_TWO_TESTS_SINGLE_SUBMISSION=$job:afterany=${dependency:-none}"
sacct -n -X -P -j "$job,229398,229399,229400,229401,229402,229403,229404,229405" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R|%E' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
