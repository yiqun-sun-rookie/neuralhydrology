#!/bin/bash
set -eo pipefail
umask 077

echo "=== VERIFY DEPLOYMENT PAYLOAD ==="
PAYLOAD="$HOME/hpc_mailbox/payload/id30-modern-moe-execution/id30_safe_data_code_20260827_v01.tar.gz"
EXPECTED=10bcbd891c06345beb1792c83ce9490a6cd0593dbe0428854582b06a82be41d8
ACTUAL=$(sha256sum "$PAYLOAD" | awk '{print $1}')
echo "expected=$EXPECTED"
echo "actual=$ACTUAL"
test "$ACTUAL" = "$EXPECTED"

echo "=== CREATE ISOLATED DEPLOYMENT ==="
TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
test ! -e "$TARGET"
mkdir -p "$TARGET/repo" "$TARGET/deployment"
cp "$PAYLOAD" "$TARGET/deployment/"
tar -xzf "$PAYLOAD" -C "$TARGET/repo"
printf '%s  %s\n' "$EXPECTED" "id30_safe_data_code_20260827_v01.tar.gz" > "$TARGET/deployment/payload.sha256"

echo "=== FREEZE DEPLOYED SOURCE ==="
cd "$TARGET/repo"
sed -i 's/\r$//' src/modern_transformer_moe/hpc/*.slurm
git init -q
git config user.name "Codex HPC deployment"
git config user.email "codex-hpc@local.invalid"
git add .
git commit -q -m "Freeze ID30 modern Transformer MoE deployment v01"
git rev-parse HEAD | tee "$TARGET/deployment/repository_commit.txt"
git status --short

echo "=== SUBMIT CANDIDATE-SAFE DATA BUILD ==="
mkdir -p logs/30_modern_transformer_moe
JOB_ID=$(sbatch --parsable src/modern_transformer_moe/hpc/submit_prepare_track0_bundles.slurm)
printf '%s\n' "$JOB_ID" | tee "$TARGET/deployment/safe_data_job_id.txt"
squeue -j "${JOB_ID%%;*}" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true

echo "=== DEPLOYMENT COMPLETE ==="
date -Is
