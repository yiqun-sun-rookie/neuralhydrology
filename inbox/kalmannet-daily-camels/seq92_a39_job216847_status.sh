#!/usr/bin/env bash
set -Eeuo pipefail

JOB_ID="216847"

printf 'SEQ92_A39_STATUS_QUERY job_id=%s\n' "${JOB_ID}"
set +e
squeue -h -j "${JOB_ID}" -o '%A|%j|%P|%T|%M|%R|%N|%u'
SQUEUE_EXIT=$?
sacct -n -X -j "${JOB_ID}" \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList -P
SACCT_EXIT=$?
set -e
printf 'SEQ92_A39_STATUS_QUERY_COMPLETE job_id=%s squeue_exit=%s sacct_exit=%s\n' \
  "${JOB_ID}" "${SQUEUE_EXIT}" "${SACCT_EXIT}"
[[ "${SACCT_EXIT}" == 0 ]] || exit "${SACCT_EXIT}"
