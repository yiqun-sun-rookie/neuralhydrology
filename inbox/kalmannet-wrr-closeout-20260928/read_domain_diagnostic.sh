#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
job=$(cat "$parent/domain_diagnostic_jobid_001.txt")
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo INVALID_DIAGNOSTIC_JOB; exit 64; fi
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
for log in "$parent/logs/domain-diagnostic-$job.out" "$parent/logs/domain-diagnostic-$job.err"; do
 if [ -f "$log" ]; then echo "LOG=$log"; tail -n 35 "$log"; fi
done
state=$(sacct -n -X -P -j "$job" -o State)
case "$state" in
 COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE) ;;
 *) echo "DIAGNOSTIC_NOT_TERMINAL=$state"; exit 0 ;;
esac
output="$parent/domain_diagnostic_output_001/job_$job"
for name in diagnostic.json failure.json; do
 file="$output/$name"
 if [ -f "$file" ]; then
   test ! -L "$file"
   test "$(stat -c %s "$file")" -le 2000000
   echo "BEGIN_SAVED_DIAGNOSTIC_FILE=$name"
   sha256sum "$file"
   base64 "$file"
   echo "END_SAVED_DIAGNOSTIC_FILE=$name"
 fi
done
echo SAVED_DOMAIN_DIAGNOSTIC_RECEIPT_NOT_ACCEPTANCE
