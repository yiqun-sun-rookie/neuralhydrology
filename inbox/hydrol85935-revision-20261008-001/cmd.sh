#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
SETUP="$ROOT/control/runtime_setup_20261009_001"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
date -Is
tail -35 "$ROOT/logs/runtime-download-20261009.log"
find "$ROOT/runtime_torch271cu118/wheels" -maxdepth 1 -type f -printf '%f %s bytes\n'
for file in "$SETUP/supervisor_exit_code" "$ROOT/runtime_torch271cu118/DOWNLOAD_COMPLETE.json" "$ROOT/runtime_torch271cu118/INSTALL_COMPLETE.json" "$ROOT/diagnostics/matched_runtime_20261009/summary.json"; do
  if test -f "$file"; then printf '\nFILE %s\n' "$file"; cat "$file"; fi
done
if test -f "$SETUP/job_id"; then
  job=$(cat "$SETUP/job_id")
  printf '\nRUNTIME_JOB_ID=%s\n' "$job"
  sacct -j "$job" -n -P --format=JobIDRaw,State,ExitCode,Elapsed,MaxRSS,AllocTRES
  squeue -j "$job" -o '%.18i %.35j %.10T %.12M %.8C %.20b %.30R' || true
  for suffix in out err; do if test -f "$ROOT/logs/runtime-$job.$suffix"; then tail -35 "$ROOT/logs/runtime-$job.$suffix"; fi; done
fi
