#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=216541
EVIDENCE="$ROOT/results/31_hydrologic_dynamic_tokens/_submissions/gpu_probe_retry_20260831_seq22/timelimit_update_seq25"
EXPECTED_JOB_NAME=id31_gpu_probe
EXPECTED_PARTITION=hgpu2p
NEW_TIME_LIMIT=00:30:00

test -d "$ROOT/.git"
test ! -e "$EVIDENCE"
mkdir -p "$EVIDENCE"
cd "$ROOT"

echo "=== PREVIOUS IDENTICAL-PROBE DURATION ===" | tee "$EVIDENCE/previous_probe_duration.txt"
sacct -j 215878 --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P \
  | tee -a "$EVIDENCE/previous_probe_duration.txt"

CURRENT_LINE=$(squeue -j "$JOB_ID" -h -o '%i|%j|%P|%T|%l')
printf '%s\n' "$CURRENT_LINE" | tee "$EVIDENCE/before.txt"
IFS='|' read -r ACTUAL_JOB_ID ACTUAL_JOB_NAME ACTUAL_PARTITION ACTUAL_STATE ACTUAL_TIME_LIMIT <<< "$CURRENT_LINE"
test "$ACTUAL_JOB_ID" = "$JOB_ID"
test "$ACTUAL_JOB_NAME" = "$EXPECTED_JOB_NAME"
test "$ACTUAL_PARTITION" = "$EXPECTED_PARTITION"
test "$ACTUAL_STATE" = "PENDING"

scontrol update JobId="$JOB_ID" TimeLimit="$NEW_TIME_LIMIT"

UPDATED_LINE=$(squeue -j "$JOB_ID" -h -o '%i|%j|%P|%T|%l')
printf '%s\n' "$UPDATED_LINE" | tee "$EVIDENCE/after.txt"
IFS='|' read -r UPDATED_JOB_ID UPDATED_JOB_NAME UPDATED_PARTITION UPDATED_STATE UPDATED_TIME_LIMIT <<< "$UPDATED_LINE"
test "$UPDATED_JOB_ID" = "$JOB_ID"
test "$UPDATED_JOB_NAME" = "$EXPECTED_JOB_NAME"
test "$UPDATED_PARTITION" = "$EXPECTED_PARTITION"
test "$UPDATED_STATE" = "PENDING"
case "$UPDATED_TIME_LIMIT" in
  30:00|00:30:00) ;;
  *) echo "Unexpected updated time limit: $UPDATED_TIME_LIMIT" >&2; exit 1 ;;
esac

JOB_RECORD=$(scontrol show job "$JOB_ID" -o)
printf '%s\n' "$JOB_RECORD" | tee "$EVIDENCE/scontrol_after.txt"
RECORDED_TIME_LIMIT=$(printf '%s\n' "$JOB_RECORD" | grep -o 'TimeLimit=[^ ]*' | cut -d= -f2)
case "$RECORDED_TIME_LIMIT" in
  30:00|00:30:00) ;;
  *) echo "Unexpected scontrol time limit: $RECORDED_TIME_LIMIT" >&2; exit 1 ;;
esac
squeue --start -j "$JOB_ID" -o '%.18i %.24j %.10l %.19S %.30R' | tee "$EVIDENCE/estimated_start_after.txt"
date -Is > "$EVIDENCE/UPDATE_COMPLETE"
echo "ID31_GPU_PROBE_TIMELIMIT_UPDATED $JOB_ID $NEW_TIME_LIMIT"
