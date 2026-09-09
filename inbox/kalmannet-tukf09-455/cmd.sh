#!/bin/bash
# TUKF09-455 v2r13: start the offline runtime input download with its attempt id.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
D="$ROOT/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/download_runtime_inputs_login.sh"
echo "TIME=$(date -Is)  HOST=$(hostname -s)"
test -f "$D" || { echo DOWNLOADER_MISSING; exit 10; }
if pgrep -f "download_runtime_inputs_login.sh" >/dev/null 2>&1; then echo ALREADY_RUNNING; pgrep -af download_runtime_inputs_login.sh; exit 0; fi
if [ -d "$ROOT/offline_inputs_v2r13" ]; then echo ALREADY_PUBLISHED; exit 0; fi
rm -f "$ROOT/status/offline_inputs_download.lock" "$ROOT/status/offline_inputs_download.launched"
ATTEMPT=v2r13-20260909-a
nohup bash "$D" "$ATTEMPT" > "$ROOT/logs/offline-inputs-download.out" 2>&1 &
echo "DOWNLOAD_LAUNCHED pid=$! attempt=$ATTEMPT" | tee "$ROOT/status/offline_inputs_download.launched"
sleep 240
if pgrep -f "download_runtime_inputs_login.sh" >/dev/null 2>&1; then echo STILL_RUNNING; else echo FINISHED_OR_DIED; fi
M="$ROOT/offline_inputs_v2r13/manifest.json"
if [ -f "$M" ]; then echo OFFLINE_INPUTS_PUBLISHED; echo "MANIFEST_SHA256=$(sha256sum "$M"|cut -d" " -f1)"; python -X utf8 -c "import json;d=json.load(open(\"$M\"));f=d.get(\"files\",{});print(\"FILE_COUNT\",len(f));print(\"TOTAL_BYTES\",sum(int(r[\"size\"]) for r in f.values()))" 2>&1; else echo NOT_PUBLISHED_YET; du -sh "$ROOT"/offline_inputs_v2r13* 2>/dev/null; fi
tail -c 500 "$ROOT/logs/offline-inputs-download.out" 2>&1
echo TUKF09_455_V2R13_DOWNLOAD_STATE
