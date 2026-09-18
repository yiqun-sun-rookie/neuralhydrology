#!/bin/bash
# kalmannet-daily-perbasin sequence=162: Phase Aw2 node 0/3: 35 tasks (KalmanNet runs only) on one hcpu48 node, matrix order
# Login node: extract request payload, then launcher_v3.py (admission + exactly one sbatch).
set -o pipefail
umask 022
echo "channel=kalmannet-daily-perbasin sequence=162 purpose=phase_aw2_node0_seq162"
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
REQ=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runtime/phase_aw2_node0_seq162
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[ -d "$ROOT/workspace" ] || { echo "FAIL_MISSING_ROOT $ROOT"; exit 81; }
[ -e "$REQ" ] && { echo "FAIL_REQUEST_DIR_EXISTS $REQ"; exit 82; }
PAYLOAD_SHA256=1f44e7f56fdc4029345ef2104d67871cd3ccfa0770a3e7b9e131d0bb24d3a963
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
RUNNING_FAMILY=$(timeout 25s squeue -u "$USER" -h -o '%j' 2>/dev/null | grep -c kdpp3)
[ "$RUNNING_FAMILY" -eq 0 ] || { echo "FAIL_FAMILY_JOBS_RUNNING count=$RUNNING_FAMILY"; exit 91; }
mkdir -p "$ROOT/runs_superseded_env" || exit 92
moved=0; for d in "$ROOT"/runs/*_KNET_BASIN_*; do [ -d "$d" ] || continue; b=$(basename "$d"); [ -e "$ROOT/runs_superseded_env/$b" ] && { echo "FAIL_SUPERSEDED_EXISTS $b"; exit 93; }; mv "$d" "$ROOT/runs_superseded_env/$b" || exit 94; moved=$((moved+1)); done
echo "KNET_RUNS_SUPERSEDED moved=$moved remaining=$(ls -d "$ROOT"/runs/*_KNET_BASIN_* 2>/dev/null | wc -l)"
"$PY" -I -B "$ROOT/launcher/launcher_v3.py" --request "$REQ" --policy "$ROOT/resource_policy_v3.json"
rc=$?; echo "LAUNCHER_EXIT=$rc"
for f in "$REQ"/submission_job*.receipt.json; do [ -f "$f" ] && { echo "RECEIPT_BEGIN $f"; cat "$f"; echo "RECEIPT_END"; }; done
exit $rc
