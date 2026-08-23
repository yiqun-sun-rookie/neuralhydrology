#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823
REPORT="$TARGET/artifacts/tukf19_hpc_deployment_v1/smoke/smoke_report.json"

echo '=== TUKF19 FAILED SMOKE EVIDENCE HASH ==='
sha256sum "$REPORT" 2>&1 || true
wc -c "$REPORT" 2>&1 || true
echo '=== TUKF19 FAILED TARGET IDENTITY ==='
sha256sum "$TARGET/_transport/tukf19_hpc_payload_v1.tar.gz" 2>&1 || true
sha256sum "$TARGET/_transport/bundle_manifest.sha256.json" 2>&1 || true
test ! -e "$TARGET/artifacts/tukf19_hpc_deployment_v1/status/formal_submission.json" && echo FORMAL_SUBMISSION_ABSENT
echo TUKF19_FAILED_SMOKE_EVIDENCE_HASH_COMPLETE
exit 0
