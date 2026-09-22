#!/usr/bin/env bash
set -eo pipefail
echo "FIXED_CONTROL_POST_RUN_QUEUE_READ_ONLY_V1"
echo "sequence=192"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "OWN_QUEUE_BEGIN"
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R'
echo "OWN_QUEUE_END"
echo "CONTROL_JOB_BEGIN"
sacct -j 227265 --noheader --parsable2 --format=JobID,JobName,User,Partition,State,ExitCode,Elapsed,Start,End
echo "CONTROL_JOB_END"
