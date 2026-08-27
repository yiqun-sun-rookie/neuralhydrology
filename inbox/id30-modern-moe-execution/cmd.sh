#!/bin/bash
set -eo pipefail
umask 077

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
PAYLOAD="$HOME/hpc_mailbox/payload/id30-modern-moe-execution/id30_execution_overlay_20260827_v02.tar.gz"
EXPECTED=dc4ce6fae2d50cb4a623d79144b981b6d58f5ecb0618aefcc0a797c7438dca29
EXPECTED_BASE=188ddf24671ce323ff2a4a27ddde561855ac3395

echo "=== VERIFY V02 OVERLAY ==="
date -Is
hostname
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
test ! -e data/camels_us_track0_development_forcing_v01
test ! -e data/camels_us_track0_supervision_v01
test ! -e src/modern_transformer_moe/registry/track0_development_forcing_manifest_v01.json
test ! -e src/modern_transformer_moe/registry/track0_supervision_manifest_v01.json

echo "=== INSTALL AND FREEZE V02 OVERLAY ==="
cp "$PAYLOAD" "$TARGET/deployment/"
tar -xzf "$PAYLOAD" -C "$ROOT"
sed -i 's/\r$//' src/modern_transformer_moe/hpc/*.slurm
git add -- \
  src/modern_transformer_moe/scripts/run_development.py \
  src/modern_transformer_moe/scripts/run_full_size_gpu_probe.py \
  src/modern_transformer_moe/scripts/build_dense_selection_report.py \
  src/modern_transformer_moe/scripts/inspect_development_runs.py \
  src/modern_transformer_moe/hpc/submit_prepare_track0_bundles.slurm \
  src/modern_transformer_moe/hpc/submit_preselection_gates.slurm \
  src/modern_transformer_moe/hpc/submit_seed100_development.slurm \
  src/modern_transformer_moe/hpc/submit_dense_selection.slurm \
  src/modern_transformer_moe/hpc/submit_m01_development.slurm \
  test/test_modern_transformer_moe_gpu_probe.py \
  test/test_modern_transformer_moe_dense_selection.py \
  test/test_modern_transformer_moe_hpc.py \
  test/test_modern_transformer_moe_runtime_inspection.py \
  test/test_camelsus_track0_supervision.py
git diff --cached --quiet && { echo "V02 overlay produced no source change"; exit 30; }
git commit -q -m "Freeze ID30 execution overlay v02"
NEW_COMMIT=$(git rev-parse HEAD)
echo "v02_commit=$NEW_COMMIT"
printf '%s  %s\n' "$EXPECTED" "id30_execution_overlay_20260827_v02.tar.gz" > \
  "$TARGET/deployment/execution_overlay_v02.sha256"
printf '%s\n' "$NEW_COMMIT" > "$TARGET/deployment/repository_commit_v02.txt"

echo "=== RESUBMIT CANDIDATE-SAFE DATA BUILD ==="
JOB_ID=$(sbatch --parsable src/modern_transformer_moe/hpc/submit_prepare_track0_bundles.slurm)
printf '%s\n' "$JOB_ID" | tee "$TARGET/deployment/safe_data_job_id_v02.txt"
squeue -j "${JOB_ID%%;*}" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
echo "=== COMPLETE ==="
date -Is
