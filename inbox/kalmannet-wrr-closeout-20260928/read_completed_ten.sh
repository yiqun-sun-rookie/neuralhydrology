#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
output="$parent/completed_ten_array_review_001"
job=$(cat "$parent/completed_ten_audit_jobid_001.txt")
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo INVALID_OWN_JOB_ID; exit 64; fi
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
for log in "$parent/logs/completed-ten-audit-$job.out" "$parent/logs/completed-ten-audit-$job.err"; do
  if [ -f "$log" ]; then printf '\nLOG=%s\n' "$log"; tail -n 60 "$log"; fi
done
state=$(sacct -n -X -P -j "$job" -o JobID,State | awk -F'|' -v id="$job" '$1==id {print $2}')
case "$state" in
  COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE) ;;
  *) echo "NOT_TERMINAL=$state"; exit 0 ;;
esac
for relative in original_headers.json original_metadata.json arrays/audit.json arrays/failure.json; do
  file="$output/$relative"
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    bytes=$(stat -c %s "$file")
    if [ "$bytes" -gt 2000000 ]; then echo "REFUSE_OVERSIZE=$relative"; exit 64; fi
    printf '\nBEGIN_SAVED_AUDIT_FILE=%s\n' "$relative"
    sha256sum "$file"
    base64 "$file"
    printf 'END_SAVED_AUDIT_FILE=%s\n' "$relative"
  fi
done
echo 'TERMINAL_SAVED_AUDIT_RECEIPT_NO_ACCEPTANCE'
