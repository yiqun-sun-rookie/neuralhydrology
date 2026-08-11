#!/bin/bash
# id26-v09-strict seq=53 : create the isolated audit checkout and submit the 24-run audit.
set -euo pipefail
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
AUDIT_REPO=$AUDIT_PARENT/neuralhydrology
TRAIN_REPO=$ROOT/codetest/neuralhydrology
STRICT_REPO=$ROOT/neuralhydrology
COMMIT=31ff9ebe3814e088fd623b836f4a802ddab856cd
BRANCH=codex/historical-band-experts-pilot
REMOTE=https://github.com/yiqun-sun-rookie/neuralhydrology.git
JOBID_FILE=$AUDIT_PARENT/training_audit_jobid.txt
export PATH=$ROOT/gitenv/bin:$PATH

echo "=== A FROZEN CHECKOUTS ==="
echo "training_head=$(git -C "$TRAIN_REPO" rev-parse HEAD)"
echo "strict_head=$(git -C "$STRICT_REPO" rev-parse HEAD)"
test "$(git -C "$TRAIN_REPO" rev-parse HEAD)" = bb519b8b9980725ac1d5f4e298d76ae80ea2c58d
test "$(git -C "$STRICT_REPO" rev-parse HEAD)" = f94183209bf44ed6e672e1c23f98020905804e6d

echo "=== B ISOLATED AUDIT CHECKOUT ==="
mkdir -p "$AUDIT_PARENT"
if [ -e "$AUDIT_REPO" ]; then
  test -d "$AUDIT_REPO/.git"
  test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
else
  git clone -q --no-checkout "$REMOTE" "$AUDIT_REPO"
fi
git -C "$AUDIT_REPO" fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
test "$(git -C "$AUDIT_REPO" rev-parse "refs/remotes/origin/$BRANCH")" = "$COMMIT"
git -C "$AUDIT_REPO" checkout -q --detach "$COMMIT"
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = "$COMMIT"
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
echo "audit_head=$(git -C "$AUDIT_REPO" rev-parse HEAD)"

echo "=== C AUDIT PRECONDITIONS ==="
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
test ! -e "$FORMAL_ROOT/training_external_audit.json"
test ! -e "$FORMAL_ROOT/state_diagnostics"
test ! -e "$JOBID_FILE"
test -f "$AUDIT_REPO/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm"

echo "=== D SUBMIT TRAINING AUDIT ==="
JID=$(sbatch --parsable "$AUDIT_REPO/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm")
printf '%s\n' "$JID" > "$JOBID_FILE"
echo "TRAINING_AUDIT_JOBID=$JID"
squeue -j "$JID" -o '%.12i %.18j %.10T %.12M %.24R'
echo "=== END ==="
