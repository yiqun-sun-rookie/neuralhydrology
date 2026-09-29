#!/bin/bash
# precip-selfrule-v05 seq=6: deploy isolated retry and submit gated eight-basin technical validation.
set -eo pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r02
PAYLOAD=$HOME/hpc_mailbox/inbox/precip-selfrule-v05/payload/v05r2/selfrule_time_v05_r02_bundle.tar.gz
EXPECTED_BUNDLE=b16e2f2c72ae422168e23f5d9af7031453018c41bcaedd58b0b79fee16e39b31
EXPECTED_WEIGHT=1c755b0d6ce977db38a8332b50160f2a62a732cb7835be8814d7c23f12a70e00
EXPECTED_CONFIG=0a3b8a4eaa46f65a761707f6b26faf6abb612946ad7bd529a157ad03b2c9f61a
EXPECTED_SCALER=d2a6ce4ad14e9f223cc89a1c5efaf1ee19e4c63dc39653267361d716b39314db

wallclock=$(date "+%F %T %z")
echo "WALLCLOCK=$wallclock"
hostname

echo "=== EXISTING USER JOBS (READ ONLY) ==="
squeue -u "$USER" -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
echo "=== PARTITION SNAPSHOT (READ ONLY) ==="
sinfo -p hgpu2p -o "%P %a %l %D %t %N" || true

test ! -e "$ROOT" || { echo "RETRY_ROOT_ALREADY_EXISTS=$ROOT"; exit 1; }
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
test "$actual_weight" = "$EXPECTED_WEIGHT" || { echo "WEIGHT_HASH_FAILED=$actual_weight"; exit 1; }
test "$actual_config" = "$EXPECTED_CONFIG" || { echo "CONFIG_HASH_FAILED=$actual_config"; exit 1; }
test "$actual_scaler" = "$EXPECTED_SCALER" || { echo "SCALER_HASH_FAILED=$actual_scaler"; exit 1; }

bash -n "$ROOT/code/src/precip_input_assimilation/hpc/prepare_and_submit_selfrule_time_v05_technical.sh"
bash -n "$ROOT/code/src/precip_input_assimilation/hpc/selfrule_time_v05_runtime_check.slurm"
bash -n "$ROOT/code/src/precip_input_assimilation/hpc/selfrule_time_v05_technical.slurm"

bash "$ROOT/code/src/precip_input_assimilation/hpc/prepare_and_submit_selfrule_time_v05_technical.sh"

echo "BUNDLE_SHA256=$actual_bundle"
echo "WEIGHT_SHA256=$actual_weight"
echo "CONFIG_SHA256=$actual_config"
echo "SCALER_SHA256=$actual_scaler"
echo "=== SUBMISSION ==="
cat "$ROOT/technical_8/submission.txt"