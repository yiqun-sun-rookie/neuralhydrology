#!/bin/bash
# precip-selfrule-v05 seq=3: deploy the frozen bundle to a new root and submit the gated eight-basin technical run.
set -eo pipefail

ROOT=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929
MAILBOX=$HOME/hpc_mailbox
PAYLOAD=$MAILBOX/inbox/precip-selfrule-v05/payload/v05/selfrule_time_v05_bundle.tar.gz
EXPECTED_BUNDLE=56fb1eb95af8bb9ff6f158fe76f29b23b49922664937d843e10658595f6ab936

date "+wallclock %F %T %z"
hostname

echo "=== A. LIVE QUEUE BEFORE SUBMISSION ==="
squeue -u sunyiq -o "%.18i %.28j %.10P %.2t %.10M %.6D %R"
sinfo -p hgpu2p -N -O nodelist,partition,statecompact,gres:18,gresused:30,cpusstate

echo "=== B. ISOLATED DEPLOYMENT ==="
test ! -e "$ROOT" || { echo "ROOT_ALREADY_EXISTS $ROOT"; exit 1; }
test -f "$PAYLOAD" || { echo "PAYLOAD_MISSING $PAYLOAD"; exit 1; }
actual_bundle=$(sha256sum "$PAYLOAD" | awk '{print $1}')
test "$actual_bundle" = "$EXPECTED_BUNDLE" || {
  echo "BUNDLE_HASH_FAILED $actual_bundle"; exit 1;
}
mkdir -p "$ROOT/code" "$ROOT/assets/c4_s100/train_data"
tar -xzf "$PAYLOAD" -C "$ROOT/code"
SOURCE_ASSET="$ROOT/code/results/precip_input_da_2026_09/local/c4_s100_96basins"
cp "$SOURCE_ASSET/model_epoch030.pt" "$ROOT/assets/c4_s100/model_epoch030.pt"
cp "$SOURCE_ASSET/config.yml" "$ROOT/assets/c4_s100/config.yml"
cp "$SOURCE_ASSET/train_data/train_data_scaler.yml" "$ROOT/assets/c4_s100/train_data/train_data_scaler.yml"

test "$(sha256sum "$ROOT/assets/c4_s100/model_epoch030.pt" | awk '{print $1}')" =   "1c755b0d6ce977db38a8332b50160f2a62a732cb7835be8814d7c23f12a70e00"
test "$(sha256sum "$ROOT/assets/c4_s100/config.yml" | awk '{print $1}')" =   "0a3b8a3d8c6e153288b480b5cef9166b80248f2968ce538f95eb38b21a21f61a"
test "$(sha256sum "$ROOT/assets/c4_s100/train_data/train_data_scaler.yml" | awk '{print $1}')" =   "d2a6ce291e137bcf30dbb39f140692882769760f59f71a29d674b02eafde14db"

bash -n "$ROOT/code/src/precip_input_assimilation/hpc/selfrule_time_v05_runtime_check.slurm"
bash -n "$ROOT/code/src/precip_input_assimilation/hpc/selfrule_time_v05_technical.slurm"
bash -n "$ROOT/code/src/precip_input_assimilation/hpc/prepare_and_submit_selfrule_time_v05_technical.sh"

echo "=== C. PREPARE, RUNTIME GATE, AND DEPENDENT ARRAY ==="
bash "$ROOT/code/src/precip_input_assimilation/hpc/prepare_and_submit_selfrule_time_v05_technical.sh"

echo "=== D. DEPLOYED HASHES ==="
sha256sum "$ROOT/code/src/precip_input_assimilation/configs/selfrule_time_v05.yml"
sha256sum "$ROOT/code/src/precip_input_assimilation/hpc/selfrule_time_v05_runtime_check.slurm"
sha256sum "$ROOT/code/src/precip_input_assimilation/hpc/selfrule_time_v05_technical.slurm"
sha256sum "$ROOT/code/src/precip_input_assimilation/hpc/prepare_and_submit_selfrule_time_v05_technical.sh"
cat "$ROOT/technical_8/submission.txt"
echo "=== SUBMISSION COMMAND COMPLETE ==="