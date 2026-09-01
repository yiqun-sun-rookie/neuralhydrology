#!/bin/bash
set -eo pipefail

ROOT=/data1/home/sunyiq/kalmannet_wrr_lr_boundary_20260901
MAILBOX=/data1/home/sunyiq/hpc_mailbox
PAYLOAD="$MAILBOX/payload/kalmannet-wrr-lr-boundary/bridge-v1"
BUNDLE="$PAYLOAD/source_bundle.tar.gz"
JOB_SCRIPT="$PAYLOAD/hpc_bridge.slurm"
OVERLAY="$PAYLOAD/overlay"
TRAIN_SOURCE=/data1/home/sunyiq/knet_project/data/processed/high_flow_aug/train_win800_19990101_01-20070527_03.pt
VAL_SOURCE=/data1/home/sunyiq/knet_project/data/processed/high_flow_aug/val_win800_20070527_04-20090314_13.pt

assert_sha256() {
  expected="$1"
  path="$2"
  actual="$(sha256sum "$path" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "SHA256_MISMATCH path=$path expected=$expected actual=$actual" >&2
    exit 1
  fi
}

test -f "$BUNDLE"
test -f "$JOB_SCRIPT"
test -d "$OVERLAY"
assert_sha256 687cb1220be270e0e329c99989e3d7a18e1c83d6cd32c61c42b35fa1747a6fd8 "$BUNDLE"
assert_sha256 662047b553848b939ebb4ed07f71f878a3389b14f500917db97be86fa2f7dc05 "$JOB_SCRIPT"
assert_sha256 76f36662b65875ae60c5f1213d30913c836aef2b78ac36d99cf4a49103cd1689 "$OVERLAY/experiments/optimize_hyper_parameters/validation_lr_boundary_20260831/run_one_lr.py"
assert_sha256 8004339f4638e0ac901e9edaa06bdb01e20caa8eff988a052128a88b3995fb21 "$OVERLAY/experiments/optimize_hyper_parameters/validation_lr_boundary_20260831/base_config.yaml"
assert_sha256 9681da8a393762b235d8c315238946d6c324eb32a894d486c2bb9a6ed2679071 "$OVERLAY/experiments/optimize_hyper_parameters/validation_lr_boundary_20260831/combos.jsonl"
assert_sha256 2b202d3846bd0b70899b05dfa9df4223b7d04b4b2333c32905de24ac3f460002 "$OVERLAY/experiments/optimize_hyper_parameters/validation_lr_boundary_20260831/source_manifest.json"
assert_sha256 d29e3a628bcb3e133503642ea69e23f5aa91083804d15198b870560f0e7ed0d9 "$OVERLAY/experiments/optimize_hyper_parameters/validation_lr_boundary_20260831/summarize_bridge.py"
assert_sha256 f958d712b151c99b6cd8118670f3d9cb68f1105e9aebfcde1a58ad5d4dcfb228 "$OVERLAY/experiments/optimize_hyper_parameters/validation_lr_boundary_20260831/registry.csv"
assert_sha256 3a4f94a2562278f09b67853ac77e060766296007cb8f8a762756ffe792792440 "$TRAIN_SOURCE"
assert_sha256 2e195fc974b5cc8cdb35df3cb7fd72a202af033ecc415acc03a87020b00bd403 "$VAL_SOURCE"

if [ -e "$ROOT" ]; then
  echo "DEPLOY_TARGET_ALREADY_EXISTS=$ROOT" >&2
  exit 1
fi

mkdir -p "$ROOT/repo" "$ROOT/logs"
tar -xzf "$BUNDLE" -C "$ROOT/repo"
cp -a "$OVERLAY/." "$ROOT/repo/"
cp "$JOB_SCRIPT" "$ROOT/hpc_bridge.slurm"
chmod 700 "$ROOT/hpc_bridge.slurm"

DATA_DIR="$ROOT/repo/data/processed/high_flow_aug"
mkdir -p "$DATA_DIR"
ln -s "$TRAIN_SOURCE" "$DATA_DIR/train_win800_19990101_01-20070527_03.pt"
ln -s "$VAL_SOURCE" "$DATA_DIR/val_win800_20070527_04-20090314_13.pt"

assert_sha256 3a4f94a2562278f09b67853ac77e060766296007cb8f8a762756ffe792792440 "$DATA_DIR/train_win800_19990101_01-20070527_03.pt"
assert_sha256 2e195fc974b5cc8cdb35df3cb7fd72a202af033ecc415acc03a87020b00bd403 "$DATA_DIR/val_win800_20070527_04-20090314_13.pt"

echo "=== DEPLOYED ==="
echo "root=$ROOT"
echo "bundle_sha256=$(sha256sum "$BUNDLE" | awk '{print $1}')"
echo "train_target=$(readlink -f "$DATA_DIR/train_win800_19990101_01-20070527_03.pt")"
echo "validation_target=$(readlink -f "$DATA_DIR/val_win800_20070527_04-20090314_13.pt")"

SUBMIT_OUTPUT="$(sbatch "$ROOT/hpc_bridge.slurm" 2>&1)"
echo "$SUBMIT_OUTPUT"
if ! printf '%s\n' "$SUBMIT_OUTPUT" | grep -qE '^Submitted batch job [0-9]+$'; then
  echo "SUBMIT_FAILED" >&2
  exit 1
fi
JOB_ID="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^Submitted batch job [0-9]+$/ {print $4; exit}')"
echo "job_id=$JOB_ID"
squeue -j "$JOB_ID" -o '%i|%j|%T|%P|%M|%R' || true
