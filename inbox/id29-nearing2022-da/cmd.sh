#!/bin/bash
# ID29 seq=117: lightweight liveness and failure audit between full artifact-count windows.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== ACTIVE TASKS ==="
squeue -h -j "$JOBS" -o '%i|%j|%T|%M|%l|%R' | sort

echo "=== ACCOUNTING COUNTS ==="
sacct -n -P -j "$JOBS" --format=JobID,State,ExitCode | awk -F'|' '
  NF >= 3 && $1 !~ /\./ {
    parent = $1
    sub(/_.*/, "", parent)
    key = parent "|" $2 "|" $3
    count[key]++
  }
  END { for (key in count) print count[key] "|" key }
' | sort -t'|' -k2,2n -k3,3

echo "=== ACTIVE FAILURE STATES ==="
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== RUNNING LOG METADATA ==="
mapfile -t RUNNING_IDS < <(squeue -h -j "$JOBS" -t RUNNING -o '%i' | sort -u)
echo "running_task_count=${#RUNNING_IDS[@]}"
for job in "${RUNNING_IDS[@]}"; do
  record=$(scontrol show job -o "$job" 2>/dev/null || true)
  if [ -z "$record" ]; then
    echo "job=$job transitioned_before_log_probe=1"
    continue
  fi
  stdout=$(sed -n 's/.* StdOut=\([^ ]*\).*/\1/p' <<<"$record")
  stderr=$(sed -n 's/.* StdErr=\([^ ]*\).*/\1/p' <<<"$record")
  echo "--- job=$job"
  if [ -f "$stdout" ]; then
    stat -c 'stdout=%n|bytes=%s|mtime=%y' "$stdout"
  else
    echo "stdout_missing=$stdout"
  fi
  if [ -f "$stderr" ]; then
    stat -c 'stderr=%n|bytes=%s|mtime=%y' "$stderr"
    if [ -s "$stderr" ]; then
      sha256sum "$stderr"
    fi
  else
    echo "stderr_missing=$stderr"
  fi
done

echo "=== REFRESHED PRECLOSURE BOUNDARY ==="
test "$(sacct -n -P -j 202388 --format=JobIDRaw,State,ExitCode | awk -F'|' '$1 == "202388" {print $2 "|" $3; exit}')" = "COMPLETED|0:0"
test -f "$ROOT/closure_20260810/provenance/preclosure_validation_202388_receipt.json"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
