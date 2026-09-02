#!/bin/bash
# TUKF09-455 v2r6: read-only progress check of the offline runtime input download.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r6_20260902
echo "=== LAUNCH MARK ==="
cat "$ROOT/status/offline_inputs_download.launched" 2>&1
echo "=== PROCESS ==="
pgrep -f "download_runtime_inputs_login.sh" >/dev/null 2>&1 && echo "DOWNLOADER_RUNNING" || echo "DOWNLOADER_NOT_RUNNING"
pgrep -f "pip download" >/dev/null 2>&1 && echo "PIP_RUNNING" || echo "PIP_NOT_RUNNING"
echo "=== TREE ==="
ls -la "$ROOT" 2>&1
echo "=== SIZE AND FILE COUNT ==="
du -sh "$ROOT"/offline_inputs_v2r6* 2>&1
find "$ROOT"/offline_inputs_v2r6* -type f -name '*.whl' 2>/dev/null | wc -l
find "$ROOT"/offline_inputs_v2r6* -type f -name '*.tar.gz' 2>/dev/null | wc -l
echo "=== FINAL PUBLISHED? ==="
if [ -d "$ROOT/offline_inputs_v2r6" ]; then echo "FINAL_PRESENT"; ls -la "$ROOT/offline_inputs_v2r6"; sha256sum "$ROOT/offline_inputs_v2r6/manifest.json" 2>&1; else echo "FINAL_NOT_YET"; fi
echo "=== LAUNCHER LOG TAIL ==="
tail -c 1200 "$ROOT/logs/offline-inputs-download.log" 2>&1
echo "=== DOWNLOAD STDERR TAIL ==="
tail -c 1200 "$ROOT"/offline_inputs_v2r6*/evidence/download-stderr.log 2>&1
echo "TUKF09_455_V2R6_DOWNLOAD_STATUS_READ_ONLY"
