#!/bin/bash
# kalmannet-daily-perbasin sequence=148: Phase A node 2/3: 77 tasks (contract-A runs + Sobol references) on one hcpu48 node, matrix order
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=148 purpose=phase_a_node2_seq148"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/phase_a_node2_seq148
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=09e7a31bb9bd3cd4041b8ac32758020abb97f82729699bacd33cd4eda00bc995
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
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
zDzKAFAAAA==
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
