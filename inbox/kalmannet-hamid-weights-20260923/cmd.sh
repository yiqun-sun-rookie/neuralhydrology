#!/bin/bash
set -eo pipefail
sequence=11
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
attempt="$root/formal_attempt_002"
array_id=$(cat "$root/formal_submission_claim_002/job_id.txt")
[[ "$array_id" =~ ^[0-9]+$ ]]
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'FORMAL_ARRAY_ID=%s\n' "$array_id"
squeue -r -h -j "$array_id" -o '%i|%j|%T|%M|%R' || true
sacct -X -j "$array_id" -n -P --format=JobID,JobName%30,State,ExitCode,Elapsed,NodeList
for path in "$attempt"/HALT.json "$attempt"/runs/*/started.json "$attempt"/runs/*/completion.json "$attempt"/runs/*/failure.json; do
 if [ -f "$path" ]; then
  printf '\nFILE=%s\n' "$path"
  tail -c 5000 "$path"
 fi
done
for path in "$attempt"/runs/*/events.jsonl; do
 if [ -f "$path" ]; then
  printf '\nRUN_EVENTS=%s\n' "$path"
  wc -l "$path"
  grep '"event": "epoch_complete"' "$path" | tail -n 2 || true
  tail -n 2 "$path"
 fi
done
for path in "$attempt"/logs/weights-"$array_id"_*.err; do
 if [ -s "$path" ]; then
  printf '\nSTDERR=%s\n' "$path"
  tail -c 4000 "$path"
 fi
done
printf '\nOWN_JOB_INVENTORY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%R'
printf '\nREAD_ONLY_FORMAL_STATUS_COMPLETE\n'
