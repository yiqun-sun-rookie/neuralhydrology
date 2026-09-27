#!/usr/bin/env bash
set -uo pipefail
phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r8_20260927'
job='228129'

printf '=== EXACT TERMINAL JOB ACCOUNTING ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
sacct -X -j "$job" -P -n --format=JobID,JobName,Partition,ElapsedRaw,State,ExitCode,Submit,Start,End || printf 'ACCOUNTING_QUERY_FAILED\n'
printf '=== READ-ONLY PHASE RECORDS ===\n'
if [[ -d "$phase" && ! -L "$phase" && "$(realpath -e "$phase")" == "$phase" ]]; then
  printf 'NEW_PHASE_DIRECTORY_PRESENT\n'
else
  printf 'NEW_PHASE_DIRECTORY_ABSENT_OR_LINKED\n'
fi
if [[ -e "$phase/basin_01142500" || -L "$phase/basin_01142500" ]]; then
  printf 'SECOND_BASIN_PATH_PRESENT\n'
else
  printf 'SECOND_BASIN_PATH_ABSENT\n'
fi
for relative in \
  control/deployed.json \
  basin_01047000/control/submission_attempt.json \
  basin_01047000/control/submission.json \
  basin_01047000/control/job_gate.json \
  basin_01047000/run/supervisor.json \
  basin_01047000/run/model/started.json \
  basin_01047000/run/model/manifest.final.sha256.json; do
  target="$phase/$relative"
  if [[ -f "$target" && ! -L "$target" ]]; then
    printf 'FILE %s\n' "$relative"
    sha256sum "$target"
    wc -c < "$target"
    head -c 3000 "$target"
    printf '\nEND_FILE %s\n' "$relative"
  else
    printf 'MISSING %s\n' "$relative"
  fi
done
printf '=== EXACT JOB LOG TAILS ===\n'
for suffix in out err; do
  target="$phase/logs/job-$job.$suffix"
  if [[ -f "$target" && ! -L "$target" ]]; then
    printf 'LOG %s\n' "$suffix"
    sha256sum "$target"
    wc -c < "$target"
    tail -n 80 "$target"
  else
    printf 'MISSING job-%s.%s\n' "$job" "$suffix"
  fi
done
printf 'READ_ONLY_TERMINAL_FAILURE_EVIDENCE_COMPLETE\n'
