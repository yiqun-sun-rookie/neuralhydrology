#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
target="$parent/three_method_analysis_002"
job=$(cat "$parent/three_method_analysis_jobid_002.txt")
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo INVALID_OWN_JOB_ID; exit 64; fi
output="$target/job_$job"
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,ReqTRES%120,AllocTRES%120,NodeList
squeue -h -u sunyiq -o '%i|%j|%T|%Z|%R' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}'
for log in "$parent/logs/three-method-$job.out" "$parent/logs/three-method-$job.err"; do
  if [ -f "$log" ]; then printf '\nLOG=%s\n' "$log"; tail -n 60 "$log"; fi
done
state=$(sacct -n -X -P -j "$job" -o JobID,State | awk -F'|' -v id="$job" '$1==id {print $2}')
case "$state" in
  COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE) ;;
  *) echo "NOT_TERMINAL=$state"; exit 0 ;;
esac
cd "$target"
sha256sum --strict --check package_files.sha256
for relative in analysis.json failure.json; do
  file="$output/$relative"
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    bytes=$(stat -c %s "$file")
    if [ "$bytes" -gt 5000000 ]; then echo "REFUSE_OVERSIZE=$relative"; exit 64; fi
    printf '\nBEGIN_THREE_METHOD_FILE=%s\n' "$relative"
    sha256sum "$file"
    base64 "$file"
    printf 'END_THREE_METHOD_FILE=%s\n' "$relative"
  fi
done
for relative in paired_800.npz paired_400.npz paired_1600.npz domain_sy2_differences.npz; do
  file="$output/$relative"
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    printf 'SAVED_ARRAY_BYTES=%s:' "$relative"
    stat -c %s "$file"
    sha256sum "$file"
  fi
done
echo 'TERMINAL_THREE_METHOD_RECEIPT_PENDING_INDEPENDENT_ACCEPTANCE'
