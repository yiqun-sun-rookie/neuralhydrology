#!/bin/bash
set -euo pipefail
umask 077

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
PAYLOAD="$HOME/hpc_mailbox/payload/id30-modern-moe-execution/id30_gate_a_overlay_20260827_v03.tar.gz"
EXPECTED=11a54b43decae1bf21ad68a03736d7f3e0f24c8a266210e8b544f6c2bae5cd03
EXPECTED_BASE=fe10599f888dd8a4e3e1e014b94f1ccf81ec0df1

echo "=== VERIFY V03 OVERLAY ==="
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

echo "=== INSTALL AND FREEZE V03 OVERLAY ==="
cp "$PAYLOAD" "$TARGET/deployment/"
tar -xzf "$PAYLOAD" -C "$ROOT"
sed -i 's/\r$//' \
  src/modern_transformer_moe/hpc/submit_preselection_gates.slurm \
  src/modern_transformer_moe/hpc/submit_dense_selection.slurm
git add -- \
  src/modern_transformer_moe/scripts/run_development.py \
  src/modern_transformer_moe/scripts/build_single_seed_dense_gate.py \
  src/modern_transformer_moe/scripts/build_track0_development_forcing_bundle.py \
  src/modern_transformer_moe/hpc/submit_preselection_gates.slurm \
  src/modern_transformer_moe/hpc/submit_dense_selection.slurm \
  test/test_modern_transformer_moe_hpc.py \
  test/test_modern_transformer_moe_single_seed_gate.py \
  test/test_camelsus_track0_supervision.py
git diff --cached --quiet && { echo "V03 overlay produced no source change"; exit 30; }
git commit -q -m "Freeze ID30 Gate A and legacy Maurer fix v03"
NEW_COMMIT=$(git rev-parse HEAD)
echo "v03_commit=$NEW_COMMIT"
printf '%s  %s\n' "$EXPECTED" "id30_gate_a_overlay_20260827_v03.tar.gz" > \
  "$TARGET/deployment/gate_a_overlay_v03.sha256"
printf '%s\n' "$NEW_COMMIT" > "$TARGET/deployment/repository_commit_v03.txt"

echo "=== RESUBMIT CANDIDATE-SAFE DATA BUILD ==="
JOB_ID=$(sbatch --parsable src/modern_transformer_moe/hpc/submit_prepare_track0_bundles.slurm)
printf '%s\n' "$JOB_ID" | tee "$TARGET/deployment/safe_data_job_id_v03.txt"
JOB_NUM=$(printf '%s' "$JOB_ID" | cut -d';' -f1)
squeue -j "$JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
echo "=== COMPLETE ==="
date -Is
