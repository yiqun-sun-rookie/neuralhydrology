#!/bin/bash
# kalmannet-daily-perbasin sequence=164: Phase Aw2 node 2/3: 35 tasks (KalmanNet runs only) on one hcpu48 node, matrix order
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=164 purpose=phase_aw2_node2_seq164"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/phase_aw2_node2_seq164
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=aaf987cb39580eb3a74f1fee8e66cdbd6310e4cb4a6b4ee2bb9ba78c16deba3c
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
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
KDPP3_PAYLOAD_BASE64
echo "$PAYLOAD_SHA256  $REQ/payload.tar.gz" | sha256sum -c - >/dev/null || { echo FAIL_PAYLOAD_SHA256; exit 85; }
tar --warning=no-timestamp -xzf "$REQ/payload.tar.gz" -C "$REQ" || { echo FAIL_EXTRACT; exit 86; }
echo "PAYLOAD_OK sha256=$PAYLOAD_SHA256 bytes=$(stat -c %s "$REQ/payload.tar.gz")"
cp "$ROOT/launcher/resource_bind.py" "$ROOT/launcher/precheck.sh" "$REQ/" || exit 89
sed -i 's/\r$//' "$REQ"/*.slurm "$REQ"/precheck.sh 2>/dev/null; true
echo "REMOTE_MATRIX_SHA256=$(sha256sum "$ROOT/workspace/configs/aligned_v3/matrix.json" | cut -c1-64)"
[ "$(sha256sum "$ROOT/workspace/configs/aligned_v3/matrix.json" | cut -c1-64)" = "d9d63c955fa1f94a16313e85d8487339dff19061b0a278ca4de08acdf3470d52" ] || { echo FAIL_MATRIX_MISMATCH; exit 90; }
"$PY" -I -B "$ROOT/launcher/launcher_v3.py" --request "$REQ" --policy "$ROOT/resource_policy_v3.json"
rc=$?; echo "LAUNCHER_EXIT=$rc"
for f in "$REQ"/submission_job*.receipt.json; do [ -f "$f" ] && { echo "RECEIPT_BEGIN $f"; cat "$f"; echo "RECEIPT_END"; }; done
exit $rc
