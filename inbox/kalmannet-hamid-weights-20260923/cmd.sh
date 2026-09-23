#!/bin/bash
set -eo pipefail
sequence=6
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
job_id=227479
test "$(cat "$root/probe_submission_claim_002/job_id.txt")" = "$job_id"
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
squeue -h -j "$job_id" -o '%i|%j|%T|%M|%R' || true
sacct -j "$job_id" -n -P --format=JobID,JobName%40,State,ExitCode,Elapsed,MaxRSS,AllocCPUS,NodeList
for path in "$root"/logs/probe-227479.out "$root"/logs/probe-227479.err "$root"/probe_attempt_002/started.json "$root"/probe_attempt_002/cached_state_check.json "$root"/probe_attempt_002/train_batch_0.json "$root"/probe_attempt_002/train_batch_1.json "$root"/probe_attempt_002/val_batch_0.json "$root"/probe_attempt_002/completion.json "$root"/probe_attempt_002/failure.json; do
  if [ -f "$path" ]; then
    printf '\nFILE=%s\n' "$path"
    tail -c 15000 "$path"
  fi
done
printf '\nREAD_ONLY_PROBE_QUERY_COMPLETE\n'
