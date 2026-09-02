#!/bin/bash
# Read-only: emit the full stage-1 verdict json so it can be archived in the laos repository.
set -o pipefail
RES=$HOME/kuwei_jdl_seedbatch_20260831/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826
echo "=== SHA256 ==="
sha256sum $RES/seedbatch_stage1_2023.json 2>&1 || true
echo "=== BEGIN JSON ==="
cat $RES/seedbatch_stage1_2023.json 2>&1 || true
echo "=== END JSON ==="
