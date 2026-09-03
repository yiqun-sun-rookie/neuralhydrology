#!/bin/bash
# Read-only: bundle the stage-1 raw prediction arrays + checkpoints so they can be
# independently recomputed on the workstation without any training code. No submission.
set -o pipefail
RUNS=$HOME/kuwei_jdl_seedbatch_20260831/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/runs
cd $RUNS || { echo "no runs dir"; exit 0; }
echo "=== A. files ==="
ls */test_predictions.npy */checkpoint.pt 2>&1 | wc -l
ls -la all_frozen_seed20260826/test_origins.npy 2>&1
echo "=== B. sha256 of every prediction array (for later verification) ==="
sha256sum */test_predictions.npy */test_origins.npy */checkpoint.pt 2>&1 | head -60
echo "=== C. bundle (tar.gz base64) ==="
tar -czf /tmp/kuwei_s1_raw.tgz */test_predictions.npy all_frozen_seed20260826/test_origins.npy */checkpoint.pt 2>&1
ls -la /tmp/kuwei_s1_raw.tgz
sha256sum /tmp/kuwei_s1_raw.tgz
echo "=== BEGIN B64 ==="
base64 -w 0 /tmp/kuwei_s1_raw.tgz
echo ""
echo "=== END B64 ==="
rm -f /tmp/kuwei_s1_raw.tgz
echo "=== DONE ==="
