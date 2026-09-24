#!/usr/bin/env bash
set -eo pipefail
phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r6'
job='227637'

echo '=== SCHEDULER ==='
accounting=$(sacct -X -j "$job" -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode)
if [ -n "$accounting" ]; then printf '%s\n' "$accounting"; else echo 'NO_ACCOUNTING_ROW'; fi
queue=$(squeue -j "$job" -h -o '%i|%j|%T|%R')
if [ -n "$queue" ]; then printf '%s\n' "$queue"; else echo 'NOT_IN_ACTIVE_QUEUE'; fi

echo '=== EXCLUSIVE PHASE ==='
if [ -d "$phase" ] && [ ! -L "$phase" ]; then echo 'PHASE_DIRECTORY_PRESENT'; else echo 'PHASE_DIRECTORY_ABSENT_OR_LINKED'; fi
if [ -e "$phase/basin_01142500" ] || [ -L "$phase/basin_01142500" ]; then echo 'SECOND_BASIN_PATH_PRESENT'; else echo 'SECOND_BASIN_PATH_ABSENT'; fi
for relative in \
  control/deployed.json \
  basin_01047000/control/submission_attempt.json \
  basin_01047000/control/submission.json \
  basin_01047000/control/job_gate.json \
  basin_01047000/control/tensor_tests/supervisor.json \
  basin_01047000/run/supervisor.json \
  basin_01047000/run/model/started.json \
  basin_01047000/run/model/manifest.final.sha256.json; do
  target="$phase/$relative"
  if [ -f "$target" ] && [ ! -L "$target" ]; then sha256sum "$target"; else printf 'MISSING %s\n' "$relative"; fi
done

echo '=== FIXED JOB LOG TAILS ==='
for suffix in out err; do
  target="$phase/logs/job-$job.$suffix"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    printf 'LOG %s\n' "$suffix"
    tail -n 20 "$target"
  else
    printf 'MISSING job-%s.%s\n' "$job" "$suffix"
  fi
done
