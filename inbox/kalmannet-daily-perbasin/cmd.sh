#!/bin/bash
# kalmannet-daily-perbasin sequence=160: confirmation: production pool path under ATEN_CPU_CAPABILITY=default passes the exact zero-gain gate on all 21 basins (development mode, 1 epoch)
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=160 purpose=zero_gain_probe5_seq160"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/zero_gain_probe5_seq160
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=ce502738f63b1b4f41d4c78ee8f1d125d009ef99aafe067b2dc2fa29a4c9d084
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
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
KDPP3_PAYLOAD_BASE64
echo "$PAYLOAD_SHA256  $REQ/payload.tar.gz" | sha256sum -c - >/dev/null || { echo FAIL_PAYLOAD_SHA256; exit 85; }
tar --warning=no-timestamp -xzf "$REQ/payload.tar.gz" -C "$REQ" || { echo FAIL_EXTRACT; exit 86; }
echo "PAYLOAD_OK sha256=$PAYLOAD_SHA256 bytes=$(stat -c %s "$REQ/payload.tar.gz")"
cp "$ROOT/launcher/resource_bind.py" "$ROOT/launcher/precheck.sh" "$REQ/" || exit 89
sed -i 's/\r$//' "$REQ"/*.slurm "$REQ"/precheck.sh 2>/dev/null; true
"$PY" -I -B "$ROOT/launcher/launcher_v3.py" --request "$REQ" --policy "$ROOT/resource_policy_v3.json"
rc=$?; echo "LAUNCHER_EXIT=$rc"
for f in "$REQ"/submission_job*.receipt.json; do [ -f "$f" ] && { echo "RECEIPT_BEGIN $f"; cat "$f"; echo "RECEIPT_END"; }; done
exit $rc
