#!/usr/bin/env bash
set -euo pipefail
root='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r8_20260927/basin_01047000/control/tensor_tests'
printf '=== BOUNDED FIRST-BASIN SYNTHETIC OUTPUT INSPECTION ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
if [[ ! -d "$root" || -L "$root" || "$(realpath -e "$root")" != "$root" ]]; then
  printf 'EXACT_TENSOR_TEST_DIRECTORY_ABSENT_OR_LINKED\n'
  exit 0
fi
printf 'EXACT_TENSOR_TEST_DIRECTORY_PRESENT\n'
printf '=== SYMBOLIC LINKS, TARGETS, AND COUNTS ===\n'
find "$root" -xdev -type l -printf '%p -> %l\n'
find "$root" -xdev -type l -printf '.' | wc -c
printf '=== BOUNDED TEST FILE RECORDS ===\n'
for relative in supervisor.json stdout.log stderr.log tensor_tests.xml; do
  target="$root/$relative"
  if [[ -f "$target" && ! -L "$target" ]]; then
    printf 'FILE %s\n' "$relative"
    sha256sum "$target"
    wc -c < "$target"
    tail -n 40 "$target"
  else
    printf 'MISSING %s\n' "$relative"
  fi
done
printf 'READ_ONLY_EXACT_OUTPUT_LINK_INSPECTION_COMPLETE\n'
