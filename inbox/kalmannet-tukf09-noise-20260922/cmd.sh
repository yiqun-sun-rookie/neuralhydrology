#!/usr/bin/env bash
set -u
phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r7_20260927'
job='228078'

printf '=== EXACT FAILED JOB ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
sacct -X -j "$job" -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,ElapsedRaw,State,ExitCode 2>&1 || printf 'SACCT_COMMAND_FAILED\n'
if queue="$(squeue -j "$job" -h -o '%i|%j|%T|%R' 2>&1)"; then
  if [[ -n "$queue" ]]; then printf '%s\n' "$queue"; else printf 'NOT_IN_ACTIVE_QUEUE\n'; fi
else
  printf 'SQUEUE_NONZERO_FOR_TERMINAL_JOB %s\n' "$queue"
fi

printf '=== EXCLUSIVE NEW PHASE ===\n'
if [[ ! -d "$phase" || -L "$phase" || "$(realpath -e "$phase")" != "$phase" ]]; then
  printf 'NEW_PHASE_DIRECTORY_ABSENT_OR_LINKED\n'
  exit 1
fi
printf 'NEW_PHASE_DIRECTORY_PRESENT\n'
if [[ -e "$phase/basin_01142500" || -L "$phase/basin_01142500" ]]; then
  printf 'SECOND_BASIN_PATH_PRESENT\n'
else
  printf 'SECOND_BASIN_PATH_ABSENT\n'
fi

printf '=== FIXED EVIDENCE FILES ===\n'
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
  if [[ -f "$target" && ! -L "$target" && "$(realpath -e "$target")" == "$target" ]]; then
    printf 'FILE %s\n' "$relative"
    sha256sum "$target" || printf 'SHA256_COMMAND_FAILED\n'
    head -c 16384 "$target" || printf 'HEAD_COMMAND_FAILED\n'
    printf '\nEND_FILE %s\n' "$relative"
  else
    printf 'MISSING_OR_LINKED %s\n' "$relative"
  fi
done

printf '=== FIXED SUBPROCESS LOG TAILS ===\n'
for relative in \
  basin_01047000/control/tensor_tests/stdout.log \
  basin_01047000/control/tensor_tests/stderr.log \
  basin_01047000/run/stdout.log \
  basin_01047000/run/stderr.log; do
  target="$phase/$relative"
  if [[ -f "$target" && ! -L "$target" && "$(realpath -e "$target")" == "$target" ]]; then
    printf 'LOG %s\n' "$relative"
    sha256sum "$target" || printf 'SHA256_COMMAND_FAILED\n'
    tail -c 32768 "$target" || printf 'TAIL_COMMAND_FAILED\n'
    printf '\nEND_LOG %s\n' "$relative"
  else
    printf 'MISSING_OR_LINKED %s\n' "$relative"
  fi
done

printf '=== FIXED JOB LOG TAILS ===\n'
for suffix in out err; do
  target="$phase/logs/job-$job.$suffix"
  if [[ -f "$target" && ! -L "$target" && "$(realpath -e "$target")" == "$target" ]]; then
    printf 'LOG %s\n' "$suffix"
    sha256sum "$target" || printf 'SHA256_COMMAND_FAILED\n'
    tail -c 32768 "$target" || printf 'TAIL_COMMAND_FAILED\n'
    printf '\nEND_LOG %s\n' "$suffix"
  else
    printf 'MISSING_OR_LINKED job-%s.%s\n' "$job" "$suffix"
  fi
done
printf 'READ_ONLY_FAILURE_EVIDENCE_QUERY_COMPLETE\n'
