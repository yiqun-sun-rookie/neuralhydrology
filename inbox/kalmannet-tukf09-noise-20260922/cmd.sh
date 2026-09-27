#!/usr/bin/env bash
set -euo pipefail
phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r7_20260927'
test_dir="$phase/basin_01047000/control/original_tests_tmp/test_limits_output_print__x__10/output"

printf '=== FIXED OUTPUT-LIMIT TEST ARTIFACTS ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
if [[ ! -d "$phase" || -L "$phase" || "$(realpath -e "$phase")" != "$phase" ]]; then
  printf 'NEW_PHASE_ABSENT_OR_LINKED\n'
  exit 1
fi
if [[ ! -d "$test_dir" || -L "$test_dir" || "$(realpath -e "$test_dir")" != "$test_dir" ]]; then
  printf 'FIXED_TEST_DIRECTORY_ABSENT_OR_LINKED\n'
  exit 1
fi
printf 'FIXED_TEST_DIRECTORY_PRESENT\n'
find "$test_dir" -maxdepth 1 -mindepth 1 -printf '%f|%y|%s\n'
missing=0
for name in stdout.log stderr.log supervisor.json; do
  target="$test_dir/$name"
  if [[ -f "$target" && ! -L "$target" && "$(realpath -e "$target")" == "$target" ]]; then
    printf 'FILE %s\n' "$name"
    size="$(stat -c '%s' "$target")"
    printf 'SIZE_BYTES=%s\n' "$size"
    sha256sum "$target"
    if [[ "$name" == 'supervisor.json' ]]; then
      if (( size > 8192 )); then
        printf 'SUPERVISOR_RECORD_EXCEEDS_BOUNDED_FULL_READ\n'
        exit 1
      fi
      cat "$target"
      printf '\nEND_SUPERVISOR\n'
    fi
  else
    printf 'MISSING_OR_LINKED %s\n' "$name"
    missing=1
  fi
done
if (( missing != 0 )); then
  printf 'FIXED_ARTIFACTS_INCOMPLETE\n'
  exit 1
fi
printf 'READ_ONLY_OUTPUT_LIMIT_EVIDENCE_COMPLETE\n'
