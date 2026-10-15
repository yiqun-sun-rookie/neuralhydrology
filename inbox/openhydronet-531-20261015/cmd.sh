#!/bin/bash
set -o pipefail
# Submit the smoke job once the data build has finished. Submits ONE job into the channel's own root; touches nothing else.
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
tail -n 4 "$ROOT/logs/build_data.log" | cut -c1-240
grep -q '^BUILD_DONE' "$ROOT/logs/build_data.log" || { echo "BUILD_NOT_DONE"; exit 1; }
ls "$ROOT/data/camels-updated-2025"
if squeue -u sunyiq -h -o '%j' | grep -qx 'ohn_smoke'; then echo "ohn_smoke already queued"; exit 0; fi
out=$(sbatch --job-name=ohn_smoke -t 01:00:00 --export=ALL,CONFIG=smoke "$ROOT/run_ohn.slurm" 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "jobid=$JID"
squeue -j "$JID" -h -o '%i %T %R'
squeue -j "$JID" -h --start -o '%S' 2>/dev/null
exit 0
