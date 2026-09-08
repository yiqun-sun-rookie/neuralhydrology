#!/bin/bash
# TUKF09-455 v2r12: start the offline runtime input download with its required attempt id.
# Detached, download only. Builds nothing, installs nothing, submits nothing.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r12_20260908
D="$ROOT/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r12/download_runtime_inputs_login.sh"
echo "TIME=$(date -Is)  HOST=$(hostname -s)"
test -f "$D" || { echo DOWNLOADER_MISSING; exit 10; }
if pgrep -f "download_runtime_inputs_login.sh" >/dev/null 2>&1; then echo ALREADY_RUNNING; pgrep -af download_runtime_inputs_login.sh; exit 0; fi
if [ -d "$ROOT/offline_inputs_v2r12" ]; then echo ALREADY_PUBLISHED; exit 0; fi
rm -f "$ROOT/status/offline_inputs_download.lock" "$ROOT/status/offline_inputs_download.launched"
ATTEMPT=v2r12-20260908-a
echo "ATTEMPT=$ATTEMPT"
nohup bash "$D" "$ATTEMPT" > "$ROOT/logs/offline-inputs-download.out" 2>&1 &
PID=$!
echo "DOWNLOAD_LAUNCHED pid=$PID attempt=$ATTEMPT" | tee "$ROOT/status/offline_inputs_download.launched"
sleep 40
echo "=== early log ==="
tail -c 1500 "$ROOT/logs/offline-inputs-download.out" 2>&1
pgrep -af download_runtime_inputs_login.sh | head -2 || echo NOT_RUNNING_ANY_MORE
du -sh "$ROOT"/offline_inputs_v2r12* 2>/dev/null || echo "no offline tree yet"
echo TUKF09_455_V2R12_DOWNLOAD_STARTED
