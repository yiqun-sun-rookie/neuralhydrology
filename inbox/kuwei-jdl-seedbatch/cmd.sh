#!/bin/bash
# Unpack the stage-1 evaluator (payload v2) and report array job 216811 status.
# Read-only with respect to the running array; no submission, no waiting loops.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
SRC=$HOME/hpc_mailbox/payload/kuwei-jdl-seedbatch/v2
echo "=== A. unpack evaluator ==="
cd $SRC && sha256sum -c bundle_manifest.sha256 2>&1 | head -2 || true
tar -xzf $SRC/laos_jdl_seedbatch_v2_tools.tar.gz -C $ROOT/laos 2>&1 | head -3
ls -la $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts/kuwei_jdl_seedbatch_evaluate.py 2>&1 || true
echo "=== B. array state counts ==="
sacct -j 216811 -X --format=State%20 --noheader 2>&1 | sort | uniq -c || true
echo "=== C. squeue ==="
squeue -u ${USER} -n kuwei-jdl-s1 -o "%.14i %.12T %R" 2>&1 | head -8 || true
echo "=== D. task 0 (all_frozen) log ==="
tail -12 $ROOT/logs/kuwei-jdl-s1-216811_0.out 2>&1 || true
echo "=== E. task 1 (hydro_only ls0) log ==="
tail -8 $ROOT/logs/kuwei-jdl-s1-216811_1.out 2>&1 || true
echo "=== F. any stderr so far ==="
tail -6 $ROOT/logs/kuwei-jdl-s1-216811_1.err 2>&1 || true
echo "=== G. run dirs produced so far ==="
ls $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/runs/ 2>&1 | head -20 || true
echo "=== DONE ==="
