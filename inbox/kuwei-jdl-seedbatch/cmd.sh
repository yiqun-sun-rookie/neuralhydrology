#!/bin/bash
# Read-only: emit the FULL phase-0 gate json from the 2026-08-28 gate job 215803 landing.
# Closes B14 outstanding item 3 (the earlier receipt truncated it with head -60). No submission.
set -o pipefail
G=$HOME/kuwei_paired/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/gates
echo "=== A. file ==="
ls -la $G/phase0_gates.json 2>&1 || true
sha256sum $G/phase0_gates.json 2>&1 || true
echo "=== BEGIN JSON ==="
cat $G/phase0_gates.json 2>&1 || true
echo ""
echo "=== END JSON ==="
echo "=== DONE ==="
