#!/bin/bash
set -eo pipefail
sequence=18
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
attempt="$root/diagnostic_20260924_v2"
job_id=$(cat "$root/diagnostic_submission_claim_20260924_v2/job_id.txt")
[[ "$job_id" =~ ^[0-9]+$ ]]
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'DIAGNOSTIC_JOB_ID=%s\n' "$job_id"
squeue -r -h -j "$job_id" -o '%i|%j|%T|%M|%R' || true
sacct -X -j "$job_id" -n -P --format=JobID,JobName%30,State,ExitCode,Elapsed,NodeList
for path in "$attempt"/full_batch_observer_audit.json "$attempt"/preflight_cpu/result.json "$attempt"/preflight_gpu/result.json "$attempt"/HALT.json "$attempt"/runs/*/full_batch_observer_parity.json "$attempt"/runs/*/diagnostic_training_observation.json "$attempt"/runs/*/failure.json; do
 if [ -f "$path" ]; then printf '\nFILE=%s\n' "$path"; tail -c 10000 "$path"; fi
done
for path in "$attempt"/runs/*/events.jsonl; do
 if [ -f "$path" ]; then printf '\nFIRST_AND_LAST_EVENTS=%s\n' "$path"; head -n 1 "$path"; tail -n 2 "$path"; fi
done
for path in "$attempt"/logs/weights-"$job_id"_*.out "$attempt"/logs/weights-"$job_id"_*.err; do
 if [ -f "$path" ]; then printf '\nLOG=%s\n' "$path"; tail -n 16 "$path"; fi
done
printf '\nOWN_JOB_INVENTORY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%R'
printf '\nREAD_ONLY_DIAGNOSTIC_STATUS_COMPLETE\n'
