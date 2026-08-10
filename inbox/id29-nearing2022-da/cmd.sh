#!/bin/bash
# ID29 seq=113: classify the only non-empty active stderr logs exactly; read-only.
set -eo pipefail

JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== EXACT NON-EMPTY STDERR ==="
for job in 202215_2 202222_8 202222_9; do
  record=$(scontrol show job -o "$job")
  stderr=$(sed -n 's/.* StdErr=\([^ ]*\).*/\1/p' <<<"$record")
  echo "--- job=$job"
  echo "stderr=$stderr"
  test -f "$stderr"
  size=$(stat -c '%s' "$stderr")
  echo "bytes=$size"
  test "$size" -le 4096
  sha256sum "$stderr"
  cat "$stderr"
  echo
done

echo "=== ACTIVE FAILURE STATES ==="
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
