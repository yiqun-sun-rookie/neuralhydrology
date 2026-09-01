#!/bin/bash
# Read-only export of the n4_impact summary tables, for the paper's Tables 2-3.
# Copies files into outbox/zhenjiang-oyv-n4/ only; touches nothing else.
set -o pipefail
SRC=/data1/home/sunyiq/zhenjiang_oyv_v1/n4_impact
DST=outbox/zhenjiang-oyv-n4/n4_impact_export_20260901
[ -d outbox ] || { echo NOT_IN_REPO_ROOT; pwd; exit 1; }
mkdir -p "$DST"
echo "--- source listing ---"
ls -la "$SRC"
echo "--- copying files under 5MB ---"
find "$SRC" -maxdepth 1 -type f -size -5M -exec cp -v {} "$DST/" \;
echo "--- exported hashes ---"
sha256sum "$DST"/* || true
echo "=== DONE ==="