#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
launch="$parent/corrected_launch_001"
jobs=$(cat "$launch/all_jobids.txt")
if ! [[ "$jobs" =~ ^[0-9]+(,[0-9]+){13}$ ]]; then echo INVALID_JOB_INDEX; exit 64; fi
sacct -n -X -P -j "$jobs" -o JobID,State,ExitCode,Elapsed,NodeList
echo LIVE_REQUESTED_GRAPHICS_RESOURCES
squeue -h -u sunyiq -o '%i|%T|%b|%C|%l|%Z|%R|%E' | awk -F'|' -v root="$parent" '$6 == root || index($6, root "/") == 1 {print}'
for case_id in main_seed43__corrected_outlet_original_states main_seed43__corrected_outlet_corrected_states; do
 job=$(cat "$launch/$case_id.jobid")
 if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo INVALID_CASE_JOB; exit 64; fi
 for log in "$launch/logs/corrected-one-$job.out" "$launch/logs/corrected-one-$job.err"; do
  if [ -f "$log" ]; then echo "LOG=$log"; tail -n 8 "$log"; fi
 done
done
echo READ_ONLY_NO_RESULT_ACCEPTANCE
