#!/bin/bash
set -eo pipefail
sequence=27
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf '\nARRAY_SQUEUE\n'
squeue -h -j 227626 -o '%i|%j|%T|%P|%R' || true
printf '\nARRAY_SACCT\n'
sacct -X -j 227626 -n -P --format=JobIDRaw,State,ExitCode,Elapsed,NodeList || true
printf '\nFIRST_CELL_ARTIFACTS\n'
first="$root/formal_attempt_003/runs/objective-current-0p05-highflow-2-seed-43"
for name in started.json initialization_check.json events.jsonl completion.json failure.json; do
 p="$first/$name"
 if [ -f "$p" ]; then
  printf 'FILE=%s\n' "$p"
  if [ "$name" = events.jsonl ]; then
   grep -m 1 'FIRST_OPTIMIZER_UPDATE_VERIFIED' "$p" || true
   tail -n 2 "$p"
  else
   cat "$p"
  fi
 else
  printf 'ABSENT=%s\n' "$p"
 fi
done
printf '\nFIRST_CELL_LOG_TAIL\n'
for p in "$root"/formal_attempt_003/logs/weights-227626_1.out "$root"/formal_attempt_003/logs/weights-227626_1.err; do
 if [ -f "$p" ]; then printf 'LOG=%s\n' "$p"; tail -n 4 "$p"; fi
done
printf '\nOWN_JOB_INVENTORY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%R'
printf '\nREAD_ONLY_REMAINING_CELLS_STATUS_COMPLETE\n'
