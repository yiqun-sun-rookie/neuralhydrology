#!/bin/bash
# TUKF09-455 v2r12: download progress. Read only.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r12_20260908
echo "TIME=$(date -Is)"
if pgrep -f "download_runtime_inputs_login.sh" >/dev/null 2>&1; then echo DOWNLOADER_RUNNING; else echo DOWNLOADER_NOT_RUNNING; fi
du -sh "$ROOT"/offline_inputs_v2r12* 2>/dev/null || echo "no tree"
M="$ROOT/offline_inputs_v2r12/manifest.json"
if [ -f "$M" ]; then echo OFFLINE_INPUTS_PUBLISHED; echo "MANIFEST_SHA256=$(sha256sum "$M"|cut -d" " -f1)"; echo "MANIFEST_SIZE=$(stat -c %s "$M")"; python -X utf8 -c "import json;d=json.load(open(\"$M\"));f=d.get(\"files\",{});print(\"FILE_COUNT\",len(f));print(\"TOTAL_BYTES\",sum(int(r[\"size\"]) for r in f.values()))" 2>&1; else echo NOT_PUBLISHED_YET; fi
tail -c 700 "$ROOT/logs/offline-inputs-download.out" 2>&1
echo TUKF09_455_V2R12_DOWNLOAD_PROGRESS
