#!/bin/bash
# ID29 seq=112: read-only liveness and runtime audit for currently running registered jobs; no artifact recount.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== ACTIVE TASKS WITH ELAPSED AND LIMIT ==="
squeue -h -j "$JOBS" -o '%i|%j|%T|%M|%l|%R' | sort

echo "=== TERMINAL AND RUNNING ARRAY ELEMENTS ==="
sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,Elapsed,Timelimit,Start,End,NodeList,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(COMPLETED|RUNNING|FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/' | sort

echo "=== ACTIVE FAILURE STATES ==="
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== RUNNING JOB LOG LIVENESS ==="
mapfile -t RUNNING_IDS < <(squeue -h -j "$JOBS" -t RUNNING -o '%i' | sort -u)
echo "running_task_count=${#RUNNING_IDS[@]}"
for job in "${RUNNING_IDS[@]}"; do
  record=$(scontrol show job -o "$job")
  stdout=$(sed -n 's/.* StdOut=\([^ ]*\).*/\1/p' <<<"$record")
  stderr=$(sed -n 's/.* StdErr=\([^ ]*\).*/\1/p' <<<"$record")
  command=$(sed -n 's/.* Command=\([^ ]*\).*/\1/p' <<<"$record")
  echo "--- job=$job"
  echo "command=$command"
  echo "stdout=$stdout"
  if [ -f "$stdout" ]; then
    stat -c 'stdout_bytes=%s stdout_mtime=%y' "$stdout"
    tail -n 5 "$stdout" || true
  else
    echo "stdout_missing=1"
  fi
  echo "stderr=$stderr"
  if [ -f "$stderr" ]; then
    stat -c 'stderr_bytes=%s stderr_mtime=%y' "$stderr"
    tail -n 5 "$stderr" || true
  else
    echo "stderr_missing=1"
  fi
done

echo "=== COMPLETED TASK DURATION SUMMARY ==="
python - <<'PY'
import json
import subprocess

by_parent = {}
output = subprocess.run(
    ['sacct', '-n', '-P', '-j', '202214,202215,202216,202222', '--format=JobIDRaw,State,ElapsedRaw'],
    check=True,
    capture_output=True,
    text=True,
).stdout
for raw in output.splitlines():
    fields = raw.split('|')
    if len(fields) < 3 or '.' in fields[0] or fields[1] != 'COMPLETED':
        continue
    parent = fields[0].split('_', 1)[0]
    try:
        elapsed = int(fields[2])
    except ValueError:
        continue
    by_parent.setdefault(parent, []).append(elapsed)
summary = {}
for parent, values in sorted(by_parent.items()):
    values.sort()
    summary[parent] = {
        'completed_tasks': len(values),
        'min_seconds': values[0],
        'median_seconds': values[len(values) // 2],
        'max_seconds': values[-1],
    }
print(json.dumps(summary, sort_keys=True))
PY

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
