#!/bin/bash
# id26-v09-strict seq=55 : preserve attempt 01, update the isolated auditor, and submit attempt 02 once.
set -euo pipefail
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
AUDIT_REPO=$AUDIT_PARENT/neuralhydrology
TRAIN_REPO=$ROOT/codetest/neuralhydrology
STRICT_REPO=$ROOT/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
OLD_JOBID_FILE=$AUDIT_PARENT/training_audit_jobid.txt
NEW_JOBID_FILE=$AUDIT_PARENT/training_audit_attempt_02_jobid.txt
REPORT=$FORMAL_ROOT/training_external_audit.json
COMMIT=ac258afd31d835d93137da8961dc1206a1ee844c
BRANCH=codex/historical-band-experts-pilot
export PATH=$ROOT/gitenv/bin:$PATH

echo "=== A PRESERVE FAILED ATTEMPT 01 ==="
OLD_JID=$(tr -d '[:space:]' < "$OLD_JOBID_FILE")
test "$OLD_JID" = 202586
IFS='|' read -r OLD_STATE OLD_EXIT <<< "$(sacct -n -X -j "$OLD_JID" --starttime 2026-08-11 --format=State,ExitCode -P)"
echo "attempt_01_jobid=$OLD_JID state=$OLD_STATE exit_code=$OLD_EXIT"
test "$OLD_STATE" = FAILED
test "$OLD_EXIT" = 1:0
tail -n 20 "$ROOT/logs/training_audit_${OLD_JID}.err"

echo "=== B FROZEN CHECKOUTS ==="
echo "training_head=$(git -C "$TRAIN_REPO" rev-parse HEAD)"
echo "strict_head=$(git -C "$STRICT_REPO" rev-parse HEAD)"
test "$(git -C "$TRAIN_REPO" rev-parse HEAD)" = bb519b8b9980725ac1d5f4e298d76ae80ea2c58d
test "$(git -C "$STRICT_REPO" rev-parse HEAD)" = f94183209bf44ed6e672e1c23f98020905804e6d

echo "=== C UPDATE ISOLATED AUDIT CHECKOUT ==="
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = 31ff9ebe3814e088fd623b836f4a802ddab856cd
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
git -C "$AUDIT_REPO" fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
test "$(git -C "$AUDIT_REPO" rev-parse "refs/remotes/origin/$BRANCH")" = "$COMMIT"
git -C "$AUDIT_REPO" checkout -q --detach "$COMMIT"
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = "$COMMIT"
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
echo "audit_head=$(git -C "$AUDIT_REPO" rev-parse HEAD)"

echo "=== D ATTEMPT 02 PRECONDITIONS ==="
test ! -e "$REPORT"
test ! -e "$NEW_JOBID_FILE"
test ! -e "$FORMAL_ROOT/state_diagnostics"
test ! -e "$FORMAL_ROOT/training_seal.json"

echo "=== E SUBMIT TRAINING AUDIT ATTEMPT 02 ==="
JID=$(sbatch --parsable "$AUDIT_REPO/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm")
printf '%s\n' "$JID" > "$NEW_JOBID_FILE"
echo "TRAINING_AUDIT_ATTEMPT_02_JOBID=$JID"
squeue -j "$JID" -o '%.12i %.18j %.10T %.12M %.24R'
echo "=== END ==="
