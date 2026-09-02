#!/bin/bash
# TUKF09-455 v2r6: start the download-only acquisition of the frozen private runtime
# inputs on login4.  Detached so this mailbox command stays short.
# No Slurm job, no training, no formal evaluation, no write inside v2r4 or v2r5.

set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r6_20260902
SCRIPT="$ROOT/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r6/download_runtime_inputs_login.sh"
LOG="$ROOT/logs/offline-inputs-download.log"
MARK="$ROOT/status/offline_inputs_download.launched"

echo "=== PRECONDITIONS ==="
hostname -s
test -f "$SCRIPT" && echo "SCRIPT_PRESENT" || { echo "SCRIPT_MISSING"; exit 1; }
sha256sum "$SCRIPT"
if [ -e "$ROOT/offline_inputs_v2r6" ]; then echo "FINAL_ALREADY_PRESENT"; else echo "FINAL_ABSENT_AS_EXPECTED"; fi

echo "=== LAUNCH ONCE, DETACHED ==="
if [ -e "$MARK" ]; then
  echo "ALREADY_LAUNCHED"
  cat "$MARK"
else
  setsid nohup bash "$SCRIPT" a20260902 < /dev/null > "$LOG" 2>&1 &
  PID=$!
  printf 'pid=%s attempt=a20260902 started=%s
' "$PID" "$(date -Is)" > "$MARK"
  echo "LAUNCHED pid=$PID"
fi

sleep 8
echo "=== EARLY STATE ==="
ls -la "$ROOT" 2>&1
echo "--- pending tree ---"
du -sh "$ROOT"/offline_inputs_v2r6.pending.* 2>&1
echo "--- launcher log tail ---"
tail -c 1500 "$LOG" 2>&1
echo "--- download stderr tail ---"
tail -c 800 "$ROOT"/offline_inputs_v2r6.pending.*/evidence/download-stderr.log 2>&1

echo "TUKF09_455_V2R6_OFFLINE_INPUT_DOWNLOAD_LAUNCHED_NO_JOB_SUBMITTED_FORMAL_EVALUATION_HOLD"
