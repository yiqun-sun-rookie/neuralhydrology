#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
date -Is
pid=$(cat "$ROOT/control/continuation_v003/coordinator_pid")
ps -p "$pid" -o pid,etime,args || true
for file in control/continuation_v003/status.json control/runtime_setup_20261009_001/supervisor_exit_code runtime_torch271cu118/DOWNLOAD_COMPLETE.json runtime_torch271cu118/INSTALL_COMPLETE.json diagnostics/matched_runtime_20261009/summary.json control/resource_pilot_v003.json control/full_v003/jobs.json; do
  if test -f "$ROOT/$file"; then printf '\nFILE %s\n' "$file"; cat "$ROOT/$file"; fi
done
printf '\nCONTINUATION_LOG\n'
tail -25 "$ROOT/logs/continuation-v003.log"
printf '\nDOWNLOAD_LOG\n'
tail -20 "$ROOT/logs/runtime-download-20261009.log"
printf '\nDOWNLOADED_FILE_SIZES\n'
find "$ROOT/runtime_torch271cu118/wheels" -maxdepth 1 -type f -printf '%f %s bytes\n'
for item in 'control/runtime_setup_20261009_001/job_id:runtime' 'control/preflight_v003_job_id:preflight' 'control/resource_pilot_v003_job_id:resource-pilot'; do
  file=${item%:*}
  kind=${item#*:}
  if test -f "$ROOT/$file"; then
    job=$(cat "$ROOT/$file")
    printf '\nSTAGE %s JOB_ID %s\n' "$kind" "$job"
    sacct -j "$job" -n -P --format=JobIDRaw,State,ExitCode,Elapsed,MaxRSS
    for suffix in out err; do if test -f "$ROOT/logs/$kind-$job.$suffix"; then tail -25 "$ROOT/logs/$kind-$job.$suffix"; fi; done
  fi
done
