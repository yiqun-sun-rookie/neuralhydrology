#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/tessera_joint_01073000_20261013_001
JID=$(cat "$ROOT/job_id.txt")
test "$JID" = 241691 || { echo UNEXPECTED_JOB_ID; exit 1; }
date -u
squeue -j "$JID" -h -o '%i %P %j %T %M %R' || true
squeue -j "$JID" --start || true
sacct -j "$JID" --format=JobID,State,ExitCode,Elapsed,MaxRSS
scontrol show job "$JID" || true
sprio -j "$JID" -l || true
sprio -w || true
sshare -U -P || true
sinfo -p hgpu2p,hgpu4,hgpu8 -N -O nodelist,partition,statecompact,gres,gresused
squeue -u sunyiq -h -o '%i %P %j %T %M %R'
echo QUEUE_INSPECTION_COMPLETE
