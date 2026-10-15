#!/bin/bash
set -o pipefail
# Submit the full upstream CAMELS-531 config (native531) as ONE single-GPU job in this channel's own root.
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
if squeue -u sunyiq -h -o '%j' | grep -qx 'ohn_native531'; then echo "ohn_native531 already queued/running"; squeue -u sunyiq -h -o '%i %j %T' | grep ohn_native531; exit 0; fi
out=$(sbatch --job-name=ohn_native531 -t 3-12:00:00 --export=ALL,CONFIG=native531 "$ROOT/run_ohn.slurm" 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "jobid=$JID"
squeue -j "$JID" -h -o '%i %T %R'
exit 0
