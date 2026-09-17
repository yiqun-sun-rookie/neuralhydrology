#!/bin/bash
# kalmannet-daily-perbasin sequence=147: Phase A node 1/3: 77 tasks (contract-A runs + Sobol references) on one hcpu48 node, matrix order
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=147 purpose=phase_a_node1_seq147"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/phase_a_node1_seq147
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=41d1e8ba0ad6bd35991af4a41904122096fa0ad27a08ae1440da8b7071668483
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
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
/mX8CfufW6AAUAAA
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
