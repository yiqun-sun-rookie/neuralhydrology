#!/bin/bash
# TUKF09-455 v2r12: offline runtime input download state. Read only.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r12_20260908
echo "TIME=$(date -Is)"
if pgrep -f "download_runtime_inputs_login.sh" >/dev/null 2>&1; then echo DOWNLOADER_RUNNING; pgrep -af download_runtime_inputs_login.sh | head -3; else echo DOWNLOADER_NOT_RUNNING; fi
echo "=== published offline inputs ==="
ls -la "$ROOT/offline_inputs_v2r12" 2>&1 | head -8
du -sh "$ROOT/offline_inputs_v2r12" 2>/dev/null
M="$ROOT/offline_inputs_v2r12/manifest.json"
if [ -f "$M" ]; then echo "MANIFEST_SHA256=$(sha256sum "$M" | cut -d" " -f1)"; python -X utf8 -c "import json;d=json.load(open(\"$M\"));v=d.get(\"files\",d);print(\"FILES\",len(v));print(\"TOTAL_BYTES\",sum(int(r[\"size\"]) for r in v.values()) if isinstance(v,dict) else \"n/a\")" 2>&1; else echo MANIFEST_ABSENT; fi
echo "=== download log tail ==="
tail -c 1200 "$ROOT/logs/offline-inputs-download.out" 2>&1
echo "=== status markers ==="
ls -la "$ROOT/status" 2>&1
echo "=== disk ==="
df -h /data1/home/sunyiq | tail -1
echo TUKF09_455_V2R12_DOWNLOAD_STATE_READ_ONLY
