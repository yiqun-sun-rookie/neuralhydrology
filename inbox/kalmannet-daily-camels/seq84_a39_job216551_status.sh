#!/usr/bin/env bash
set -Eeuo pipefail

JOB_ID="216551"

set +e
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%M|%l|%R|%u|%Z|%k'
SQUEUE_RC=$?
set -e
printf 'SEQ84_A39_SQUEUE_EXIT job_id=%s exit_code=%s\n' "$JOB_ID" "$SQUEUE_RC"
sacct -X -j "$JOB_ID" -n -P \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES,ReqTRES
printf 'SEQ84_A39_STATUS_COMPLETE job_id=%s\n' "$JOB_ID"
