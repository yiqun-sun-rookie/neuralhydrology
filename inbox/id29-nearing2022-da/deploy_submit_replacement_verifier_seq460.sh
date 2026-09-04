#!/bin/bash
# Deploy exact versioned files into new formal-closure paths and submit one bounded verifier job.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
FORMAL="$ROOT/results/29_nearing2022_da_ar/formal_closure"
DIAG="$FORMAL/diagnostics"
DEPLOY="$FORMAL/warmup_pair_v2_20260904"
RUNBASE="$DIAG/warmup_pair_v2_20260904"
LOGDIR="$RUNBASE/logs"
FINAL="$RUNBASE/replacement_verification"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC="$SCRIPT_DIR/payload/warmup_pair_v2_20260904"
PREPARER="$DEPLOY/prepare_warmup_target_pair_v2.py"
WRAPPER="$DEPLOY/run_replacement_verifier_v2_1.slurm"

echo "=== AUTHORIZED ACTION BOUNDARY ==="
echo "deploy_new_files_only=yes"
echo "single_verifier_wall_limit=00:30:00"
echo "paired_training_submission_permitted=no"

echo "=== RECHECK PAYLOAD AND SERVER GATES ==="
test -d "$SRC"
test ! -L "$SRC"
test -f "$SRC/prepare_warmup_target_pair_v2.py"
test -f "$SRC/run_replacement_verifier_v2_1.slurm"
test ! -L "$SRC/prepare_warmup_target_pair_v2.py"
test ! -L "$SRC/run_replacement_verifier_v2_1.slurm"
test "$(sha256sum "$SRC/prepare_warmup_target_pair_v2.py" | awk '{print $1}')" = \
  0533a682b1892f71866222624b96b3df1829ba4aa5d233735af9f115c44fd6ec
test "$(sha256sum "$SRC/run_replacement_verifier_v2_1.slurm" | awk '{print $1}')" = \
  7ff105778ef1ad29ab1628ba62041834bacd4b91d6c675189b9f4328eb2d2e9e
test "$(sha256sum "$ROOT/neuralhydrology/datasetzoo/basedataset.py" | awk '{print $1}')" = \
  4658816ea3110a1c2efcf54c3dcf00d5c0982459dca4f7ac985beb983b12df0d
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py" | awk '{print $1}')" = \
  0bcabc96f9e702f2317464f1f0123c29d49d5f7f0f972a10ea3e01bbf18fe987
for J in 202510 202511; do
  ROW=$(sacct -j "$J" -X -n -P --format=JobIDRaw,State,ExitCode | awk -F'|' -v expected="$J" '$1==expected {print}')
  test "$(printf '%s\n' "$ROW" | sed '/^$/d' | wc -l)" -eq 1
  IFS='|' read -r JOB_ID STATE EXIT_CODE <<<"$ROW"
  test "$JOB_ID" = "$J"
  test "$STATE" = COMPLETED
  test "$EXIT_CODE" = 0:0
done
QUEUE=$(squeue -u sunyiq -h -o '%j')
CONFLICT=$(printf '%s\n' "$QUEUE" | grep -c '^N22-replv2$' || true)
test "$CONFLICT" = 0
test ! -e "$DEPLOY"
test ! -e "$RUNBASE"
test ! -e "$FINAL"

echo "=== CREATE NEW VERSIONED PATHS ==="
mkdir "$DEPLOY"
mkdir "$RUNBASE"
mkdir "$LOGDIR"
install -m 644 "$SRC/prepare_warmup_target_pair_v2.py" "$PREPARER"
install -m 755 "$SRC/run_replacement_verifier_v2_1.slurm" "$WRAPPER"
test ! -L "$PREPARER"
test ! -L "$WRAPPER"
cmp "$SRC/prepare_warmup_target_pair_v2.py" "$PREPARER"
cmp "$SRC/run_replacement_verifier_v2_1.slurm" "$WRAPPER"
sha256sum "$PREPARER" "$WRAPPER"

echo "=== STATIC WRAPPER CHECKS ==="
bash -n "$WRAPPER"
grep -qx '#SBATCH --partition=hgpu4' "$WRAPPER"
grep -qx '#SBATCH --time=00:30:00' "$WRAPPER"
if grep -q '^#SBATCH --mem' "$WRAPPER"; then echo "FORBIDDEN_MEM_DIRECTIVE"; exit 1; fi
if grep -q $'\r' "$WRAPPER"; then echo "CRLF_DETECTED"; exit 1; fi
if grep -Eq '(^|[[:space:]])set[[:space:]]+-[^[:space:]]*u' "$WRAPPER"; then echo "FORBIDDEN_SET_U"; exit 1; fi

echo "=== SUBMIT SINGLE VERIFIER ==="
cd "$ROOT"
SUBMIT_OUTPUT=$(sbatch "$WRAPPER" 2>&1)
printf '%s\n' "$SUBMIT_OUTPUT"
JID=$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '$1=="Submitted" && $2=="batch" && $3=="job" && $4 ~ /^[0-9]+$/ && NF==4 {print $4}')
test "$(printf '%s\n' "$JID" | sed '/^$/d' | wc -l)" -eq 1
test -n "$JID"
echo "VERIFIER_JOB_ID=$JID"
scontrol show job "$JID" 2>/dev/null || true
squeue -j "$JID" -h -o '%i|%j|%T|%M|%L|%R' 2>/dev/null || true
exit 0
