#!/bin/bash
# kalmannet-daily-perbasin sequence=146: Phase A node 0/3: 77 tasks (contract-A runs + Sobol references) on one hcpu48 node, matrix order
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=146 purpose=phase_a_node0_seq146"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/phase_a_node0_seq146
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=8a448c74b68bf32a99874c9176b97ea98808798290f0f21087859ea0f43a7d31
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
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
syoAUAAA
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
