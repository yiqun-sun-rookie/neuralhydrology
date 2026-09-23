#!/usr/bin/env bash
set -eo pipefail

job_id=227494
phase=/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_v2

echo 'SACCT_HISTORY'
sacct -X -j "$job_id" -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode
echo 'EXPECTED_MARKERS'
for relative in \
  control/deployed.json \
  basin_01047000/control/submission_attempt.json \
  basin_01047000/control/submission.json \
  basin_01047000/control/original_tests.xml \
  basin_01047000/control/new_gate_tests.xml \
  basin_01047000/control/tensor_tests/tensor_tests.xml \
  basin_01047000/control/job_gate.json \
  basin_01047000/run/supervisor.json \
  basin_01047000/run/model/manifest.final.sha256.json \
  logs/job-227494.out \
  logs/job-227494.err
do
  path="$phase/$relative"
  if [ -f "$path" ] && [ ! -L "$path" ]; then
    stat -c "$relative|%s|%Y" -- "$path"
  else
    echo "$relative|MISSING"
  fi
done
