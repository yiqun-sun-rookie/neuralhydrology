#!/bin/bash
set -eo pipefail
sequence=8
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
array_id=$(cat "$root/formal_submission_claim_001/job_id.txt")
[[ "$array_id" =~ ^[0-9]+$ ]]
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'FORMAL_ARRAY_ID=%s\n' "$array_id"
squeue -r -h -j "$array_id" -o '%i|%j|%T|%M|%R' || true
sacct -X -j "$array_id" -n -P --format=JobID,JobName%30,State,ExitCode,Elapsed,NodeList
for path in "$root"/FORMAL_HALT.json "$root"/logs/weights-"$array_id"_*.out "$root"/logs/weights-"$array_id"_*.err "$root"/formal_runs/*/started.json "$root"/formal_runs/*/completion.json "$root"/formal_runs/*/failure.json; do
 if [ -f "$path" ]; then
  printf '\nFILE=%s\n' "$path"
  tail -c 8000 "$path"
 fi
done
for path in "$root"/formal_runs/*/events.jsonl; do
 if [ -f "$path" ]; then
  printf '\nFIRST_AND_LAST_EVENTS=%s\n' "$path"
  head -n 1 "$path"
  tail -n 2 "$path"
 fi
done
printf '\nOWN_JOB_INVENTORY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%R'
printf '\nREAD_ONLY_FORMAL_QUERY_COMPLETE\n'
