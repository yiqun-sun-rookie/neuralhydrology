#!/bin/bash
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01
test -f "$TASK_ROOT/pilot_job_id.txt" || { echo 'PILOT_JOB_RECEIPT_MISSING'; exit 2; }
JOB_RAW=$(cat "$TASK_ROOT/pilot_job_id.txt")
JOB_ID=${JOB_RAW%%;*}
case "$JOB_ID" in ''|*[!0-9]*) echo INVALID_JOB_ID; exit 3;; esac
date -Is
sacct -j "$JOB_ID" --format=JobID,JobName%24,State,ExitCode,Elapsed,AllocCPUS,MaxRSS,NodeList -P
squeue -j "$JOB_ID" -o '%.18i %.12j %.10T %.10M %.6D %R'
if test -f "$TASK_ROOT/pilot/summary.json"; then
  printf 'PILOT_SUMMARY\n'
  cat "$TASK_ROOT/pilot/summary.json"
else
  printf 'PILOT_SUMMARY_NOT_PRESENT\n'
fi
if test -f "$TASK_ROOT/pilot-tests.xml"; then
  printf 'TEST_XML\n'
  cat "$TASK_ROOT/pilot-tests.xml"
fi
for suffix in out err; do
  LOGFILE="$TASK_ROOT/logs/id29-xaj-technical_${JOB_ID}.${suffix}"
  if test -f "$LOGFILE"; then
    printf 'LOG_%s\n' "$suffix"
    tail -n 35 "$LOGFILE"
  fi
done
printf 'STATUS_COMPLETE\n'
