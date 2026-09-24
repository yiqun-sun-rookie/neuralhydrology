#!/bin/bash
set -eo pipefail
sequence=12
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
attempt="$root/formal_attempt_002"
run="$attempt/runs/objective-current-0p05-highflow-2-seed-42"
array_id=$(cat "$root/formal_submission_claim_002/job_id.txt")
[[ "$array_id" =~ ^[0-9]+$ ]]
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'FORMAL_ARRAY_ID=%s\n' "$array_id"
printf '\nRECOVERY_EVENTS\n'
grep '"event": "FULL_EPOCH_REPLAY_REQUIRED"' "$run/events.jsonl" || true
printf '\nEPOCH_COMPLETIONS\n'
grep '"event": "epoch_complete"' "$run/events.jsonl" || true
printf '\nLAST_STDOUT\n'
tail -n 90 "$attempt/logs/weights-"$array_id"_0.out"
printf '\nRUN_FILE_NAMES\n'
find "$run" -maxdepth 1 -type f -printf '%f\n' | sort
printf '\nREAD_ONLY_FAILURE_DIAGNOSIS_COMPLETE\n'
