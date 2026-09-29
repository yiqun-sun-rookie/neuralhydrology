#!/bin/bash
# precip-selfrule-v05 seq=17: deploy and submit the isolated batch-384 resource/equivalence probe.
set -eo pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_batch384_probe_20260929
PAYLOAD=$HOME/hpc_mailbox/inbox/precip-selfrule-v05/payload/batch384p1/selfrule_time_v05_batch384_probe_bundle.tar.gz
EXPECTED_BUNDLE=2c94ac140b67a6a0b325434a1b15510ac4d626073f36059f375f7c145ccafcf5
EXPECTED_WEIGHT=1c755b0d6ce977db38a8332b50160f2a62a732cb7835be8814d7c23f12a70e00
EXPECTED_CONFIG=0a3b8a3d8c6e153288b480b5cef9166b80248f2968ce538f95eb38b21a21f61a
EXPECTED_SCALER=d2a6ce291e137bcf30dbb39f140692882769760f59f71a29d674b02eafde14db
EXPECTED_DRAW=67089437a8c36d881c6ee108184a03448f941d29a150b4064cc4b5141967b6d7

date "+wallclock %F %T %z"
hostname
echo "=== CURRENT USER JOBS (READ ONLY) ==="
squeue -u "$USER" -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true

test ! -e "$ROOT" || { echo "PROBE_ROOT_ALREADY_EXISTS=$ROOT"; exit 1; }
test -f "$PAYLOAD" || { echo "PAYLOAD_MISSING=$PAYLOAD"; exit 1; }
actual_bundle=$(sha256sum "$PAYLOAD" | cut -d' ' -f1)
test "$actual_bundle" = "$EXPECTED_BUNDLE" || {
  echo "BUNDLE_HASH_FAILED expected=$EXPECTED_BUNDLE actual=$actual_bundle"
  exit 1
}

mkdir -p "$ROOT/code" "$ROOT/assets/c4_s100/train_data"
tar -xzf "$PAYLOAD" -C "$ROOT/code"
SOURCE="$ROOT/code/results/precip_input_da_2026_09/local/c4_s100_96basins"
cp "$SOURCE/model_epoch030.pt" "$ROOT/assets/c4_s100/model_epoch030.pt"
cp "$SOURCE/config.yml" "$ROOT/assets/c4_s100/config.yml"
cp "$SOURCE/train_data/train_data_scaler.yml" "$ROOT/assets/c4_s100/train_data/train_data_scaler.yml"
cp "$SOURCE/basin_draw.json" "$ROOT/assets/c4_s100/basin_draw.json"

actual_weight=$(sha256sum "$ROOT/assets/c4_s100/model_epoch030.pt" | cut -d' ' -f1)
actual_config=$(sha256sum "$ROOT/assets/c4_s100/config.yml" | cut -d' ' -f1)
actual_scaler=$(sha256sum "$ROOT/assets/c4_s100/train_data/train_data_scaler.yml" | cut -d' ' -f1)
actual_draw=$(sha256sum "$ROOT/assets/c4_s100/basin_draw.json" | cut -d' ' -f1)
test "$actual_weight" = "$EXPECTED_WEIGHT" || { echo "WEIGHT_HASH_FAILED=$actual_weight"; exit 1; }
test "$actual_config" = "$EXPECTED_CONFIG" || { echo "CONFIG_HASH_FAILED=$actual_config"; exit 1; }
test "$actual_scaler" = "$EXPECTED_SCALER" || { echo "SCALER_HASH_FAILED=$actual_scaler"; exit 1; }
test "$actual_draw" = "$EXPECTED_DRAW" || { echo "DRAW_HASH_FAILED=$actual_draw"; exit 1; }

bash -n "$ROOT/code/src/precip_input_assimilation/hpc/prepare_and_submit_selfrule_batch384_probe.sh"
bash -n "$ROOT/code/src/precip_input_assimilation/hpc/selfrule_time_v05_batch384_probe.slurm"
DEPENDENCY_JOB_ID=231273 bash "$ROOT/code/src/precip_input_assimilation/hpc/prepare_and_submit_selfrule_batch384_probe.sh"

echo "BUNDLE_SHA256=$actual_bundle"
echo "WEIGHT_SHA256=$actual_weight"
echo "CONFIG_SHA256=$actual_config"
echo "SCALER_SHA256=$actual_scaler"
echo "DRAW_SHA256=$actual_draw"
echo "=== SUBMISSION ==="
cat "$ROOT/submission.txt"
