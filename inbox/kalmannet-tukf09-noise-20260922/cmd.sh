#!/usr/bin/env bash
set -u
phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r6'
job='227637'

echo '=== SCHEDULER ==='
sacct -X -j "$job" -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,ElapsedRaw,State,ExitCode 2>&1 || echo 'SACCT_COMMAND_FAILED'

echo '=== EXCLUSIVE PHASE ==='
if [ -d "$phase" ] && [ ! -L "$phase" ]; then echo 'PHASE_DIRECTORY_PRESENT'; else echo 'PHASE_DIRECTORY_ABSENT_OR_LINKED'; fi
if [ -e "$phase/basin_01142500" ] || [ -L "$phase/basin_01142500" ]; then echo 'SECOND_BASIN_PATH_PRESENT'; else echo 'SECOND_BASIN_PATH_ABSENT'; fi

echo '=== FIXED EVIDENCE FILES ==='
for relative in \
  control/deployed.json \
  basin_01047000/control/submission_attempt.json \
  basin_01047000/control/submission.json \
  basin_01047000/control/job_gate.json \
  basin_01047000/control/original_tests.xml \
  basin_01047000/control/new_gate_tests.xml \
  basin_01047000/control/tensor_tests/supervisor.json \
  basin_01047000/control/tensor_tests/tensor_tests.xml \
  basin_01047000/run/supervisor.json \
  basin_01047000/run/model/started.json \
  basin_01047000/run/model/manifest.final.sha256.json; do
  target="$phase/$relative"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    printf 'FILE %s\n' "$relative"
    sha256sum "$target" || echo 'SHA256_COMMAND_FAILED'
    head -c 8192 "$target" || echo 'HEAD_COMMAND_FAILED'
    printf '\nEND_FILE %s\n' "$relative"
  else
    printf 'MISSING %s\n' "$relative"
  fi
done

echo '=== FIXED SUPERVISED SUBPROCESS LOG TAILS ==='
for relative in \
  basin_01047000/control/tensor_tests/stdout.log \
  basin_01047000/control/tensor_tests/stderr.log \
  basin_01047000/run/stdout.log \
  basin_01047000/run/stderr.log; do
  target="$phase/$relative"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    printf 'LOG %s\n' "$relative"
    sha256sum "$target" || echo 'SHA256_COMMAND_FAILED'
    tail -c 32768 "$target" || echo 'TAIL_COMMAND_FAILED'
    printf '\nEND_LOG %s\n' "$relative"
  else
    printf 'MISSING %s\n' "$relative"
  fi
done

echo '=== FIXED JOB LOG TAILS ==='
for suffix in out err; do
  target="$phase/logs/job-$job.$suffix"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    printf 'LOG %s\n' "$suffix"
    sha256sum "$target" || echo 'SHA256_COMMAND_FAILED'
    tail -c 32768 "$target" || echo 'TAIL_COMMAND_FAILED'
    printf '\nEND_LOG %s\n' "$suffix"
  else
    printf 'MISSING job-%s.%s\n' "$job" "$suffix"
  fi
done
echo '=== END READ-ONLY EVIDENCE QUERY ==='
