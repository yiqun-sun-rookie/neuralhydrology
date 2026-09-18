#!/bin/bash
# kalmannet-daily-perbasin sequence=167: post-Phase-A independent verification of every run (best-checkpoint recompute) and the summary over the complete matrix
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=167 purpose=verify_node_seq167"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/verify_node_seq167
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=b7a3beaa9d827709782f3e7ffce005170b2f974ff80615f9a84c2c29cc16ed42
mkdir -p "$REQ" || { echo FAIL_MKDIR; exit 84; }
base64 -d > "$REQ/payload.tar.gz" <<'KDPP3_PAYLOAD_BASE64'
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
1b9JpKDufprc0Y52tKMd7egb6Dfc/4kkACgAAA==
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
