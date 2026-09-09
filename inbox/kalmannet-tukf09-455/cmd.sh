#!/bin/bash
# TUKF09-455 v2r13: what is the download actually doing. Read only.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
echo "TIME=$(date -Is)"
pgrep -af "download_runtime_inputs_login.sh" | head -3 || echo NOT_RUNNING
pgrep -af "pip download|pip install|curl|wget" | head -5 || echo NO_FETCHER
du -sh "$ROOT"/offline_inputs_v2r13* 2>/dev/null
find "$ROOT"/offline_inputs_v2r13.pending.* -type f 2>/dev/null | wc -l
ls -la "$ROOT"/offline_inputs_v2r13.pending.*/ 2>/dev/null | head -12
echo "=== DOWNLOAD LOG TAIL ==="
tail -c 3000 "$ROOT/logs/offline-inputs-download.out" 2>&1
echo "=== NETWORK CHECK ==="
getent hosts pypi.org >/dev/null && echo DNS_OK || echo DNS_FAIL
timeout 25 curl -sS -o /dev/null -m 20 -w "pypi=%{http_code}\n" https://pypi.org/simple/ 2>&1
echo TUKF09_455_V2R13_DOWNLOAD_DIAGNOSTIC
