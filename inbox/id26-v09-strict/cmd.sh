#!/bin/bash
# id26-v09-strict seq=23 : lightweight scheduler-limit and script query, no waiting loop.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
echo "=== PARTITION ==="
scontrol show partition hgpu2p 2>&1 | tr ' ' '\n' | grep -E '^(PartitionName|MaxTime|DefaultTime|State)='
echo "=== EXISTING SUITE SCRIPT ==="
sed -n '1,220p' "$ROOT/jobs/suite.slurm" 2>&1
echo "=== CURRENT JOB ID ==="
cat "$ROOT/suite_jobid.txt" 2>&1
echo "=== END ==="
