#!/bin/bash
set -eo pipefail
umask 077

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
PAYLOAD="$HOME/hpc_mailbox/payload/id30-modern-moe-execution/id30_shell_compat_overlay_20260827_v04.tar.gz"
EXPECTED=1ce1de67779939db3fc408286de546cebe4adfc1acd0ed11d5faf6b63a0d2e6d
EXPECTED_BASE=e8d0131cc2cb627d8aee583510a8ceb998331aee
FAILED_JOB=$(tr -d '[:space:]' < "$TARGET/deployment/preselection_gates_job_id_v01.txt")
FAILED_JOB_NUM=$(printf '%s' "$FAILED_JOB" | cut -d';' -f1)
NEW_JOB_RECORD="$TARGET/deployment/preselection_gates_job_id_v02.txt"

echo "=== VERIFY CONTROLLED RETRY PRECONDITIONS ==="
date -Is
hostname
FAILED_STATE=$(sacct -j "$FAILED_JOB_NUM" --format=State -n -P | head -1)
echo "failed_job_id=$FAILED_JOB_NUM failed_state=$FAILED_STATE"
test "$FAILED_STATE" = "FAILED"
test ! -e "$NEW_JOB_RECORD"
ACTUAL=$(sha256sum "$PAYLOAD" | awk '{print $1}')
echo "expected_payload=$EXPECTED"
echo "actual_payload=$ACTUAL"
test "$ACTUAL" = "$EXPECTED"
cd "$ROOT"
ACTUAL_BASE=$(git rev-parse HEAD)
echo "expected_base=$EXPECTED_BASE"
echo "actual_base=$ACTUAL_BASE"
test "$ACTUAL_BASE" = "$EXPECTED_BASE"
git diff --quiet
git diff --cached --quiet

echo "=== INSTALL AND FREEZE V04 SHELL-COMPATIBILITY OVERLAY ==="
cp "$PAYLOAD" "$TARGET/deployment/"
tar -xzf "$PAYLOAD" -C "$ROOT"
sed -i 's/\r$//' \
  src/modern_transformer_moe/hpc/submit_preselection_gates.slurm \
  src/modern_transformer_moe/hpc/submit_seed100_development.slurm \
  src/modern_transformer_moe/hpc/submit_dense_selection.slurm \
  src/modern_transformer_moe/hpc/submit_m01_development.slurm
git add -- \
  src/modern_transformer_moe/hpc/submit_preselection_gates.slurm \
  src/modern_transformer_moe/hpc/submit_seed100_development.slurm \
  src/modern_transformer_moe/hpc/submit_dense_selection.slurm \
  src/modern_transformer_moe/hpc/submit_m01_development.slurm \
  test/test_modern_transformer_moe_hpc.py
git diff --cached --quiet && { echo "V04 overlay produced no source change"; exit 30; }
git commit -q -m "Freeze ID30 shell compatibility overlay v04"
NEW_COMMIT=$(git rev-parse HEAD)
echo "v04_commit=$NEW_COMMIT"
printf '%s  %s\n' "$EXPECTED" "id30_shell_compat_overlay_20260827_v04.tar.gz" > \
  "$TARGET/deployment/shell_compat_overlay_v04.sha256"
printf '%s\n' "$NEW_COMMIT" > "$TARGET/deployment/repository_commit_v04.txt"

echo "=== SUBMIT CONTROLLED PRESELECTION RETRY ==="
NEW_JOB=$(sbatch --parsable src/modern_transformer_moe/hpc/submit_preselection_gates.slurm)
printf '%s\n' "$NEW_JOB" | tee "$NEW_JOB_RECORD"
NEW_JOB_NUM=$(printf '%s' "$NEW_JOB" | cut -d';' -f1)
scontrol update jobid="$NEW_JOB_NUM" partition=hgpu2
sleep 2
squeue -j "$NEW_JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
echo "=== COMPLETE ==="
date -Is
