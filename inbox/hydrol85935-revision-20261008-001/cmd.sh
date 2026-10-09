#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
CONT="$ROOT/control/continuation_v003"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
date -Is
pid=$(cat "$CONT/coordinator_pid")
ps -p "$pid" -o pid,etime,args || true
for file in "$CONT/status.json" "$ROOT/control/full_v003/jobs.json" "$ROOT/control/resource_pilot_v003.json"; do
  if test -f "$file"; then printf '\nFILE %s\n' "$file"; cat "$file"; fi
done
printf '\nCONTINUATION_LOG\n'
tail -20 "$ROOT/logs/continuation-v003.log"
printf '\nDOWNLOAD_LOG\n'
tail -25 "$ROOT/logs/runtime-download-20261009.log"
printf '\nDOWNLOADED_FILE_SIZES\n'
find "$ROOT/runtime_torch271cu118/wheels" -maxdepth 1 -type f -printf '%f %s bytes\n'
if test -f "$ROOT/control/runtime_setup_20261009_001/job_id"; then
  job=$(cat "$ROOT/control/runtime_setup_20261009_001/job_id")
  printf '\nRUNTIME_JOB_ID=%s\n' "$job"
  sacct -j "$job" -n -P --format=JobIDRaw,State,ExitCode,Elapsed,MaxRSS
  for suffix in out err; do if test -f "$ROOT/logs/runtime-$job.$suffix"; then tail -20 "$ROOT/logs/runtime-$job.$suffix"; fi; done
fi
