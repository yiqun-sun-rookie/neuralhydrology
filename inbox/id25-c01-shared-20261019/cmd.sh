#!/bin/bash
set -u
root=/data1/home/sunyiq/id25_graice_shared_c01_20261019_001
old=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
probe=/data1/home/sunyiq/id25_graice_shared_probe_20261019_001
if test -e "$root"; then echo NEW_ROOT_ALREADY_EXISTS; ls -ld "$root"; else echo NEW_ROOT_UNUSED; fi
timeout 30 squeue -h -u sunyiq -n id25_c01_shared_261019 -o '%i|%j|%T|%R'
printf 'SQUEUE_EXIT=%s\n' "$?"
timeout 30 sacct -S 2026-10-18 -X -u sunyiq --name=id25_c01_shared_261019 --format=JobIDRaw,JobName%32,State,ExitCode -n -P
printf 'SACCT_EXIT=%s\n' "$?"
timeout 30 scontrol -o show node ngu004
for file in "$old/venv/bin/python" "$old/venv/runtime_ready" "$old/inputs/inputs.npz" "$old/runs/lat+026_lon-082/scalers.json" "$old/predictions.npz" "$probe/probe_output/gpu_preflight.json" "$probe/provenance/cpu_contract.json"; do
  if test -r "$file"; then printf 'READABLE=%s\n' "$file"; else printf 'UNREADABLE=%s\n' "$file"; fi
done
echo METADATA_ONLY_NO_PREFLIGHT_NO_SUBMISSION
