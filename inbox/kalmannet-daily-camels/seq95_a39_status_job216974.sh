#!/usr/bin/env bash
set -u

JOB_ID="216974"
echo "SEQ95_A39_STATUS_QUERY job_id=${JOB_ID}"

set +e
squeue -h -j "${JOB_ID}" -o '%A|%j|%P|%T|%u|%k|%Z|%M|%N'
squeue_exit=$?
sacct -n -X -j "${JOB_ID}" +  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList -P
sacct_exit=$?
set -e

echo "SEQ95_A39_STATUS_QUERY_COMPLETE job_id=${JOB_ID} squeue_exit=${squeue_exit} sacct_exit=${sacct_exit}"
[[ "${sacct_exit}" == "0" ]]
