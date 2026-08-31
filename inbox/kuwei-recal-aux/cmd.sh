#!/bin/bash
# READ-ONLY status query for Phase-0 gate job 215803 (submitted from kuwei-paired-recal seq=7
# on 2026-08-28). No sbatch, no scancel, no writes, no cleanup, no waiting loops.
set -o pipefail
JDL=$HOME/kuwei_paired/jdl_gate
GATES=$HOME/kuwei_paired/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826/gates
echo "=== A. sacct 215803 ==="
sacct -j 215803 --format=JobID%14,JobName%18,Partition%14,State%22,ExitCode%9,Submit%20,Start%20,End%20,Elapsed%12 2>&1 | head -8 || true
echo "=== B. squeue any kuwei job ==="
squeue -u ${USER} -o "%.10i %.18j %.14P %.10T %R" 2>&1 | head -12 || true
echo "=== C. job output files ==="
ls -la $JDL/kuwei-jdl-gates-215803.out $JDL/kuwei-jdl-gates-215803.err 2>&1 | head -4 || true
echo "=== D. stdout tail ==="
tail -45 $JDL/kuwei-jdl-gates-215803.out 2>&1 || true
echo "=== E. stderr tail ==="
tail -25 $JDL/kuwei-jdl-gates-215803.err 2>&1 || true
echo "=== F. gate json on HPC ==="
ls -la $GATES 2>&1 | head -5 || true
cat $GATES/phase0_gates.json 2>&1 | head -60 || true
echo "=== DONE ==="
