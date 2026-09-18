#!/bin/bash
# kalmannet-daily-perbasin sequence=163: Phase Aw2 node 1/3: 35 tasks (KalmanNet runs only) on one hcpu48 node, matrix order
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=163 purpose=phase_aw2_node1_seq163"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/phase_aw2_node1_seq163
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=0b6948f078a28e87609e4f7b5f54216d3be09fef7e9b53384a91772c428e8b5a
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
